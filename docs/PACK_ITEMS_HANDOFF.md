# 좀비탈출 — 테스트 결제 팩 아이템 작업 이어받기

- 작성: 2026-10-01 (A 담당 작업 인계)
- 브랜치: `feat/pack-items` (main `0fe5f6a` 에서 시작, **아직 PR 안 함**)
- 기획 원본: 노션 "좀비탈출 — 테스트 결제 요금 패키지 (3종)" (아래 1장에 그대로 옮김, 사용자 수정 반영)
- 코드 프리즈 10/1 24:00, 최종 제출 10/2 10:00

---

## 0. 한눈에 — 지금 어디까지 했나

| 순서 | 할 일 | 상태 |
|---|---|---|
| 1 | 기기 안 인벤토리 + 테스트 지급 | **완료** (`scripts/stage/inventory.gd`, 동작 확인함) |
| 2 | 아이템 효과 7종 | **완료** — 게임에 연결, 창 모드로 확인 |
| 3 | 출발 전 준비 화면 · 달리는 중 아이템 칸(1·2 키) · 위험 감지 붉은 가장자리 | **완료** |
| 4 | YOU DIED 화면 "한 번 더"(부활) + 상황별 팩 권유 (1.4 표) | **완료** — 결제 연결 전에는 테스트 지급 |
| 5 | 사용자 수정 규칙 (부활·모닥불 한 판 하나, 부활 무적 2초) | **완료** |
| 6 | PRD 4.12·Q3 갱신 | **완료** |
| 7 | PR → 머지 | 남음 |
| 8 | 백엔드(C): 서버 상품 3종 + 구성 수량 지급, 토스 Android SDK 연결 | C 에게 전달 필요 |

검증 (2026-10-01): 검사 5종 모두 750m 완주·끼임 탈출 0 (팩 UI 는 플레이 모드에서만 떠서 검사에 영향 없음).
창 모드 흐름 확인: 출발 준비 → 테스트 지급(전설+생존 키트) → 예비 칼·탄약 팩·위험 감지 켜고 출발(칼 2·예비탄 7) → 1 광란(쏴도 탄창 7 그대로) · 2 신호탄(앞 32m 보급) · 같은 판 광란 두 번째는 안 됨 → 위험 감지 붉은 가장자리 → 잡혀 죽음 → "한 번 더 (부활 ×2)" → 부활(2초 무적, 부활 2→1) → 다시 죽음 → "이번 판은 이미 다시 일어났습니다 · 생존 키트 ₩1,100" → 누르면 테스트 지급.

---

## 1. 확정 기획 (노션 원본 + 사용자 수정)

### 1.1 팩 3종 — 가격 사다리 1,100 → 3,300 → 5,500원, 주력은 가운데
| 상품 ID | 이름 | 가격 | 구성 | 대상 |
|---|---|---|---|---|
| `pack_survival_kit` | 생존 키트 | 1,100원 | 예비 칼 1 · 시작 탄약 팩 1 · 보급 신호탄 1 · 아드레날린 1 | 처음 몇 번 죽어 본 사람 |
| `pack_one_more` | 한 번 더 패키지 | 3,300원 | 부활 1 · 광란의 15초 1 · 모닥불 1 | 끝 반전에서 막힌 사람 (**주력**) |
| `pack_legend` | 전설의 생존자 | 5,500원 | 부활 2 · 예비 칼 2 · 광란의 15초 2 · 위험 감지 2 · 황금 권총(영구) · 서포터 배지(영구) | 꼭 깨고 싶은 사람 |

상점·제안 화면에는 항상 **"테스트 결제입니다. 실제 돈이 나가지 않습니다"** (PRD F-115).
카드 그림: `art/shop/pack_*.png` (main 에 머지됨, PR #14), 다시 만들기 `python3 art/shop/make_packs.py`.

### 1.2 아이템 효과
| 아이템 ID | 이름 | 효과 | 종류 |
|---|---|---|---|
| `revive` | 부활 | 죽은 자리에서 다시 일어남, **2초** 무적 (칼로 빠져나올 때와 같은 시간) | 1회 소모 |
| `knife_plus` | 예비 칼 | 이번 판 칼 +1 (최대 2자루) | 1회 소모 |
| `frenzy_30` | 광란의 15초 | 15초 동안 탄이 줄지 않고 재장전 없음 — **무적 아님** | 1회 소모 |
| `ammo_start_pack` | 시작 탄약 팩 | 예비탄 7발 들고 출발 | 1회 소모 |
| `flare_supply` | 보급 신호탄 | 버튼 → 앞 30m 에 보급 상자 | 1회 소모 |
| `bonfire` | 모닥불 | 다음 판을 절반(375m)부터 시작 | 1회 소모 |
| `danger_sense` | 위험 감지 | 매복·광전사 1초 전 화면 가장자리가 붉게 번쩍 | 1회 소모 |
| `adrenaline` | 아드레날린 | **[3] 키**, 8초 동안 앞으로 1.4배 · 좌우 1.8배 빠르게 + 잡힐 순간 30% 확률로 빠져나감 (끝 반전 마지막 좀비 제외) · 시야 넓어짐 + 화면 가장자리 왜곡. 생존 키트에 1개 (2026-10-01) | 1회 소모 |
| `gold_pistol` | 황금 권총 | 겉모습만 황금색, 위력 같음 | 영구 |
| `supporter_badge` | 서포터 배지 | 사망·완주 화면에 배지 | 영구 |

### 1.3 밸런스 원칙 (다크소울 난이도 유지) — 사용자 수정 반영
| 원칙 | 규칙 |
|---|---|
| 한 판에 종류별 1개 | 소모 아이템은 쓰면 사라지고 한 판에 종류별 1개. **부활과 모닥불은 같은 종류("다시 일어나기")로 묶어 한 판에 하나만** — 둘 다 쓰면 목숨이 3개가 된다 |
| 부활해도 그대로 | 탄약·보급·칼 그대로. 죽은 자리에서 일어나 **2초 무적** |
| 광란은 전략 아이템 | 탄 무한·재장전 없음일 뿐 **무적 아님** → 마지막 바닥 좀비는 여전히 직접 쏴야 한다 |
| 영구는 겉모습뿐 | 황금 권총 위력 같음, 배지는 결과 화면에만 |

### 1.4 결제 유도 순간 (YOU DIED 화면, RETRY 옆)
| 죽은 상황 | RETRY 옆에 뜨는 것 | 아래 한 줄 |
|---|---|---|
| 절반(375m) 넘게 달리고 죽음 | 한 번 더 ₩3,300 | "남은 32m, 한 번 더?" (남은 거리는 실제 값) |
| 그 전에 죽음 | 생존 키트 ₩1,100 | "예비 칼이 있었다면…" |
| 같은 구간에서 2번째 죽음부터 — 길 중간 광전사 | 전설의 생존자 ₩5,500 | "위험 감지면 2초 먼저 보인다" |
| 같은 구간에서 2번째 죽음부터 — 끝 반전 | 전설의 생존자 ₩5,500 | "광란의 15초를 아껴 뒀다면" |

부활을 가지고 있으면 먼저 **"한 번 더 (부활 ×N)"** 버튼을 보여 주고, 없을 때 위 표의 팩을 권한다.
결제 연결 전에는 팩 버튼이 **테스트 지급**(`Inventory.grant_pack`)으로 이어진다.

---

## 2. 만들어 둔 코드

### 2.1 `godot/scripts/stage/inventory.gd` — 완료 (새 파일, 미커밋)
- `class_name Inventory` (RefCounted, 전부 static). 저장: `user://inventory.json` (`{item_id: 수량}`) — 서버 `inventory` 와 같은 모양이라 백엔드 연결 시 읽어 와서 채우기만 하면 된다.
- `count(item)` · `has(item)` · `use(item)`(영구는 줄지 않음) · `add(item, n)` · `grant_pack(pack)` · `item_name(item)`
- `ITEMS` (9종, consumable/permanent) · `PACKS` (3종, 가격·구성) — 가격 정본은 서버.
- 확인함: 한 번 더 지급 → revive 0→2, use → 1, 전설 지급 → gold_pistol 1, use 해도 1 유지, 파일 저장 OK.

### 2.2 `godot/scripts/stage/showcase.gd` — 효과 함수 추가 (수정, 미커밋)
추가한 것 (아직 **아무도 호출하지 않음**):
- 변수: `danger_sense`, `run_used`, `_frenzy_t`, `_grab_e`, `_warned_pounce`, `_knife_n`, 상수 `FRENZY_TIME 30`, `START_AMMO_PACK 7`, `FLARE_AHEAD 32`, `REVIVE_GRACE 3.0`(→ **2.0 으로 바꿀 것**), `GOLD_TINT`
- `signal danger(side)` — 위험 감지 (길목 매복 1초 전 = 0, 광전사 = 나타난 쪽, 사이드 질주 = 그 쪽, 바닥 좀비 = 0). `danger_sense` 가 true 일 때만.
- `apply_loadout(picks)` — 예비 칼(칼 +1, 최대 2), 시작 탄약 팩(예비탄 +7), 위험 감지 켜기
- `skip_to(d)` — 모닥불: d 앞의 좀비·보급·광전사·매복·사이드 이벤트 건너뛰기
- `use_frenzy()` · `frenzy_left()` — 광란 (한 판 1번). 광란 중: 쏴도 `_mag` 안 줄고, 빈 탄창이어도 쏘고, `reload()` 막힘, 총알 줄이 가득 찬 채 붉게 깜빡
- `use_flare(dist)` — 앞 32m 에 초록 보급 (한 판 1번)
- `revive()` — 나를 문 좀비(`_grab_e`)를 쓰러뜨리고 `_grace_t = REVIVE_GRACE`, HUD·권총 다시 보이기
- `_refresh_knife()` — 칼 아이콘 흐림/×2 표시 (`_grab` 의 칼 사용도 이걸로 바꿈)
- `_gold_pistol()` — 황금 권총: 총 부품(Frame·Slide·Magazine·Trigger) 재질만 황금 금속으로 (setup 에서 `Inventory.has("gold_pistol")` 이면 자동)
- `_grab` 에서 `_grab_e = e` 기억

### 2.3 `godot/scripts/stage/run_items_ui.gd` — UI (새 파일, 미커밋, **아직 붙이지 않음 → 한 번도 실행 안 됨**)
- `class_name RunItemsUI` (CanvasLayer, layer 6). 톤은 YOU DIED 와 같게 (어두운 판·뼈색·핏빛·Palatino 계열)
- `open_loadout()` — 출발 준비 창: 예비 칼·시작 탄약 팩·모닥불·위험 감지 켜기/끄기 + 수량, "출발" 버튼, **[테스트 지급]** 팩 3개 버튼. 출발 시 켠 것만 `Inventory.use` 후 `signal start_run(picks)`
- `is_open()` · `confirm()` (엔터로 출발용)
- 달리는 중 아이템 칸 (오른쪽 위, 일시정지 아래): "1 광란의 15초 ×N (남은 초)", "2 보급 신호탄 ×N" — 누르면 `signal use_item(item)`. `refresh_slots(run_used, frenzy_left)` · `hide_slots()`
- `warn(side)` — 위험 감지 붉은 가장자리 (왼쪽/가운데/오른쪽, 0.9초 동안 깜빡이며 사라짐)

---

## 3. 남은 작업 (순서대로)

### 3.1 `stage_preview.gd` 에 붙이기 (플레이 모드 `_play` 일 때만)
1. `_ready` 에서 `var ui := RunItemsUI.new(); holder.add_child(ui)` 후 연결:
   - `_showcase.danger.connect(ui.warn)`
   - `ui.use_item.connect(...)`: `"frenzy_30"` → `_showcase.use_frenzy()`, `"flare_supply"` → `_showcase.use_flare(_dist)`
   - `ui.start_run.connect(...)`: `_showcase.apply_loadout(picks)`; `picks.has("bonfire")` 이면 `_body.position.z = -375.0; _dist = 375.0; _showcase.skip_to(375.0)` (모닥불)
2. 출발 전 게임을 멈춰 두기: 준비 창이 열려 있는 동안 `_process` 에서 `_step` 하지 않기 (일시정지 버튼과 겹치지 않게).
3. 키: `KEY_1` → 광란, `KEY_2` → 보급 신호탄, 준비 창 열렸을 때 `KEY_ENTER` → `ui.confirm()`. (`_unhandled_input`)
4. 매 프레임 `ui.refresh_slots(_showcase.run_used, _showcase.frenzy_left())`, 사망 시 `ui.hide_slots()`.
5. **Retry(`reload_current_scene`) 후 다시 준비 창이 떠야 한다** — 다시 시작마다 열린다.
6. `--sim` / `--frames` / `--shots` 모드에서는 UI 를 만들지 않는다 (검사가 막히지 않게).

### 3.2 YOU DIED 화면 "한 번 더" + 권유 (1.4 표대로)
- `_death_cam` 에서 RETRY 와 같이 나타나는 두 번째 버튼:
  - 부활 있음 → "한 번 더 (부활 ×N)" → `Inventory.use("revive")` → 부활 처리
  - 없음 → 상황별 팩 + 한 줄 문구 → 누르면 (결제 연결 전) `Inventory.grant_pack` 후 버튼을 "한 번 더"로 바꿈
- 부활 처리: `_dead = false`, `_dead_t = 0`, 화면 피·어둠·YOU DIED·버튼 숨기기, `_label`·일시정지 버튼 다시 보이기, 카메라는 `_apply_camera` 로 돌아감, `_showcase.revive()`, `_melee = false`.
- 부활·모닥불은 한 판에 하나만 (1.3): 모닥불로 시작한 판이면 부활 버튼 대신 팩 권유만 (또는 막힘 안내).
- "같은 구간 2번째 죽음": 죽은 거리를 `static var` 로 남겨 비교 (광전사 구간 = `BERSERK_AT` 근처, 끝 반전 = 718m 이후). `_deaths` 처럼 static 이면 Retry 뒤에도 남는다.
- 남은 거리 문구는 `StageBuilderV2.remaining(_dist)`.

### 3.3 규칙 수정
- `showcase.gd` `REVIVE_GRACE := 3.0` → **2.0**
- 부활·모닥불 같은 종류: `run_used["rise"] = true` 같은 공용 키로 둘 중 하나만.

### 3.4 검증 (매번 — 기존 규칙 그대로)
```bash
cd ~/3D_Game_MVP/godot && for m in "" "--straight" "--into" "--wiggle" "--showcase"; do godot --headless --path . res://scenes/stage/stage_preview.tscn -- --sim $m 2>&1 | grep "\[sim\]"; done
```
- 다섯 개 모두 "[sim] 완주", 끼임 탈출 0 이어야 한다.
- 새 기능은 창 모드로 확인 (`godot --path . --resolution 1560x720 res://scenes/stage/stage_preview.tscn`): 준비 창 → 테스트 지급 → 출발 → 1/2 키 → 위험 감지 깜빡임 → 죽어서 "한 번 더" → 부활 → Retry 후 준비 창 다시.
- 화면 확인은 SceneTree 스크립트로 뷰포트를 PNG 로 찍는 방식 (`root.get_viewport().get_texture().get_image().save_png(...)`, `--always-on-top` 을 주면 가려져도 그려진다).
- 테스트 인벤토리 비우기: `rm ~/Library/Application\ Support/Godot/app_userdata/3D\ Zombie\ Runner\ \(가칭\)/inventory.json` (경로는 `OS.get_user_data_dir()` 로 확인)

### 3.5 마무리
- PRD 4.12 테스트 상품 표·Q3 를 1장 내용으로 갱신
- 커밋 → PR → 머지. **커밋에 넣지 말 것**: `godot/playtest_500/`·`godot/forest_tour_v3/`(Codex 작업물), `art/concept/`(AI 이미지·스크린샷), `art/source/`, `godot/scenes/fx/{dust_impact,hit_blood,muzzle_flash,smoke_red}.gd.uid`(팀원 파일), `godot/assets/models/*_Diffuse.png` 등 엔진이 뽑은 텍스처
- 백엔드(C, na06078): `backend/supabase/functions/_shared/결제.ts` 의 `PRODUCTS` 에 3종 추가 + 구매 시 구성 수량 지급 — **C 담당이라 직접 고치지 말고 전달**. 앱 내 토스 Android SDK(Godot 플러그인) 담당은 미정.

---

## 4. 참고 — 이 브랜치 이전에 main 에 들어간 것 (전부 머지됨)
- #11 750m 스테이지 / #13 팀원 동작 연결·다크소울 난이도·반전·YOU DIED·권총 텍스처 / #12 타이틀·로그인 화면 시안(세권) / #14 팩 카드 3장 / #7 백엔드(C)
- `godot/project.godot` 은 main 값(`stage_preview.tscn`, 1920×1080)으로 되돌려 둠 (Codex 가 바꿨던 것). Codex 백업: 없음 — 필요하면 Codex 세션 기록 참고.
- 같은 저장소를 Codex 도 만진다 → 커밋 안 된 낯선 변경은 출처부터 확인.

## 5. 상품점 연동 (백엔드 C 님께, 2026-10-01)

계획: 백엔드에서 상품점 페이지를 따로 만든다. 아래 팩 카드 그림을 보여 주고, 카드를 누르면 토스 테스트 결제로 들어간다.

### 5.1 상품 목록 (서버가 가격 정본)
| 상품 ID | 이름 | 가격 | 구성 (아이템 ID × 개수) | 카드 그림 |
|---|---|---|---|---|
| `pack_survival_kit` | 생존 키트 | 1,100원 | `knife_plus`×1 · `ammo_start_pack`×1 · `flare_supply`×1 · `adrenaline`×1 | `art/shop/pack_survival_kit.png` |
| `pack_one_more` | 한 번 더 | 3,300원 | `revive`×1 · `frenzy_30`×1 · `bonfire`×1 | `art/shop/pack_one_more.png` |
| `pack_legend` | 전설의 생존자 | 5,500원 | `revive`×2 · `knife_plus`×2 · `frenzy_30`×2 · `danger_sense`×2 · `gold_pistol`(영구) · `supporter_badge`(영구) | `art/shop/pack_legend.png` |

- 지금 서버에는 `ammo_start_pack` 단품(1,100원)만 있다 → 팩 3종을 서버 상품으로 추가해야 한다.
- `adrenaline` 은 새 아이템이다 (2026-10-01).
- `frenzy_30` 은 이름만 "광란의 15초"로 바뀌었고 ID 는 그대로다.

### 5.2 아이템 ID (게임 `godot/scripts/stage/inventory.gd` ITEMS)
| ID | 이름 | 종류 |
|---|---|---|
| `revive` | 부활 | 소모 |
| `knife_plus` | 예비 칼 | 소모 |
| `frenzy_30` | 광란의 15초 | 소모 |
| `ammo_start_pack` | 시작 탄약 팩 | 소모 |
| `flare_supply` | 보급 신호탄 | 소모 |
| `bonfire` | 모닥불 | 소모 |
| `danger_sense` | 위험 감지 | 소모 |
| `adrenaline` | 아드레날린 | 소모 |
| `gold_pistol` | 황금 권총 | 영구 |
| `supporter_badge` | 서포터 배지 | 영구 |

### 5.3 카드 그림
- 크기: 1080×1350 PNG 3장. 다시 만들 때는 `python3 art/shop/make_packs.py` (Chrome headless 로 HTML 을 찍는다).
- 그림 속 "구매하기" 줄과 "테스트 결제입니다 · 실제 돈이 나가지 않습니다" 문구는 **그림일 뿐**이다.
  - 실제로 누르는 버튼은 상점 페이지에서 만든다 (카드 전체를 버튼으로 하거나, 위에 진짜 버튼을 겹친다).
- 그림 안 가격은 위 표와 같아야 한다. 서버 가격을 바꾸면 `make_packs.py` 의 `CARDS` 도 같이 바꾸고 다시 만든다.

### 5.4 결제 흐름·보안 (기존 `backend/📖백엔드 연동 계약.md` 규칙 그대로)
- 상점 페이지는 `product_id` 만 보낸다. 금액은 서버가 정한다 (요청의 임의 금액은 거부).
- 토스 시크릿 키는 서버에서만 쓴다.
  - 브라우저·앱은 `api.tosspayments.com` 을 직접 부르지 않는다.
  - 브라우저 SDK 초기화에는 클라이언트 키만 쓴다.
- 승인이 끝나면 서버 인벤토리를 **아이템 ID → 개수** 모양으로 내려 준다.
  - 게임은 이 모양을 `user://inventory.json` 과 같은 형태로 받아 쓴다 (`Inventory` 클래스).
- 영구 아이템(`gold_pistol`, `supporter_badge`)은 1 이상이면 "있음"으로 본다.

### 5.5 팩을 바꿀 때 같이 맞출 세 곳
1. 서버 상품 목록 (가격 정본)
2. 게임 `godot/scripts/stage/inventory.gd` 의 `PACKS`
3. 카드 그림 `art/shop/make_packs.py` → `python3 art/shop/make_packs.py` 로 다시 만들기
