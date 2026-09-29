# WU-20 근거 — zombie_tank.glb (2026-09-29)

캐릭터: Mixamo **PumpkinHulk** (원본 `art/source/mixamo/tank_pumpkinhulk.fbx`, git 제외). 동작은 zombie_walker 와 같은 Mixamo 동작을 공유한다 (TECH_SPEC 5.4 "동일 뼈대 … 애니메이션을 공유").

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/import_mixamo.py -- \
  --character art/source/mixamo/tank_pumpkinhulk.fbx --height 2.2 \
  --anim idle="art/source/mixamo/scary_zombie_pack/zombie idle.fbx" \
  --anim walk="art/source/mixamo/scary_zombie_pack/zombie walk.fbx" \
  --anim attack="art/source/mixamo/scary_zombie_pack/zombie attack.fbx" \
  --anim hit="art/source/mixamo/Zombie Reaction Hit.fbx" \
  --anim death="art/source/mixamo/scary_zombie_pack/zombie death.fbx" \
  --in-place walk,hit --out godot/assets/models/zombie_tank.glb
```
변환 결과: 키 2.040 → 2.200 m / 그림 2048×2048 두 장 → 1024×1024 / 삼각형 9,620 (상한 이하라 줄이지 않음) / 수평 이동 walk 1.486 → 0.000 m, hit 0.799 → 0.000 m / 캐릭터에 없는 뼈 경고 없음

탱커는 PRD F-42 "크고 느리지만" 이라 run 을 넣지 않았다 (걷기 속도 0.8 m/s 는 게임 코드가 정한다).

## 검사 (`art/blender/validate.py`) — 통과
| 항목 | 결과 | 규격 |
|---|---|---|
| 이름 | `zombie_tank` | 5.2 |
| 그림 | pumpkinHulk_diffuse 1024×1024, pumpkinHulk_normal 1024×1024 | 5.2 최대 1024×1024 |
| 삼각형 | 9,620 | 5.3 좀비 10,000 이하 |
| 키 | 2.200 m | 5.2 탱커 예외 2.0 - 2.4 m |
| 원점 | 발밑 z 0.001 | 5.2 |
| 정면 | Godot -Z | 5.2 |
| 애니메이션 | idle, walk, attack, hit, death | 5.4 / WU-20 (walk 또는 run) |
| walk 제자리 | 0.000 m | 5.4 |

## Godot 4.7.2 불러오기
뼈 66개, 메시 1개, 애니메이션 attack 2.53초 · death 2.83초 · hit 2.20초 · idle 4.30초 · walk 4.07초

## 눈으로 확인
그림을 입힌 미리보기(기본 자세·걷기·공격, 앞·옆)에서 동작이 몸에 자연스럽게 입혀지고 팔다리가 꼬이지 않음. 미리보기는 `art/previews/zombie_tank_*.png` (git 제외).
