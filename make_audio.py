"""Generate small original placeholder effects; no external audio assets."""
import math
import pathlib
import random
import struct
import wave

out = pathlib.Path(__file__).with_name("audio")
out.mkdir(exist_ok=True)
rng = random.Random(7)
rate = 22050
for name, duration in [("shot", .13), ("noise", .38), ("smoke", .65), ("alert", .32), ("pickup", .4)]:
    samples = []
    for i in range(int(duration * rate)):
        t = i / rate
        if name == "shot":
            sample = (rng.uniform(-1, 1) * .75 + math.sin(t * 2 * math.pi * 105) * .25) * math.exp(-t * 38)
        elif name == "noise":
            sample = (math.sin(t * 2 * math.pi * 1270) + math.sin(t * 2 * math.pi * 1980)) * .4 * math.exp(-t * 15)
        elif name == "smoke":
            sample = rng.uniform(-1, 1) * .4 * math.sin(math.pi * t / duration)
        elif name == "alert":
            sample = math.sin(t * 2 * math.pi * (440 if t < .16 else 660)) * .5 * math.sin(math.pi * t / duration)
        else:
            sample = math.sin(t * 2 * math.pi * (660 if t < .13 else 880 if t < .26 else 1100)) * .4 * math.sin(math.pi * t / duration)
        samples.append(struct.pack("<h", int(max(-1, min(1, sample)) * 20000)))
    with wave.open(str(out / f"{name}.wav"), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(rate)
        target.writeframes(b"".join(samples))
