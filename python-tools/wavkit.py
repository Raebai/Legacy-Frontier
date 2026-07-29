"""Minimal, dependency-free WAV read/write + DSP for the combat SFX pipeline.

WHY THIS EXISTS AND NOT ffmpeg / pydub / numpy.
This machine has no ffmpeg on PATH and the project rule is "no new dependencies
unless clearly justified" (CLAUDE.md). Python 3.13 also REMOVED `audioop`, which
is what a script like this would historically have leaned on for resampling and
sample-width conversion, and the stdlib `wave` module refuses WAVE_FORMAT_EXTENSIBLE
(0xFFFE) outright -- which is the format several of the premium source packs ship.
So the RIFF parsing is done here by hand. It is ~150 lines and it removes an
install step from a pipeline the maker has to be able to re-run.

WHAT IT HANDLES on read: PCM integer 8/16/24/32-bit, IEEE float 32/64-bit, and
WAVE_FORMAT_EXTENSIBLE (resolved via the sub-format GUID's first two bytes).
Any channel count, any sample rate.

WHAT IT WRITES: 16-bit PCM mono. Game one-shots do not need 96 kHz / 24-bit /
stereo -- that is mastering headroom for a sound designer, and carrying it into
the repo would multiply asset weight by ~6x for no audible gain through a
2D game's SFX bus.
"""

from __future__ import annotations

import math
import struct
from pathlib import Path

# WAVE format tags we understand.
_FMT_PCM = 0x0001
_FMT_FLOAT = 0x0003
_FMT_EXTENSIBLE = 0xFFFE

TARGET_RATE = 44100


class WavError(Exception):
    pass


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

def read_mono(path: str | Path) -> tuple[list[float], int]:
    """Decode `path` to a mono float list in [-1, 1] plus its sample rate.

    Channels are AVERAGED rather than dropped: several source packs are true
    stereo recordings where the transient sits fractionally off-centre, and
    taking only the left channel would quietly lose level on those.
    """
    data = Path(path).read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise WavError(f"{path}: not a RIFF/WAVE file")

    fmt_tag = channels = bits = 0
    rate = 0
    payload = b""

    pos = 12
    end = len(data)
    while pos + 8 <= end:
        cid = data[pos:pos + 4]
        (size,) = struct.unpack("<I", data[pos + 4:pos + 8])
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt_tag, channels, rate, _br, _ba, bits = struct.unpack("<HHIIHH", body[:16])
            if fmt_tag == _FMT_EXTENSIBLE and len(body) >= 26:
                # The real format lives in the first two bytes of the SubFormat
                # GUID; the rest of the GUID is the fixed KSDATAFORMAT suffix.
                (fmt_tag,) = struct.unpack("<H", body[24:26])
        elif cid == b"data":
            payload = body
        # RIFF chunks are word-aligned: an odd size carries one pad byte.
        pos += 8 + size + (size & 1)

    if not payload or channels == 0 or rate == 0:
        raise WavError(f"{path}: missing fmt/data chunk")

    samples = _decode(payload, fmt_tag, bits)
    if channels > 1:
        frames = len(samples) // channels
        mono = [0.0] * frames
        inv = 1.0 / channels
        for i in range(frames):
            base = i * channels
            mono[i] = sum(samples[base:base + channels]) * inv
        samples = mono
    return samples, rate


def _decode(raw: bytes, fmt_tag: int, bits: int) -> list[float]:
    if fmt_tag == _FMT_FLOAT:
        if bits == 32:
            return list(struct.unpack("<%df" % (len(raw) // 4), raw[:len(raw) // 4 * 4]))
        if bits == 64:
            return list(struct.unpack("<%dd" % (len(raw) // 8), raw[:len(raw) // 8 * 8]))
        raise WavError(f"unsupported float width {bits}")
    if fmt_tag != _FMT_PCM:
        raise WavError(f"unsupported format tag 0x{fmt_tag:04X}")
    if bits == 8:
        # 8-bit WAV is UNSIGNED (0..255, midpoint 128) -- unlike every other width.
        return [(b - 128) / 128.0 for b in raw]
    if bits == 16:
        n = len(raw) // 2
        return [v / 32768.0 for v in struct.unpack("<%dh" % n, raw[:n * 2])]
    if bits == 24:
        n = len(raw) // 3
        out = [0.0] * n
        for i in range(n):
            b0, b1, b2 = raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]
            v = b0 | (b1 << 8) | (b2 << 16)
            if v & 0x800000:
                v -= 0x1000000
            out[i] = v / 8388608.0
        return out
    if bits == 32:
        n = len(raw) // 4
        return [v / 2147483648.0 for v in struct.unpack("<%di" % n, raw[:n * 4])]
    raise WavError(f"unsupported PCM width {bits}")


# ---------------------------------------------------------------------------
# DSP
# ---------------------------------------------------------------------------

def resample(samples: list[float], src_rate: int, dst_rate: int = TARGET_RATE) -> list[float]:
    """Linear interpolation. Adequate here because every source is 44.1-96 kHz
    going DOWN to 44.1 kHz on material that is broadband noise/impact -- the
    interpolation artefacts sit above where any of this content lives."""
    if src_rate == dst_rate or not samples:
        return samples
    ratio = src_rate / dst_rate
    out_len = int(len(samples) / ratio)
    out = [0.0] * out_len
    for i in range(out_len):
        src = i * ratio
        i0 = int(src)
        i1 = min(i0 + 1, len(samples) - 1)
        f = src - i0
        out[i] = samples[i0] * (1.0 - f) + samples[i1] * f
    return out


def find_onset(samples: list[float], rate: int, threshold: float = 0.02) -> int:
    """First sample index whose short-window peak crosses `threshold`.

    Used to strip the leading silence that library recordings carry -- if a clip
    starts with 300 ms of nothing, a gameplay one-shot fires 300 ms late, which
    reads as a broken hit rather than a quiet one.
    """
    win = max(1, rate // 200)  # 5 ms
    for start in range(0, len(samples) - win, win):
        if max(abs(v) for v in samples[start:start + win]) >= threshold:
            return max(0, start - win)
    return 0


def find_peak_window(samples: list[float], rate: int, win_s: float = 0.10) -> int:
    """Index of the loudest `win_s` window (by RMS).

    This is how a thunder crack is located inside seven minutes of rain, or the
    single usable transient inside a two-minute drone, WITHOUT being able to
    listen to the file. Coarse hop (a quarter window) keeps it fast on the
    80 MB sources.
    """
    win = max(1, int(rate * win_s))
    hop = max(1, win // 4)
    best_i, best = 0, -1.0
    for start in range(0, max(1, len(samples) - win), hop):
        acc = 0.0
        # Sub-sample the window: full RMS over 80 MB of samples is needlessly slow
        # and the answer does not change for material this broadband.
        for j in range(start, start + win, 8):
            acc += samples[j] * samples[j]
        if acc > best:
            best, best_i = acc, start
    return best_i


def fade(samples: list[float], rate: int, fade_in_s: float, fade_out_s: float) -> list[float]:
    """Equal-power-ish edges. The fade-out matters most: a clip cut mid-waveform
    produces a click on every single play, which is the cheapest way to make a
    good sample sound like a broken one."""
    n = len(samples)
    fi = min(int(rate * fade_in_s), n // 2)
    fo = min(int(rate * fade_out_s), n // 2)
    for i in range(fi):
        samples[i] *= math.sin(0.5 * math.pi * i / fi) ** 2
    for i in range(fo):
        samples[n - 1 - i] *= math.sin(0.5 * math.pi * i / fo) ** 2
    return samples


def normalise(samples: list[float], peak: float = 0.9) -> list[float]:
    """Peak-normalise. The whole roster lands at the same ceiling so that the
    per-key mix in Sfx.gd (weight trims, layer levels) is the ONLY thing setting
    relative loudness -- otherwise a quietly-recorded source silently overrides
    a deliberate mix decision."""
    m = max((abs(v) for v in samples), default=0.0)
    if m <= 1e-9:
        return samples
    g = peak / m
    return [v * g for v in samples]


def gain_db(samples: list[float], db: float) -> list[float]:
    if db == 0.0:
        return samples
    g = 10.0 ** (db / 20.0)
    return [v * g for v in samples]


# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

def write_wav16(path: str | Path, samples: list[float], rate: int = TARGET_RATE) -> int:
    """16-bit PCM mono. Returns bytes written."""
    frames = bytearray()
    for v in samples:
        # Clamp BEFORE the int cast: a normalised-to-0.9 signal cannot clip, but
        # a manual gain_db can, and a wrapped int is a full-scale click.
        iv = int(max(-1.0, min(1.0, v)) * 32767.0)
        frames += struct.pack("<h", iv)
    data = bytes(frames)
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
    hdr += b"fmt " + struct.pack("<IHHIIHH", 16, _FMT_PCM, 1, rate, rate * 2, 2, 16)
    hdr += b"data" + struct.pack("<I", len(data))
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(hdr + data)
    return len(hdr) + len(data)
