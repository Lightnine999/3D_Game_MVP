"""OpenAI 파노라마(가로 띠) → 게임용 360° 하늘 (A 소유)

비유: 가로로 긴 풍경 사진 한 장을 원통 안쪽에 두르는데, 사진이 반 바퀴밖에 안 되니
나머지 반 바퀴는 좌우를 뒤집은 사본으로 이어 붙여 이음매가 보이지 않게 한다.
위쪽(하늘 꼭대기)은 원본 맨 윗줄 색을 이어 올려 채우고, 아래쪽은 안개색으로 채운다.

- 입력: art/sky_src/openai_panorama.webp (2000x667, 지평선 = 위에서 약 370px, 안개 = 540px 아래)
- 출력: godot/assets/textures/v2/sky_pano.png (4096x2048 정거방위, 정면 = 가운데)
실행: python3 tools/assets/make_sky_from_panorama.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art/sky_src/openai_panorama.webp"
OUT = ROOT / "godot/assets/textures/v2/sky_pano.png"
W, H = 4096, 2048
SRC_HORIZON = 370 / 667          # 원본에서 산 밑(지평선) 높이 비율
FOG = np.array([70, 76, 88], np.float32)   # 원본 아래쪽 안개색 = 게임 안개색 (stage_builder_v2.gd FOG_NEAR)


def main() -> None:
    strip = Image.open(SRC).convert("RGB")
    sw = W // 2                                               # 원본이 반 바퀴(180°)를 덮는다
    sh = round(strip.height * sw / strip.width)
    strip = np.asarray(strip.resize((sw, sh), Image.LANCZOS), np.float32)
    half = np.concatenate([strip, strip[:, ::-1]], axis=1)    # 원본 + 좌우 반전 = 한 바퀴 (이음매 없음)
    half = np.roll(half, W // 4, axis=1)                      # 원본 가운데가 화면 정면(u = 0.5)으로
    top = H // 2 - round(SRC_HORIZON * sh)                    # 원본 지평선을 하늘 지평선(H/2)에 맞춘다
    sky = np.zeros((H, W, 3), np.float32)
    sky[top:top + sh] = half
    # 위쪽: 원본 맨 윗줄 색을 그대로 위로 이어 올리고, 꼭대기로 갈수록 조금 어둡게
    # (정면 시야는 위로 약 30°까지라 원본 띠(33°까지)가 보이는 곳을 다 덮는다 — 윗부분은 거의 안 보임)
    row = half[:4].mean(axis=0)
    ys = np.arange(top)[:, None, None].astype(np.float32)
    fade = np.clip(1 - ys / top, 0, 1)                        # 0 = 원본 윗줄 색, 1 = 꼭대기
    # 위로 갈수록 가로로 점점 더 흐리게 → 세로 줄무늬 없이 단색으로 녹는다
    for y in range(top):
        f = float(fade[y, 0, 0])
        sky[y] = ndimage.gaussian_filter1d(row, 4 + 120 * f, axis=0, mode="wrap") * (1 - 0.25 * f ** 1.5)
    # 아래쪽: 안개색으로 채운다 (땅에 가려 거의 안 보이지만 안개와 이어지게)
    sky[top + sh:] = FOG
    Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8)).save(OUT)
    print("[sky] ->", OUT, "strip", sw, "x", sh, "top", top)


if __name__ == "__main__":
    main()
