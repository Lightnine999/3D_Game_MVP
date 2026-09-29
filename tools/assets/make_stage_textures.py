"""스테이지용 텍스처 생성 (A 소유).

- grass_card.png : 풀 카드(X자 사각형)에 붙일 마른 풀 이미지 (RGBA, 알파 = 풀잎 모양)
- sky_panorama.png : 하늘 + 원경 폐허·숲 실루엣 파노라마 (정거방위, 2:1)
    OpenAI 콘셉트가 준비되면 이 파일만 같은 이름으로 교체한다 (TECH_SPEC 13.3.1 가짜 부품 규칙)

실행: python3 tools/assets/make_stage_textures.py godot/assets/textures
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

# 레퍼런스 분위기 (art/reference 4장 중 3장 — 저작권 자료라 git 제외): 해질녘 세피아 안개 + 지평선의 주황빛 + 붉은 갈색 마른 풀
# ⚠️ FOG 값은 Godot 안개 색(godot/scripts/stage/stage_builder.gd의 FOG_COLOR)과 반드시 같게 맞춘다
FOG = (122, 106, 88)           # 안개·하늘 아랫부분 (따뜻한 회갈색)
SKY_TOP = (40, 32, 29)         # 하늘 위쪽 (어두운 갈색)
GLOW = (214, 152, 92)          # 지평선 너머 해질녘 빛
SILHOUETTE_FAR = (96, 84, 72)  # 먼 능선 (안개에 반쯤 묻힘)
SILHOUETTE_NEAR = (62, 53, 46) # 폐허 도시·전봇대 실루엣


def grass_card(size=512, seed=7):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(95):
        x0 = rnd.uniform(0.05, 0.95) * size
        h = rnd.uniform(0.45, 0.98) * size
        lean = rnd.uniform(-0.25, 0.25) * size
        w = rnd.uniform(3, 7)
        # 붉은 갈색 ~ 올리브 마른 풀
        t = rnd.random()
        base = (int(92 + 40 * t), int(58 + 30 * (1 - t)), int(38 + 10 * t))
        tip = (min(255, base[0] + 45), min(255, base[1] + 35), min(255, base[2] + 20))
        steps = 14
        for i in range(steps):
            a = i / steps
            b = (i + 1) / steps
            xa = x0 + lean * a * a
            xb = x0 + lean * b * b
            ya = size - h * a
            yb = size - h * b
            wa = w * (1 - a) + 0.6
            col = tuple(int(base[k] + (tip[k] - base[k]) * a) for k in range(3)) + (255,)
            d.polygon([(xa - wa, ya), (xa + wa, ya), (xb + wa * 0.8, yb), (xb - wa * 0.8, yb)], fill=col)
        # 이삭 (위쪽 끝)
        if rnd.random() < 0.35:
            xt, yt = x0 + lean, size - h
            d.ellipse([xt - 5, yt - 14, xt + 5, yt + 6], fill=tip + (255,))
    return img


def ridge(width, base_y, amp, freq, rnd, jag=0.0):
    """가로 한 줄의 실루엣 높이 (연속 사인 합 + 들쭉날쭉)."""
    xs = np.arange(width)
    ph = [rnd.uniform(0, math.tau) for _ in range(4)]
    y = np.zeros(width)
    for k, f in enumerate((1, 2.3, 5.1, 11.7)):
        y += np.sin(xs / width * math.tau * f * freq + ph[k]) / (k + 1)
    y = base_y - amp * (y * 0.5 + 0.5)
    if jag:
        y -= np.array([rnd.uniform(0, jag) for _ in xs])
    return y


def sky_panorama(w=4096, h=2048, seed=3):
    rnd = random.Random(seed)
    img = np.zeros((h, w, 3), dtype=np.float32)
    horizon = h // 2
    ys = np.arange(h)[:, None]
    # 하늘: 위는 어두운 청회색, 지평선 쪽은 안개 색 + 따뜻한 빛 띠
    t = np.clip(ys / horizon, 0, 1)
    sky = np.array(SKY_TOP) * (1 - t) + np.array(FOG) * t
    glow = np.exp(-((ys - horizon + 30) / 70.0) ** 2) * 0.55
    sky = sky * (1 - glow) + np.array(GLOW) * glow
    img[:] = sky[:, None, :]  # (높이, 3) → (높이, 1, 3)으로 늘려 가로 전체에 채움
    img[horizon:] = FOG  # 지평선 아래는 안개로 채움

    # 구름 얼룩 (부드러운 노이즈)
    noise = Image.effect_noise((w // 8, h // 8), 60).resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(24))
    n = (np.asarray(noise, dtype=np.float32) / 255.0 - 0.5)[:, :, None]
    upper = (ys < horizon)[:, :, None]  # (높이, 1, 1)
    img += n * 22 * upper

    canvas = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(canvas)

    # 먼 산·숲 능선
    far = ridge(w, horizon - 8, 70, 1.0, rnd)
    d.polygon([(0, h)] + [(x, far[x]) for x in range(0, w, 4)] + [(w, h)], fill=SILHOUETTE_FAR)

    # 폐허 도시 스카이라인 (부서진 빌딩 + 전봇대 + 급수탑)
    x = 0
    while x < w:
        bw = rnd.randint(40, 140)
        bh = rnd.randint(40, 190) if rnd.random() < 0.55 else rnd.randint(15, 50)
        top = horizon - bh
        pts = [(x, horizon + 5), (x, top)]
        # 무너진 윗면
        for k in range(1, 5):
            pts.append((x + bw * k / 4, top + rnd.randint(0, int(bh * 0.35))))
        pts.append((x + bw, horizon + 5))
        d.polygon(pts, fill=SILHOUETTE_NEAR)
        x += bw + rnd.randint(10, 160)
    for _ in range(18):  # 전봇대
        px = rnd.randint(0, w)
        d.rectangle([px, horizon - 110, px + 4, horizon + 5], fill=SILHOUETTE_NEAR)
        d.rectangle([px - 22, horizon - 104, px + 26, horizon - 100], fill=SILHOUETTE_NEAR)
    for _ in range(3):  # 급수탑
        px = rnd.randint(0, w)
        d.rectangle([px, horizon - 200, px + 70, horizon - 140], fill=SILHOUETTE_NEAR)
        d.rectangle([px + 10, horizon - 140, px + 14, horizon + 5], fill=SILHOUETTE_NEAR)
        d.rectangle([px + 56, horizon - 140, px + 60, horizon + 5], fill=SILHOUETTE_NEAR)

    # 실루엣 아래쪽을 안개로 녹이기
    arr = np.asarray(canvas, dtype=np.float32)
    mist = np.clip((ys - (horizon - 60)) / 70.0, 0, 1)[:, :, None] * 0.75
    arr = arr * (1 - mist) + np.array(FOG) * mist
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


grass_card().save(OUT / "grass_card.png")
sky_panorama().save(OUT / "sky_panorama.png")
print("[textures] grass_card.png, sky_panorama.png ->", OUT)
