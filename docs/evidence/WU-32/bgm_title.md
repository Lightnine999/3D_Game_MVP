# WU-32 근거 — 타이틀 배경음 `bgm_title.ogg` (2026-09-29)

## 곡
- **Oldschool Horror Theme** — EmoPreben, **CC0** — https://opengameart.org/content/oldschool-horror-theme
- 제작자가 **메뉴 음악**으로 만든 곡 (원본 3분 18초, 7.3 MB). 👤 사용자가 CC0 후보 3곡 중 2번을 타이틀용으로 골랐다
- 원본은 `art/source/audio/emopreben_oldschool_horror_theme.ogg` (git 제외)

## 만든 방법
```bash
blender -b --factory-startup --python art/blender/make_bgm_loop.py -- \
  --src art/source/audio/emopreben_oldschool_horror_theme.ogg \
  --length 180 --crossfade 4 --bitrate 96000 --out godot/assets/audio/bgm_title.ogg
```
- 멜로디가 있는 곡이라 너무 짧게 자르면 중간에 끊긴 느낌이 난다 → 요청 범위(120 - 180초)의 최대인 **180초**, 이음은 게임 배경음(3초)보다 긴 **4초**

## 검사
| 항목 | 결과 |
|---|---|
| 길이 | 180.00 초, 44,100 Hz 스테레오 |
| 크기 | 7.3 MB → **1.9 MB** |
| 이음새 세기 | 끝 50 ms 0.0781 / 처음 50 ms 0.0903 |
| 이음새 튐 | 끝 → 처음 샘플 차 0.0122 — 곡 안 **보통** 이웃 샘플 차(중간값 0.0191)보다도 작음 |
| 크기 수준 | 최고 0.615, 평균 -19.6 dBFS (게임 배경음 -21.5 dBFS 보다 약간 큼 — 타이틀이라 괜찮음) |
| Godot 4.7.2 | `AudioStreamOggVorbis`, 180.00 초, `loop = true` 동작 |

## C 에게 전달
- 13.3.1 ①-5 "`bgm_title` (타이틀) → C 의 `main` 이 재생". 반복을 켜고(`stream.loop = true`), `BGM` 버스로 재생

## 남은 확인 (👤)
- 소리를 사람이 들어 확인: 3분 지점(180초)에서 처음으로 넘어갈 때 멜로디가 어색하게 끊기지 않는지
