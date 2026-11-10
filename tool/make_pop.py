"""生成 90ms 的“啵”声：44.1kHz 单声道 16-bit 正弦下滑音。"""

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sfx" / "pop.wav"
SAMPLE_RATE = 44100
DURATION = 0.09
START_HZ = 900
END_HZ = 300


def main() -> None:
    count = int(SAMPLE_RATE * DURATION)
    frames = bytearray()
    phase = 0.0
    for i in range(count):
        t = i / SAMPLE_RATE
        frequency = START_HZ + (END_HZ - START_HZ) * (i / count)
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        sample = 0.6 * math.exp(-18 * t) * math.sin(phase)
        frames += struct.pack("<h", round(sample * 32767))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(bytes(frames))
    print(f"wrote {OUT} ({count} samples)")


if __name__ == "__main__":
    main()
