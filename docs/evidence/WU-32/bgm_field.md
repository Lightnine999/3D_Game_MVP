# WU-32 근거 — 게임 배경음 `bgm_field.ogg` (2026-09-29)

## 곡
- "Horror Atmosphere" 페이지의 **Post Apocalyptic Wastelands [Loop Ready]** — Juhani Junkala (SubspaceAudio), **CC0**
  - https://opengameart.org/content/horror-atmosphere
  - 제작자 설명: 공포 게임·포스트 아포칼립스에 맞는 드문드문한 분위기 곡, 주로 으스스한 분위기음과 배경 소음, 끊김 없이 반복되게 제작
- 고른 이유: PRD F-62 "배경음(공포 앰비언트)". 멜로디보다 소음 위주라 좀비 신음·발소리(효과음)를 가리지 않는다
- 👤 사용자가 CC0 후보 3곡 중 1번으로 골랐다. 원본 5분 23초·13.6 MB 는 `art/source/audio/` (git 제외)

## 만든 방법 (Blender 내장 오디오 도구 aud, 추가 설치 없음)
```bash
blender -b --factory-startup --python art/blender/make_bgm_loop.py -- \
  --src art/source/audio/juhani_junkala_post_apocalyptic_wastelands_loop.ogg \
  --length 150 --crossfade 3 --bitrate 96000 --out godot/assets/audio/bgm_field.ogg
```
- 원본 앞 150초를 쓰고, 150초 뒤에 이어지는 3초를 서서히 줄이며 곡 시작에 겹쳐 **끝 → 처음이 이어지게** 했다
- 요청 길이 120 - 180초의 가운데인 150초

## 검사
| 항목 | 결과 |
|---|---|
| 길이 | 150.00 초, 44,100 Hz 스테레오 |
| 크기 | 13.6 MB → **1.6 MB** |
| 이음새 세기 | 끝 50 ms 0.0074 / 처음 50 ms 0.0099 (갑자기 커지거나 작아지지 않음) |
| 이음새 튐 | 끝 → 처음 샘플 차 0.0228 = 곡 안 이웃 샘플 차의 상위 1.73% 수준 (상위 1% 기준 0.0265 보다 작음) → 딸깍 소리 가능성 낮음 |
| 크기 수준 | 최고 0.958, 평균 -21.5 dBFS |
| Godot 4.7.2 | `AudioStreamOggVorbis`, 길이 150.00 초, `loop = true` 설정 동작 |

## C 에게 전달 (13.3.1 ①-5 "배경음 → C 의 main 이 재생")
- 재생할 때 **반복을 켜야** 한다: 가져오기 설정(Import 탭)의 Loop 를 켜거나, 코드에서 `stream.loop = true`
- `BGM` 버스로 재생한다. 효과음을 가리지 않게 BGM 버스 음량을 SFX 보다 낮게 시작하는 것을 권장

## 남은 확인 (👤)
- 저는 소리를 직접 들을 수 없다. 이음새(150초 → 0초)에서 끊김·딸깍 소리가 없는지, 분위기가 맞는지 **사람이 들어 확인**해야 한다
