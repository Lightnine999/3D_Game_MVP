"""Poly Haven HDRI → 게임용 하늘 파노라마 (A 소유)

비유: 실사 하늘 사진(HDRI)에 분홍 셀로판지를 씌우고, 그 앞에 안개 낀 산 실루엣 종이를 오려 붙이는 일.

- 입력: art/polyhaven/industrial_sunset_puresky_2k.hdr (CC0, polyhaven.com)
- 출력: godot/assets/textures/v2/sky_ph.png (4096x2048, LDR)
- 모바일 렌더러에서 HDR 하늘을 그대로 쓰는 대신, 미리 톤매핑·색보정해 PNG로 굽는다.

⚠️ 지평선 아래·안개 색(FOG)은 scripts/stage/stage_builder_v2.gd 의 FOG_NEAR 와 맞춘다.
실행: python3 tools/assets/make_sky_from_hdri.py
"""
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art/polyhaven/industrial_sunset_puresky_2k.hdr"   # 원본은 게임 빌드에 넣지 않음
OUT = ROOT / "godot/assets/textures/v2/sky_ph.png"
W, H = 4096, 2048

FOG = np.array([88, 96, 110], dtype=np.float32)          # stage_builder_v2.gd FOG_NEAR
MOUNTAIN = np.array([62, 66, 78], dtype=np.float32)
SUN_U = 0.60                                              # 원본에서 해가 있는 가로 위치 (0~1)


def load_hdri() -> np.ndarray:
    bgr = cv2.imread(str(SRC), cv2.IMREAD_ANYDEPTH | cv2.IMREAD_COLOR)
    rgb = bgr[:, :, ::-1].astype(np.float32)
    rgb = np.roll(rgb, int((0.5 - SUN_U) * rgb.shape[1]), axis=1)   # 해를 화면 정면(가운데)으로
    return cv2.resize(rgb, (W, H), interpolation=cv2.INTER_CUBIC)


def grade(hdr: np.ndarray) -> np.ndarray:
    x = hdr * 0.9
    x = x / (1.0 + x)                                     # Reinhard 톤매핑
    x = np.power(np.clip(x, 0, 1), 1 / 2.2)
    lum = x @ np.array([0.299, 0.587, 0.114], np.float32)
    lo, hi = np.percentile(lum[: H // 2], [2, 99.5])
    lum = np.clip((lum - lo) / (hi - lo), 0, 1) ** 1.35   # 구름 그늘은 어둡게, 빛 받은 곳은 밝게
    # 밝기 → 색 그라데이션 (어두운 보라 구름 → 분홍 → 해 근처 살구색)
    stops = np.array([0.0, 0.45, 0.8, 1.0], np.float32)
    cols = np.array([[58, 42, 56], [150, 88, 98], [214, 128, 118], [246, 196, 168]], np.float32)
    out = np.stack([np.interp(lum, stops, cols[:, c]) for c in range(3)], axis=-1)
    ys = np.arange(H)[:, None, None].astype(np.float32)
    out *= 0.72 + 0.28 * np.clip(ys / (H * 0.45), 0, 1)   # 하늘 꼭대기는 더 어둡게
    return np.clip(out, 0, 255)


def add_mountains_and_mist(img: np.ndarray, seed: int = 11) -> np.ndarray:
    horizon = H // 2
    ys = np.arange(H)[:, None].astype(np.float32)
    t = np.clip(ys / horizon, 0, 1)
    haze = np.clip((t - 0.7) / 0.3, 0, 1) ** 1.5          # 지평선 근처는 안개 색으로
    img = img * (1 - haze[:, :, None]) + FOG * haze[:, :, None]
    img[horizon:] = FOG
    canvas = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(canvas)
    rng = np.random.default_rng(seed)
    for layer, (base, amp, col_mix) in enumerate([(horizon - 20, 260, 0.75), (horizon - 5, 200, 0.55), (horizon + 5, 120, 0.35)]):
        xs = np.arange(0, W, 4)
        ridge = np.zeros(len(xs))
        for k, f in enumerate((1, 2, 3, 7, 17, 41)):
            ridge += np.sin(xs / W * math.tau * f + rng.uniform(0, math.tau)) / (k + 1) ** 1.1
        ridge = np.abs(ridge) ** 1.3
        ridge = ridge / ridge.max()
        mask = np.clip(np.sin(xs / W * math.tau * 2 + layer) * 0.5 + 0.7, 0.2, 1)
        ys_r = base - amp * ridge * mask
        col = tuple(int(c) for c in (MOUNTAIN * (1 - col_mix) + FOG * col_mix))
        d.polygon([(0, H)] + [(int(x), int(y)) for x, y in zip(xs, ys_r)] + [(W, H)], fill=col)
    arr = np.asarray(canvas, np.float32)
    mist = np.clip((ys - (horizon - 140)) / 150, 0, 1)[:, :, None] * 0.8   # 산 아래를 안개로 녹임
    return arr * (1 - mist) + FOG * mist


def main() -> None:
    sky = add_mountains_and_mist(grade(load_hdri()))
    Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)).save(OUT)
    print("[sky] ->", OUT)


if __name__ == "__main__":
    main()
