#!/usr/bin/env python3
# 生成五秒有限提示音，使用标准PCM和短衰减双音。
from head import Path, pi, sin, pack, wavopen


# 写入工程原生音频资源，末段保留静音间隔。
def generate():
    target = Path(__file__).resolve().parent.parent / "Resources/Reminder.wav"
    with wavopen(str(target), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(16000)
        frames = bytearray()
        for sample in range(80000):
            time = sample / 16000
            phase = time % 2.5
            fade = min(1, phase / 0.025) * max(0, 1 - phase / 0.65) ** 2 if phase < 0.65 else 0
            value = 0.45 * fade * (0.65 * sin(2 * pi * 660 * time) + 0.35 * sin(2 * pi * 880 * time))
            frames.extend(pack("<h", round(value * 32767)))
        sound.writeframes(frames)


if __name__ == "__main__":
    generate()
