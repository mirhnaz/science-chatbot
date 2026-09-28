# The launch video's music (music.wav), generated here so it needs no
# licence: a soft pad with twinkles for the night-sky opening, a bright chord
# on the logo, then gentle plucked arpeggios over C–G–Am–F, ending on C.
import math, random, struct, wave

RATE, LENGTH = 44100, 54.0
N = int(RATE * LENGTH)
buf = [0.0] * N
random.seed(7)
freq = lambda midi: 440.0 * 2 ** ((midi - 69) / 12)

def note(start, dur, midi, amp, attack=0.005, decay=None, harmonics=((1, 1.0),)):
    """Adds a note; `decay` (s) makes it a pluck, else a held tone with a soft release."""
    f = freq(midi)
    i0, i1 = int(start * RATE), min(N, int((start + dur) * RATE))
    for i in range(max(0, i0), i1):
        t = (i - i0) / RATE
        env = min(1.0, t / attack)
        env *= math.exp(-t / decay) if decay else min(1.0, (dur - t) / 0.4)
        s = sum(a * math.sin(2 * math.pi * f * h * t) for h, a in harmonics)
        buf[i] += amp * env * s

def pad(start, dur, midis, amp):
    for m in midis:
        note(start, dur, m, amp, attack=1.2, harmonics=((1, 1.0), (2, 0.15)))
        note(start, dur, m + 0.07, amp * 0.5, attack=1.2)   # a slight detune for warmth

# Night sky (0–10 s): an airy Am(add9) pad and random twinkles.
pad(0.0, 10.4, [57, 64, 71, 72], 0.045)
for k in range(22):
    note(0.6 + k * 0.42 + random.uniform(-0.1, 0.1), 1.6, random.choice([84, 86, 88, 91, 93, 96]), 0.035, decay=0.45, harmonics=((1, 1.0), (3, 0.2)))

# Logo (10 s): a bright C major chord, bell-like.
for m in [60, 64, 67, 72, 76, 79]:
    note(10.0, 3.0, m, 0.05, decay=1.1, harmonics=((1, 1.0), (2, 0.3), (4, 0.08)))

# Main section (10.8–51.6 s): 100 bpm, one chord per bar.
beat = 0.6
chords = [[60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60]]      # C G Am F
patterns = [[0, 1, 2, 3, 2, 1, 2, 3], [0, 2, 1, 3, 2, 3, 1, 2]]
t, bar = 10.8, 0
while t < 51.6:
    c = chords[bar % 4]
    pad(t, beat * 4 + 0.3, [m + 12 for m in c], 0.022)
    note(t, beat * 4, c[0] - 12, 0.07, attack=0.02, harmonics=((1, 1.0), (2, 0.25)))   # bass
    tones = [c[0] + 12, c[1] + 12, c[2] + 12, c[0] + 24]
    for j, idx in enumerate(patterns[(bar // 4) % 2]):
        when = t + j * beat / 2
        if when >= 51.6:
            break
        note(when, 0.9, tones[idx], 0.05 if j % 2 == 0 else 0.038, decay=0.28, harmonics=((1, 1.0), (2, 0.35), (3, 0.1)))
    t += beat * 4
    bar += 1

# End card (51.6 s): C major rings out.
for m in [48, 60, 64, 67, 72, 76]:
    note(51.6, 2.4, m, 0.05, decay=1.3, harmonics=((1, 1.0), (2, 0.2)))

# Fade in and out, normalise to −3 dB, and write 16-bit mono.
for i in range(N):
    t = i / RATE
    buf[i] *= min(1.0, t / 1.5) * min(1.0, (LENGTH - t) / 1.2)
peak = max(abs(x) for x in buf) or 1.0
gain = 0.707 / peak
with wave.open('music.wav', 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x * gain)) * 32767)) for x in buf))
print('wrote music.wav')
