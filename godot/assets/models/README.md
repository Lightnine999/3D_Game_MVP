# 3D 모델 폴더 — 주인: A

| 폴더 | 내용 |
|---|---|
| `trees/` | 나무·그루터기 (구해 온 에셋 최적화본 + 직접 만든 `v2_tree_*`, v1 `prop_tree_*`) |
| `vehicles/` | 폐차·버스·트럭 (구해 온 에셋 최적화본 + `v2_car_*`·`v2_bus`·`v2_truck`, v1 `obs_wreck_car*`) |
| `house/` | 폐가·판잣집·폐허 (구해 온 에셋 최적화본 + `v2_house_*`·`v2_shack`, v1 `prop_ruin_*`) |
| `props/` | 그 밖의 소품·구조물: 드럼통·상자·가방·잔해·표지판·다리·성벽·정문·투광등·송전탑·급수탑 |

- 코드는 폴더를 몰라도 된다: `ModelLibrary.path("이름")`이 네 폴더에서 이름으로 찾는다 (`scripts/stage/model_library.gd`)
- `v2_*` = Blender 스크립트로 직접 만든 것 (`art/blender/make_stage_v2.py`), 재질 이름으로 질감을 입힌다
- 그 밖 = 구해 온 에셋을 `art/blender/optimize_glb.py`로 줄인 것 (원래 텍스처 유지)

## 구해 온 에셋 (원본은 `art/source_assets/`, 용량이 커서 git·APK에서 제외)

최적화: 조각 합치기 → 면 수 줄이기 → 텍스처 512px(폐허 1024px) → 실제 크기 → 원점 = 바닥 가운데

| 최적화본 | 원본 파일 | 면 수 (원본 → 최적화) | 크기 | 비고 |
|---|---|---|---|---|
| trees/tree_dead_02 | dead_tree (2).glb | 137k → 12k | 키 12m | CC BY 4.0 (ASSETS_LICENSE.md) |
| trees/tree_dead_03 | dead_tree (3).glb | 78k → 12k | 키 14m | CC BY 4.0 (ASSETS_LICENSE.md) |
| trees/tree_dead_small | dead_tree.glb | 3k | 키 6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| trees/tree_old_01 | old_tree.glb | 8k | 키 9m | CC BY 4.0 (ASSETS_LICENSE.md) |
| trees/stump_old_01 | ga_free_201_old_tree_stump.glb | 1.33M → 15k | 높이 0.9m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_junk_01 | abandoned__junk_car.glb | 29k → 8k | 길이 4.5m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_abandoned_01 | abandoned_car.glb | 5k | 길이 4.6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_thunderbird_1957 | thunderbird_hillbilly_1957.glb | 647k → 9k (텍스처 256px) | 길이 5.3m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_scan_01 | destroyed_car_1_raw_scan.glb | 2.5M → 30k | 길이 4.6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_scan_02 | destroyed_car_02_raw_scan.glb | 2.5M → 50k | 길이 4.6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_scan_03 | destroyed_car_03_raw_scan.glb | 2.5M → 56k | 길이 4.6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_scan_06 | destroyed_car_06_raw_scan.glb | 2.5M → 44k | 길이 4.6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_scan_07 | destroyed_car_07_raw_scan.glb | 2.5M → 49k | 길이 4.6m | CC BY 4.0 (ASSETS_LICENSE.md) |
| vehicles/car_scan_red | little_red_car_free_raw_scan.glb | 2.5M → 55k | 길이 4.2m | CC BY 4.0 (ASSETS_LICENSE.md) |
| house/house_abandoned_01 | pixellabs-abandoned-house-3642.glb | 50k → 12k | 높이 14m | Pixabay (ASSETS_LICENSE.md) |
| house/house_abandoned_02 | pixellabs-abandoned-house-3643.glb | 50k → 12k | 높이 12m | Pixabay (ASSETS_LICENSE.md) |
| house/house_shack_01 | pixellabs-shack-4810.glb | 50k → 10k | 높이 4.5m | Pixabay (ASSETS_LICENSE.md) |
| house/house_slum_01 | pixellabs-slum-4808.glb | 50k → 12k | 높이 6.5m | Pixabay (ASSETS_LICENSE.md) |
| props/drum_oil_01 | oil_drum.glb | 11k → 3k | 높이 0.9m | CC BY 4.0 (ASSETS_LICENSE.md) |
| props/drum_oil_02 | oil_drum_by_rishabh.glb (같은 파일 `(1)` 사본은 제외) | 17k → 3k | 높이 0.9m | CC BY 4.0 (ASSETS_LICENSE.md) |
| props/drum_old_01 | old_drum.glb | 0.9k | 높이 0.9m | CC BY 4.0 (ASSETS_LICENSE.md) |
| props/drum_explosive | modern_dirty_explosive_barrel_model.glb | 0.7k | 높이 0.95m | CC BY 4.0 (ASSETS_LICENSE.md) |
| props/barrel_pack_01 - 05 | barrel_pack_-_low_poly_props.glb (5개를 하나씩 분리) | 0.4k씩 | 높이 1m | CC BY 4.0 (ASSETS_LICENSE.md) |
| props/drum_pile_01 | oil_drums.glb (드럼통 무더기) | 7k → 6k | 높이 1m | CC BY 4.0 (ASSETS_LICENSE.md) |

빠진 원본: `dead_tree (1)`·`dead_tree (4)`·`old_tree_3d_model_free`·`realistic_dead_tree`(모바일용으로 줄이면 가지가 조각나서 제외), `a_forest_3_with_a_road_at_night_for_game.glb`(작은 숲 한 판이라 배치용 아님), `zoo-park_dead_tree.glb`(하늘 돔이 함께 들어 있음)

라이선스와 출처는 **`/ASSETS_LICENSE.md`**에 정리했다 (GLB 안의 작가·라이선스 정보로 확인, 2026-09-29). 비상업(NC) 모델 3개는 제외했다.
