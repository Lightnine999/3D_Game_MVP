"""효과음 원본(CC0)을 게임용 효과음으로 정리한다 — TECH_SPEC 13.3.1 ①-5 `godot/assets/audio/sfx_<이름>.ogg`
Blender 에 들어 있는 오디오 도구(aud)와 numpy 만 쓴다.

사용:
  blender -b --factory-startup --python art/blender/make_sfx.py            # 표(RECIPES)에 있는 것 전부
  blender -b --factory-startup --python art/blender/make_sfx.py -- sfx_knife sfx_bite   # 일부만

하는 일 (소리마다):
  1. 한 채널(mono)로 합친다 — 3D 공간에서 소리 방향을 들려주려면 mono 여야 한다
  2. (start, end) 가 있으면 그 구간만 쓴다
  3. 앞뒤 조용한 부분을 잘라낸다 (최고값보다 40 dB 작은 부분)
  4. mix 가 있으면 다른 소리를 겹친다 (예: 물림 = 좀비 소리 + 살 부딪는 소리)
  5. 최고 크기를 peak_db 로 맞춘다 (종류마다 다르게 — 발소리는 작게, 비명은 크게)
  6. 끝을 20 ms 동안 줄여 딸깍 소리를 막는다
  7. Ogg Vorbis mono 44.1 kHz 로 저장한다
"""
import os
import sys

import aud
import numpy as np

SRC = "art/source/audio/sfx"
OUT = "godot/assets/audio"
RATE = 44100

# 이름: 원본, 최고 크기(dBFS), 그 밖의 설정 — 원본은 모두 CC0 (ASSETS_LICENSE.md)
RECIPES = {
    # 게임 효과음 (B 가 재생, SFX 버스)
    "sfx_pistol":        {"synth": "pistol", "peak_db": -3, "bitrate": 96000},   # 직접 합성 (-1 dB 는 압축 뒤 순간값이 1.0 을 넘어 -3 dB) (받은 녹음은 라이선스가 불분명해 쓰지 않음)
    "sfx_step":          {"src": "kenney_impact-sounds/Audio/footstep_grass_000.ogg", "peak_db": -12},  # 0.36초마다 반복돼 -6 dB 는 배경음을 덮었다 (시뮬레이션)
    "sfx_breath":        {"src": "oga_breathing_tired.wav", "peak_db": -8},
    "sfx_empty_click":   {"src": "kenney_rpg-audio/Audio/metalClick.ogg", "peak_db": -6},
    "sfx_zombie_groan":  {"src": "oga_zombies/zombies/zombie-16.wav", "peak_db": -3},   # 가장 낮고 긴 소리 (1.44초, 밝기 890 Hz)
    "sfx_zombie_scream": {"src": "oga_zombies/zombies/zombie-10.wav", "peak_db": -1},   # 크고 밝은 소리 (-13.3 dB, 1885 Hz)
    "sfx_supply_pickup": {"src": "kenney_rpg-audio/Audio/handleCoins.ogg", "peak_db": -4},  # 탄약이 짤랑이는 느낌
    "sfx_knife":         {"src": "kenney_rpg-audio/Audio/knifeSlice.ogg", "peak_db": -3},
    "sfx_bite":          {"src": "oga_zombies/zombies/zombie-24.wav", "peak_db": -2,      # 가장 짧은 좀비 소리 (0.33초)
                          "mix": {"src": "kenney_impact-sounds/Audio/impactSoft_heavy_000.ogg", "at": 0.02, "gain": 0.8}},
    "sfx_hit_obstacle":  {"src": "kenney_impact-sounds/Audio/impactMetal_heavy_000.ogg", "peak_db": -2},  # 폐차·드럼통
    # UI 효과음 (C 가 재생, UI 버스)
    "sfx_ui_click":      {"src": "kenney_interface-sounds/Audio/click_001.ogg", "peak_db": -8},
    "sfx_ui_purchase":   {"src": "kenney_interface-sounds/Audio/confirmation_001.ogg", "peak_db": -6},
    "sfx_mission_done":  {"src": "kenney_interface-sounds/Audio/confirmation_004.ogg", "peak_db": -4},
}


def load_mono(path):
    s = aud.Sound(os.path.join(SRC, path)).resample(RATE, False)
    d = s.data()
    return (d.mean(axis=1) if d.ndim > 1 else d).astype(np.float32)


def trim_silence(x, below_db=40.0):
    thr = np.max(np.abs(x)) * 10 ** (-below_db / 20)
    idx = np.where(np.abs(x) > thr)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(RATE * 0.005))            # 앞은 5 ms 여유
    b = min(len(x), idx[-1] + int(RATE * 0.03))        # 뒤는 30 ms 여유 (울림 꼬리)
    return x[a:b]


def lowpass(x, cutoff):
    """한 단 저역 필터 (높은 소리를 깎아 둔하게)."""
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def synth_pistol():
    """권총 소리 합성: 파열음(딱) + 몸통(쿵) + 들판 잔향 + 메아리 두 번. 난수 고정이라 매번 같다."""
    rng = np.random.default_rng(7)
    n = int(RATE * 0.9)
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n).astype(np.float32)
    crack = np.diff(noise, prepend=0.0) * np.exp(-t / 0.004) * (t < 0.02)            # 날카로운 파열음
    crack = lowpass(crack, 7000) * 2.0                                                 # 7 kHz 위를 깎아 압축 때 튀지 않게
    freq = 60 + 120 * np.exp(-t / 0.03)                                               # 180 Hz → 60 Hz
    boom = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t / 0.06) * 0.9       # 낮게 떨어지는 쿵
    thud = lowpass(noise * np.exp(-t / 0.08), 900) * 2.5                               # 둔한 폭발 잡음
    tail = lowpass(noise * np.exp(-t / 0.3), 1800) * 0.35                              # 들판 잔향
    x = crack * 0.9 + boom + thud + tail
    for delay, gain in ((0.12, 0.25), (0.26, 0.12)):                                   # 멀리서 돌아오는 메아리
        d = int(RATE * delay)
        x[d:] += lowpass(x[:-d] * gain, 1200)
    return np.tanh(x * 1.6).astype(np.float32)                                         # 살짝 거칠게


def build(name, r):
    x = synth_pistol() if r.get("synth") == "pistol" else load_mono(r["src"])
    if "start" in r or "end" in r:
        x = x[int(r.get("start", 0) * RATE): int(r["end"] * RATE) if "end" in r else None]
    x = trim_silence(x)
    if "mix" in r:
        m = r["mix"]
        y = trim_silence(load_mono(m["src"])) * m.get("gain", 1.0)
        off = int(m.get("at", 0) * RATE)
        out = np.zeros(max(len(x), off + len(y)), dtype=np.float32)
        out[:len(x)] += x
        out[off:off + len(y)] += y
        x = out
    x = x / max(np.max(np.abs(x)), 1e-9) * 10 ** (r["peak_db"] / 20)
    n_in, n_out = int(RATE * 0.003), min(len(x) // 4, int(RATE * 0.02))
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    path = os.path.join(OUT, name + ".ogg")
    aud.Sound.buffer(x.reshape(-1, 1), RATE).write(
        path, RATE, aud.CHANNELS_MONO, aud.FORMAT_S16, aud.CONTAINER_OGG, aud.CODEC_VORBIS, r.get("bitrate", 64000))
    rms = float(np.sqrt(np.mean(x ** 2)))
    print("MAKE_SFX %-18s %5.2f초  최고 %5.1f dB  평균 %6.1f dB  %5.1f KB  <- %s%s" % (
        name, len(x) / RATE, r["peak_db"], 20 * np.log10(max(rms, 1e-9)), os.path.getsize(path) / 1024,
        r.get("src", "직접 합성").split("/")[-1], " + " + r["mix"]["src"].split("/")[-1] if "mix" in r else ""))


def main():
    want = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(RECIPES)
    os.makedirs(OUT, exist_ok=True)
    for name in want:
        build(name, RECIPES[name])


main()
