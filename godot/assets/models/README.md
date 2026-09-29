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

| 최적화본 | 원본 파일 | 면 수 (원본 → 최적화) | 크기 | 라이선스 |
|---|---|---|---|---|
| trees/tree_dead_01 | dead_tree (1).glb | 232k → 12k | 키 10m | ⚠️ 확인 필요 |
| trees/tree_dead_02 | dead_tree (2).glb | 137k → 12k | 키 12m | ⚠️ 확인 필요 |
| trees/tree_dead_03 | dead_tree (3).glb | 78k → 12k | 키 14m | ⚠️ 확인 필요 |
| trees/tree_dead_04 | dead_tree (4).glb | 120k → 25k | 키 11m | ⚠️ 확인 필요 |
| trees/tree_dead_small | dead_tree.glb | 3k | 키 6m | ⚠️ 확인 필요 |
| trees/tree_dry_01 | dry_tree_vurvur_house_5.glb | 2k | 키 6.5m | ⚠️ 확인 필요 |
| trees/tree_fantasy_dead | old_fantasy_dead_tree.glb | 720k → 14k | 키 12m | ⚠️ 확인 필요 |
| trees/tree_old_01 | old_tree.glb | 8k | 키 9m | ⚠️ 확인 필요 |
| trees/tree_old_02 | old_tree_3d_model_free.glb | 603k → 30k | 키 8m | ⚠️ 확인 필요 |
| trees/tree_dead_real | realistic_dead_tree.glb | 998k → 12k | 키 9m | ⚠️ 확인 필요 |
| trees/stump_old_01 | ga_free_201_old_tree_stump.glb | 1.33M → 15k | 높이 0.9m | ⚠️ 확인 필요 |
| vehicles/car_junk_01 | abandoned__junk_car.glb | 29k → 8k | 길이 4.5m | ⚠️ 확인 필요 |
| vehicles/car_abandoned_01 | abandoned_car.glb | 5k | 길이 4.6m | ⚠️ 확인 필요 |
| vehicles/car_thunderbird_1957 | thunderbird_hillbilly_1957.glb | 647k → 9k (텍스처 256px) | 길이 5.3m | ⚠️ 확인 필요 |
| vehicles/car_scan_01 | destroyed_car_1_raw_scan.glb | 2.5M → 30k | 길이 4.6m | ⚠️ 확인 필요 |
| vehicles/car_scan_02 | destroyed_car_02_raw_scan.glb | 2.5M → 50k | 길이 4.6m | ⚠️ 확인 필요 |
| vehicles/car_scan_03 | destroyed_car_03_raw_scan.glb | 2.5M → 56k | 길이 4.6m | ⚠️ 확인 필요 |
| vehicles/car_scan_06 | destroyed_car_06_raw_scan.glb | 2.5M → 44k | 길이 4.6m | ⚠️ 확인 필요 |
| vehicles/car_scan_07 | destroyed_car_07_raw_scan.glb | 2.5M → 49k | 길이 4.6m | ⚠️ 확인 필요 |
| vehicles/car_scan_red | little_red_car_free_raw_scan.glb | 2.5M → 55k | 길이 4.2m | ⚠️ 확인 필요 |
| vehicles/car_scan_barricade | scrap_barricade_car_free_raw_scan.glb | 2.5M → 47k | 길이 5m | ⚠️ 확인 필요 |
| house/house_abandoned_01 | pixellabs-abandoned-house-3642.glb | 50k → 12k | 높이 14m | ⚠️ 확인 필요 |
| house/house_abandoned_02 | pixellabs-abandoned-house-3643.glb | 50k → 12k | 높이 12m | ⚠️ 확인 필요 |
| house/house_shack_01 | pixellabs-shack-4810.glb | 50k → 10k | 높이 4.5m | ⚠️ 확인 필요 |
| house/house_slum_01 | pixellabs-slum-4808.glb | 50k → 12k | 높이 6.5m | ⚠️ 확인 필요 |

빠진 원본: `a_forest_3_with_a_road_at_night_for_game.glb`(작은 숲 한 판이라 배치용 아님), `zoo-park_dead_tree.glb`(하늘 돔이 함께 들어 있음)

⚠️ **이 저장소는 공개**다. 위 에셋을 푸시하기 전에 각 출처의 라이선스(재배포 허용·출처 표기 의무)를 확인해 이 표를 채운다.
