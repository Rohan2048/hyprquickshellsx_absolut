#!/usr/bin/env python3
"""
mic-level.py <source> -- prints the microphone's loudness (0-100, one line every ~60 ms) until killed.
Reads raw samples with parec (PipeWire / PulseAudio), so it shows what the mic really delivers at its
current volume. 0 = silence (-60 dB or lower), 100 = full scale.
"""
import array
import math
import subprocess
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "@DEFAULT_SOURCE@"
RATE = 8000
CHUNK = RATE // 16 * 2          # ~62 ms of s16le mono
try:
    p = subprocess.Popen(["parec", "--device=" + src, "--format=s16le", "--rate=%d" % RATE, "--channels=1",
                          "--latency-msec=40"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
except FileNotFoundError:
    sys.exit(1)
try:
    while True:
        buf = p.stdout.read(CHUNK)
        if not buf:
            break
        a = array.array("h")
        a.frombytes(buf[: len(buf) // 2 * 2])
        if not a:
            continue
        rms = math.sqrt(sum(x * x for x in a) / len(a)) / 32768.0
        db = 20 * math.log10(rms) if rms > 0 else -90
        print(max(0, min(100, int(round((db + 60) / 60 * 100)))), flush=True)
finally:
    p.kill()
