"""스테이지 v2 질감·하늘 생성 (A 소유) — 새 콘셉트: 분홍 노을 + 차가운 청회색 안개 + 폐허 마을

만드는 파일 (godot/assets/textures/v2/)
- sky_v2.png        : 하늘 파노라마 (분홍·붉은 구름, 안개 속 산 능선) 4096x2048 정거방위
- grass_v2.png      : 어두운 올리브·마른 갈색 풀 카드 (RGBA)
- bush_v2.png       : 잔가지 덤불 카드 (RGBA)
- planks.png        : 낡은 회색 나무판자 (이음매 없이 반복)
- rust.png          : 녹슨 금속 (반복)
- concrete.png      : 얼룩진 콘크리트 (반복)
- chainlink.png     : 철조망 (RGBA, 반복)
- fire.png, smoke.png : 불꽃·연기 입자 (RGBA)

⚠️ SKY 아랫부분·FOG 색은 Godot 안개 색(scripts/stage/stage_builder_v2.gd FOG_COLOR)과 같게 맞춘다.
실행: python3 tools/assets/make_stage_textures_v2.py godot/assets/textures/v2
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

FOG = np.array([112, 121, 130], dtype=np.float32)        # 차가운 청회색 안개
CLOUD_PINK = np.array([214, 128, 118], dtype=np.float32)
CLOUD_DARK = np.array([92, 66, 72], dtype=np.float32)
MOUNTAIN = np.array([74, 80, 90], dtype=np.float32)


def tile_noise(size, scale, seed):
    """이음매 없이 반복되는 부드러운 노이즈 (0-1). 주파수 영역에서 저역 통과."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx ** 2 + fy ** 2)
    spectrum = np.fft.fft2(white) * np.exp(-(f * size / scale) ** 2)
    n = np.real(np.fft.ifft2(spectrum))
    return (n - n.min()) / (n.max() - n.min() + 1e-9)


def fbm(size, seed, octaves=(4, 12, 40, 120), weights=(0.5, 0.25, 0.15, 0.1)):
    return sum(w * tile_noise(size, s, seed + i) for i, (s, w) in enumerate(zip(octaves, weights)))


def save_rgb(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(OUT / name)


# ── 나무판자 (가로 판자, 판자마다 색 차이, 나뭇결, 틈) ─────────────
def planks(size=1024, boards=8, seed=1):
    rng = random.Random(seed)
    grain = tile_noise(size, 200, seed)[:, :] * 0.6 + fbm(size, seed + 5) * 0.4
    img = np.zeros((size, size, 3), np.float32)
    bh = size // boards
    base = np.array([88, 86, 82], np.float32)
    for k in range(boards):
        tint = rng.uniform(0.75, 1.15)
        warm = np.array([rng.uniform(-4, 8), rng.uniform(-3, 3), rng.uniform(-6, 2)])
        rows = slice(k * bh, (k + 1) * bh)
        # 나뭇결: 가로로 길게 늘인 노이즈
        g = np.roll(grain[rows], rng.randint(0, size), axis=1)
        streak = np.repeat(tile_noise(size, 900, seed + k)[k * bh:(k + 1) * bh, :1], size, axis=1)
        shade = (0.72 + 0.45 * g + 0.15 * streak)[:, :, None]
        img[rows] = (base * tint + warm) * shade
        img[k * bh:k * bh + 3] *= 0.35                                   # 판자 사이 틈
        img[k * bh + 3:k * bh + 6] *= 1.12                               # 틈 아래 모서리 빛
    stains = fbm(size, seed + 9)[:, :, None]
    img *= 0.7 + 0.45 * stains                                            # 물때 얼룩
    for _ in range(26):                                                   # 못 자국
        x, y = rng.randrange(size), rng.randrange(boards) * bh + bh // 2
        img[y - 2:y + 3, x - 2:x + 3] *= 0.4
    save_rgb(img, "planks.png")


def rust(size=1024, seed=2):
    n1 = fbm(size, seed)
    n2 = tile_noise(size, 60, seed + 3)
    blot = np.clip((n1 - 0.28) * 2.6, 0, 1)[:, :, None]   # 녹이 대부분 덮도록 (콘셉트의 갈색 폐차)
    dark = np.array([48, 28, 20], np.float32)
    orange = np.array([150, 70, 30], np.float32)
    paint = np.array([80, 78, 70], np.float32)                            # 벗겨진 옛 페인트
    img = paint * (1 - blot) + (dark * (1 - n2[:, :, None]) + orange * n2[:, :, None]) * blot
    img *= (0.75 + 0.4 * tile_noise(size, 300, seed + 7))[:, :, None]
    save_rgb(img, "rust.png")


def concrete(size=1024, seed=3):
    n = fbm(size, seed)
    speck = tile_noise(size, 400, seed + 4)
    img = np.array([118, 118, 116], np.float32) * (0.7 + 0.35 * n)[:, :, None]
    img *= (0.9 + 0.2 * speck)[:, :, None]
    streak = np.repeat(tile_noise(size, 50, seed + 6)[:1, :], size, axis=0)   # 위에서 흘러내린 얼룩
    img *= (0.8 + 0.25 * streak)[:, :, None]
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    rng = random.Random(seed)
    for _ in range(14):                                                   # 금
        x, y = rng.randrange(size), rng.randrange(size)
        pts = [(x, y)]
        for _ in range(rng.randint(4, 9)):
            x += rng.randint(-40, 40); y += rng.randint(10, 50)
            pts.append((x % size, y % size))
        d.line(pts, fill=(58, 58, 58), width=2)
    im.save(OUT / "concrete.png")


# ── 풀·덤불 카드 ──────────────────────────────────────────────────
def grass_card(size=512, seed=7):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 풀잎 뿌리는 가운데 좁은 곳에 모으고 끝은 바깥으로 퍼지게 (부채꼴 포기) → 카드가 사각형으로 보이지 않는다
    for _ in range(110):
        x0 = rnd.gauss(0.5, 0.07) * size
        h = rnd.uniform(0.3, 0.97) * size
        spread = (x0 / size - 0.5) * rnd.uniform(2.5, 5.0) + rnd.uniform(-0.18, 0.18)
        tip_x = min(0.96, max(0.04, x0 / size + spread))
        lean = (tip_x - x0 / size) * size
        w = rnd.uniform(2.5, 6)
        t = rnd.random()
        if t < 0.65:   # 어두운 올리브·회녹색
            base = (int(46 + 22 * t), int(54 + 18 * t), int(38 + 8 * t))
        else:          # 마른 갈색 (콘셉트의 가을 풀)
            base = (int(96 + 30 * t), int(74 + 18 * t), int(46))
        tip = tuple(min(255, c + 38) for c in base)
        steps = 12
        for i in range(steps):
            a, b = i / steps, (i + 1) / steps
            xa, xb = x0 + lean * a * a, x0 + lean * b * b
            ya, yb = size - h * a, size - h * b
            wa = w * (1 - a) + 0.5
            col = tuple(int(base[k] + (tip[k] - base[k]) * a) for k in range(3)) + (255,)
            d.polygon([(xa - wa, ya), (xa + wa, ya), (xb + wa * 0.7, yb), (xb - wa * 0.7, yb)], fill=col)
    img.save(OUT / "grass_v2.png")


def bush_card(size=512, seed=8):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def twig(x, y, ang, length, width, depth):
        x2 = x + math.cos(ang) * length
        y2 = y - math.sin(ang) * length
        c = (rnd.randint(28, 44), rnd.randint(28, 40), rnd.randint(24, 32), 255)
        d.line([(x, y), (x2, y2)], fill=c, width=max(1, int(width)))
        if depth > 0:
            for _ in range(rnd.randint(2, 3)):
                twig(x2, y2, ang + rnd.uniform(-0.7, 0.7), length * rnd.uniform(0.55, 0.75), width * 0.65, depth - 1)
        else:
            if rnd.random() < 0.6:   # 마른 잎 몇 개
                r = rnd.uniform(3, 6)
                lc = (rnd.randint(60, 100), rnd.randint(40, 60), rnd.randint(28, 40), 255)
                d.ellipse([x2 - r, y2 - r, x2 + r, y2 + r], fill=lc)

    for _ in range(9):
        twig(size / 2 + rnd.uniform(-60, 60), size, math.pi / 2 + rnd.uniform(-0.8, 0.8), size * rnd.uniform(0.18, 0.28), 6, 4)
    img.save(OUT / "bush_v2.png")


def chainlink(size=256, cells=8):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    step = size // cells
    col = (70, 72, 74, 255)
    for i in range(-cells, cells * 2):
        d.line([(i * step, 0), (i * step + size, size)], fill=col, width=3)
        d.line([(i * step + size, 0), (i * step, size)], fill=col, width=3)
    img.save(OUT / "chainlink.png")


def particle(name, size, inner, outer, soft):
    y, x = np.mgrid[0:size, 0:size]
    r = np.sqrt((x - size / 2) ** 2 + ((y - size / 2) * (1.25 if name == "fire.png" else 1.0)) ** 2) / (size / 2)
    a = np.clip(1 - r, 0, 1) ** soft
    rgb = np.array(inner, np.float32) * (1 - r[:, :, None]).clip(0, 1) + np.array(outer, np.float32) * r[:, :, None].clip(0, 1)
    img = np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(OUT / name)


# ── 하늘 파노라마 ────────────────────────────────────────────────
def sky(w=4096, h=2048, seed=11):
    horizon = h // 2
    ys = np.arange(h)[:, None].astype(np.float32)
    # 구름: 가로로 긴 노이즈 (반복되게 가로 방향만 tile)
    n = fbm(2048, seed, octaves=(3, 8, 24, 70), weights=(0.45, 0.3, 0.17, 0.08))
    n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
    t = np.clip(ys / horizon, 0, 1)                                    # 0 = 천정, 1 = 지평선
    cloud_mix = np.clip((n - 0.35) * 2.2, 0, 1)
    top = CLOUD_DARK * (1 - cloud_mix[:, :, None]) + CLOUD_PINK * cloud_mix[:, :, None]
    glow = np.exp(-((ys - horizon * 0.72) / (h * 0.18)) ** 2)          # 지평선 위 붉은 띠
    top = top * (1 + 0.25 * glow[:, :, None])
    haze = np.clip((t - 0.55) / 0.45, 0, 1) ** 1.3                     # 지평선 쪽은 안개 색
    img = top * (1 - haze[:, :, None]) + FOG * haze[:, :, None]
    img[horizon:] = FOG
    canvas = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(canvas)
    rng = np.random.default_rng(seed)
    # 산 능선 3겹 (멀수록 안개색에 가까움)
    for layer, (base, amp, col_mix) in enumerate([(horizon - 20, 260, 0.75), (horizon - 5, 200, 0.55), (horizon + 5, 120, 0.35)]):
        xs = np.arange(0, w, 4)
        ridge = np.zeros(len(xs))
        for k, f in enumerate((1, 2, 3, 7, 17, 41)):
            ridge += np.sin(xs / w * math.tau * f + rng.uniform(0, math.tau)) / (k + 1) ** 1.1
        ridge = np.abs(ridge) ** 1.3                                   # 뾰족한 봉우리
        ridge = ridge / ridge.max()
        mask = np.clip(np.sin(xs / w * math.tau * 2 + layer) * 0.5 + 0.7, 0.2, 1)   # 산이 몰린 곳·빈 곳
        ys_r = base - amp * ridge * mask
        col = tuple(int(c) for c in (MOUNTAIN * (1 - col_mix) + FOG * col_mix))
        d.polygon([(0, h)] + [(int(x), int(y)) for x, y in zip(xs, ys_r)] + [(w, h)], fill=col)
    arr = np.asarray(canvas, np.float32)
    mist = np.clip((ys - (horizon - 140)) / 150, 0, 1)[:, :, None] * 0.8   # 산 아래를 안개로 녹임
    arr = arr * (1 - mist) + FOG * mist
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)).save(OUT / "sky_v2.png")


planks()
rust()
concrete()
grass_card()
bush_card()
chainlink()
particle("fire.png", 128, (255, 236, 170), (240, 90, 20), 1.6)
particle("smoke.png", 128, (120, 122, 126), (70, 72, 76), 2.2)
sky()
print("[textures v2] done ->", OUT)
