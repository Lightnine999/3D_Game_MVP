# 타이틀 이미지 "좀비탈출" (A → C 전달)

타이틀 화면(PRD F-70 "게임 제목, 시작, 설정 버튼, 배경은 안개 낀 들판")은 C 의 일이다. A 는 **그림만** 만들어 여기 둔다.

| 파일 | 내용 |
|---|---|
| `title_zombie_escape.png` | 완성 그림 1920×1080 — 배경 + 제목 + 부제 + "화면을 눌러 시작"(자리 표시) |
| `title_zombie_escape_logo.png` | 제목 글자만 (투명 배경) — C 가 타이틀 화면에 배경·버튼과 따로 올려 쓰도록 |

- 배경: `godot/scenes/stage/title_art.tscn` 으로 **팀 스테이지 맵의 탈출 지점(요새 정문·투광등)** 앞에서 좀비 5마리가 다가오는 장면을 찍었다
- 제목: 굵은 한글 글꼴 → 가장자리를 갉아먹듯 거칠게 → 핏물 흘러내림 → 손톱 긁힘 → 녹슨 핏빛 질감 → 어두운 테두리·붉은 빛 (`make_title.py`)
- 게임 이름 "좀비탈출" 은 사용자가 정했다 (PRD 는 아직 "가칭 · 정식 게임명 미정" — 팀 확인 필요)

## 글꼴 — 주의
윈도우 기본 **맑은 고딕 Bold** 를 썼다. 사용자 결정(2026-09-30): 과제용 비상업이라 괜찮음.
**유료 전환(상용) 전에는** 상업 이용 가능한 OFL 글꼴(예: 검은고딕 Black Han Sans, 도현 Do Hyeon)로 바꿔 다시 만든다 — `make_title.py` 의 `FONT` 한 줄만 바꾸면 된다.

## 다시 만들기
```bash
godot --path godot --resolution 1920x1080 res://scenes/stage/title_art.tscn -- --out=art/previews/title_bg.png
python art/title/make_title.py --bg art/previews/title_bg.png --out art/title/title_zombie_escape.png
```
