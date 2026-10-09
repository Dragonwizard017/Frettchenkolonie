#!/usr/bin/env python3
"""Synthetisiert die UI-Sounds (eigene Synthese, keine fremden Samples -> keine Lizenzfragen).
Warm/holzig: Sinus + leichte Obertöne, kurze Hüllkurven, minimaler Rausch-Transient."""
import numpy as np, wave, os
SR = 44100
OUT = "/home/claude/w/assets/sfx"
rng = np.random.default_rng(7)

def t(dur): return np.arange(int(SR * dur)) / SR
def env(n, attack=0.003, tau=0.05):
    x = np.arange(n) / SR
    a = np.minimum(1.0, x / max(attack, 1e-4))
    return a * np.exp(-x / tau)
def tone(freq, dur, tau, harm=(1.0, 0.35, 0.12), attack=0.003, glide=None):
    x = t(dur)
    f = np.full_like(x, freq) if glide is None else np.linspace(freq, glide, len(x))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = sum(h * np.sin((i + 1) * ph) for i, h in enumerate(harm))
    return y * env(len(x), attack, tau)
def click_noise(dur=0.004, lvl=0.25):
    x = t(dur); return rng.standard_normal(len(x)) * np.exp(-x / (dur / 3)) * lvl
def mix(*parts):
    n = max(len(p) for p in parts); out = np.zeros(n)
    for p in parts: out[:len(p)] += p
    return out
def seq(notes, gap=0.0):
    out = np.zeros(0)
    for n in notes:
        out = np.concatenate([out, n, np.zeros(int(SR * gap))])
    return out
def lowpass(y, k=0.35):
    out = np.zeros_like(y); a = 0.0
    for i, v in enumerate(y): a += k * (v - a); out[i] = a
    return out
def save(name, y, peak=0.8):
    y = y / (np.max(np.abs(y)) + 1e-9) * peak
    fade = int(0.004 * SR); y[-fade:] *= np.linspace(1, 0, fade)
    pcm = (y * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    print(name, len(pcm) / SR, "s")

# Klick: kurzer "Holz-Tap"
save("ui_click", mix(tone(620, 0.09, 0.016, (1, 0.5, 0.2)), tone(930, 0.07, 0.010, (1, 0.2)) * 0.5, click_noise()), 0.7)
# Hover: sehr leises, feines Ticken
save("ui_hover", tone(1480, 0.04, 0.007, (1, 0.15)) * 0.9, 0.35)
# Fenster öffnen: sanft aufsteigend
save("ui_open", mix(tone(430, 0.19, 0.07, glide=640), tone(860, 0.17, 0.05, (1, 0.2), glide=1280) * 0.35), 0.62)
# Fenster schließen: sanft absteigend
save("ui_close", mix(tone(640, 0.17, 0.06, glide=400), tone(1280, 0.15, 0.04, (1, 0.2), glide=800) * 0.30), 0.58)
# Schalter an/aus
save("ui_toggle_on", seq([tone(560, 0.07, 0.025), tone(840, 0.10, 0.04)]), 0.6)
save("ui_toggle_off", seq([tone(840, 0.07, 0.025), tone(560, 0.10, 0.04)]), 0.55)
# Auswahl (Dropdown etc.)
save("ui_select", mix(tone(700, 0.10, 0.03), click_noise(0.003, 0.15)), 0.6)
# Regler-Tick
save("ui_tick", mix(tone(1100, 0.03, 0.006, (1, 0.3)), click_noise(0.002, 0.2)), 0.45)
# Fehler/Verweigert: dumpfer Doppel-Brummer
buzz = lambda f: lowpass(np.sign(np.sin(2 * np.pi * f * t(0.09))) * env(int(SR * 0.09), 0.004, 0.05), 0.12)
save("ui_error", seq([buzz(170), buzz(150)], 0.03), 0.6)
# Bestätigung: aufsteigender Dreiklang
save("ui_confirm", seq([tone(523, 0.09, 0.04), tone(659, 0.09, 0.04), tone(784, 0.18, 0.09)]), 0.6)
# Laden fertig: heller Glockenton
save("ui_done", mix(tone(660, 0.45, 0.16, (1, 0.4, 0.2)), tone(990, 0.40, 0.13, (1, 0.25)) * 0.6, tone(1320, 0.30, 0.09, (1, 0.1)) * 0.35), 0.7)
