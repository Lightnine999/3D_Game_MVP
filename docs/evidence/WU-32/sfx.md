# WU-32 근거 — 효과음 (2026-09-29)

TECH_SPEC 13.3.1 ①-5 목록의 효과음 **13종 모두** 완료 (`sfx_pistol` 은 직접 합성).

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/make_sfx.py
```
`make_sfx.py` 의 표(RECIPES)에 소리마다 원본·크기를 적어 두었다. 한 줄만 고쳐 다시 만들 수 있다.
처리: mono 로 합치기(3D 방향용) → 앞뒤 조용한 부분 자르기 → (물림만) 두 소리 겹치기 → 최고 크기 맞추기 → 끝 20 ms 줄이기 → Ogg Vorbis mono 44.1 kHz

## 결과 (모두 원본 CC0)
| 이름 | 쓰는 곳 | 원본 | 길이 | 최고 | 크기 |
|---|---|---|---|---|---|
| `sfx_step` | B | Kenney Impact · footstep_grass_000 | 0.12초 | -12 dB (처음 -6, 배경음을 덮어 낮춤) | 4 KB |
| `sfx_breath` | B | Breathing Tired (mikeask) — 원본이 매우 작아(평균 -43.9 dB) 키움 | 3.17초 | -8 dB | 27 KB |
| `sfx_empty_click` | B | Kenney RPG · metalClick | 0.37초 | -6 dB | 6 KB |
| `sfx_zombie_groan` | B | Zombies Sound Pack · zombie-16 | 1.41초 | -3 dB | 13 KB |
| `sfx_zombie_scream` | B | Zombies Sound Pack · zombie-10 | 0.65초 | -1 dB | 8 KB |
| `sfx_supply_pickup` | B | Kenney RPG · handleCoins (탄약 짤랑) | 0.72초 | -4 dB | 9 KB |
| `sfx_knife` | B | Kenney RPG · knifeSlice | 0.37초 | -3 dB | 6 KB |
| `sfx_bite` | B | zombie-24 + Kenney Impact · impactSoft_heavy_000 | 0.45초 | -2 dB | 6 KB |
| `sfx_hit_obstacle` | B | Kenney Impact · impactMetal_heavy_000 (폐차·드럼통) | 0.16초 | -2 dB | 4 KB |
| `sfx_ui_click` | C | Kenney Interface · click_001 | 0.04초 | -8 dB | 4 KB |
| `sfx_ui_purchase` | C | Kenney Interface · confirmation_001 | 0.29초 | -6 dB | 4 KB |
| `sfx_mission_done` | C | Kenney Interface · confirmation_004 | 0.49초 | -4 dB | 5 KB |

## 좀비 소리 고르는 방법
Zombies Sound Pack 의 24개는 이름이 번호뿐이라, 길이·평균 크기·밝기(주파수 무게중심)를 재서 골랐다 (저는 소리를 들을 수 없다).
- 신음 = **가장 낮고 긴** zombie-16 (1.44초, 890 Hz — 24개 중 가장 낮음)
- 비명 = **크고 밝은** zombie-10 (-13.3 dB, 1,885 Hz)
- 물림 = **가장 짧은** zombie-24 (0.33초) 에 살 부딪는 소리를 겹침

## 확인
- Godot 4.7.2: 12개 모두 `AudioStreamOggVorbis` 로 열림, 12개 모두 1채널(mono)
- 👤 사람이 들어서 확인할 것: 좀비 신음·비명이 맞게 골라졌는지, 크기 차이가 자연스러운지

## 총성 `sfx_pistol` — 직접 합성
- 처음 받은 "Gunshot Sounds" (OpenGameArt, 올린 사람 Tabasco) 는 페이지에는 CC0 이지만, **zip 안 `creativecommons.txt` 에는 "Copyright (c) 2009 Vincent Sevedge … Creative Commons Attribution 3.0"** 이라고 적혀 있다
- ASSETS_LICENSE 규칙 5 "라이선스가 불분명하면 쓰지 않는다" 에 따라 **쓰지 않았다** (원본은 git 제외 폴더에만 있음)
- 👤 사용자가 대안 3가지(직접 합성 / Free Firearm Sound Library 194 MB / 원출처 불분명한 22 Pistol) 중 **직접 합성**을 골랐다
- `make_sfx.py` 의 `synth_pistol()`: 파열음(딱, 20 ms) + 180 → 60 Hz 로 떨어지는 몸통(쿵) + 둔한 폭발 잡음 + 들판 잔향 + 메아리 2번(0.12·0.26초). 난수를 고정해 매번 같은 소리
- 결과: 0.90초, mono, 13 KB. 구간별 세기 0 - 20 ms -5.6 dB → 20 - 100 ms -8.4 → 100 - 200 ms -12.8 → 200 - 400 ms -20.4 → 400 ms 뒤 -33.0 dB
- 고친 문제: 최고 크기 -1 dB 로 만들면 Ogg 압축 뒤 순간값이 1.0 을 넘어 찌그러졌다 (0.175%). -3 dB 로 낮춰도 1.096 → 파열음의 7 kHz 위를 깎고 압축 품질을 96 kbps 로 올려 **찌그러짐 0%** (최고 0.994)
- Godot 4.7.2 에서 13개 모두 열림
- 👤 진짜 녹음보다 덜 사실적일 수 있으니 들어 보고, 필요하면 나중에 CC0 녹음(Free Firearm Sound Library)으로 바꾼다


## 2026-09-30 총성 다시 만들기 — 3가지 + 무작위 재생
- 한 가지 소리만 반복되면 연사할 때 기계처럼 들려서, **합성 총성(매번 다른 난수·낮은 음) + 슬라이드 철컥(Kenney metalLatch) + 탄피가 땅에 떨어지는 소리(Kenney impactMetal_light, 음을 높여 작은 금속처럼)** 를 겹친 3가지를 만들었다
  - `sfx_pistol.ogg` (이름 그대로 — 기존 코드는 바뀌지 않음), `sfx_pistol_2.ogg`, `sfx_pistol_3.ogg` — 각 0.9초, 최고 -3 dB, 압축 뒤 잘림 0%
- `sfx_pistol_random.tres` (AudioStreamRandomizer): 3가지 중 하나를 고르고 음 높이 ±6%, 크기 ±1.5 dB 로 바꿔 낸다
  - **B:** `player.stream = preload("res://assets/audio/sfx_pistol_random.tres")` — `sfx_pistol.ogg` 대신 쓰면 된다 (SFX 버스)
- 원본은 모두 CC0 (Kenney RPG Audio · Impact Sounds, 이미 기록됨)
