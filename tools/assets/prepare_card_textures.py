"""오려낸 폐차·나무 그림 → Godot 카드용 질감 (색 + 노멀맵) (A 소유)

비유: 사진을 판자에 붙여 세우되(카드), 사진 밝기로 "울퉁불퉁 지도"(노멀맵)를 만들어
빛이 옆에서 오면 판자인데도 굴곡이 있는 것처럼 음영이 생기게 한다.

- 입력: art/cards_src/cut/*.png (extract_card_sprites.py 결과)
- 출력: godot/assets/textures/cards/<이름>.png (색+투명), <이름>_n.png (노멀맵)
- 크기: 긴 변을 768px 가까이 맞춘다 (작은 조각은 최대 2.5배 확대), 노멀맵은 절반 크기
- 가장자리 번짐: 투명한 곳에 가까운 색을 번지게 채워, 밉맵에서 검은 테두리가 생기지 않게 한다
실행: python3 tools/assets/prepare_card_textures.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art/cards_src/cut"
OUT = ROOT / "godot/assets/textures/cards"
MAX_SIDE = 768             # 원거리(12m 밖) 전용이라 이 정도면 충분 — APK 용량 절약

# 오린 조각 → 게임 이름 (stage_builder_v2.gd CARDS 와 같은 이름)
NAMES = {
    "sheet_a_01": "card_excavator", "sheet_a_05": "card_semi_truck", "sheet_a_06": "card_jeep_wreck",
    "sheet_a_07": "card_van_front", "sheet_a_11": "card_van_rear", "sheet_a_12": "card_roadster",
    "sheet_b_02": "card_sedan_green", "sheet_c_05": "card_pickup_blue", "sheet_c_06": "card_hatchback",
    "sheet_c_07": "card_jeep", "sheet_c_11": "card_bus",
    "sheet_a_02": "card_tree_burnt", "sheet_a_03": "card_tree_rock_a", "sheet_a_04": "card_tree_moss_a",
    "sheet_a_08": "card_stump_mushroom", "sheet_a_09": "card_tree_rock_b", "sheet_a_10": "card_log_fallen",
    "sheet_b_01": "card_tree_dead_a", "sheet_c_02": "card_tree_dead_b", "sheet_c_03": "card_tree_twist_a",
    "sheet_c_04": "card_stump_roots", "sheet_c_08": "card_tree_white", "sheet_c_09": "card_tree_moss_b",
    "sheet_c_10": "card_tree_twist_b",
    # 그린스크린 시트 (서 있는 것만 — 누운 통나무·가지와 그림 오류가 있는 조각은 뺐다)
    "sheet_d_green_01": "card_stump_cut", "sheet_d_green_05": "card_twig_pile", "sheet_d_green_10": "card_stick_bundle",
    "sheet_d_green_11": "card_roots_gnarled", "sheet_d_green_12": "card_roots_stump",
}


def bleed(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    # 투명한 픽셀은 가장 가까운 불투명 픽셀 색으로 채운다
    solid = alpha > 0.5
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    return rgb[iy, ix]


def normal_map(rgb: np.ndarray, alpha: np.ndarray, strength: float = 2.2) -> np.ndarray:
    lum = rgb.mean(axis=2) / 255.0
    height = ndimage.gaussian_filter(lum, 1.2) * 0.7 + ndimage.gaussian_filter(alpha, 3.0) * 0.3   # 가장자리는 둥글게
    dx = ndimage.sobel(height, axis=1) * strength
    dy = ndimage.sobel(height, axis=0) * strength
    n = np.dstack([-dx, dy, np.ones_like(dx)])                   # OpenGL 방식 (Y 위쪽)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for src, name in NAMES.items():
        im = Image.open(SRC / f"{src}.png").convert("RGBA")
        im = im.crop(im.getbbox())
        # 작게 잘린 조각은 최대 2.5배까지 키운다 (투명도도 부드럽게 보간되어 외곽 계단이 줄어든다)
        scale = min(2.5, MAX_SIDE / max(im.size))
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        arr = np.asarray(im).astype(np.float32)
        rgb, alpha = arr[:, :, :3], arr[:, :, 3] / 255.0
        color = np.dstack([bleed(rgb, alpha), alpha * 255]).clip(0, 255).astype(np.uint8)
        Image.fromarray(color, "RGBA").save(OUT / f"{name}.png")
        nm = Image.fromarray(normal_map(rgb, alpha), "RGB")
        nm.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS).save(OUT / f"{name}_n.png")
        print(f"{name}: {im.width}x{im.height}")


if __name__ == "__main__":
    main()
