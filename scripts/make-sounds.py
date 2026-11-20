#!/usr/bin/env python3
"""Makes the reminder sounds in WaterTracker/Sounds.

They are synthesised from scratch (sine waves and filtered noise), so the app
ships no third-party audio. Run it again after changing a sound:

    python3 scripts/make-sounds.py

Output: 16-bit mono linear PCM WAV, which iOS accepts for notification sounds
(it must be shorter than 30 seconds).
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44_100
OUT = Path(__file__).resolve().parent.parent / "WaterTracker" / "Sounds"


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq_start, freq_end, seconds, decay, partials=((1, 1.0),), attack=0.004):
    """A tone that glides from freq_start to freq_end with an exponential fade."""
    n = int(RATE * seconds)
    out = []
    phase = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        freq = freq_start + (freq_end - freq_start) * (i / n)
        env = math.exp(-t * decay) * min(1.0, t / attack)
        value = 0.0
        for k, (mult, amp) in enumerate(partials):
            phase[k] += 2 * math.pi * freq * mult / RATE
            value += amp * math.sin(phase[k])
        out.append(value * env)
    return out


def mix(*tracks):
    """Overlays tracks given as (start_seconds, samples)."""
    length = max(int(start * RATE) + len(s) for start, s in tracks)
    out = [0.0] * length
    for start, samples in tracks:
        offset = int(start * RATE)
        for i, v in enumerate(samples):
            out[offset + i] += v
    return out


def normalise(samples, peak=0.8):
    top = max(abs(v) for v in samples) or 1.0
    # A short fade at the end avoids a click.
    fade = int(RATE * 0.02)
    for i in range(1, fade + 1):
        samples[-i] *= i / fade
    return [v / top * peak for v in samples]


def drop():
    # A water drop: a quick upward pitch sweep, then a softer echo.
    return mix((0.0, tone(600, 1500, 0.16, 22)), (0.22, tone(700, 1700, 0.14, 26)))


def bubbles():
    random.seed(7)
    tracks = []
    t = 0.0
    for _ in range(7):
        base = random.uniform(500, 900)
        tracks.append((t, tone(base, base * 2.2, 0.08, 40)))
        t += random.uniform(0.06, 0.12)
    return mix(*tracks)


def chime():
    # Two rising notes (E6, B6), like a soft doorbell.
    bell = ((1, 1.0), (2, 0.25), (3, 0.08))
    return mix((0.0, tone(1318.5, 1318.5, 0.9, 5, bell)), (0.16, tone(1975.5, 1975.5, 1.0, 4.5, bell)))


def bell():
    # A small bell: inharmonic partials with a long ring.
    partials = ((1, 1.0), (2.76, 0.45), (5.40, 0.2), (8.93, 0.1))
    return tone(880, 880, 1.6, 3.2, partials, attack=0.002)


def wave_sound():
    # A gentle wave: low-passed noise that swells and fades.
    random.seed(3)
    seconds = 1.8
    n = int(RATE * seconds)
    out = []
    low = 0.0
    for i in range(n):
        t = i / seconds / RATE
        env = math.sin(math.pi * t) ** 2
        cutoff = 0.02 + 0.06 * env
        low += cutoff * (random.uniform(-1, 1) - low)
        out.append(low * env)
    return out


SOUNDS = {
    "drop": drop,
    "bubbles": bubbles,
    "chime": chime,
    "bell": bell,
    "wave": wave_sound,
}


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"reminder-{name}.wav"
    data = normalise(samples + silence(0.05))
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in data))
    print(f"{path.relative_to(OUT.parent.parent)}: {len(data) / RATE:.2f} s")


if __name__ == "__main__":
    for name, make in SOUNDS.items():
        write(name, make())
