# WU-00 근거 — 폴더 구조와 .gitignore 검증

- 검증일: 2026-09-28
- 저장소: `3D_Game_MVP` 독립 저장소 (`git init -b main`, `git rev-parse --show-toplevel` = `3D_Game_MVP`)

## 1. 무시되어야 하는 파일 (가짜 파일을 만들어 `git check-ignore`로 확인)
| 가짜 파일 | 결과 |
|---|---|
| `.env`, `.env.local` | ✅ 무시됨 |
| `art/source/mixamo/zombie.fbx` | ✅ 무시됨 |
| `art/previews/front.png` | ✅ 무시됨 |
| `build/game.aab` | ✅ 무시됨 |
| `godot/.godot/cache.bin` | ✅ 무시됨 |
| `upload.keystore`, `release.jks` | ✅ 무시됨 |
| `my-service-account.json` | ✅ 무시됨 |
| `godot/export_credentials.cfg` | ✅ 무시됨 |
| `DevelopDoc/.DS_Store` | ✅ 무시됨 |
| `.omc/state`, `DevelopDoc/.omc/state` | ✅ 무시됨 |

## 2. 추적되어야 하는 파일
| 파일 | 결과 |
|---|---|
| `.env.example` (빈 템플릿) | ✅ 추적 가능 |

## 3. 가짜 파일을 둔 상태의 `git status --short -uall`
문서 7개와 빈 폴더 표시용 `.gitkeep` 7개만 나타났고, 비밀·원본·산출물 경로는 하나도 나타나지 않았다.

## 4. 정리
- 가짜 파일은 검증 후 삭제했다.
- 단, `.env`와 `.env.local`(내용: `test` 한 줄)은 env 파일 삭제를 막는 보안 훅 때문에 삭제하지 않았다. 두 파일 모두 git에서 무시되므로 커밋되지 않는다.
