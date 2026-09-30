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
    # 총성 3가지 — 쏠 때마다 다른 소리(sfx_pistol_random.tres 가 무작위로 고름). 합성 총성 + 슬라이드 철컥 + 탄피 떨어지는 소리
    # (-1 dB 는 압축 뒤 순간값이 1.0 을 넘어 -3 dB) (받은 녹음은 라이선스가 불분명해 쓰지 않음)
    "sfx_pistol":        {"synth": "pistol", "seed": 7, "boom": 180, "peak_db": -3, "bitrate": 96000,
                          "mix": [{"src": "kenney_rpg-audio/Audio/metalLatch.ogg", "at": 0.035, "gain": 0.22, "pitch": 1.3},
                                  {"src": "kenney_impact-sounds/Audio/impactMetal_light_000.ogg", "at": 0.42, "gain": 0.55, "pitch": 1.8},
                                  {"src": "kenney_impact-sounds/Audio/impactMetal_light_002.ogg", "at": 0.55, "gain": 0.3, "pitch": 2.0}]},
    "sfx_pistol_2":      {"synth": "pistol", "seed": 11, "boom": 165, "peak_db": -3, "bitrate": 96000,
                          "mix": [{"src": "kenney_rpg-audio/Audio/metalLatch.ogg", "at": 0.03, "gain": 0.2, "pitch": 1.4},
                                  {"src": "kenney_impact-sounds/Audio/impactMetal_light_001.ogg", "at": 0.38, "gain": 0.55, "pitch": 1.9},
                                  {"src": "kenney_impact-sounds/Audio/impactMetal_light_003.ogg", "at": 0.5, "gain": 0.3, "pitch": 2.1}]},
    "sfx_pistol_3":      {"synth": "pistol", "seed": 23, "boom": 195, "peak_db": -3, "bitrate": 96000,
                          "mix": [{"src": "kenney_rpg-audio/Audio/metalLatch.ogg", "at": 0.04, "gain": 0.24, "pitch": 1.2},
                                  {"src": "kenney_impact-sounds/Audio/impactMetal_light_004.ogg", "at": 0.45, "gain": 0.55, "pitch": 1.7}]},
    "sfx_step":          {"src": "kenney_impact-sounds/Audio/footstep_grass_000.ogg", "peak_db": -12},  # 0.36초마다 반복돼 -6 dB 는 배경음을 덮었다 (시뮬레이션)
    "sfx_breath":        {"src": "oga_breathing_tired.wav", "peak_db": -8},
    "sfx_empty_click":   {"src": "kenney_rpg-audio/Audio/metalClick.ogg", "peak_db": -6},
    # 좀비 신음 4가지 — 음산하게 (음 낮춤 + 한 옥타브 아래 목울림 + 떨림 + 고음 깎기 + 들판 잔향). sfx_zombie_groan_random.tres 가 무작위로
    "sfx_zombie_groan":   {"src": "oga_zombies/zombies/zombie-16.wav", "pitch": 0.8, "peak_db": -3, "bitrate": 80000,   # 가장 낮고 긴 소리
                           "mix": [{"src": "oga_zombies/zombies/zombie-16.wav", "pitch": 0.5, "at": 0.03, "gain": 0.45}],
                           "eerie": {"tremolo": 7.0, "depth": 0.3, "cutoff": 3200, "reverb": 0.35}},
    "sfx_zombie_groan_2": {"src": "oga_zombies/zombies/zombie-17.wav", "pitch": 0.75, "peak_db": -3, "bitrate": 80000,
                           "mix": [{"src": "oga_zombies/zombies/zombie-17.wav", "pitch": 0.48, "at": 0.04, "gain": 0.4}],
                           "eerie": {"tremolo": 5.5, "depth": 0.35, "cutoff": 3000, "reverb": 0.4}},
    "sfx_zombie_groan_3": {"src": "oga_zombies/zombies/zombie-18.wav", "pitch": 0.72, "peak_db": -3, "bitrate": 80000,
                           "mix": [{"src": "oga_zombies/zombies/zombie-16.wav", "pitch": 0.55, "at": 0.1, "gain": 0.35}],
                           "eerie": {"tremolo": 8.5, "depth": 0.28, "cutoff": 3400, "reverb": 0.35}},
    "sfx_zombie_groan_4": {"src": "oga_zombies/zombies/zombie-21.wav", "pitch": 0.7, "peak_db": -3, "bitrate": 80000,
                           "mix": [{"src": "oga_zombies/zombies/zombie-21.wav", "pitch": 0.45, "at": 0.05, "gain": 0.4}],
                           "eerie": {"tremolo": 6.5, "depth": 0.32, "cutoff": 2800, "reverb": 0.45}},
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


def load_mono(path, pitch=1.0):
    s = aud.Sound(os.path.join(SRC, path))
    if pitch != 1.0:
        s = s.pitch(pitch)                             # 높게 = 작은 물체 (탄피)
    s = s.resample(RATE, False)
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


def synth_pistol(seed=7, boom_hz=180):
    """권총 소리 합성: 파열음(딱) + 몸통(쿵) + 들판 잔향 + 메아리 두 번. 난수 고정이라 매번 같다.
    seed·boom_hz 를 바꾸면 조금씩 다른 총성이 된다 (연사할 때 똑같이 들리지 않게)."""
    rng = np.random.default_rng(seed)
    n = int(RATE * 0.9)
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n).astype(np.float32)
    crack = np.diff(noise, prepend=0.0) * np.exp(-t / 0.004) * (t < 0.02)            # 날카로운 파열음
    crack = lowpass(crack, 7000) * 2.0                                                 # 7 kHz 위를 깎아 압축 때 튀지 않게
    freq = 60 + (boom_hz - 60) * np.exp(-t / 0.03)                                    # boom_hz → 60 Hz
    boom = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t / 0.06) * 0.9       # 낮게 떨어지는 쿵
    thud = lowpass(noise * np.exp(-t / 0.08), 900) * 2.5                               # 둔한 폭발 잡음
    tail = lowpass(noise * np.exp(-t / 0.3), 1800) * 0.35                              # 들판 잔향
    x = crack * 0.9 + boom + thud + tail
    for delay, gain in ((0.12, 0.25), (0.26, 0.12)):                                   # 멀리서 돌아오는 메아리
        d = int(RATE * delay)
        x[d:] += lowpass(x[:-d] * gain, 1200)
    return np.tanh(x * 1.6).astype(np.float32)                                         # 살짝 거칠게


def reverb(x, wet, tail=1.3):
    """들판 잔향 (Schroeder: 빗살 필터 4개 + 올패스 2개). wet = 잔향 비율, tail = 꼬리 길이(초)."""
    n = len(x) + int(RATE * tail)
    dry = np.zeros(n, dtype=np.float32)
    dry[:len(x)] = x
    out = np.zeros(n, dtype=np.float32)
    for ms, fb in ((29.7, 0.80), (37.1, 0.79), (41.1, 0.78), (43.7, 0.77)):
        d = int(RATE * ms / 1000)
        y = dry.copy()
        for i in range(d, n):                             # y[i] = x[i] + fb·y[i-d]
            y[i] += fb * y[i - d]
        out += y * 0.25
    for ms, g in ((5.0, 0.7), (1.7, 0.7)):
        d = int(RATE * ms / 1000)
        y = np.zeros(n, dtype=np.float32)
        for i in range(n):
            xd = out[i - d] if i >= d else 0.0
            yd = y[i - d] if i >= d else 0.0
            y[i] = -g * out[i] + xd + g * yd
        out = y
    out = lowpass(out, 2500)                               # 멀리서 울리는 소리는 둔하다
    return dry * (1 - wet) + out * wet * 2.2


def eerie(x, e):
    """음산하게: 떨림(꾸르륵) → 고음 깎기 → 들판 잔향."""
    t = np.arange(len(x)) / RATE
    wob = 1 - e.get("depth", 0.3) * (0.5 + 0.5 * np.sin(2 * np.pi * e.get("tremolo", 7.0) * t + np.sin(2 * np.pi * 1.3 * t)))
    x = (x * wob).astype(np.float32)
    x = lowpass(x, e.get("cutoff", 3200))
    return reverb(x, e.get("reverb", 0.35))


def build(name, r):
    x = synth_pistol(r.get("seed", 7), r.get("boom", 180)) if r.get("synth") == "pistol" else load_mono(r["src"], r.get("pitch", 1.0))
    if "start" in r or "end" in r:
        x = x[int(r.get("start", 0) * RATE): int(r["end"] * RATE) if "end" in r else None]
    x = trim_silence(x)
    mixes = r.get("mix", [])
    for m in (mixes if isinstance(mixes, list) else [mixes]):             # 여러 소리를 정해진 시각에 겹친다
        y = trim_silence(load_mono(m["src"], m.get("pitch", 1.0))) * m.get("gain", 1.0)
        off = int(m.get("at", 0) * RATE)
        out = np.zeros(max(len(x), off + len(y)), dtype=np.float32)
        out[:len(x)] += x
        out[off:off + len(y)] += y
        x = out
    if "eerie" in r:
        x = eerie(x, r["eerie"])
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
        r.get("src", "직접 합성").split("/")[-1],
        "".join(" + " + m["src"].split("/")[-1] for m in (r["mix"] if isinstance(r.get("mix"), list) else [r["mix"]] if "mix" in r else []))))


def main():
    want = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(RECIPES)
    os.makedirs(OUT, exist_ok=True)
    for name in want:
        build(name, RECIPES[name])


main()
