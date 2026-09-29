# WU-20 근거 — zombie_walker.glb (2026-09-29)

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/import_mixamo.py -- \
  --character "art/source/mixamo/scary_zombie_pack/X Bot.fbx" \
  --anim idle="art/source/mixamo/scary_zombie_pack/zombie idle.fbx" \
  --anim walk="art/source/mixamo/scary_zombie_pack/zombie walk.fbx" \
  --anim run="art/source/mixamo/scary_zombie_pack/zombie run.fbx" \
  --anim attack="art/source/mixamo/scary_zombie_pack/zombie attack.fbx" \
  --anim death="art/source/mixamo/scary_zombie_pack/zombie death.fbx" \
  --out godot/assets/models/zombie_walker.glb
```
변환 결과: 삼각형 49,112 → 8,998 / 수평 이동 walk 1.379 → 0.000 m, run 2.476 → 0.000 m, hit 0.741 → 0.000 m

hit 는 5.4 필수 대상은 아니지만 "이동은 코드가 담당"(5.4) 원칙에 따라 살아 있는 동안 쓰는 동작이라 제자리로 만들었다. death 는 쓰러진 뒤라 그대로 둔다.

## 검사 (`art/blender/validate.py`)
| 항목 | 결과 | 규격 |
|---|---|---|
| 이름 | `zombie_walker` 통과 | 5.2 소문자_스네이크케이스 + `zombie_` |
| 삼각형 | 8,998 통과 | 5.3 좀비 10,000 이하 |
| 키 | 1.810 m 통과 | 5.2 1.7 - 1.9 m |
| 원점 | 발밑 z -0.001 통과 | 5.2 발밑 중앙 |
| 정면 | Godot -Z 통과 (발끝 방향으로 판정, 정면 미리보기로 확인) | 5.2 |
| walk / run 제자리 | 0.000 m / 0.000 m 통과 | 5.4 In Place |
| 애니메이션 | idle, walk, run, attack, **hit**, death 통과 | 5.4 / WU-20 |

## 검사기 자체 시험 (WU-11 조건)
일부러 규격을 어긴 모델 3개가 모두 **실패로 잡혔다**: 원점 오류(발밑 0.499 m), 이름 오류(`BadZombie`), 폴리곤 초과(53,988).

## Godot 4.7.2 불러오기
임시 프로젝트에서 `--import` 후 확인: 뼈 65개, 메시 2개, 애니메이션 6개 (아래 GODOT_CHECK 결과).

## 남은 것 (👤 다운로드 필요)
- ~~`hit`~~ → `Zombie Reaction Hit.fbx` 로 해결
- ~~매복 일어나기~~ → `Getting Up.fbx` 받음 (zombie_ambusher 만들 때 사용)
- 좀비 4종 구분용 캐릭터 (지금은 X Bot 하나)
- 이동 모션은 다음부터 Mixamo 에서 **In Place 체크**해서 받기 (이번엔 스크립트로 변환)

미리보기 4장(앞·옆·뒤·위)은 `art/previews/zombie_walker_*.png` (git 제외).
