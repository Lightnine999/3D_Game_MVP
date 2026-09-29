"""나무 사이에 세울 안개 판 그림 (A 소유)

비유: 무대 연기(드라이아이스)를 사진으로 찍어 반투명 판에 붙인 것. 여러 장을 겹쳐 세우면
나무 사이에 옅은 안개층이 떠 있는 것처럼 보인다 (모바일 렌더러는 입체 안개를 지원하지 않아서 쓰는 방법).

- 출력: godot/assets/textures/v2/mist.png (1024x256, 흰색 + 부드러운 투명도, 좌우가 이어지게 반복)
- 색은 셰이더가 안개색으로 칠한다 (scripts/stage/mist.gdshader)
실행: python3 tools/assets/make_mist_texture.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/assets/textures/v2/mist.png"
W, H = 1024, 256


def main() -> None:
    rng = np.random.default_rng(29)
    n = np.zeros((H, W), np.float32)
    for scale, weight in ((64, 0.55), (24, 0.3), (9, 0.15)):   # 큰 덩어리 + 중간 + 잔 결
        base = rng.random((H // scale + 2, W // scale + 2)).astype(np.float32)
        up = ndimage.zoom(base, scale, order=3, mode="grid-wrap")[:H, :W]
        n += up * weight
    n = (n - n.min()) / (n.max() - n.min())
    ys = np.linspace(0, 1, H)[:, None]
    vertical = np.clip(np.sin(ys * np.pi), 0, 1) ** 1.2 * np.clip((1 - ys) * 1.6, 0, 1)   # 가운데·아래가 짙고 위·밑단은 흐리게
    xs = np.linspace(0, 1, W)[None, :]
    sides = np.clip(np.sin(xs * np.pi) * 1.4, 0, 1)              # 판의 좌우 끝도 흐리게 (네모 모서리가 안 보이게)
    alpha = np.clip((n - 0.25) * 1.6, 0, 1) * vertical * sides
    alpha = ndimage.gaussian_filter(alpha, 3)
    rgba = np.dstack([np.full((H, W), 255, np.uint8)] * 3 + [(alpha * 255).astype(np.uint8)])
    Image.fromarray(rgba, "RGBA").save(OUT)
    print("[mist] ->", OUT)


if __name__ == "__main__":
    main()
