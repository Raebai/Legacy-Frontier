@echo off
REM ===================================================================
REM STICKSPIRE daily ops. Registered by install_daily_task.ps1.
REM
REM THIS DOES NOT POST. It refills a queue that the VENDOR posts from.
REM A local task that posted was built once and deleted (commit 7060ac3)
REM because it needed the laptop awake, plugged in and logged on at the
REM same minute every day, and failed silently otherwise. This one only
REM tops the queue back up to 30 days, so it can miss two weeks of runs
REM without costing a single post.
REM
REM WARNING: PURE ASCII, NO BOM, NOTHING CLEVER. cmd.exe reads a .cmd in
REM the console OEM codepage, not UTF-8. An earlier wrapper carried the
REM same em dashes and warning glyphs as the rest of the repo, the bytes
REM mangled, several REM lines stopped being REM lines, and cmd tried to
REM execute the fragments - seven "'M' is not recognized" errors before
REM it reached the python line by luck. A batch file is not a source file.
REM ===================================================================
setlocal
set REPO=%~dp0..
set LOG=%REPO%\content\daily_post.log
set PY=python

echo. >> "%LOG%"
echo ==== %DATE% %TIME% ==== >> "%LOG%"

REM 1. Snapshot what the posts have done. Read-only; builds the history
REM    that makes "views at 72 hours old" comparable between posts.
"%PY%" "%REPO%\python-tools\insights.py" --pull >> "%LOG%" 2>&1

REM 2. Re-rank the unposted clips from what that history says, and write
REM    content/queue_order.json for step 3 to drain in.
"%PY%" "%REPO%\python-tools\insights.py" --rank --apply >> "%LOG%" 2>&1

REM 3. Top the clip pool back up. Refuses to run while Godot is open,
REM    MEASURES every render before keeping it (a null renderer writes
REM    a valid-looking black rectangle), and deletes anything that fails
REM    inspection or the fight-quality gate.
"%PY%" "%REPO%\python-toolsuto_shoot.py" --live --max 3 >> "%LOG%" 2>&1

REM 4. Give any newly shot clip its 9:16 cut, so YouTube keeps getting
REM    Shorts without anybody having to remember. Clips that already
REM    have one are skipped, so this is a no-op on most days.
"%PY%" "%REPO%\python-tools\make_portrait.py" >> "%LOG%" 2>&1

REM 5. Fill every unqueued day in the next 30. Idempotent: a second run
REM    finds no gaps and sends nothing, which is what makes it safe here.
"%PY%" "%REPO%\python-tools\daily_post.py" --topup 30 --live >> "%LOG%" 2>&1
set TOPUP=%ERRORLEVEL%

REM 6. Ask whether the posts that were due have actually gone out. This
REM    is the only step that can detect a silent vendor-side failure.
"%PY%" "%REPO%\python-tools\daily_post.py" --verify >> "%LOG%" 2>&1
set VERIFY=%ERRORLEVEL%

if not "%TOPUP%"=="0" goto problem
if not "%VERIFY%"=="0" goto problem
echo OK >> "%LOG%"
endlocal
exit /b 0

:problem
echo NEEDS ATTENTION topup=%TOPUP% verify=%VERIFY% >> "%LOG%"
REM Leave a file the next session will see. There is no mail server here
REM and a toast on a locked laptop is a notification nobody receives.
echo %DATE% %TIME% topup=%TOPUP% verify=%VERIFY% - see content\daily_post.log > "%REPO%\content\ALERT.txt"
endlocal
exit /b 1
