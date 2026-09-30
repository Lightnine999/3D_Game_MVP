# 카드 시퀀스(스프라이트 시트) 이펙트 그림 만들기 — 입자를 실제로 뿌리지 않고 그림 한 장의 칸을 차례로 넘긴다 (용량·폰 성능)
# 실행: python3 tools/assets/make_fx_atlases.py → godot/assets/textures/fx/*.png
# 모두 이 스크립트가 수식으로 그린다 (외부 에셋 없음). 신호탄·연기는 흰색으로 그려 게임에서 초록/빨강으로 물들인다
import os, math
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "assets", "textures", "fx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(20260930)


def blob(canvas, cx, cy, r, amount, sharp=2.0):
    """canvas(H,W) 에 둥근 빛 점 하나를 더한다 (가우시안)"""
    h, w = canvas.shape
    x0, x1 = int(max(cx - r * 3, 0)), int(min(cx + r * 3 + 1, w))
    y0, y1 = int(max(cy - r * 3, 0)), int(min(cy + r * 3 + 1, h))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / max(r * r, 1e-4)
    canvas[y0:y1, x0:x1] += amount * np.exp(-d2 * sharp)


def streak(canvas, p0, p1, r, amount, steps=6):
    for k in range(steps):
        t = k / (steps - 1)
        blob(canvas, p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, r, amount * (0.4 + 0.6 * t))


def sheet(frames, cols):
    h, w = frames[0].shape[:2]
    rows = math.ceil(len(frames) / cols)
    out = np.zeros((rows * h, cols * w, 4), np.float32)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        out[r * h:(r + 1) * h, c * w:(c + 1) * w] = f
    return out


def save(arr, name):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    p = os.path.join(OUT, name)
    img.save(p, optimize=True)
    print(name, img.size, os.path.getsize(p) // 1024, "KB")


# 1) 신호탄 불꽃 (반복 16칸, 128px): 흰 심지 + 위로 뿜었다 떨어지는 불똥 + 은은한 빛무리. 더하기 섞기로 그린다
S = 128
sparks = [(rng.random(), math.radians(rng.uniform(-85, 85)), rng.uniform(40, 105), rng.uniform(0.9, 1.8)) for _ in range(130)]
frames = []
for f in range(16):
    t = f / 16
    c = np.zeros((S, S), np.float32)
    ox, oy = S * 0.5, S * 0.5
    flick = 1.0 + 0.18 * math.sin(t * math.tau * 3) + 0.08 * math.sin(t * math.tau * 7)
    blob(c, ox, oy, 34 * flick, 0.28, 1.0)              # 빛무리
    blob(c, ox, oy, 9 * flick, 0.9, 1.5)                # 심지 빛
    blob(c, ox, oy, 3.5, 1.6, 2.0)                      # 하얀 심지
    for ph, ang, spd, sz in sparks:
        u = (t + ph) % 1.0                              # 불똥마다 자기 박자 → 끝과 처음이 이어진다
        def pos(u):
            return (ox + math.sin(ang) * spd * 0.85 * u, oy - math.cos(ang) * spd * 0.8 * u + 58 * u * u)
        p1 = pos(u)
        p0 = pos(max(u - 0.05, 0))
        streak(c, p0, p1, sz, 0.55 * (1 - u) ** 1.3)
    a = np.clip(c, 0, 1)
    rgb = np.stack([np.clip(c * 1.1, 0, 1)] * 3, -1)
    frames.append(np.concatenate([rgb, a[..., None]], -1))
save(sheet(frames, 4), "fx_flare_4x4.png")

# 2) 신호탄 연기 기둥 (반복 16칸, 128x256): 뭉게뭉게 올라가며 커지고 옅어지는 연기. 보통 섞기로 그린다
W, H = 128, 256
puffs = [(i / 14 + rng.uniform(-0.02, 0.02), rng.uniform(0, math.tau), rng.uniform(0.6, 1.2)) for i in range(14)]
frames = []
for f in range(16):
    t = f / 16
    c = np.zeros((H, W), np.float32)
    for ph, sw, big in puffs:
        u = (t + ph) % 1.0
        y = H * 0.95 - u * H * 0.88
        x = W * 0.5 + math.sin(u * 5 + sw) * 10 * u + 14 * u * u
        r = (6 + 30 * u) * big
        fade = min(u / 0.12, 1.0) * (1 - u) ** 1.2
        for k in range(4):                              # 한 뭉치를 작은 덩어리 몇 개로 (뭉게뭉게)
            blob(c, x + math.cos(sw + k * 1.7) * r * 0.45, y + math.sin(sw + k * 2.3) * r * 0.3, r * 0.7, 0.35 * fade, 1.2)
    a = np.clip(c, 0, 0.85)
    rgb = np.ones((H, W, 3), np.float32) * 0.92
    frames.append(np.concatenate([rgb, a[..., None]], -1))
save(sheet(frames, 4), "fx_flare_smoke_4x4.png")

# 3) 피 튐 (한 번 16칸, 128px): 맞는 순간 핏방울이 퍼지며 떨어지고 붉은 안개가 번졌다 사라진다
drops = [(math.radians(rng.uniform(-100, 100)), rng.uniform(25, 70), rng.uniform(1.5, 4.2)) for _ in range(55)]
frames = []
for f in range(16):
    u = f / 15
    c = np.zeros((S, S), np.float32)
    ox, oy = S * 0.5, S * 0.45
    blob(c, ox, oy, 10 + 34 * u, 0.9 * (1 - u) ** 1.5, 1.0)   # 피 안개
    blob(c, ox, oy, 6 + 8 * u, 1.2 * max(1 - u * 2.2, 0), 1.6)
    for ang, spd, sz in drops:
        e = 1 - (1 - u) ** 2                                # 처음엔 빠르게, 점점 느리게
        px = ox + math.sin(ang) * spd * e
        py = oy - math.cos(ang) * spd * e * 0.8 + 55 * u * u
        blob(c, px, py, sz * (1 - 0.5 * u), 1.4 * (1 - u) ** 0.8, 1.6)
    a = np.clip(c, 0, 1)
    dark = np.clip(c, 0, 1)
    rgb = np.stack([0.42 + 0.28 * dark, 0.02 + 0.03 * dark, 0.02 + 0.02 * dark], -1)
    frames.append(np.concatenate([rgb, a[..., None]], -1))
save(sheet(frames, 4), "fx_blood_splash_4x4.png")

# 4) 바닥 핏자국 (한 장 256px): 쓰러진 좀비 밑 — 게임에서 몇 초 뒤 옅어져 사라진다 (PRD N-08)
S2 = 256
c = np.zeros((S2, S2), np.float32)
for _ in range(9):
    blob(c, S2 / 2 + rng.normal(0, 22), S2 / 2 + rng.normal(0, 16), rng.uniform(18, 38), 1.2, 1.4)
for _ in range(40):
    ang = rng.uniform(0, math.tau)
    d = rng.uniform(40, 110)
    blob(c, S2 / 2 + math.cos(ang) * d, S2 / 2 + math.sin(ang) * d * 0.8, rng.uniform(2, 7), 1.5, 1.8)
a = np.clip((c - 0.35) * 3.0, 0, 0.92)
rgb = np.stack([0.30 + 0.12 * np.clip(c, 0, 1), np.full_like(c, 0.015), np.full_like(c, 0.015)], -1)
save(np.concatenate([rgb, a[..., None]], -1), "fx_blood_pool.png")

# 5) 화면 피 (1024x512): 물릴 때 화면 가장자리에 튀는 피 — 가운데는 비워 둔다
W3, H3 = 1024, 512
c = np.zeros((H3, W3), np.float32)
for _ in range(26):
    side = rng.integers(4)
    x = rng.uniform(0, W3) if side < 2 else (rng.uniform(0, 110) if side == 2 else W3 - rng.uniform(0, 110))
    y = (rng.uniform(0, 80) if side == 0 else H3 - rng.uniform(0, 80)) if side < 2 else rng.uniform(0, H3)
    r = rng.uniform(25, 70)
    blob(c, x, y, r, 1.4, 1.3)
    for _k in range(10):
        blob(c, x + rng.normal(0, r * 1.2), y + rng.normal(0, r * 1.2), rng.uniform(3, 10), 1.4, 1.8)
    if side == 0:                                           # 위쪽에서 흘러내리는 피 줄기
        L = rng.uniform(40, 150)
        for k in range(30):
            blob(c, x + rng.normal(0, 1.5), y + L * k / 29, 5 - 3 * k / 29, 1.2, 1.5)
a = np.clip((c - 0.3) * 2.2, 0, 0.9)
rgb = np.stack([0.38 + 0.2 * np.clip(c, 0, 1), np.full_like(c, 0.01), np.full_like(c, 0.01)], -1)
save(np.concatenate([rgb, a[..., None]], -1), "fx_blood_screen.png")
