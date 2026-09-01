"""Prove the nightly wrapper still runs all six of its steps, and reads every exit code.

    python python-tools/check_daily_ops.py

WHY THIS EXISTS, AND IT IS NOT HYPOTHETICAL
-------------------------------------------
`daily_ops.cmd` contained `"%REPO%\\python-tools<BEL>uto_shoot.py"` - a literal 0x07
byte where `\\a` was meant, written by some tool that read the path as a C escape. cmd
does not care, python said `can't open file ...\\x07uto_shoot.py`, the wrapper did not
check that step's exit code, and it went on to report OK. The shoot therefore never ran
for days. The only symptom reaching a human was the queue saying OUT OF CLIPS and the
runway sitting at 0 days, which reads like "we need more clips", not "the thing that
makes clips is not being called".

So this checks the two properties that failure needed, plus the one that hid it:

  1. THE FILE IS PURE BYTES. ASCII, no BOM, CRLF only, and NO control characters -
     which is what makes a stray 0x07 an error here rather than a silent path.
  2. EVERY SCRIPT IT NAMES EXISTS, resolved the way cmd resolves it, so a typo in a
     path fails at check time instead of at 11:47 into a log nobody reads.
  3. EVERY STEP'S FAILURE IS SURFACED - checked ONE STEP AT A TIME. Failing all six at
     once proves nothing: step 1 jumps to :problem and the wrapper exits 1 whether or
     not step 3's code is ever read. An earlier draft of this file did exactly that and
     passed a wrapper with the shoot's check deleted. So each step is failed alone.

The stub is a .cmd, which TRANSFERS control instead of returning the way python.exe
does, so the copy under test has `call` inserted. That is the only edit; the step order,
the quoting, %~dp0 and every ERRORLEVEL check are the shipped ones.
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import tempfile

BS = chr(92)
ROOT = pathlib.Path(__file__).resolve().parent.parent
OPS = ROOT / "python-tools" / "daily_ops.cmd"

## (script, required argument, the token that identifies this step to the stub, and the
## label the alert must use for it). Order is the order the nightly run must make them.
EXPECTED = [
    ("insights.py", "--pull", "--pull", "pull"),
    ("insights.py", "--rank", "--rank", "rank"),
    ("auto_shoot.py", "--live", "auto_shoot", "shoot"),
    ("make_portrait.py", "", "make_portrait", "cut"),
    ("daily_post.py", "--topup", "--topup", "topup"),
    ("daily_post.py", "--verify", "--verify", "verify"),
]

STUB = (
    "@echo off\r\n"
    "echo STUB saw: %*\r\n"
    'if "%STUB_FAIL%"=="" exit /b 0\r\n'
    # findstr, not find: `echo %* | find "--pull"` matched nothing here (the piped line
    # carries a trailing space and find is fussier about the needle), so every step
    # silently "succeeded" and an earlier draft of this checker passed a wrapper whose
    # exit-code checks had been deleted.
    'echo %*| findstr /c:"%STUB_FAIL%" >nul\r\n'
    'if errorlevel 1 exit /b 0\r\n'
    "exit /b 3\r\n"
)


def check_bytes(raw: bytes) -> list[str]:
    bad = []
    if not all(c < 128 for c in raw):
        bad.append("file is not pure ASCII")
    if raw[:3] == b"\xef\xbb\xbf":
        bad.append("file has a UTF-8 BOM")
    stray = sorted({c for c in raw if c < 32 and c not in (9, 10, 13)})
    if stray:
        bad.append("stray control byte(s): " + ", ".join(hex(c) for c in stray))
    if raw.count(b"\n") != raw.count(b"\r\n"):
        bad.append("mixed line endings; cmd wants CRLF throughout")
    return bad


def check_paths(src: str) -> list[str]:
    return [f"names {s}, which does not exist"
            for s in sorted(set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*\.py)", src)))
            if not (ROOT / "python-tools" / s).is_file()]


def stub_wrapper(src: str, work: pathlib.Path) -> tuple[str, pathlib.Path, pathlib.Path]:
    stub = work / "stub_py.cmd"
    stub.write_bytes(STUB.encode("ascii"))
    log, alert = work / "ops.log", work / "ALERT.txt"
    out = src.replace("set PY=python", "set PY=" + str(stub))
    out = out.replace('"%PY%"', 'call "%PY%"')
    out = out.replace("set LOG=%REPO%" + BS + "content" + BS + "daily_post.log",
                      "set LOG=" + str(log))
    out = out.replace('"%REPO%' + BS + "content" + BS + 'ALERT.txt"', '"' + str(alert) + '"')
    if str(stub) not in out or str(log) not in out:
        raise SystemExit("check_daily_ops: could not stub the wrapper; has it been "
                         "restructured? Update this checker rather than deleting it.")
    return out, log, alert


def run(stubbed: str, log: pathlib.Path, fail_token: str) -> tuple[int, str]:
    # The copy must live beside the real one: %REPO% is derived from %~dp0.
    copy = ROOT / "python-tools" / "_daily_ops_check.cmd"
    copy.write_bytes(stubbed.encode("ascii"))
    log.unlink(missing_ok=True)
    try:
        p = subprocess.run(["cmd", "/c", str(copy)],
                           env=dict(os.environ, STUB_FAIL=fail_token),
                           capture_output=True, text=True)
    finally:
        copy.unlink(missing_ok=True)
    return p.returncode, (log.read_text("ascii", "replace") if log.exists() else "")


def main() -> int:
    if not OPS.is_file():
        print(f"DAILY OPS CHECK: FAIL - {OPS} is missing")
        return 1

    raw = OPS.read_bytes()
    src = raw.decode("ascii", "replace")
    problems = check_bytes(raw) + check_paths(src)

    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        stubbed, log, _alert = stub_wrapper(src, work)

        # (a) nothing fails: every step must run, in order, and the run must report OK.
        code, out = run(stubbed, log, "")
        saw = [ln.split("STUB saw:", 1)[1].strip()
               for ln in out.splitlines() if "STUB saw:" in ln]
        if code != 0:
            problems.append(f"with every step succeeding the run exited {code}, expected 0")
        if "OK" not in out:
            problems.append("with every step succeeding the run did not log OK")
        if len(saw) != len(EXPECTED):
            problems.append(f"ran {len(saw)} step(s), expected {len(EXPECTED)}")
        for i, (script, arg, _tok, _label) in enumerate(EXPECTED):
            got = saw[i] if i < len(saw) else ""
            if script not in got or (arg and arg not in got):
                problems.append(f"step {i + 1} should be {script} {arg}".rstrip()
                                + f", saw: {got or '(none)'}")

        # (b) ONE step fails at a time. This is the part that has teeth: an unchecked
        #     ERRORLEVEL is only visible when every OTHER step succeeds.
        for i, (script, _arg, token, label) in enumerate(EXPECTED, start=1):
            code, out = run(stubbed, log, token)
            if code != 1:
                problems.append(f"step {i} ({script} {token}) failed but the run exited "
                                f"{code}; its exit code is not being checked")
            if f"{label}=3" not in out:
                problems.append(f"step {i} ({script} {token}) failed but the alert never "
                                f"said {label}=3")

    if problems:
        print("DAILY OPS CHECK: FAIL")
        for pr in problems:
            print("  -", pr)
        return 1
    print(f"DAILY OPS CHECK: ok ({len(EXPECTED)} steps run in order; each one's failure "
          f"surfaced on its own; file bytes clean)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
