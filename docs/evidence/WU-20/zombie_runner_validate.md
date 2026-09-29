# WU-20 근거 — zombie_runner.glb (2026-09-29)

캐릭터: Mixamo **Ch10** (원본 `art/source/mixamo/runner_ch10.fbx`, git 제외). 마르고 상의가 없어 달릴 때 팔다리 윤곽이 잘 보인다 → PRD F-41 러너.

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/import_mixamo.py -- \
  --character art/source/mixamo/runner_ch10.fbx \
  --anim idle="art/source/mixamo/scary_zombie_pack/zombie idle.fbx" \
  --anim walk="art/source/mixamo/scary_zombie_pack/zombie walk.fbx" \
  --anim run="art/source/mixamo/scary_zombie_pack/zombie run.fbx" \
  --anim attack="art/source/mixamo/scary_zombie_pack/zombie attack.fbx" \
  --anim hit="art/source/mixamo/Zombie Reaction Hit.fbx" \
  --anim death="art/source/mixamo/scary_zombie_pack/zombie death.fbx" \
  --in-place walk,run,hit --out godot/assets/models/zombie_runner.glb
```
변환 결과: 뼈 이름 65개 `mixamorig5:` → `mixamorig:` 통일 / 삼각형 49,593 → 9,000 / 그림 4096×4096 여덟 장 → 1024×1024 / 수평 이동 walk 1.379, run 2.476, hit 0.741 → 모두 0.000 m

## 처음 만들 때 생긴 문제와 고친 방법
- **문제:** Mixamo 가 이 캐릭터의 뼈 이름에 숫자를 붙였다(`mixamorig5:Hips`). 동작 파일은 `mixamorig:Hips` 라서 동작이 몸에 전혀 입혀지지 않았다 (T 자로 서 있는 상태).
- **검사기가 놓침:** 애니메이션 이름만 확인하고, 실제로 뼈가 움직이는지는 보지 않아 처음에는 "통과"로 나왔다.
- **고침:** ① `import_mixamo.py` 가 뼈 이름의 숫자를 떼어 통일하고, 뼈 대부분이 안 맞으면 멈춘다 ② `validate.py` 에 "애니메이션이 뼈를 움직이는지"(최대 회전 1° 이상) 검사를 추가했다. 잘못 만든 러너를 새 검사기로 검사하면 6개 애니메이션 모두 "뼈를 움직이지 않음 (0.00°)" 으로 실패하는 것을 확인했다.
- 워커·탱커도 새 검사기로 다시 검사해 모두 통과했다.

## 검사 (`art/blender/validate.py`) — 통과
| 항목 | 결과 | 규격 |
|---|---|---|
| 그림 | 1024×1024 여덟 장 (Diffuse·Normal·Specular·Glossiness × 2) | 5.2 |
| 삼각형 | 9,000 | 5.3 |
| 키 | 1.773 m | 5.2 1.7 - 1.9 m |
| 원점 / 정면 | 발밑 z -0.002 / Godot -Z | 5.2 |
| 애니메이션 | idle, walk, run, attack, hit, death — 모두 뼈가 움직임 | 5.4 / WU-20 |
| walk / run 제자리 | 0.000 / 0.000 m | 5.4 |

## Godot 4.7.2
뼈 65개, 메시 1개, 애니메이션 6개 (attack 2.53 · death 2.83 · hit 2.20 · idle 4.30 · run 0.83 · walk 4.07초)

## 눈으로 확인
그림을 입힌 미리보기(달리기·공격)에서 동작이 몸에 입혀짐. `art/previews/zombie_runner_*.png` (git 제외).

## 참고
파일 크기 9.5 MB — 그림이 여덟 장이라 크다. 휴대폰 로딩이 느리면 Specular·Glossiness 를 빼거나 512 로 줄이는 것을 검토한다 (TECH_SPEC 10.3 첫 실행 로딩 5초).
