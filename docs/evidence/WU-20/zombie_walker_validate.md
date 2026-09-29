# WU-20 근거 — zombie_walker.glb (2026-09-29, 캐릭터 교체)

캐릭터: Mixamo **FuzZombie** (경찰 제복 좀비, 원본 `art/source/mixamo/walker_fuzzombie.fbx`, git 제외). 옷 입은 보통 체형이고 경찰 모자·조끼 실루엣이 다른 3종과 구분된다 → PRD F-40 워커. 처음에는 X Bot(마네킹)으로 임시로 만들었다가 이 캐릭터로 교체했다.

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/import_mixamo.py -- \
  --character art/source/mixamo/walker_fuzzombie.fbx --height 1.85 \
  --anim idle="art/source/mixamo/scary_zombie_pack/zombie idle.fbx" \
  --anim walk="art/source/mixamo/scary_zombie_pack/zombie walk.fbx" \
  --anim run="art/source/mixamo/scary_zombie_pack/zombie run.fbx" \
  --anim attack="art/source/mixamo/scary_zombie_pack/zombie attack.fbx" \
  --anim hit="art/source/mixamo/Zombie Reaction Hit.fbx" \
  --anim death="art/source/mixamo/scary_zombie_pack/zombie death.fbx" \
  --in-place walk,run,hit --out godot/assets/models/zombie_walker.glb
```
변환 결과: 키 2.044 → 1.850 m (모자 포함 키가 1.7 - 1.9 m 를 넘어서 맞춤) / 삼각형 9,845 (상한 이하라 그대로) / 그림 2048×2048 열 장 → 1024×1024 / 수평 이동 walk 1.248, run 2.241, hit 0.670 → 모두 0.000 m

## 검사 (`art/blender/validate.py`) — 통과
| 항목 | 결과 | 규격 |
|---|---|---|
| 그림 | 모두 1024×1024 이하 | 5.2 |
| 삼각형 | 9,845 | 5.3 |
| 키 | 1.850 m | 5.2 1.7 - 1.9 m |
| 원점 / 정면 | 발밑 z -0.006 / Godot -Z | 5.2 |
| 애니메이션 | idle, walk, run, attack, hit, death — 모두 뼈가 움직임 | 5.4 / WU-20 |
| walk / run 제자리 | 0.000 / 0.000 m | 5.4 |

## Godot 4.7.2
뼈 67개, 메시 4개 (몸·눈·안경·머리카락), 애니메이션 6개 (attack 2.53 · death 2.83 · hit 2.20 · idle 4.30 · run 0.83 · walk 4.07초)

## 4종 구분 (WU-20 "4종이 서로 구분된다")
네 좀비를 나란히 세운 그림 `art/previews/lineup_4_zombies.png` (git 제외): 경찰복 워커 · 마르고 상의 없는 러너 · 거대한 탱커(2.2 m) · 검은 몸에 초록 발광 매복.

## 참고
셔츠와 입가에 피 표현이 있다. TECH_SPEC 9.5 콘텐츠 등급은 "좀비·총기 폭력 → 12세 이상 예상".
