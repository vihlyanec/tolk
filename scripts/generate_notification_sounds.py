#!/usr/bin/env python3
"""Clean original notification tones, without metallic or detuned partials.

One clear upper tone, a quiet octave at the strike, and a soft muted body
two octaves below. Stable pitch, smooth attacks, no FM, echo or beating.
Deterministic mono 16-bit PCM / 44.1 kHz for native notifications.
"""
import math
from pathlib import Path
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parents[1] / 'Resources'


def render(name, length, notes):
    samples = [0.0] * round(length * RATE)
    for onset, frequency, duration, gain in notes:
        for i in range(round(duration * RATE)):
            index = round(onset * RATE) + i
            if index >= len(samples):
                break
            t = i / RATE
            attack = .5 - .5 * math.cos(math.pi * min(1, t / .006))
            release = .5 - .5 * math.cos(math.pi * min(1, (duration - t) / .080))
            phase = 2 * math.pi * frequency * t
            voice = (math.sin(phase) * math.exp(-t / .24)
                     + .045 * math.sin(phase * 2) * math.exp(-t / .065))
            # A restrained, rounded low tone adds body without extra overtones.
            body_attack = .5 - .5 * math.cos(math.pi * min(1, t / .018))
            body = .20 * math.sin(phase / 4) * math.exp(-t / .20)
            samples[index] += gain * release * (attack * voice + body_attack * body)
    for i in range(max(0, len(samples) - round(.025 * RATE)), len(samples)):
        samples[i] *= (len(samples) - 1 - i) / (.025 * RATE)
    peak = max(abs(x) for x in samples)
    data = [round(x * .40 / max(peak, .001) * 32767) for x in samples]
    with wave.open(str(ROOT / name), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(struct.pack('<' + 'h' * len(data), *data))


def main():
    # D major: D6 -> F#6, a short ascending major third.
    render('FocusStart.wav', 1.12, [(0, 1174.6591, .76, .80),
        (.20, 1479.9777, .85, .88)])
    # E minor: B5 -> E5, a lower, spacious falling response.
    render('FocusEnd.wav', 1.95, [(0, 987.7666, .95, .76),
        (.32, 659.2551, 1.20, .88)])
    # Bb major: a double Bb5 pickup resolving to D6.
    render('TaskReminder.wav', 1.48, [(0, 932.3275, .48, .74),
        (.16, 932.3275, .48, .65), (.40, 1174.6591, .95, .88)])


if __name__ == '__main__':
    main()
