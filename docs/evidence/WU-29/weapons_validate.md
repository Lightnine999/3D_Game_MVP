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

## 피격 이펙트 `scenes/fx/hit_blood.tscn` (+ `hit_blood.gd`)
좀비가 **총·칼에 맞았을 때** 튀는 피. PRD N-08 "과도한 유혈 표현 없음", TECH_SPEC 13.3.1 ①-4 약속대로 만들었다.

| 항목 | 내용 |
|---|---|
| 구성 | 핏방울 16개(작은 구, 0.45초) + 흐린 붉은 방울 5개(0.35초). `CPUParticles3D` (휴대폰·웹에서 안정) |
| 쓰는 법 (B) | `add_child(fx)` → 위치 지정 → `fx.play()` (총). 칼은 `fx.play(1.5)` 로 조금 더 (0.5 - 2.0 로 제한) |
| 방향 | 노드의 -Z 를 공격한 쪽으로 돌려 두면 피는 뒤쪽으로 튄다 |
| 스스로 사라짐 | 재생 끝(약 0.55초) 뒤 `queue_free` — 자기 안의 Timer 로 처리해 언제 불러도 동작 |
| 과한 유혈 방지 | 바닥에 고이지 않음, 살점·신체 절단 없음, 화면에 피 묻지 않음, 0.5초 안에 사라짐 |

### 시험 (Godot 4.7.2 임시 프로젝트)
- 시작 직후 `play()`: 핏방울 16개 재생 / `play(1.5)`: 24개 재생 / 게임 도중 부름: 재생
- 1.0초 뒤 세 개 모두 스스로 사라짐, 오류 0개
- 처음 만든 판에서 잡은 문제 2개와 고친 방법:
  1. `@onready` 로 노드를 찾게 해서 `add_child` 바로 뒤 `play()` 하면 재생이 안 됐다 → `play()` 안에서 찾도록 고침
  2. 흐린 방울을 네모 판(Quad)으로 만들었더니 1 m 크기의 빨간 네모로 보였다 → 작은 둥근 방울로 바꿈

### 눈으로 확인
워커 좀비 가슴에 맞았을 때 0.08·0.18·0.32초 캡처 (`scratchpad` 의 `hit_blood_*.png`, 저장소에는 넣지 않음): 작은 붉은 방울이 퍼졌다가 핏방울 몇 개가 튀고 떨어지며 사라진다.
