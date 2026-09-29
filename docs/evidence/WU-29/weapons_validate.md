# WU-29 근거 — weapon_pistol.glb · weapon_knife.glb (2026-09-29)

## 권총 `weapon_pistol.glb`
- 원본: Quaternius "Ultimate Guns Pack" 의 Pistol (poly.pizza, **CC0**, 59 KB glb) — 👤 사용자가 후보 4종 중 1번 다운로드를 허락함
  - 원본 위치 `art/source/cc0/quaternius_pistol_3b53f0fe.glb` (git 제외)
- 만든 방법:
  ```bash
  blender -b --factory-startup --python art/blender/prep_weapon.py -- \
    --src art/source/cc0/quaternius_pistol_3b53f0fe.glb --length 0.2 --out godot/assets/models/weapon_pistol.glb
  ```
- 결과: 길이 1.82 → **0.200 m**, 총구 = Godot -Z, 원점 = 손잡이 가운데, 삼각형 1,040, 그림 없음(재질 색 5개), 애니메이션 없음

## 칼 `weapon_knife.glb`
- 외부 에셋 없이 **Blender 스크립트로 제작** (WU-29 "없으면 Blender 스크립트로 제작"). CC0 칼 팩은 190 MB 압축 파일이라 쓰지 않음
  ```bash
  blender -b --factory-startup --python art/blender/make_knife.py -- --out godot/assets/models/weapon_knife.glb
  ```
- 결과: 길이 **0.251 m** (칼날 0.14 m + 가드 + 손잡이 + 폼멜), 칼끝 = Godot -Z, 원점 = 손잡이 가운데, 삼각형 52
- TECH_SPEC 13.3.1 ①-2 모델 목록에 `weapon_knife.glb` 를 추가했다 (칼 모델 담당이 비어 있었음)

## 검사 (`art/blender/validate.py`) — 둘 다 통과
| 항목 | 권총 | 칼 | 규격 |
|---|---|---|---|
| 이름 | `weapon_pistol` | `weapon_knife` | 5.2 |
| 삼각형 | 1,040 | 52 | 5.3 무기 5,000 이하 |
| 길이 | 0.200 m | 0.251 m | 13.3.1 0.2 m / 0.25 m (±10%) |
| 원점 | 손잡이 (모델 안, 앞쪽이 더 김) | 손잡이 | 13.3.1 "원점 = 손잡이" |
| 앞쪽 | Godot -Z | Godot -Z | 13.3.1 ①-1 "정면 -Z" |

검사기 자체 시험: 모델을 180° 돌린 권총 → "앞쪽이 Godot -Z 가 아님" 실패, 10배 큰 칼 → "길이 2.505 m 가 약속 0.25 m 와 다름" 실패. 좀비 4종은 그대로 통과.

## Godot 4.7.2
| 파일 | 메시 | 애니메이션 | 앞(-Z) 끝 | 뒤(+Z) 끝 | 길이 |
|---|---|---|---|---|---|
| weapon_pistol | 1 | 없음 | -0.166 | 0.034 | 0.200 m |
| weapon_knife | 1 | 없음 | -0.197 | 0.054 | 0.250 m |

## 눈으로 확인
`art/previews/weapon_pistol_side.png`(옆), `weapon_pistol_front_view_from_muzzle.png`(총구 쪽에서 구멍이 보임), `weapon_knife_side.png`, `weapon_knife_three_quarter.png` (git 제외)

## WU-29 남은 것
- `prop_supply_crate.glb` (낙하산 보급 상자)
- 이펙트 4종 `scenes/fx/` (총구 섬광, 피격, 빨간 연막, 충돌 먼지) — Godot 프로젝트(WU-05 공통 뼈대)가 있어야 장면을 만들 수 있다
