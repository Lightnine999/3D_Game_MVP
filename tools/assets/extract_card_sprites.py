"""AI 이미지(체크무늬가 박힌 가짜 투명 배경)에서 폐차·나무를 하나씩 오려 투명 PNG로 저장 (A 소유)

비유: 체크무늬 식탁보 위에 놓인 장난감 사진에서, 식탁보 무늬를 "여기엔 이 색이 있어야 해"라고 계산해
그 색과 같은 곳만 지우고, 남은 덩어리를 하나씩 가위로 오려 내는 일.

- 입력: art/cards_src/*.webp (2000x1091, 체크 한 칸 약 16-17px — 밝은 회색 약 112 / 어두운 회색 약 56)
- 출력: art/cards_src/cut/<원본>_<번호>.png (투명 배경, 여백 포함) + 한눈에 보는 contact.png
실행: python3 tools/assets/extract_card_sprites.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art/cards_src"
OUT = SRC / "cut"
MIN_AREA = 4000            # 이보다 작은 덩어리는 버림 (잡티·워터마크)


def background_mask(rgb: np.ndarray) -> np.ndarray:
    """체크 배경 = 주변 7x7 대부분이 '정확히 두 가지 회색(밝은 칸·어두운 칸)' 중 하나인 곳.
    AI가 그린 체크무늬는 칸 간격이 곳곳에서 달라서 전체 격자 계산 대신 주변만 본다."""
    gray = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    border = np.concatenate([gray[:12].ravel(), gray[-12:].ravel()])
    light = float(np.median(border[border > 84]))
    dark = float(np.median(border[border <= 84]))
    is_l = (np.abs(gray - light) < 9) & (sat < 12)
    is_d = (np.abs(gray - dark) < 9) & (sat < 12)
    pure = ndimage.uniform_filter((is_l | is_d).astype(np.float32), 7)
    cand = (pure > 0.62) & (sat < 14) & (gray > dark - 14) & (gray < light + 14)
    # 원본에 남은 가로 얼룩: 체크가 옆으로 문질러진 띠 — 세로 7px 동안 값이 거의 같은 무채색
    # (사진 속 물체는 질감이 있어 세로로 이렇게 일정하지 않다)
    vm = ndimage.uniform_filter1d(gray, 7, axis=0)
    vstd = np.sqrt(np.maximum(ndimage.uniform_filter1d(gray * gray, 7, axis=0) - vm * vm, 0))
    cand |= (sat < 9) & (vstd < 1.8) & (gray > dark - 6) & (gray < light + 6)
    labels, n = ndimage.label(cand, structure=np.ones((3, 3)))
    idx = np.arange(1, n + 1)
    n_light = ndimage.sum(cand & is_l, labels, idx)
    n_dark = ndimage.sum(cand & is_d, labels, idx)
    touch = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    keep = np.zeros(n + 1, bool)
    for i in idx:
        # 진짜 배경은 밝은 칸·어두운 칸이 모두 들어 있다. 한 가지 색만 있으면 물체 속 회색(타이어·그림자)
        keep[i] = i in touch or (n_light[i - 1] > 40 and n_dark[i - 1] > 40)
    return keep[labels]


def _fast_std(gray: np.ndarray) -> np.ndarray:
    m = ndimage.uniform_filter(gray, 3)
    m2 = ndimage.uniform_filter(gray * gray, 3)
    return np.sqrt(np.maximum(m2 - m * m, 0))


def cut(path: Path) -> list[Path]:
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    fg = ~background_mask(rgb)
    # 물체 가장자리에 붙어 남은 체크 조각(회색 띠): 체크 두 색과 거의 같고 주변에도 체크 색이 많은 픽셀
    gray = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    checker_px = ((np.abs(gray - 113) < 10) | (np.abs(gray - 56) < 10)) & (sat < 10)
    near = ndimage.uniform_filter(checker_px.astype(np.float32), 9)
    edge_band = ndimage.distance_transform_edt(fg) < 8             # 바깥 배경에서 8px 이내만 (물체 안쪽 회색 칠은 보존)
    fg &= ~(checker_px & (near > 0.45) & edge_band)
    fg = ndimage.binary_opening(fg, iterations=1)                 # 가는 잡티 제거
    labels, n = ndimage.label(fg, structure=np.ones((3, 3)))
    sizes = ndimage.sum(fg, labels, range(1, n + 1))
    solid = np.isin(labels, [i + 1 for i, s in enumerate(sizes) if s >= 150])   # 작은 파편 제거
    # 물건 나누기: 가는 연결(잔가지·바닥 잔여물)을 끊은 모양으로 덩어리를 찾고,
    # 잔가지는 가장 가까운 덩어리에 다시 붙인다 (25px보다 멀면 버림)
    core = ndimage.binary_opening(solid, iterations=3)
    groups, g = ndimage.label(core, structure=np.ones((3, 3)))
    gsizes = ndimage.sum(core, groups, range(1, g + 1))
    for i, s in enumerate(gsizes, start=1):
        if s < MIN_AREA:
            groups[groups == i] = 0
    dist, (iy, ix) = ndimage.distance_transform_edt(groups == 0, return_indices=True)
    owner = np.where(solid & (dist < 25), groups[iy, ix], 0)
    alpha = ndimage.gaussian_filter(ndimage.binary_erosion(solid, iterations=1).astype(np.float32), 0.6)
    out = []
    for k in sorted(set(np.unique(owner)) - {0}):
        part = owner == k
        ys, xs = np.nonzero(part)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        a = alpha[y0:y1, x0:x1] * part[y0:y1, x0:x1]
        rgba = np.dstack([rgb[y0:y1, x0:x1], a * 255]).clip(0, 255).astype(np.uint8)
        im = Image.fromarray(rgba, "RGBA")
        pad = Image.new("RGBA", (im.width + 8, im.height + 8), (0, 0, 0, 0))
        pad.paste(im, (4, 4))
        name = OUT / f"{path.stem}_{len(out) + 1:02d}.png"
        pad.save(name)
        out.append(name)
    return out


def contact(files: list[Path]) -> None:
    thumbs = []
    for f in files:
        im = Image.open(f)
        im.thumbnail((240, 240))
        bg = Image.new("RGB", (250, 270), (255, 0, 255))
        bg.paste(im, ((250 - im.width) // 2, (250 - im.height) // 2), im)
        ImageDraw.Draw(bg).text((6, 252), f.stem, fill=(255, 255, 255))
        thumbs.append(bg)
    cols = 6
    sheet = Image.new("RGB", (cols * 250, ((len(thumbs) + cols - 1) // cols) * 270), (40, 40, 40))
    for i, t in enumerate(thumbs):
        sheet.paste(t, ((i % cols) * 250, (i // cols) * 270))
    sheet.save(OUT / "contact.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    files = []
    for p in sorted(SRC.glob("*.webp")):
        got = cut(p)
        print(p.name, "->", len(got))
        files += got
    contact(files)


if __name__ == "__main__":
    main()
