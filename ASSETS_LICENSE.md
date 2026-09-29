# ASSETS_LICENSE — 외부 에셋 출처·라이선스 기록

게임에 들어가는 **모든 외부 에셋**(직접 스크립트로 만든 것 제외)을 여기에 기록한다 (TECH_SPEC 3.2, FINAL_CHECKLIST 7.2).

## 규칙
1. 에셋을 받기 **전에** 출처·라이선스를 확인하고, 받은 날 바로 기록한다.
2. 라이선스는 **CC0 우선**. CC-BY는 크레딧 표기 위치를 반드시 적는다.
3. Mixamo 원본(FBX)은 `art/source/`에만 두고 커밋하지 않는다 (재배포 금지).
4. AI 생성물(OpenAI 이미지, AI 음악)은 **상업 이용 가능 여부**를 확인해 적는다.
5. 라이선스가 불분명하면 쓰지 않는다.

## 기록 양식
| 에셋명 | 종류 | 출처 URL | 제작자 | 라이선스 | 상업 이용 | 크레딧 표기 위치 | 다운로드일 | 사용 위치 (파일) |
|---|---|---|---|---|---|---|---|---|
| (예시) 권총 모델 | 3D 모델 | https://example.com/... | 제작자명 | CC0 | 가능 | 불필요 | YYYY-MM-DD | `godot/assets/models/weapon_pistol.glb` |

## 3D 모델
| 에셋명 | 종류 | 출처 URL | 제작자 | 라이선스 | 상업 이용 | 크레딧 표기 위치 | 다운로드일 | 사용 위치 (파일) |
|---|---|---|---|---|---|---|---|---|

## 캐릭터·애니메이션 (Mixamo)
| 캐릭터/모션명 | 종류 | 출처 URL | 제작자 | 라이선스 | 상업 이용 | 크레딧 표기 위치 | 다운로드일 | 사용 위치 (파일) |
|---|---|---|---|---|---|---|---|---|
| X Bot | 캐릭터 (Scary Zombie Pack 포함) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb` |
| zombie idle | 애니메이션 → `idle` | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb`, `godot/assets/models/zombie_tank.glb`, `godot/assets/models/zombie_runner.glb` |
| zombie walk | 애니메이션 → `walk` (제자리로 변환) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb`, `godot/assets/models/zombie_tank.glb`, `godot/assets/models/zombie_runner.glb` |
| zombie run | 애니메이션 → `run` (제자리로 변환) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb`, `godot/assets/models/zombie_runner.glb` |
| zombie attack | 애니메이션 → `attack` | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb`, `godot/assets/models/zombie_tank.glb`, `godot/assets/models/zombie_runner.glb` |
| zombie death | 애니메이션 → `death` | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb`, `godot/assets/models/zombie_tank.glb`, `godot/assets/models/zombie_runner.glb` |
| Zombie Reaction Hit | 애니메이션 → `hit` (제자리로 변환) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_walker.glb`, `godot/assets/models/zombie_tank.glb`, `godot/assets/models/zombie_runner.glb` |
| PumpkinHulk | 캐릭터 (탱커, 키 2.2 m 로 키움, 그림 1024 로 줄임) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_tank.glb` |
| Ch10 | 캐릭터 (러너, 삼각형 49,593 → 9,000, 그림 4096 → 1024) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | `godot/assets/models/zombie_runner.glb` |
| Getting Up | 애니메이션 (매복 좀비 일어나기 예정) | https://www.mixamo.com/ | Adobe (Mixamo) | Mixamo 이용 약관 (게임 내 사용 무료, 원본 재배포 금지) | 가능 (TECH_SPEC 3.2 기준, 출시 전 Adobe 약관 재확인) | 불필요 | 2026-09-29 | 아직 사용 안 함 (`zombie_ambusher.glb` 예정) |

## 사운드
| 에셋명 | 종류 | 출처 URL | 제작자 | 라이선스 | 상업 이용 | 크레딧 표기 위치 | 다운로드일 | 사용 위치 (파일) |
|---|---|---|---|---|---|---|---|---|

## AI 생성물
| 결과물 | 도구 | 요금제 | 이용 약관 확인일 | 상업 이용 | 사용 위치 (파일) |
|---|---|---|---|---|---|
