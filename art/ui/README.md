# HUD 아이콘 (A → C 전달)

HUD 는 C 의 일이다 — WU-31 "HUD: 진행 막대, 탄약 수, 칼 아이콘, 사격 버튼, 일시정지 버튼",
TECH_SPEC "`godot/assets/ui/` (C) 아이콘·폰트·UI 테마".
A 는 **그림만** 만들어 여기(`art/ui/`)에 둔다. C 의 폴더에는 넣지 않았다.
쓸 아이콘은 C 가 `godot/assets/ui/` 로 복사해서 쓴다.

## 정해진 모양 — PRD F-78

> HUD **무기 표시**: **화면 최상단 중앙**(진행 막대보다 위)에 권총 아이콘과 남은 탄약 수를 숫자로 보여준다.
> **탄약이 0발이면 권총 아이콘을 흐리게** 하고 숫자는 `0`으로 표시한다.
> 칼은 가지고 있으면 칼 아이콘을 보여주고, **1회 사용하면 아이콘이 없어진다** (F-35).

| 상태 | 화면 |
|---|---|
| 탄약 있음 | `icon_pistol.png` + 숫자 (흰색) |
| 탄약 0발 | `icon_pistol_empty.png` (흐린 권총) + `0` (시안에서는 빨간색) — 사격 버튼도 흐리게 (F-13) |
| 칼 있음 | `icon_knife.png` 표시 |
| 칼 사용 뒤 | 칼 아이콘을 **숨긴다** (흐린 그림 없음). 판 너비가 줄어 권총만 가운데 남는다 |

## 아이콘 — `art/ui/icons/`

모두 256×256 PNG, 투명 배경, 어두운 테두리·옅은 밝은 테·그림자 포함.
권총·칼·보급 상자는 게임 3D 모델을 그대로 찍어 화면 속 물건과 모양이 같다.

| 파일 | 무엇 | 찍은 모델 |
|---|---|---|
| `icon_pistol.png` | 권총 옆모습, 총구가 오른쪽 | `weapon_pistol.glb` |
| `icon_pistol_empty.png` | 흐린 권총 (0발) | 위 그림을 흐리게 |
| `icon_knife.png` | 칼, 칼날이 오른쪽 위 | `weapon_knife.glb` |
| `icon_ammo.png` | 탄약 한 발 — F-78 에서는 안 쓴다. 조작 안내(F-71)·보급 알림 등에 필요하면 사용 | 아이콘용으로 따로 만듦 |
| `icon_supply.png` | 보급 상자 (낙하산 빼고) — F-78 에서는 안 쓴다. 조작 안내(F-71) 보급 설명 등에 사용 | `prop_supply_crate.glb` |

Godot: 가져오기 설정은 기본값(Lossless), `TextureRect` 의 `expand_mode` 로 줄여 쓴다 (시안 기준 권총 60 px · 칼 55 px · 숫자 38 px — 처음 시안의 절반으로 줄였다).

## 다시 만들기

```bash
blender -b --factory-startup --python art/blender/render_icons.py   # 모델 촬영 → art/previews/icons_raw/ (커밋 안 함)
python art/ui/finish_icons.py                                       # 테두리 → art/ui/icons/
```
