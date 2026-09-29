# HUD 아이콘 · 무기 표시 시안 (A → C 전달)

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

## 시안 — 1920×1080 (TECH_SPEC 6.1 기준 해상도)

| 파일 | 내용 |
|---|---|
| `hud_mock_full.png` | 게임 화면 전체: 최상단 중앙 무기 표시 → 그 아래 진행 막대(F-54) / 오른쪽 위 일시정지 / 오른쪽 아래 사격 버튼(F-11) |
| `hud_mock_states.png` | 무기 표시 세 상태: ① 8발·칼 있음 ② 0발 ③ 칼 사용 뒤 |

배경 좀비는 A 의 좀비 모델을 찍은 것이고, 길·안개는 대충 그린 것이다.
글씨는 윈도우 기본 글꼴(맑은 고딕)로 그렸고 게임에는 넣지 않는다 — 게임 글꼴은 C 가 정한다.

## 다시 만들기

```bash
blender -b --factory-startup --python art/blender/render_icons.py   # 모델 촬영 → art/previews/icons_raw/ (커밋 안 함)
python art/ui/finish_icons.py                                       # 테두리 → art/ui/icons/
python art/ui/make_hud_mock.py                                      # 시안 → art/ui/hud_mock_*.png
```
