# WU-20 근거 — zombie_ambusher.glb (2026-09-29)

캐릭터: Mixamo **Ch45** (원본 `art/source/mixamo/ambusher_ch45.fbx`, git 제외). 몸 평균색이 R0.14 G0.16 B0.17 로 거의 검어 어두운 풀숲·안개 속에 묻힌다 → PRD F-43 "풀숲·안개 속에 누워 있다가 8m 안에 들어오면 갑자기 일어난다". 몸 일부가 초록빛으로 스스로 빛난다(Emissive 그림).

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/import_mixamo.py -- \
  --character art/source/mixamo/ambusher_ch45.fbx \
  --anim idle="art/source/mixamo/scary_zombie_pack/zombie idle.fbx" \
  --anim walk="art/source/mixamo/scary_zombie_pack/zombie walk.fbx" \
  --anim attack="art/source/mixamo/scary_zombie_pack/zombie attack.fbx" \
  --anim hit="art/source/mixamo/Zombie Reaction Hit.fbx" \
  --anim death="art/source/mixamo/scary_zombie_pack/zombie death.fbx" \
  --anim getup="art/source/mixamo/Getting Up.fbx" \
  --anim scream="art/source/mixamo/scary_zombie_pack/zombie scream.fbx" \
  --in-place walk,hit,getup --out godot/assets/models/zombie_ambusher.glb
```
변환 결과: 뼈 이름 65개 `mixamorig1:` → `mixamorig:` 통일 / 삼각형 29,012 → 9,000 / 그림 2048×2048 다섯 장 → 1024×1024 / 수평 이동 walk 1.379, hit 0.741, getup 0.888 → 모두 0.000 m

- `getup`: 누운 자세(첫 프레임)에서 일어나기. 누워 있는 동안은 첫 프레임에서 멈춰 두고, 8m 안에 들어오면 재생하는 식으로 쓴다 (게임 코드 담당 B 와 맞출 것)
- `scream`: 일어날 때 비명. PRD F-43 의 "일어날 때 비명 효과음" 과 함께 쓴다
- 일어난 뒤 이동은 walk (PRD 1.5 m/s 는 게임 코드가 정한다)

## 검사 (`art/blender/validate.py`) — 통과
| 항목 | 결과 | 규격 |
|---|---|---|
| 그림 | 1024×1024 다섯 장 (Diffuse·Emissive·Normal·Specular·Glossiness) | 5.2 |
| 삼각형 | 9,000 | 5.3 |
| 키 | 1.850 m | 5.2 1.7 - 1.9 m |
| 원점 / 정면 | 발밑 z 0.000 / Godot -Z | 5.2 |
| 애니메이션 | idle, walk, attack, hit, death + getup, scream — 모두 뼈가 움직임 | 5.4 / WU-20 |
| walk 제자리 | 0.000 m | 5.4 |

## Godot 4.7.2
뼈 65개, 메시 1개, 애니메이션 7개 (attack 2.53 · death 2.83 · getup 7.63 · hit 2.20 · idle 4.30 · scream 2.83 · walk 4.07초)

## 눈으로 확인
`getup` 처음(엎드려 누움) → 중간(웅크리고 일어나는 중), `scream` 중간(몸을 숙이고 소리침). `art/previews/zombie_ambusher_*.png` (git 제외).

## 이름 정정 (2026-09-29)
처음에 `get_up` 으로 만들었으나 TECH_SPEC 13.3.1 ①-2 약속 이름은 `getup` 이다 (B 의 코드가 이 이름으로 부른다). `getup` 으로 다시 만들었고, `validate.py` 가 13.3.1 약속의 애니메이션 이름을 검사하도록 했다 (옛 이름 `get_up` 파일은 실패로 잡힘).
