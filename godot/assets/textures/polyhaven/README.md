# Poly Haven 질감 (CC0)

출처: https://polyhaven.com — 라이선스 CC0 (출처 표기 의무 없음, 상업적 사용 가능). 기록용으로 남긴다.
받은 날: 2026-09-29, 해상도 1K JPG (색 `diff` · 노멀 `nor_gl` · 거칠기 `rough`)

| 에셋 | 쓰는 곳 |
|---|---|
| weathered_planks | 폐가 벽·상자·나무껍질 (`wood_*`, `bark`) |
| rusty_metal_02 | 폐차·드럼통·정문·버스 (`rust_*`, `paint_bus`) |
| concrete_wall_003 | 성벽·다리·잔해 (`concrete*`) |
| brown_mud_leaves_01 | 진흙길 바닥 (`ground_v2.gdshader`) |

HDRI `industrial_sunset_puresky_2k.hdr` 는 게임에 넣지 않고 `art/polyhaven/`에 두고,
`tools/assets/make_sky_from_hdri.py`로 분홍 노을 색보정 + 산 능선을 합성해 `textures/v2/sky_ph.png`를 만든다.

import 설정: VRAM 압축 + 밉맵, `nor_gl`은 노멀맵으로 가져온다 (`.import` 파일 참고).
