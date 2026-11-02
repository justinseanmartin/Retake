#!/usr/bin/env python3 -I
"""Makes the example's music and sound effects, so none of them is anyone else's recording.

Run from anywhere; writes music.m4a, tap.m4a, chime.m4a and whoosh.m4a beside this file, with
ffmpeg to encode them. Pure Python, so it's slow-ish (a few seconds) but needs nothing installed.
"""

import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 44_100
HERE = os.path.dirname(os.path.abspath(__file__))


def note(name):
    """A note's frequency, from its name, such as C4 or F#3."""
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    pitch, octave = name[:-1], int(name[-1])
    return 440 * 2 ** ((names[pitch] + 12 * (octave + 1) - 69) / 12)


def add(buffer, start, samples):
    first = int(start * RATE)
    for i, sample in enumerate(samples):
        if first + i < len(buffer):
            buffer[first + i] += sample


def tone(frequency, length, attack, decay, harmonics=(1.0,), detune=0.0):
    """A note that swells over `attack` seconds and dies away exponentially at `decay` per second."""
    out = []
    for i in range(int(length * RATE)):
        t = i / RATE
        envelope = min(1.0, t / attack) * math.exp(-decay * t)
        # A short release, so a note never ends on a click.
        envelope *= min(1.0, (length - t) / 0.05)
        sample = 0.0
        for n, level in enumerate(harmonics, start=1):
            sample += level * math.sin(2 * math.pi * frequency * n * t)
            if detune:
                sample += level * math.sin(2 * math.pi * frequency * n * (1 + detune) * t)
        out.append(envelope * sample)
    return out


def lowpass(buffer, cutoff):
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    value = 0.0
    for i, sample in enumerate(buffer):
        value += alpha * (sample - value)
        buffer[i] = value
    return buffer


def normalize(buffer, peak):
    loudest = max(abs(s) for s in buffer) or 1
    return [s * peak / loudest for s in buffer]


def music():
    """A calm 96 bpm loop, C G Am F, as pad, arpeggio and bass, 32 seconds long."""
    beat = 60 / 96
    bar = 4 * beat
    chords = [
        ["C3", "C4", "E4", "G4", "C5"],
        ["G2", "B3", "D4", "G4", "B4"],
        ["A2", "A3", "C4", "E4", "A4"],
        ["F2", "A3", "C4", "F4", "A4"],
    ]
    length = 32.0
    buffer = [0.0] * int((length + 2) * RATE)
    t, index = 0.0, 0
    while t < length:
        bass, *upper = chords[index % len(chords)]
        for name in upper[:3]:
            add(buffer, t, [0.12 * s for s in tone(note(name), 2 * bar, 0.6, 0.15, (1.0, 0.3), detune=0.003)])
        add(buffer, t, [0.35 * s for s in tone(note(bass), 2 * bar, 0.02, 0.5, (1.0, 0.5, 0.2))])
        # Eighth notes over the chord, up and back.
        pattern = upper + upper[-2:0:-1]
        for step in range(16):
            name = pattern[step % len(pattern)]
            add(buffer, t + step * beat / 2, [0.18 * s for s in tone(note(name), 0.6, 0.004, 6.0, (1.0, 0.25, 0.1))])
        t += 2 * bar
        index += 1
    return normalize(lowpass(buffer[: int(length * RATE)], 3200), 0.7)


def tap():
    return normalize(tone(1400, 0.08, 0.001, 60.0, (1.0, 0.4)), 0.6)


def chime():
    buffer = [0.0] * int(1.6 * RATE)
    add(buffer, 0.0, tone(note("E6"), 1.5, 0.002, 3.0, (1.0, 0.2, 0.08)))
    add(buffer, 0.11, tone(note("B6"), 1.4, 0.002, 3.2, (1.0, 0.2, 0.08)))
    return normalize(buffer, 0.6)


def whoosh():
    """Noise through a filter that sweeps up and back."""
    random.seed(7)
    length = 0.7
    out, value = [], 0.0
    for i in range(int(length * RATE)):
        t = i / length / RATE
        cutoff = 300 + 4000 * math.sin(math.pi * t) ** 2
        alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        value += alpha * (random.uniform(-1, 1) - value)
        out.append(value * math.sin(math.pi * t) ** 1.5)
    return normalize(out, 0.5)


def write(name, samples, bitrate):
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "sound.wav")
        with wave.open(path, "wb") as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(RATE)
            file.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
        destination = os.path.join(HERE, name)
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", path, "-c:a", "aac", "-b:a", bitrate, "-map_metadata", "-1", destination],
            check=True,
        )
        print(destination)


if __name__ == "__main__":
    write("tap.m4a", tap(), "64k")
    write("chime.m4a", chime(), "64k")
    write("whoosh.m4a", whoosh(), "64k")
    write("music.m4a", music(), "96k")
    sys.exit(0)
