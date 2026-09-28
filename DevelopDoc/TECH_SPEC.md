# TECH_SPEC — 3D 좀비 생존 러너 MVP (기술 명세)

| 항목 | 내용 |
|---|---|
| 문서 버전 | v0.4 |
| 작성일 | 2026-09-28 |
| 상태 | DRAFT (검토 중) |
| 가칭 | 3D_Game_MVP (정식 게임명 미정) |
| 레퍼런스 게임 | Into the Dead (PikPok) — 1인칭 자동 달리기 좀비 생존 |
| 관련 문서 | `README.md`, `DevelopDoc/PRD.md`, `DevelopDoc/CONTRACTS.md`, `DevelopDoc/WORK_UNITS.md`, `DevelopDoc/FINAL_CHECKLIST.md` |

> 이 문서는 **무엇으로(도구) 어떻게(구조·규칙) 만드는가**를 정한다.
> **무엇을 만드는가(게임 기획·기능 범위)**는 `PRD.md`에서 정한다.

---

## 1. 개요

### 1.1 한 줄 요약
안개 낀 밤 들판을 1인칭으로 자동 질주하며 좀비를 피하고 쏘는 모바일 3D 생존 게임. Godot 4로 만들고 Google Play에 출시한다.

### 1.2 목표 플랫폼
| 구분 | 내용 |
|---|---|
| 주 플랫폼 | **Android (Google Play)** |
| 화면 방향 | 가로 (Landscape) |
| 보조 플랫폼 | Web (Godot HTML5) — 아이폰 사용자 테스터용 체험판. 앱과 같은 로그인·토스 테스트 결제·채팅 제공 (마감 범위) |
| 일정 | 내부 마감 **2026-10-01 24:00** (머지·코드 동결), 최종 마감 **2026-10-02 10:00** (PRD 0장) |
| 테스트 기기 | **Galaxy S24 Ultra (SM-S928N)** — Android 16(API 36), Snapdragon 8 Gen 3(SM8650), arm64-v8a, 화면 설정 FHD+ 1080×2340(19.5:9, 최대 QHD+ 3120×1440), 가변 최대 120Hz, 펀치홀 카메라. 최상급 기기이므로 중급 기기 기준도 따로 둔다 (10.3). USB 연결 확인: `docs/evidence/WU-03/` |

### 1.3 개발 원칙
1. **바이브 코딩** — Claude가 스크립트·코드·씬 파일을 작성하고 명령줄로 실행·검증한다. Blender와 Godot 에디터를 사람이 열지 않아도 되는 구조를 유지한다.
2. **모든 산출물은 텍스트 우선** — 모델은 Python 스크립트로, 씬은 `.tscn` 텍스트로 관리해 git에서 변경 내용을 추적할 수 있게 한다.
3. **Claude가 눈으로 확인하는 단계** — Blender 미리보기 렌더와 Godot 스크린샷을 PNG로 뽑아 결과를 확인한 뒤 다음 단계로 넘어간다.
4. **마감 범위 우선** — 마감까지 게임 스테이지 1개 + 회원가입·로그인 + 토스 테스트 결제 + 문의·제보 채팅을 완성한다. 구글 결제·비공개 테스트·정식 출시는 마감 이후다.

---

## 2. 핵심 기술 결정 (요약)

| # | 결정 | 이유 | 버린 대안 |
|---|---|---|---|
| D1 | 게임 엔진 **Godot 4** | 씬·리소스가 텍스트 파일이라 Claude가 직접 수정 가능 / 명령줄 빌드 / 무료(MIT) / GDScript가 파이썬과 유사 | Unity — 씬이 YAML+GUID라 스크립트 수정 시 깨지기 쉽고 에디터 작업 비중이 큼 |
| D2 | 렌더러 **Mobile** | Android 대상. 조명·그림자·글로우 품질이 Compatibility보다 좋음 | Forward+ — 모바일 성능 부담 / Compatibility — 웹 체험판에서만 사용 |
| D3 | 안개 표현 **거리·높이 안개 + 안개 판(반투명 평면)** | 볼류메트릭 안개는 Forward+ 전용이라 Mobile에서 사용 불가 | 볼류메트릭 안개 |
| D4 | 배경·소품 **Blender 스크립트 생성** | 로우폴리 소품은 코드로 충분히 생성 가능, 어둠·안개가 디테일을 가려줌 | 수작업 모델링 |
| D5 | 좀비 **Mixamo 캐릭터 + 모션** | 리깅과 좀비 전용 모션(걷기·달리기·공격·사망)이 이미 있음 → 리깅 문제 해소 | Blender 스크립트 리깅 — 인체형 리깅·스키닝 품질 확보가 어려움 |
| D6 | 1인칭 **팔 모델 생략** (MVP) | 총만 화면에 띄우고 흔들림·반동을 코드로 구현 → 리깅 불필요 | Mixamo 팔 모델 |
| D7 | 무기 **CC0 무료 에셋 우선** | 1인칭에서 총이 화면에 크게 보여 품질이 중요 | Blender 스크립트 (에셋이 없을 때 대안) |
| D8 | 결제 **마감 전 = 웹·앱 모두 토스페이먼츠 테스트 결제 / Google Play 출시 버전 = 앱은 Google Play Billing** | 마감 전 테스트는 APK 직접 배포라 Play 정책과 무관하고, 토스 테스트 결제는 Play Console 인증 없이 바로 검증할 수 있다. Play에 올리는 버전부터 앱 결제는 구글 결제로 교체한다(디지털 상품은 Play 결제가 원칙). 두 결제는 서버의 구매 기록·지급 로직(`purchases`, `inventory`)을 공유해 교체 부담을 줄인다 | 마감 전 구글 결제 — Play Console 본인 인증(며칠)과 내부 테스트 업로드가 필요해 마감 내 보장 불가 |
| D9 | 백엔드 **Supabase** (Auth: 익명 로그인 + 이메일·비밀번호) | 게스트(익명) 계정으로 바로 시작하고, 가입 시 같은 계정에 이메일을 연결해 기록이 이어진다. 인증·DB·Edge Function을 한 곳에서 처리 | 자체 서버 / 구글 로그인 — OAuth·앱 서명 등록 설정이 마감 내 부담 |
| D10 | 출시 전략 **MVP 테스트 = Google 비공개 테스트 14일** | 개인 계정의 정식 출시 조건(12명 이상 × 14일 연속)을 피드백 수집 기간과 겹쳐 전체 일정 단축 | 웹 MVP 후 별도 비공개 테스트 |
| D11 | 카메라 **세로 시야 고정(Keep Height)** | 화면이 넓은 폰일수록 좌우가 더 보여 와이드한 들판 느낌(PRD F-66)을 준다. 세로 시야가 고정이라 좀비 크기·UI 판단이 기종마다 달라지지 않는다 | 가로 시야 고정 — 넓은 폰에서 위아래가 잘려 답답해짐 |
| D12 | 미션 **데이터 분리 (Resource)** | 스테이지 추가 시 코드 수정 없이 미션만 추가 (PRD F-95) | 미션을 코드에 직접 작성 |
| D13 | 문의·제보 채팅 **OpenAI API를 Edge Function에서 호출** | API 키를 서버에만 두고, 사용량 제한·대화 저장·제보 정리를 한 곳에서 처리 (PRD 4.13) | 게임에서 OpenAI 직접 호출 — 키 노출 |
| D15 | 관리자 **Supabase 관리 화면(Studio) + 관리자 역할 + 전용 보기(뷰)** | 마감 72시간 안에 관리자 웹 페이지를 새로 만들면 C가 과부하. Studio는 표 조회·수정·검색을 이미 제공하므로 권한(RLS)과 보기만 만든다 (PRD 4.14) | 전용 관리자 웹 페이지 — 약 3시간 추가 (P2) |
| D16 | 협업 **기능 단위 소유 + 약속서 + 가짜 부품 + 하루 두 번 조립** | 한 기능의 장면·스크립트·DB 표·서버 함수를 한 사람이 맡아 파일 충돌을 막고, 담당 간 경계는 CONTRACTS.md의 약속(이름·신호·크기)으로만 연결한다. 기다리지 않도록 가짜 부품으로 먼저 만들고 같은 이름으로 교체한다 | 업무 종류별 분담(장면은 C, 스크립트는 B 등) — 같은 파일 동시 수정으로 충돌 |
| D14 | 앱 결제 결과 **폰 브라우저 결제 + 앱 복귀 시 서버 조회** | Godot에는 기본 인앱 웹뷰가 없다. 결제는 시스템 브라우저에서 하고, 앱으로 돌아오면(`NOTIFICATION_APPLICATION_RESUMED`) 서버의 주문 상태를 조회해 반영한다. 결제창 표시를 믿지 않으므로 보안상으로도 유리 | 인앱 웹뷰 플러그인 — 추가 의존성·호환성 위험 / 딥링크 — Gradle 빌드·매니페스트 수정 필요 |

---

## 3. 기술 스택

### 3.1 개발 도구
| 영역 | 도구 | 버전 | 설치 상태 | 조작 주체 |
|---|---|---|---|---|
| 게임 엔진 | Godot | **4.7.2 stable** | ✅ 설치됨 (`/opt/homebrew/bin/godot`), 내보내기 템플릿 4.7.2 설치됨 | Claude |
| 스크립트 언어 | GDScript | Godot 번들 | - | Claude |
| 3D 모델링 | Blender (headless, Python `bpy`) | 5.2.2 LTS | ✅ 설치됨 (`/opt/homebrew/bin/blender`) | Claude |
| 콘셉트 아트 | 나노바나나 (Gemini 이미지 생성 API) | - | API 키 필요 | Claude (키 설정은 사용자) |
| 캐릭터·모션 | Mixamo (Adobe) | - | Adobe 계정 필요 | 다운로드는 사용자, 정리는 Claude |
| 테스트 프레임워크 | GUT (Godot Unit Test) | Godot 4 호환판 | 미설치 | Claude |
| Android 빌드 | OpenJDK 17, Android SDK (platform-tools, build-tools 35.0.1, platforms android-35, cmdline-tools, cmake 3.10.2.4988404, ndk 28.1.13356709) | Godot 4.7 공식 문서 요구 버전 | ✅ 설치됨 (`JAVA_HOME`, `ANDROID_HOME`은 `~/.zshrc`에 등록) | Claude |
| 백엔드 | Supabase (Postgres, Auth, Edge Functions) + Supabase CLI | CLI 2.118.0, Deno 2.9.6 | ✅ CLI 설치됨, 프로젝트 생성 필요 | Claude (프로젝트 생성은 사용자) |
| 결제 (앱) | Google Play Billing + Godot Google Play Billing 플러그인 | 설치 시 Godot 버전 호환 확인 | - | Claude |
| 결제 (웹, 테스트) | 토스페이먼츠 결제위젯 JavaScript SDK + 테스트 키 | 구현 시 공식 가이드로 최신 버전 확인 | 개발자센터 가입 필요 | Claude (가입·키 확인은 사용자) |
| 웹 호스팅 | Vercel (웹 체험판 + **토스 결제 페이지**·성공·실패 페이지) | CLI 59.16.0 | ✅ CLI 설치됨 | Claude |
| LLM (채팅) | OpenAI API (Edge Function에서 호출) | 모델은 구현 시 공식 문서로 확인 (Q8) | API 키 필요 | Claude (키 발급·Secrets 등록은 사용자) |
| 배포 | Google Play Console | - | 개발자 계정 필요 | 사용자 (첫 업로드), 이후 선택적 자동화 |
| 런타임 (보조) | Node.js | v22 | ✅ 설치됨 | 보조 스크립트용 |

> 모든 버전은 설치 시점에 공식 문서로 재확인하고 이 표를 갱신한다. 특히 Blender 5.x는 `bpy` API가 이전 버전과 다를 수 있으므로 코드 작성 전 문서를 조회한다.

### 3.2 에셋 출처
| 에셋 | 1순위 | 2순위 | 라이선스 조건 |
|---|---|---|---|
| 콘셉트 이미지 | 나노바나나 | - | 생성 이미지 이용 약관 확인 |
| 배경·소품 | Blender 스크립트 | CC0 에셋 (Kenney, Quaternius, Poly Pizza) | CC0 |
| 무기 (총·칼) | CC0 에셋 | Blender 스크립트 | CC0 (받기 전 출처·라이선스 확인) |
| 좀비 캐릭터·모션 | Mixamo | 나노바나나 → AI 3D 생성(Tripo/Meshy) → Mixamo 자동 리깅 (MVP 이후) | Mixamo: 게임 내 사용 무료, **원본 파일 재배포 금지** |
| 효과음 | Kenney 오디오 (CC0) | freesound.org | 파일별 라이선스 확인 (CC0 우선, CC-BY는 크레딧 표기) |
| 배경음 | AI 음악 도구 (예: Suno) | CC0 음원 | **무료 요금제는 상업 이용 불가일 수 있음 → 출시 전 확인** |

모든 외부 에셋은 `ASSETS_LICENSE.md`에 출처·라이선스·다운로드일을 기록한다 (11장 참고).

---

## 4. 시스템 아키텍처

```
┌──────────────────────── 에셋 파이프라인 (로컬, 명령줄) ────────────────────────┐
│                                                                              │
│  나노바나나 ──→ art/concept/*.png (분위기 정답지)                               │
│                                                                              │
│  Blender 스크립트 ─┐                                                          │
│  CC0 무기 에셋 ────┼──→ Blender 정리 스크립트 ──→ 자동 검사 ──→ *.glb            │
│  Mixamo FBX ──────┘     (크기·원점·이름·폴리곤)     │                           │
│                                                  └──→ 미리보기 PNG (Claude 확인) │
└──────────────────────────────────────────────────────┬───────────────────────┘
                                                       ↓
┌──────────────────────── Godot 4 클라이언트 (Android) ──────────────────────────┐
│  godot/assets/models/*.glb → 씬(.tscn) + GDScript                              │
│  ├─ 게임 루프 (달리기·좀비·사격·스폰)                                             │
│  ├─ UI (HUD, 결과 화면, 상점)                                                   │
│  ├─ BackendClient ──── HTTPS ────┐                                            │
│  └─ BillingClient ── Play 결제 ──┼───────────┐                                 │
└──────────────────────────────────┼───────────┼────────────────────────────────┘
                                   ↓           ↓
┌────────────── Supabase ──────────────┐   ┌──── Google Play ────┐
│ Auth (익명 로그인)                     │   │ Play Billing         │
│ Postgres (profiles/scores/purchases)  │←──│ Play Developer API   │
│ Edge Functions                        │──→│ (구매 검증·확인 처리)  │
│  ├─ submit-score (점수 검증)           │   └─────────────────────┘
│  ├─ verify-google-purchase (결제 검증) │
│  ├─ create-toss-order (주문 생성)       │
│  ├─ confirm-toss-payment (결제 승인)    │
│  └─ support-chat (문의·제보 → OpenAI)  │──→ OpenAI API
└──────────────────────────────────────┘
          ↑
   Vercel: 토스 결제 페이지 (웹 게임·앱 공통) ──→ Toss Payments (테스트)
```

- **마감 범위**: Supabase Auth(게스트·이메일), 토스 테스트 결제(웹·앱 공통 결제 페이지, 8.5), 문의·제보 채팅(7.5).
- 웹 빌드는 같은 Godot 프로젝트를 웹으로 내보내 Vercel에 올린다. 로그인·결제·채팅은 앱과 같은 서버를 쓴다.
- 위 그림의 Google Play Billing 경로(`verify-google-purchase`)는 **마감 이후** Play 출시 버전에서 사용한다.

---

## 5. 에셋 파이프라인

### 5.1 단계
| 단계 | 입력 | 처리 | 출력 | 실행 |
|---|---|---|---|---|
| 1. 콘셉트 | 프롬프트 | 나노바나나 이미지 생성 | `art/concept/*.png` | API 스크립트 |
| 2. 생성 | 파라미터 | Blender 모델 생성 스크립트 | `.blend` (중간 산출물) | `blender -b -P art/blender/make_*.py -- <옵션>` |
| 3. 가져오기 | Mixamo FBX, CC0 에셋 | Blender 정리 스크립트 (크기·원점·이름 통일, 폴리곤 감소) | `.blend` | `blender -b -P art/blender/import_*.py -- <파일>` |
| 4. 미리보기 | `.blend` | 4방향 렌더 + 애니메이션 프레임 모음 이미지 | `art/previews/*.png` | `blender -b -P art/blender/render_preview.py` |
| 5. 검사 | `.blend` / `.glb` | 규칙 검사 (5.3) | 통과/실패 리포트 | `art/blender/validate.py` |
| 6. 내보내기 | `.blend` | glTF 2.0 바이너리 | `godot/assets/models/*.glb` | `art/blender/export_glb.py` |
| 7. Godot 가져오기 | `.glb` | Godot 리소스 가져오기 | `.import` | `godot --headless --path godot --import` |

전 단계를 `pipeline.sh`로 묶는다.
```bash
./pipeline.sh asset zombie_walker   # 에셋 하나를 생성부터 Godot 가져오기까지
./pipeline.sh assets                # 전체 에셋
```

### 5.2 공통 규격
| 항목 | 규격 |
|---|---|
| 단위 | 1 Blender unit = 1 m = 1 Godot unit |
| 축 | glTF 내보내기 기본값 사용 (Blender Z-up → glTF Y-up 자동 변환). Godot에서 캐릭터 정면은 -Z |
| 원점 | 캐릭터·소품 모두 **발밑 중앙** (지면 y = 0) |
| 좀비 키 | 1.7 - 1.9 m |
| 텍스처 | 최대 1024×1024, Godot에서 VRAM 압축(ETC2/ASTC) |
| 재질 | 로우폴리 단색/팔레트 텍스처 우선, 재질 수 최소화 |
| 파일 이름 | `소문자_스네이크케이스` — 예: `zombie_walker.glb`, `prop_barn.glb`, `weapon_pistol.glb` |
| 접두사 | `zombie_` 좀비 / `prop_` 소품 / `obs_` 장애물 / `env_` 지형 타일 / `weapon_` 무기 / `fx_` 이펙트 (전체 목록: CONTRACTS ①-2) |

### 5.3 폴리곤·성능 예산 (자동 검사 기준)
| 대상 | 삼각형 수 상한 |
|---|---|
| 좀비 1마리 | 10,000 |
| 무기 1개 | 5,000 |
| 소품 1개 | 2,000 |
| 지형 타일 1개 | 5,000 |
| 화면 전체 (동시 표시) | 300,000 |

검사 스크립트는 위 상한 초과, 원점 위치 오류, 크기 이상(좀비 키 범위 이탈), 애니메이션 이름 누락을 **실패**로 보고한다.

### 5.4 좀비 애니메이션 규격
| 애니메이션 이름 | 용도 | Mixamo 다운로드 옵션 |
|---|---|---|
| `idle` | 대기 | - |
| `walk` | 느린 좀비 이동 | **In Place** 체크 |
| `run` | 빠른 좀비 이동 | **In Place** 체크 |
| `attack` | 공격 | - |
| `hit` | 피격 | - |
| `death` | 사망 | - |

- 모든 좀비는 Mixamo 동일 뼈대를 사용해 애니메이션을 공유한다 (Godot 리타깃).
- 이동은 코드가 담당하므로 이동 모션은 반드시 **In Place**로 받는다.
- 다운로드 목록(캐릭터·모션·옵션)은 작업 단위에서 Claude가 정리해 사용자에게 전달한다.

### 5.5 1인칭 무기 (Viewmodel)
- 팔 모델 없이 무기만 카메라 앞에 배치한다.
- 걷기 흔들림(bob), 사격 반동(recoil), 재장전 동작은 코드(Tween)로 구현한다.

---

## 6. Godot 클라이언트

### 6.1 프로젝트 설정
| 항목 | 값 |
|---|---|
| 렌더러 | Mobile |
| 화면 방향 | Landscape (sensor landscape) |
| 기준 해상도 | 1920×1080, stretch mode `canvas_items`, aspect `expand` |
| 물리 | Godot 기본 3D 물리 (필요 시 Jolt 검토) |
| 입력 | 터치 + 개발용 키보드/마우스 동시 지원 |
| 카메라 비율 | `keep_aspect = KEEP_HEIGHT` — 세로 시야(FOV) 고정, 넓은 화면일수록 좌우 시야 확장 (D11) |
| 세로 시야 | 초기값 60° (와이드 폰 21:9에서 가로 시야가 과하게 왜곡되지 않는지 확인 후 조정) |
| 지원 비율 | 16:9 - 21:9 가로. `aspect = expand`로 검은 띠 없이 꽉 채움 |
| Safe area | `DisplayServer.get_display_safe_area()`로 노치·카메라 구멍 영역을 받아 HUD 여백에 반영 |

### 6.1.1 깊이감 층 구성 (PRD F-67, F-68)
| 층 | 거리 | 내용 | 표현 |
|---|---|---|---|
| 근경 | 0-10m | 풀, 소품, 장애물 | 선명, 빠르게 스쳐 지나감 |
| 중경 | 10-40m | 좀비, 장애물, 보급 상자 | 안개로 점점 흐려짐 (플레이 영역) |
| 원경 | 40-150m | 나무 줄, 헛간 불빛, 송전탑 실루엣 | 단순한 저폴리 판(카드)으로 그리고 안개 색에 거의 묻힘 |
| 배경 | 무한 | 밤하늘, 달, 구름 | 하늘 셰이더 (카메라와 함께 이동) |

- 원경 실루엣은 플레이어와 함께 천천히 따라와 **달려도 멀리 있는 것은 느리게 움직이는** 시차(패럴랙스)를 만든다.
- 이동 가능 폭 바깥에도 저폴리 들판·나무 줄을 배치해 화면 끝에서 세계가 끊기지 않게 한다. 바깥 영역은 충돌·AI 계산을 하지 않는다.

### 6.2 폴더 구조 (Godot 프로젝트) — 괄호는 소유자 (13.1)
장면(.tscn)과 그 스크립트(.gd)는 **같은 소유자**가 맡는다.
```
godot/
├── project.godot              (C) 입력 키·충돌 레이어는 CONTRACTS ④
├── export_presets.cfg         (C)
├── assets/
│   ├── models/                (A) .glb (파이프라인 출력, 1단계는 가짜 부품)
│   ├── audio/                 (A)
│   └── ui/                    (C) 아이콘·폰트·UI 테마
├── scenes/
│   ├── main.tscn              (C) 진입점·화면 전환 (GameLayer + UILayer, CONTRACTS ④)
│   ├── game/                  (B) game.tscn — 한 판 조립 (A의 환경·타일 + 플레이어 + 스포너)
│   ├── stage/                 (A) 지형 타일, 환경(안개·조명), 원경, 헛간·탈출 트럭 배치물
│   ├── fx/                    (A) 총구 섬광, 피격, 연막, 먼지
│   ├── actors/                (B) player, zombie
│   ├── weapons/               (B) pistol, supply_drop
│   ├── debug/                 (B) 테스트 패널
│   └── ui/                    (C) hud, stage_card, result, shop, account, support_chat, settings
├── scripts/                   ← scenes/와 같은 구조, 같은 소유자
│   ├── stage/                 (A) far_layers(원경 시차) 등 연출 스크립트
│   ├── core/                  (B) game_state(신호 약속 ②), run_controller, stage_stream, spawner, mission_system, difficulty_config
│   ├── actors/  weapons/  debug/   (B)
│   ├── services/              (C) backend_client, auth_client, payment_client, support_chat, session(약속 ③)
│   └── ui/                    (C)
├── data/                      (B) stage_data.tres (미션·스테이지 정보)
└── tests/                     각자 자기 기능의 테스트 (tests/b_*, tests/c_*)
```

### 6.3 모듈 책임
| 모듈 | 책임 | 의존 |
|---|---|---|
| `run_controller` | 자동 전진, 좌우 이동, 달린 거리 계산 | 입력 |
| `spawner` | 전방 좀비·소품·아이템 배치, 피할 수 없는 배치 방지 | 난이도 설정 |
| `zombie_ai` | 상태 머신 (대기 → 추적 → 공격 → 사망), 애니메이션 전환 | 플레이어 위치 |
| `weapon` | 사격(레이캐스트), 탄약, 재장전, 반동 | 입력, 좀비 피격 |
| `game_state` | 체력, 점수, 게임오버, 결과 | 모든 게임 모듈 |
| `difficulty_config` | 밸런스 상수 전부 (속도, 스폰 간격, 좀비 수, 장애물 감속) — **밸런스 조정은 이 파일만 수정** | 없음 |
| `camera_rig` | 1인칭 카메라, Keep Height 비율, 흔들림(bob·충돌·잡힘), 원경 시차 | run_controller |
| `obstacle` | 폐차·드럼통·쓰레기 더미 충돌 판정, 비틀거림 + 감속(1초, 50%) | run_controller |
| `mission_system` | 미션 정의(Resource) 로드, 게임 이벤트(처치·도착·구역 통과) 구독, 달성 판정, 로컬 저장 | game_state |
| `stage_data` | 스테이지 이름·설명·목표 거리·대표 이미지·미션 3개 (Resource, `.tres` 텍스트) | 없음 |
| `backend_client` | Supabase 인증, 점수 제출, 인벤토리 조회 | Supabase |
| `auth_client` | 게스트 자동 로그인, 이메일 가입(게스트 계정에 연결)·로그인·로그아웃, 세션 저장·갱신 (7.4) | Supabase Auth |
| `payment_client` | 토스 테스트 결제: 주문 생성 요청 → 웹은 결제 페이지로 이동 / 앱은 브라우저로 열기 → 복귀 시 주문 상태 조회 (8.5) | backend_client, auth_client |
| `support_chat` | 문의·제보 채팅 UI, 메시지 전송, 버그 제보 시 기기·게임 정보 자동 첨부 (7.5) | backend_client, auth_client |
| `billing_client` | (마감 이후) Play 결제 연결·구매·검증 요청 | Billing 플러그인, backend_client |
| `session` | 로그인 상태·구매 효과 등 서비스 → 게임 전달값 (`is_logged_in`, `is_admin`, `start_ammo_bonus`) — CONTRACTS ③ | auth_client, payment_client |
| `test_panel` | 테스트 모드 패널 (무적, 거리 건너뛰기, 탄약·칼 지급, 좀비 소환, FPS 표시). 디버그 빌드 또는 `session.is_admin`일 때만 활성 (PRD 4.15) | game_state, session |
| `far_layers` (A) | 원경 실루엣의 시차 이동 (6.1.1) | camera_rig 위치 읽기만 |

게임 로직 모듈은 `backend_client`·`billing_client` 없이도 동작해야 한다 (오프라인 플레이 가능, 테스트 용이).

### 6.3.1 미션 판정 구조
```
game_state ── 이벤트 발행 ──→ mission_system
  zombie_killed(type)          미션마다 조건 검사
  zone_entered(zone_id)        예: {type: "kill_count", target: 15}
  stage_cleared()                  {type: "pass_zone", zone: "barn_inside"}
  knife_used()                     {type: "survive"}
                                 → 달성 시 mission_completed 알림 → HUD 토스트
                                 → 결과 화면에 ★ 표시, user://에 달성 기록 저장
```
- 미션 종류(`survive`, `kill_count`, `pass_zone`, `no_knife` 등)는 코드에 구현하고, **어떤 스테이지에 어떤 미션을 몇으로** 줄지는 `stage_data`에서만 정한다.
- 헛간 통과(`pass_zone`)는 헛간 내부에 Area3D 구역을 두어 판정한다. 헛간 모델에는 통과 가능한 내부 통로가 있어야 한다.

### 6.4 성능 기법
- 스테이지는 **지형 타일 재사용**: 플레이어 앞에 타일을 붙이고 뒤로 지나간 타일은 재활용(오브젝트 풀).
- 좀비도 오브젝트 풀로 재사용하고, 멀리 있는 좀비는 애니메이션 갱신 빈도를 낮춘다.
- 시야 거리를 안개로 제한해 멀리 있는 물체를 그리지 않는다 (카메라 far 거리 = 안개 끝 거리).
- 동시 표시 좀비 수 상한을 `difficulty_config`에서 관리한다.

---

## 7. 백엔드 (Supabase) — 계정·결제·채팅

### 7.1 테이블 (초안)
| 테이블 | 주요 컬럼 | 용도 |
|---|---|---|
| `profiles` | `id`(= auth.users.id), `nickname`, `is_guest`, `role`(`user` \| `admin`), `created_at` | 게스트·가입 계정 공통 (가입해도 같은 `id` 유지). `role`은 사용자가 스스로 바꿀 수 없음 |
| `scores` | `id`, `user_id`, `distance_m`, `kills`, `duration_s`, `app_version`, `created_at` | 기록·랭킹 |
| `purchases` | `id`, `user_id`, `platform`(`google_play` \| `toss_test`), `product_id`, `purchase_token`(UNIQUE — 구글은 구매 토큰, 토스는 paymentKey), `order_id`, `amount`, `status`, `verified_at`, `created_at` | 결제 기록 (앱·웹 공통) |
| `toss_orders` | `order_id`(PK), `user_id`, `product_id`, `amount`, `status`(`ready` \| `paid` \| `failed`), `created_at` | 토스 결제 전에 서버가 만드는 주문. 승인 시 금액 대조용 |
| `mission_progress` | `user_id`, `stage_id`, `mission_id`, `completed_at` | 미션 달성 기록 (2단계. MVP는 기기 로컬 저장) |
| `inventory` | `user_id`, `item_id`, `quantity`, `updated_at` | 보유 아이템 |
| `support_threads` | `id`, `user_id`, `kind`(`question` \| `bug`), `status`(`ai_answered` \| `needs_human` \| `in_progress` \| `closed`), `summary`·`category`(P2, 비워 둠), `created_at` | 문의·제보 한 건 |
| `support_messages` | `id`, `thread_id`, `role`(`user` \| `assistant` \| `team`), `content`, `created_at` | 대화 내용 |
| `bug_context` | `thread_id`, `app_version`, `platform`, `device_model`, `os_version`, `last_run`(거리·사망 원인 등 JSON), `created_at` | 버그 제보에 자동 첨부되는 정보 |
| `chat_usage` | `user_id`, `day`, `count` | 1인 하루 메시지 제한(PRD F-124) |
| 보기 `admin_members` | 회원 목록 (이메일 일부 가림), 가입·게스트 구분, 가입일 | 관리자 (PRD F-131) |
| 보기 `admin_purchases` | 구매 내역·상품별 합계 | 관리자 (F-132) |
| 보기 `admin_support` | 문의·제보 목록, 첨부 정보, 상태 | 관리자 (F-133) |

**마이그레이션 파일은 기능별로 나누고 소유자가 만든다** (D16): `0001_profiles_auth.sql`·`0002_purchases.sql`·`0003_support.sql`·`0004_admin_views.sql`(C), `0010_scores.sql`(B, 마감 이후). 다른 사람 파일을 고치지 않고, 바꿀 게 있으면 새 번호 파일을 추가한다.

### 7.2 보안 규칙
- 모든 테이블 **RLS 활성화**.
- 클라이언트(anon key + 사용자 JWT)는 **자기 행만 조회** 가능.
- `scores`, `purchases`, `inventory`, `toss_orders`, `support_*`, `bug_context`, `chat_usage`의 **쓰기는 Edge Function(service role)만** 가능. 클라이언트 직접 INSERT/UPDATE 금지.
- 클라이언트는 자기 `toss_orders`의 `status`를 조회해 결제 결과를 확인한다 (D14).
- 채팅·제보 내용은 개인정보가 섞일 수 있으므로 관리자만 조회, 테스터 간 공개 없음. 개인정보처리방침에 명시 (PRD N-09).
- 관리자 판정은 DB 함수 `is_admin()`(= `profiles.role = 'admin'`)으로만 한다. `admin_*` 보기는 `is_admin()`이 참일 때만 결과를 준다. `role`은 마이그레이션·Studio에서만 지정한다.
- 랭킹은 상위 N개만 노출하는 읽기 전용 뷰로 공개한다.
- service role 키와 Google 서비스 계정 키는 **Supabase Secrets에만** 저장한다. 게임 빌드·저장소에 포함 금지.

### 7.3 Edge Functions
| 함수 | 입력 | 처리 | 출력 |
|---|---|---|---|
| `submit-score` | 거리, 킬 수, 플레이 시간, 앱 버전 | 사용자 인증 확인 → 물리적으로 불가능한 값 거부 (예: 거리 ÷ 시간이 최고 속도 × 1.2 초과) → 저장 | 저장 결과, 순위 |
| `verify-google-purchase` | `product_id`, `purchase_token` | 사용자 인증 → Google Play Developer API로 구매 검증 → 중복 토큰 거부 → `purchases` 기록 → `inventory` 지급 → 구매 확인(acknowledge) | 지급 결과 |
| `create-toss-order` | `product_id` | 사용자 인증 → **서버가 상품 가격표로 금액 결정** → `toss_orders`에 `ready`로 저장 | `order_id`, `amount`, 주문명 |
| `confirm-toss-payment` | `paymentKey`, `order_id`, `amount` | `toss_orders`의 금액과 대조(다르면 거부) → 토스 결제 승인 API 호출(테스트 시크릿 키) → `purchases` 기록 → `inventory` 지급 → `toss_orders.status = paid` | 지급 결과 |
| `support-chat` | `thread_id`(선택), `kind`, `message`, (버그면) 기기·게임 정보 | 사용자 인증 → 하루 제한 확인(`chat_usage`) → 게임 안내문(규칙·조작·알려진 문제)을 시스템 프롬프트로 OpenAI 호출 → 답변 저장 → 버그 제보이거나 답하기 어려우면 `needs_human` | 답변, `thread_id` |
| `delete-account` | - | 사용자 인증 → 본인 데이터(`profiles`, `inventory`, `support_*`) 삭제 → Auth 계정 삭제 (service role, 서버에서만) (PRD F-107) | 삭제 결과 |

### 7.4 인증 흐름 (PRD 4.11)
```
앱 첫 실행 → 저장된 세션 없음 → 익명 로그인(게스트) → 바로 플레이
계정 화면 → 이메일·비밀번호 입력 → 현재 게스트 계정에 이메일 연결 (같은 user_id 유지 → 기록·구매 그대로)
다른 기기 → 이메일 로그인 → 같은 user_id
로그아웃 → 세션 삭제 → 새 게스트
```
- 세션(access·refresh 토큰)은 기기 `user://`에 저장하고 만료 전 자동 갱신한다. 토큰을 로그에 찍지 않는다.
- 이메일 확인(메일 인증) 사용 여부는 WU-51에서 결정한다 (마감 내 테스트 편의를 위해 끌 수 있음 → 출시 전 다시 켬).
- 구현 전 Supabase 공식 문서로 익명 로그인·계정 연결 API를 확인한다.

### 7.5 문의·제보 채팅 흐름 (PRD 4.13)
```
[게임] 문의·제보 화면 → 메시지 입력 (버그 제보면 기기·게임 정보 자동 첨부)
  → [Edge Function] support-chat → 하루 제한 확인 → OpenAI 호출 (API 키는 Secrets)
  → DB 저장 (support_threads / support_messages / bug_context)
  → [게임] 답변 표시
[관리자] Supabase 관리 화면의 admin_support 보기에서 needs_human 건 확인 → 팀 답변 작성 → 상태 변경 (7.6)
```
| 규칙 | 이유 |
|---|---|
| OpenAI 키는 Supabase Secrets에만 | 게임·웹 빌드에 넣으면 누구나 꺼내 쓸 수 있음 |
| 1인 하루 30회 + OpenAI 대시보드 월 한도 | 비용 폭주 방지 (PRD F-124, N-10) |
| LLM에게 도구(결제 환불, DB 수정 등) 권한을 주지 않는다. 답변만 한다 | 채팅으로 LLM을 속여 조작하는 공격 방지 |
| 시스템 프롬프트: 게임 규칙·조작·알려진 문제 문서만 근거로 답하고, 모르면 "팀에 전달했어요" | 없는 기능을 지어내 안내하는 것 방지 (F-125) |
| 사용자 메시지·제보 원문을 서버 로그에 통째로 찍지 않는다 | 개인정보 유출 방지 |
| 구현 전 OpenAI 공식 문서로 모델·API 형식 확인 | 모델·API가 자주 바뀜 (Q8) |

### 7.6 관리자 (PRD 4.14, D15)
```
관리자 계정 지정: 마이그레이션 또는 Studio에서 profiles.role = 'admin'
        ↓
Supabase 관리 화면(Studio) 로그인 (팀 계정)
        ↓
보기(뷰)로 확인: admin_members / admin_purchases / admin_support
        ↓
문의 답변: support_messages에 role = 'team'으로 추가, support_threads.status 변경
```
- Studio 접근 권한은 팀원 3명에게만 준다 (Supabase 프로젝트 멤버).
- 게임 안의 테스트 패널은 `profiles.role = 'admin'`인 계정에서도 열린다 (PRD F-141).
- 전용 관리자 웹 페이지는 P2 (F-135). 과제 요건이 전용 페이지를 요구하면 범위를 다시 정한다 (PRD Q6).

---

## 8. 결제

> **마감 범위는 8.5 토스 테스트 결제(웹·앱 공통)**다. 8.1 - 8.4의 Google Play Billing은 **마감 이후** Play 출시 버전에서 앱 결제를 교체할 때 쓴다.

### 8.1 구매 흐름 (Google Play Billing, 마감 이후)
```
[게임] 상점에서 상품 선택
  → [Play 결제 시트] 사용자 결제 (테스트: 라이선스 테스터 + 테스트 카드)
  → [게임] purchase_token 수신
  → [Edge Function] verify-google-purchase → Google 서버에서 진위 확인
  → [DB] purchases 기록 + inventory 지급
  → [게임] 소모성 상품은 consume 처리 → 아이템 반영
```

### 8.2 규칙
| 규칙 | 이유 |
|---|---|
| 서버 검증 전에는 아이템을 지급하지 않는다 | 변조된 클라이언트로 무료 획득 방지 |
| 구매는 **3일 이내 확인(acknowledge)** 처리 | 미확인 구매는 Google이 자동 환불 |
| 소모성 상품은 지급 후 consume | 미처리 시 같은 상품 재구매 불가 |
| 같은 `purchase_token`은 한 번만 지급 | 중복 지급 방지 (DB UNIQUE 제약) |
| 앱 재실행 시 미처리 구매 조회·재검증 | 결제 중 앱 종료 대비 |

### 8.3 상품
- 마감 전 테스트 상품: PRD 4.12 (`ammo_start_pack` 소모성, `supporter_badge` 비소모성). 서버 가격표(`create-toss-order`)와 게임 상점이 같은 상품 ID를 쓴다.
- 정식 상품 구성은 비공개 테스트 설문 이후 결정 (PRD Q3). 구글 결제로 교체할 때도 같은 상품 ID를 유지한다.

### 8.4 테스트 환경
- 결제 프로필(판매자 계정) 생성 → 결제 기능이 포함된 빌드를 **내부 테스트 트랙**에 업로드 → 인앱 상품 등록 → 라이선스 테스터 등록.
- 테스트 기기에는 **Play 스토어 테스트 링크로 설치**한다 (`adb` 직접 설치 빌드는 결제가 정상 동작하지 않을 수 있음).

### 8.5 토스페이먼츠 테스트 결제 — 웹·앱 공통 (마감 범위)
**적용 범위: 웹 빌드와 Android APK 모두** (D8). 결제 페이지(Vercel)와 서버 흐름을 하나로 공유하고, 결과는 **서버의 주문 상태로만** 반영한다 (D14).

```
            [게임] 상점에서 상품 선택
                     ↓
  [Edge Function] create-toss-order → 서버가 가격표로 금액을 정해 주문 생성 (order_id)
                     ↓
      ┌──────────────┴──────────────┐
  🌐 웹 게임                        📱 앱
  같은 탭에서 결제 페이지로 이동       OS.shell_open()으로 폰 브라우저에서 결제 페이지 열기
      └──────────────┬──────────────┘
                     ↓
  [Vercel 결제 페이지 ?order_id=...] 토스 결제위젯 (테스트 클라이언트 키 test_ck_...)
                     ↓ 테스트 결제 (실제 돈 안 나감)
  [성공 URL] paymentKey, orderId, amount → 결제 페이지가 confirm-toss-payment 호출
  [Edge Function] 주문 금액 대조 → 토스 승인 API (테스트 시크릿 키 test_sk_...)
                  → purchases 기록 + inventory 지급 + toss_orders.status = paid
                     ↓
      ┌──────────────┴──────────────┐
  🌐 결제 페이지 → 게임 페이지로 복귀   📱 사용자가 앱으로 돌아옴 (NOTIFICATION_APPLICATION_RESUMED)
      └──────────────┬──────────────┘
                     ↓
  [게임] 자기 toss_orders.status 조회 (RLS) → paid면 아이템 반영, failed/ready면 안내
```

- 결제 페이지는 주문의 소유자만 결제할 수 있도록 `order_id`와 함께 사용자 확인값(서버가 발급한 1회용 토큰)을 받는다.
- 앱 복귀 후 상태가 아직 `ready`면 몇 초 간격으로 짧게 재조회한다(최대 30초).

| 규칙 | 이유 |
|---|---|
| **시크릿 키(`test_sk_`)는 Edge Function에만** 둔다. 웹 빌드·Vercel 공개 환경변수(`NEXT_PUBLIC_` 등)에 넣지 않는다 | 브라우저에 노출되면 누구나 결제 승인 API를 호출할 수 있음 |
| 브라우저는 토스 서버 API(`api.tosspayments.com`)를 **직접 호출하지 않는다**. 승인은 Edge Function이 한다 | 시크릿 키 보호, 금액 위변조 방지 |
| 결제 금액은 **서버가 주문을 만들 때 정하고**, 승인 전에 성공 URL로 돌아온 금액과 대조한다 | 사용자가 URL의 금액을 바꿔 싸게 결제하는 공격 방지 |
| 같은 `paymentKey`는 한 번만 지급한다 (`purchases.purchase_token` UNIQUE) | 새로고침 등으로 인한 중복 지급 방지 |
| 결제위젯은 **별도 결제 페이지(Vercel)**에 둔다. 웹 게임·앱이 같은 페이지를 쓴다 | 결제 코드를 한 곳에서만 관리, 앱은 브라우저로 열기만 하면 됨 |
| 결과는 게임이 결제창 표시가 아니라 **서버 주문 상태**로 확인한다 | 결제 성공 화면 위조·중간 이탈 대비 |
| Google Play 출시 버전의 앱에서는 토스 결제를 끈다 (구글 결제로 교체) | 디지털 상품은 Play 결제가 원칙 (D8) |
| 구현 시 토스페이먼츠 공식 연동 가이드(MCP)로 최신 SDK·API를 확인한다 | SDK 버전·API가 바뀔 수 있음 |

**테스트 시나리오** (웹·앱 각각): 결제 성공 / 사용자가 결제창 닫기 / 결제 실패 / 성공 URL의 금액 위변조 / 같은 결제로 승인 두 번 요청 / (앱) 결제 중 앱으로 돌아왔다가 다시 결제 페이지로 가기

---

## 9. 빌드·배포

### 9.1 빌드
```bash
./pipeline.sh build-android   # 에셋 검사 → 테스트 → 서명된 .aab
./pipeline.sh install-device  # 디버그 빌드를 USB 연결 폰에 설치 (adb)
./pipeline.sh build-web       # 웹 체험판 (Compatibility 렌더러 + 토스 결제 HTML 셸)
```
내부적으로 `godot --headless --path godot --export-release "Android" build/game.aab` 를 사용한다.

### 9.2 서명
| 항목 | 규칙 |
|---|---|
| 업로드 키 | `keytool`로 생성, **git 제외**, 저장소 밖에 보관 + 별도 백업 |
| 앱 서명 | Google Play 앱 서명 사용 (업로드 키 분실 시 재설정 요청 가능) |
| 키 비밀번호 | 환경변수로 주입, 파일·저장소에 기록 금지 |

### 9.3 Android 설정
| 항목 | 값 |
|---|---|
| 패키지 이름 | 미정 (예: `com.<개발자>.<게임명>`) — **한 번 정하면 변경 불가** |
| Target API | Google Play의 현재 요구 수준 (빌드 시점에 공식 문서로 확인) |
| 권한 | 인터넷, 결제(`BILLING`) 외 최소화 |
| 버전 | `versionCode` 업로드마다 +1, `versionName` = 의미적 버전 |

### 9.4 Play Console 트랙
| 트랙 | 인원 | 용도 |
|---|---|---|
| 내부 테스트 | 최대 100명, 심사 없음 | 개발자 확인, 결제 테스트 |
| 비공개 테스트 | **12명 이상 × 14일 연속** | MVP 피드백 + 정식 출시 조건 충족 |
| 프로덕션 | 전체 | 정식 출시 |

- 첫 업로드는 사용자가 Play Console에서 직접 수행한다.
- 이후 업로드는 선택적으로 Google Play Developer API(서비스 계정)로 자동화한다.

### 9.5 스토어 등록 자료
| 항목 | 준비 방법 |
|---|---|
| 아이콘 512×512, 대표 이미지 1024×500 | 나노바나나 시안 → 정리 |
| 스크린샷 | Godot 게임 화면 자동 캡처 |
| 개인정보처리방침 URL | 정적 페이지 (blog_ggg 또는 Vercel) |
| 데이터 보안 양식 | Supabase 저장 항목(익명 ID, 이메일, 구매 기록, 채팅·제보 내용, 기기 모델) 기준으로 작성 |
| 콘텐츠 등급 | IARC 설문 (좀비·총기 폭력 → 12세 이상 예상) |
| 타겟 연령 | 13세 이상 (아동 대상 선택 시 가족 정책 적용) |

---

## 10. 테스트·검증

### 10.1 자동 검증
| 대상 | 도구 | 기준 |
|---|---|---|
| 에셋 규격 | `validate.py` (Blender) | 5.2·5.3 규격 전부 통과 |
| 에셋 외형 | 미리보기 렌더 PNG | 콘셉트 이미지와 비교해 Claude·사용자 확인 |
| 게임 로직 | GUT (headless) | 이동, 스폰, 사격, 피격, 게임오버, 점수 계산 테스트 통과 |
| 화면 | Godot 스크린샷 | 안개·조명·UI 배치 확인 |
| 백엔드 | Edge Function 테스트 | 정상 값 저장, 비정상 값 거부, RLS로 타인 데이터 접근 차단 |
| 결제 | 라이선스 테스터 구매 | 승인·거절·중복 토큰·앱 중단 후 복구 시나리오 |

### 10.2 실기기 검증
- USB 디버깅으로 사용자 폰에 설치 → `adb logcat`으로 로그와 오류 확인.
- 성능 측정: Godot 성능 모니터(FPS, 드로우 콜, 메모리)를 게임 안 디버그 오버레이로 표시.

### 10.3 성능 목표
| 항목 | 목표 |
|---|---|
| FPS (Galaxy S24 Ultra) | **60fps 유지** (가장 붐비는 구간 포함) |
| FPS (중급 기기 기준) | 30fps 이상 유지 — 테스터 대부분은 최상급 폰이 아니므로 비공개 테스트에서 중급 기기 테스터의 결과로 확인 |
| 동시 좀비 수 | 최소 15마리에서 위 FPS 유지 |
| 발열 | 한 판(3-4분) 연속 플레이 후에도 프레임이 크게 떨어지지 않음 (5판 연속 플레이로 확인) |
| 첫 실행 로딩 | 5초 이내 |
| 설치 용량 | 150MB 이하 |

---

## 11. 저장소·파일 관리

### 11.1 폴더 구조 (괄호는 소유자, 13.1)
```
3D_Game_MVP/
├── README.md                (C)
├── DevelopDoc/              (문서 — 수정 시 팀 공유)
│   ├── PRD.md
│   ├── TECH_SPEC.md         # 이 문서
│   ├── CONTRACTS.md         # 담당 간 약속 (각 약속의 주인이 수정)
│   ├── WORK_UNITS.md
│   └── FINAL_CHECKLIST.md
├── ASSETS_LICENSE.md        (A)
├── pipeline.sh              (C) tools/assets·tools/build를 순서대로 부르기만 함
├── tools/
│   ├── assets/              (A) 에셋 생성·검사·내보내기 실행 스크립트
│   ├── build/               (C) 안드로이드·웹 빌드, 설치, 조립 확인 스크립트
│   └── check_setup.sh       (C) 팀원 컴퓨터 도구 설치 점검
├── art/                     (A)
│   ├── STYLE.md             # 아트 규칙서 (팔레트, 비율, 분위기)
│   ├── concept/             # 나노바나나 콘셉트 이미지
│   ├── blender/
│   │   ├── lib/             # 공통 함수 (재질, 검사, 내보내기)
│   │   ├── make_*.py        # 모델 생성 (make_placeholders.py = 가짜 부품)
│   │   ├── import_*.py      # 외부 에셋 정리
│   │   ├── render_preview.py
│   │   ├── validate.py
│   │   └── export_glb.py
│   ├── source/              # 외부 원본 (Mixamo FBX 등) — git 제외
│   └── previews/            # 미리보기 렌더 — git 제외
├── godot/                   # Godot 프로젝트 (6.2)
├── backend/supabase/
│   ├── migrations/          # 기능별 SQL 파일, 파일마다 소유자 (7.1)
│   └── functions/           (C) create-toss-order, confirm-toss-payment, support-chat, delete-account
├── web/
│   └── pay/                 (C) 토스 테스트 결제 페이지 (Vercel)
├── docs/
│   ├── evidence/            # 작업 근거 (각자)
│   └── SECURITY_REVIEW.md   (C) 보안 점검 보고서 (12.1)
└── build/                   # 빌드 산출물 — git 제외
```

### 11.2 git 제외 대상 (`.gitignore`)
| 대상 | 이유 |
|---|---|
| `art/source/` (Mixamo FBX 등 원본) | Mixamo 원본 재배포 금지 |
| `art/previews/`, `build/`, `godot/.godot/` | 재생성 가능한 산출물 |
| `*.keystore`, `*.jks` | 앱 서명 키 |
| `.env`, 서비스 계정 JSON | 비밀 정보 |

### 11.3 저장소 결정 사항
- **결정 (2026-09-28)**: `3D_Game_MVP`는 자체 `.git`을 가진 **독립 저장소**로 분리하고, 로컬 위치도 학습 워크스페이스(`aiffel_work`) 밖의 `~/3D_Game_MVP`로 옮긴다. 다른 실습의 커밋 이력·폴더 구조와 섞이지 않고, 3인 팀이 이 저장소만 공유하면 된다.
- 저장소는 **공개(Public)**로 운영한다. 비밀 정보는 `.gitignore` + `scripts/git-hooks/pre-commit`(비밀 키 검사) 2중으로 막는다 (12장).
- 커밋·푸시 전에는 `git remote -v`로 원격이 이 프로젝트 저장소인지 확인한다 (루트 저장소로 잘못 푸시하는 사고 방지).
- 어느 쪽이든 커밋 전 untracked 목록을 사람이 직접 검토하고, 비밀 정보·원본 에셋이 포함되지 않았는지 확인한다.

---

## 12. 보안·비밀 관리

| 비밀 | 저장 위치 | 사용처 |
|---|---|---|
| Gemini API 키 | 로컬 `.env` | 콘셉트 이미지 생성 스크립트 |
| Supabase URL, anon key | 게임 빌드 설정 | 클라이언트 (공개돼도 되는 키. RLS로 보호) |
| Supabase service role key | Supabase Secrets | Edge Functions만 |
| Google Play 서비스 계정 JSON | Supabase Secrets (+ 업로드 자동화 시 로컬 `.env` 경로) | 구매 검증, 업로드 자동화 |
| 업로드 키스토어·비밀번호 | 저장소 밖 + 백업, 비밀번호는 환경변수 | Android 서명 |
| 토스 테스트 클라이언트 키 (`test_ck_`) | 웹 빌드 설정 | 브라우저 결제위젯 초기화 (공개돼도 되는 키) |
| 토스 테스트 시크릿 키 (`test_sk_`) | Supabase Secrets | `confirm-toss-payment`만 |
| OpenAI API 키 | Supabase Secrets | `support-chat`만 |

- 비밀 값은 채팅·문서·커밋에 적지 않는다. 사용자가 `.env`에 직접 입력한다.
- 코드는 환경변수가 없으면 즉시 오류를 내고 멈춘다.

### 12.1 보안 점검 (PRD N-11)
**방식**: 기능을 만들 때 공격 테스트를 같이 작성하고(각 WU 완료 조건), 3일차에 **Claude 보안 검토 에이전트**로 전체를 한 번에 점검한 뒤, 사람이 결과를 확인하고 서명한다. 결과는 `docs/SECURITY_REVIEW.md`.

| # | 점검 항목 | 방법 | 통과 기준 |
|---|---|---|---|
| S1 | RLS 우회 | 사용자 A 토큰으로 B의 데이터 조회·수정 시도 | 전부 거부 |
| S2 | 관리자 권한 우회 | 일반 사용자가 `admin_*` 보기 조회, 자기 `role`을 `admin`으로 수정 시도 | 전부 거부 |
| S3 | 결제 위변조 | 성공 URL 금액 변경, 남의 주문으로 승인, 같은 결제 두 번 승인 | 전부 거부·1회만 지급 |
| S4 | 비밀 키 노출 | 저장소 현재 파일 + **git 이력 전체** + APK·웹 빌드 문자열 검색 (service role, 토스 시크릿, OpenAI, 키스토어) | 0건 |
| S5 | 채팅 남용 | 하루 제한 초과, 인증 없이 호출, "환불해줘·관리자로 만들어줘" 요청 | 거부, DB 변화 없음 |
| S6 | 로그 노출 | `adb logcat`, Edge Function 로그에서 토큰·키·채팅 원문 검색 | 0건 |
| S7 | 테스트 모드 노출 | 일반 계정 + 릴리스 빌드에서 테스트 패널 열기 시도 | 열리지 않음 |
| S8 | 회원 탈퇴 | 탈퇴 후 같은 토큰으로 조회, 관리자 보기에서 흔적 확인 | 데이터 삭제됨 |

- 발견 사항은 마감 전에 고치거나, 위험도(높음·중간·낮음)와 이유를 보고서에 남긴다.
- 로그인·결제를 만든 C가 아닌 **B가 결과를 교차 확인하고 서명**한다 (만든 사람과 확인하는 사람 분리).

---

## 13. 역할 분담

### 13.1 파일 소유권 (3인, PRD 2.1 — 기능 단위 소유, D16)
| 역할 | 소유 (장면·스크립트·DB·함수를 기능 단위로) |
|---|---|
| **A. 월드·비주얼** | `art/`, `tools/assets/`, `ASSETS_LICENSE.md`, `godot/assets/models/`·`audio/`, `godot/scenes/stage/`·`fx/`, `godot/scripts/stage/` |
| **B. 게임플레이** | `godot/scenes/game/`·`actors/`·`weapons/`·`debug/`, `godot/scripts/core/`·`actors/`·`weapons/`·`debug/`, `godot/data/stage_data.tres`, `godot/tests/b_*`, `migrations/0010_scores.sql`(마감 이후) |
| **C. 서비스·UI·배포** | `godot/scenes/ui/`·`scripts/ui/`·`scripts/services/`, `godot/assets/ui/`, `godot/tests/c_*`, `migrations/0001 - 0004`, `backend/supabase/functions/`, `web/`, `tools/build/`, `docs/SECURITY_REVIEW.md` |

### 13.1.1 공동 파일 — 주인이 한 명씩 있다
공동 파일은 **주인만 수정**한다. 다른 사람은 주인에게 요청하고, 주인이 반영한다.

| 파일 | 주인 | 이유 |
|---|---|---|
| `godot/project.godot`, `export_presets.cfg` | C | 빌드·입력·렌더러 설정 |
| `godot/scenes/main.tscn` | C | 화면 전환과 조립 |
| `pipeline.sh` | C | tools/assets(A)·tools/build(C)를 부르기만 함 |
| `godot/scripts/core/game_state.gd`의 **신호 목록** | B | 약속 ② (CONTRACTS) |
| `godot/scripts/core/difficulty_config.gd`, `data/stage_data.tres` | B | 밸런스·미션 수치 |
| `scripts/services/session.gd` | C | 약속 ③ |
| `.gitignore`, `scripts/git-hooks/` | C | 저장소 규칙 |
| `DevelopDoc/CONTRACTS.md` | 약속별 주인 (①A ②B ③④C) | 약속 변경은 주인이 문서부터 고치고 팀에 알림 |

### 13.1.2 협업 규칙
| 규칙 | 내용 |
|---|---|
| 브랜치 | 각자 `a/<작업>`, `b/<작업>`, `c/<작업>` 브랜치에서 작업. `main`에 직접 커밋 금지 (C의 조립 커밋 제외) |
| 조립(머지) | **하루 두 번 (점심·저녁)** C가 세 브랜치를 `main`에 머지 → 자동 확인 → 폰 확인 (WORK_UNITS WU-39) |
| 자동 확인 | GUT 전체 통과 + 메인 장면 10초 무화면 실행 오류 0개 + 서명 APK 빌드 성공 |
| 깨졌을 때 | 방금 머지한 조각을 되돌리고, 그 조각의 주인이 고쳐 다시 올림 |
| 조립 후 | 세 명 모두 최신 `main`을 받아서 이어서 작업 |
| 가짜 부품 교체 | 진짜 부품은 **같은 경로·같은 이름**으로 덮어쓴다 (CONTRACTS) |
| 도와주기 | 2일차 저녁(M4) 점검에서 늦은 라인의 **기능 조각을 통째로** 넘긴다 (장면·스크립트·DB·함수 전부). 반쪽 분할 금지 |

### 13.2 Claude와 사람의 역할
| 작업 | Claude | 사용자 |
|---|---|---|
| 스크립트·코드·씬·SQL 작성 | ✅ | - |
| 명령줄 실행 (Blender, Godot, 빌드, 테스트) | ✅ | 도구 설치 허락 |
| 결과 확인 (렌더·스크린샷) | ✅ | 스타일·재미 피드백 |
| 계정 생성·로그인·결제·키 발급 | ❌ | ✅ Play Console, 결제 프로필, Adobe, Gemini, Supabase |
| Mixamo 다운로드 | 목록 정리 | ✅ 다운로드 |
| Play Console 업로드·상품 등록·테스터 관리 | 입력 내용 정리 | ✅ |
| 외부 에셋 다운로드 | 출처·파일명·용량 안내 | ✅ 허락 |
| 폰 개발자 옵션·USB 디버깅 | 방법 안내 | ✅ 설정 |

---

## 14. 제약·리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| 볼류메트릭 안개 미지원 (Mobile 렌더러) | 분위기 약화 | 거리·높이 안개 + 안개 판 + 어두운 조명으로 1일차에 분위기 검증 |
| Blender 5.x `bpy` API 변경 | 스크립트 오류 | 문서 조회 후 작은 스크립트부터 검증. **WU-04 확인**: 렌더 엔진은 `BLENDER_EEVEE`(4.x의 `_NEXT` 아님), glTF는 `export_scene.gltf(export_format="GLB")` 동작, 연산자 enum은 동적이라 `bl_rna`로 목록이 안 보이므로 실행해서 확인 (`docs/evidence/WU-04/`) |
| 저가형 폰 성능 부족 | 버벅임, 이탈 | 폴리곤 예산 자동 검사, 오브젝트 풀, 좀비 수 상한, 품질 옵션 |
| adb 연결 끊김·권한 | 설치·로그 확인 불가 | 폰에서 "이 컴퓨터에서 항상 허용" 체크. 삼성 보안 폴더 때문에 `pm` 명령은 `--user 0` 사용. 실행은 `am start -n <패키지>/com.godot.game.GodotAppLauncher` (WU-04) |
| 조명·안개가 소품 색을 바꿈 | 의도한 색이 안 보임 (WU-04에서 갈색 상자가 회색으로 보임) | STYLE.md에서 달빛·안개 색과 팔레트를 함께 정하고 폰 화면으로 확인 (WU-10, WU-13) |
| Mixamo 모델이 다른 게임과 비슷함 | 차별성 부족 | MVP 이후 콘셉트 → AI 3D 생성 → Mixamo 리깅으로 교체 |
| 테스터 12명 × 14일 미달 | 정식 출시 지연 | 15-20명 사전 모집, 참여 유지 안내 |
| 배경음 AI 도구 라이선스 | 출시 후 분쟁 | 출시 전 약관 확인, 필요 시 CC0 음원으로 교체 |
| 개인 개발자 주소 공개 (유료 상품 판매 시) | 개인정보 노출 | 정식 출시 전 공개용 주소 결정 |
| Google 정책·콘솔 변경 | 절차 오류 | 각 단계 시작 시 공식 문서 재확인 |
| **마감 72시간 + 범위 확대** | 미완성 제출 | WORK_UNITS 1.3 범위 축소 순서 사전 합의, 매일 저녁 진행 점검, 10/1 24:00 코드 동결 |
| **C 역할 과부하** (서비스·UI·배포, 약 26시간) | 결제·채팅·UI 동시 지연 | 범위 축소(관리자 = Studio, 채팅 요약 P2, 보안 점검 = 테스트 선작성 + 에이전트), Claude 세션 2개 병렬, 공통 UI 부품 먼저, 2일차 점검에서 기능 조각 단위로 넘김 |
| 머지 충돌 | 조립 지연 | 기능 단위 파일 소유, 공동 파일 주인제, 하루 두 번 조립 (13.1.2) |
| 가짜 부품과 진짜 부품 불일치 | 교체 시 깨짐 | CONTRACTS ① 규격을 `validate.py`가 자동 검사 (이름·크기·원점·애니메이션 이름) |
| OpenAI 비용 폭주·남용 | 예상 밖 청구 | 1인 하루 30회, OpenAI 월 한도 설정, 키는 Secrets에만 |
| 채팅으로 LLM 조작 시도 (프롬프트 인젝션) | 잘못된 안내 | LLM에 도구 권한 없음(답변만), 규칙 문서 근거 답변, 결제 문제는 사람 확인 |
| 앱 결제 후 복귀 흐름 혼란 | 결제했는데 반영 안 됨 | 복귀 시 자동 재조회 + "결제 확인 중" 안내, 상점에 "결제 내역 새로고침" 버튼 |

---

## 15. 미결 사항

| # | 항목 | 결정 시점 |
|---|---|---|
| Q1 | ~~테스트 폰 기종~~ → **결정**: Galaxy S24 Ultra, 60fps 목표 + 중급 기기 30fps 기준 (10.3) | 2026-09-28 |
| Q2 | Godot 정확한 버전, Billing 플러그인 호환 버전 | 설치 시 |
| Q3 | ~~이동 조작 방식~~ → **결정**: 드래그 + 기울이기, 설정에서 선택 (PRD F-02 - F-05) | PRD v0.1 |
| Q4 | ~~스테이지·좀비·무기~~ → **결정**: 1,000m 목표 거리, 좀비 4종, 권총(낙하산 보급 탄약) + 칼(스테이지당 1회) (PRD 4장). 상품 구성은 미정 (PRD Q3) | PRD v0.1 |
| Q5 | 게임 정식 이름, Android 패키지 이름 | 첫 업로드 전 |
| Q6 | ~~저장소 분리 여부~~ → **결정**: 독립 저장소 (11.3) | 2026-09-28 |
| Q7 | 광고 도입 여부 | MVP 피드백 이후 |
| Q8 | OpenAI 모델 (비용·속도) | 10/1 채팅 구현 시작 전, 공식 문서 확인 |
| Q9 | Supabase 이메일 확인(메일 인증) 사용 여부 | WU-51 |
| Q10 | 과제 제출 요건 원문 (관리자·테스트 모드·보안 점검 해석 검증, PRD Q6) | 9/29 (화) 오전 |

---

## 16. 변경 이력

| 버전 | 날짜 | 내용 |
|---|---|---|
| v0.1 | 2026-09-28 | 최초 작성 — 대화에서 확정한 기술 스택 정리 (Godot 4 + Blender 스크립트 + Mixamo + Supabase + Google Play Billing, 토스페이먼츠 제외) |
| v0.1.1 | 2026-09-28 | PRD v0.1 작성에 따라 미결 사항 Q3, Q4 결정 처리 |
| v0.4 | 2026-09-29 | PRD v0.4 반영 — D15 관리자 = Supabase Studio + 역할 + 보기, D16 기능 단위 소유·약속서·가짜 부품·하루 두 번 조립. 6.2·11.1 폴더에 소유자 표기(tools/assets·tools/build 분리, scenes/fx·debug 추가), 모듈 session·test_panel·far_layers, profiles.role·admin 보기·기능별 마이그레이션 파일, delete-account 함수, 7.6 관리자, 12.1 보안 점검표(S1 - S8), 13.1 파일 소유권·공동 파일 주인·협업 규칙, 리스크 갱신, Q10 |
| v0.3 | 2026-09-28 | PRD v0.3 반영 — 일정(내부 10/1 24:00, 최종 10/2 10:00), D8 수정(마감 전 웹·앱 토스 테스트 결제), D9 이메일+게스트 인증, D13 OpenAI 채팅, D14 앱 결제 복귀 조회, 모듈(auth_client·payment_client·support_chat), 테이블(support_threads·support_messages·bug_context·chat_usage), support-chat 함수, 7.4 인증 흐름, 7.5 채팅 흐름, 8.5 웹·앱 공통 결제 흐름, 역할 재배정, 리스크 5건, Q8·Q9 |
| v0.2.3 | 2026-09-28 | WU-04 파이프라인 시험 결과를 14장 리스크에 반영 (Blender 5.2 API, adb 권한, 조명에 의한 색 변화) |
| v0.2.2 | 2026-09-28 | 테스트 기기 Galaxy S24 Ultra 확정, 성능 목표 60fps + 중급 기기 30fps 기준, 발열 기준 추가 (Q1) |
| v0.2.1 | 2026-09-28 | 도구 설치 결과(3.1) 반영, Q6 저장소 독립 분리 결정 (11.3) |
| v0.2 | 2026-09-28 | PRD v0.2 반영 — D8 수정(앱 구글 결제 + 웹 토스 테스트 결제), D11 카메라 Keep Height, D12 미션 데이터 분리, 6.1.1 깊이감 층, 모듈(camera_rig·obstacle·mission_system·stage_data), 6.3.1 미션 판정, 테이블(toss_orders·mission_progress), Edge Function(create-toss-order·confirm-toss-payment), 8.5 토스 흐름·보안 규칙, 비밀 키 2종, 13.1 3인 팀 역할 |
