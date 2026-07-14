#!/usr/bin/env python3
"""Generates placeholder SFX for AL67X (Phase 10 audio pass).

Pure-stdlib synthesis (no deps): punchy, distinct placeholder sounds until
custom audio is produced. Each sound has its own audio identity so hits are
readable by ear alone (spec Section 11 hit-feel goal):
  enemy_hit  - mid "thunk" w/ click transient (hitmarker)
  enemy_die  - low pop sweep
  player_hit - harsh low crunch (you got hurt)
  blob_hit   - high squeaky pop (a Mini-Allan died)
  eat        - soft rising blip (shawarma pickup)
  ui_tap / ui_confirm / ui_error
  level_up   - small ascending arpeggio
  unlock_sting - bigger fanfare arpeggio (reveals)

Regenerate any time:  python3 tools/generate_placeholder_sfx.py
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx", "generated")
random.seed(67)


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
            for s in samples))
    print("wrote", os.path.relpath(path))


def env(i, n, attack=0.005, curve=3.0):
    t = i / n
    a = min(1.0, (i / SR) / attack) if attack > 0 else 1.0
    return a * (1.0 - t) ** curve


def sweep(dur, f0, f1, wave_fn=math.sin, curve=3.0, noise=0.0, attack=0.002):
    n = int(SR * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        phase += 2 * math.pi * f / SR
        s = wave_fn(phase)
        if noise:
            s += noise * (random.random() * 2 - 1) * (1.0 - t) ** 2
        out.append(s * env(i, n, attack, curve))
    return out


def square(p):
    return 1.0 if math.sin(p) >= 0 else -1.0


def tone(dur, freq, wave_fn=math.sin, curve=2.0, attack=0.004):
    return sweep(dur, freq, freq, wave_fn, curve, 0.0, attack)


def click(dur=0.008, amp=1.0):
    n = int(SR * dur)
    return [amp * (random.random() * 2 - 1) * (1.0 - i / n) for i in range(n)]


def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0.0 for l in layers) for i in range(n)]


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


# Hits — distinct identities.
write_wav("enemy_hit", mix(click(0.008, 0.9), sweep(0.09, 700, 250, math.sin, 4.0, 0.15)))
write_wav("enemy_die", mix(click(0.006, 0.5), sweep(0.2, 420, 70, math.sin, 3.0, 0.25)))
write_wav("player_hit", mix(click(0.012, 1.0), sweep(0.22, 170, 60, square, 2.5, 0.35)))
write_wav("blob_hit", mix(click(0.004, 0.4), sweep(0.14, 1500, 480, math.sin, 4.0, 0.1)))
write_wav("eat", sweep(0.07, 480, 850, math.sin, 2.0, 0.0))
write_wav("shield_break", mix(click(0.02, 1.0), sweep(0.24, 2400, 500, math.sin, 2.0, 0.5)))

# UI.
write_wav("ui_tap", tone(0.045, 1250, math.sin, 3.0))
write_wav("ui_confirm", concat(tone(0.06, 660), tone(0.09, 880)))
write_wav("ui_error", sweep(0.16, 150, 110, square, 1.5, 0.05))

# Splash: 10s cinematic — riser into a huge chord hit at the logo pop (~5s).
def riser(dur, f0, f1):
    n = int(SR * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * (t ** 2)
        phase += 2 * math.pi * f / SR
        amp = (t ** 1.5) * 0.7
        s_val = math.sin(phase) + 0.35 * math.sin(phase * 2.01) + 0.2 * (random.random() * 2 - 1) * t
        out.append(s_val * amp)
    return out

def chord_hit(dur, freqs):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / n
        amp = (1.0 - t) ** 1.8
        s_val = sum(math.sin(2 * math.pi * f * i / SR + j) for j, f in enumerate(freqs)) / len(freqs)
        out.append(s_val * amp)
    return out

write_wav("splash_sting", concat(
    riser(4.9, 55, 440),
    mix(chord_hit(4.5, [110, 220, 277, 330, 440]), click(0.03, 1.2))))

# Stings.
write_wav("level_up", concat(tone(0.08, 523), tone(0.08, 659), tone(0.14, 784)))
write_wav("unlock_sting", concat(
    tone(0.09, 523), tone(0.09, 659), tone(0.09, 784),
    mix(tone(0.28, 1046, math.sin, 1.5), tone(0.28, 1318, math.sin, 1.5))))

print("done")
