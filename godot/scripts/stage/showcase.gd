# 시연 연출 — 스테이지 미리보기에 좀비·권총·보급·이펙트·HUD 를 얹어 "한 판처럼" 보여 준다 (A 확인용)
#
# ⚠️ 게임 코드가 아니다. 실제 좀비 AI·사격·보급·HUD 는 B·C 가 만든다 (TECH_SPEC 13.3).
#    여기서는 모든 에셋을 한 화면에 모아 분위기·크기·색·소리 타이밍을 확인하는 것이 목적이다.
# 사용: stage_preview 가 --showcase 인자를 받으면 이 노드를 붙이고 매 걸음 update() 를 부른다.
# 소리: 영상 프레임에는 소리가 없어서, 사건(총성·비명·줍기) 시각을 events.json 으로 남기고 ffmpeg 로 입힌다.
class_name ShowcaseDirector
extends Node3D

const UI_DIR := "res://assets/ui/icons/" # Team APK-packaged icons.
const HUD_ICON_FILES := ["icon_pistol.png", "icon_pistol_empty.png", "icon_knife.png", "icon_supply.png", "icon_ammo.png"]
const MUZZLE := Vector3(0, 0.08, -0.166)       # weapon_pistol.glb 총구 위치 (PR #4)
const SHOOT_RANGE := 10.0                     # 이 거리 안에 들어온 좀비를 쏜다 (손 뻗고 다가오는 모습이 보이게 가까이)
const SHOT_GAP := 0.45                        # 연사 간격 (초)

const FIRST_ZOMBIE := 70.0                    # 첫 좀비 지점 (2026-09-30 "초반에 좀 더 걷다가") — 25 → 70m, 약 7초 걷고 나서 멀리 보인다
const INTRO_SAFE := 3                         # 처음 이만큼은 풀숲에 엎드린 매복을 넣지 않는다 (안 보이다 갑자기 튀어나와 잡던 문제)
const ZOMBIE_COUNT := 150                     # 스테이지(750m)에 150마리 (약 4.4m 마다 한 마리 — 500m·100마리 때 밀도), 4종을 골고루
const SPAWN_AHEAD := 36.0                     # 이만큼 앞에서 나타난다 (달빛 테두리로 멀리서도 보인다)
const KINDS := ["walker", "runner", "tank", "ambusher"]
const INFINITE_AMMO := false                  # true 면 총알 무한 (HUD 에 ∞) — 2026-09-30 플레이 테스트부터 끔
# 탄창 (2026-09-30 피드백): 시작 7발. 보급 상자를 먹으면 권총 한 정이 무작위로 나오고, 그 모델의 탄창 크기(최대 30발)가
# 새 탄창 크기가 된다. 받은 총알은 예비탄으로 쟁여 두고 R(폰 RELOAD)로 재장전한다 — 재장전은 시간이 걸린다
const HUD_TOP := 48.0                         # 총알 줄 윗변 (2026-10-01 "너무 상단에 붙었다" 22 → 48)
const HUD_K := 1.2                            # 총알·총 HUD 크기 배율
const LINE_W := 200.0                         # 진행 실선 길이 (px) — 왼쪽 위 거리 숫자 아래
const HUD_WHITE := Color(0.96, 0.95, 0.93)    # HUD 흰색 (살짝 따뜻한 흰색 — 순백은 노을 화면에서 튄다)
const START_MAG := 7                          # 시작 탄창 7발 (예비탄 0)
# [이름, 탄창] — 실제 총 모델명(상표)은 쓰지 않는다 (2026-09-30 저작권·상표 점검). 탄창 크기로만 구분
# 보급 1번에 최대 15발 (2026-09-30 "총알을 줄이고 회피를 살리자"): 15 / 12 / 9 / 7발 중 무작위
const PISTOLS := [["소형 권총", 7], ["컴팩트 권총", 9], ["표준 권총", 12], ["풀사이즈 권총", 15]]
const RELOAD_TIME := 1.5                      # 재장전 기본 시간 (초) + 탄창이 클수록 조금 더 (30발 = 2.1초)
const RELOAD_PER_ROUND := 0.02
# 보급 계획: [달린 거리(750m 기준), 초록?] — 빨강·초록을 번갈아
# 11개 → 9개 → 7개 (2026-09-30 두 번째 "20% 더 줄여": 회피를 살린다), 약 100m 간격
# 초록 불빛 보급은 하늘에서 초록 불을 뿜으며 내려온다. 강·다리(510-530m) 위에는 떨어뜨리지 않는다
# 첫 보급(26m 빨강)은 뺐다 (2026-09-30 "처음부터 총알을 너무 많이 준다") → 첫 보급은 125m, 모두 6개
const SUPPLY_PLAN := [[125.0, true], [225.0, false], [330.0, true], [440.0, false], [585.0, true], [680.0, false]]
const DROP_AHEAD := 55.0                      # 이만큼 앞에서 떨어지기 시작 → 착지할 때 약 30m 앞 (PRD F-20: 40-60m 앞 착지에 가깝게)
const DROP_HEIGHT := 20.0
const DROP_SPEED := 4.0                       # 낙하 속도 (m/s)
const PICK_X := 2.3                           # 옆으로 이 거리 안을 지나가면 줍는다
const PICK_Z := 1.6
# 좀비 행동 (2026-09-30 "액션·스피드·모션을 다양하게"): 모델 4종은 그대로, 한 마리마다 행동 스타일을 무작위로 고른다
#   shamble 비틀비틀 걷기 / jog 뛰어오기 / sprint 전력 질주 / idle 서 있다가 가까워지면 출발 / crawl 기어 오기
#   crawl_run 빠르게 기어 오기 / rise 누워 있다가 일어나 달려오기 / stomp 탱커(가까워지면 포효 후 돌진)
#   feed 길가에 쭈그려 시체를 뜯어먹다가 가까워지면 비명을 지르고 달려온다
#   무게·크기에 따라 강·중·약: 러너(가볍다) 빠른 스타일 위주, 워커·매복(보통) 중간, 탱커(무겁다) 느림
const STYLES := {
	"walker": [["shamble", 36], ["jog", 22], ["idle", 14], ["crawl", 16], ["feed", 12]],
	"runner": [["sprint", 50], ["jog", 25], ["crawl_run", 25]],
	"tank": [["stomp", 100]],
	"ambusher": [["rise", 50], ["jog", 20], ["crawl", 18], ["feed", 12]],
}
const STYLE_SPEED := {"shamble": [1.6, 2.6], "jog": [2.6, 3.8], "sprint": [4.2, 5.8], "idle": [1.8, 3.2], "crawl": [0.9, 1.4],
	"crawl_run": [2.2, 3.2], "rise": [3.8, 5.0], "stomp": [1.3, 1.9], "event": [5.4, 6.6], "feed": [2.8, 3.8],
	"berserk": [BERSERK_SPEED, BERSERK_SPEED], "pounce": [6.5, 6.5]}
const TANK_CHARGE := 1.8                      # 탱커 돌진 배율
const RISE_AT := 28.0                         # 누운 좀비가 일어나기 시작하는 거리 (일어나는 데 약 2.7초 — 멀리서 보인다)
const IDLE_WAKE := [13.0, 20.0]               # 서 있던 좀비가 출발하는 거리
# 사이드 질주 이벤트 (2026-09-30): 가끔 빠른 좀비 2-3마리가 양옆 멀리서 먼저 비명을 질러 알리고 대각선으로 달려든다
const EVENT_FROM := 130.0                     # 첫 이벤트 지점
const EVENT_GAP := [70.0, 110.0]              # 이벤트 사이 거리
const EVENT_AHEAD := 38.0                     # 이만큼 앞, 옆으로 8-11m 떨어진 곳에서 나타난다 (갑자기 튀어나오지 않게)
const SCREAM_TIME := 0.9                      # 달려들기 전에 비명을 지르며 멈춰 있는 시간
# 반전 (2026-09-30 "재미가 없다"): ① 광전사 — 사람이 달리는 속도의 두 배(초속 10m)로 돌진, 비명 한 번 뒤 8m 앞부터는 방향 고정(비키면 피한다)
#   ② 길목 매복 — 풀숲에 숨어 있다가 내 바로 앞 8.5m, 내가 달리는 줄에서 벌떡 일어나 덮친다 (순간적으로 비키거나 쏘지 않으면 잡힌다)
#   지점은 750m 기준 달린 거리. 마지막 매복은 결승 10m 전
const BERSERK_AT := [165.0, 295.0, 420.0, 560.0, 690.0]
const BERSERK_SPEED := 10.0                   # = 사람 달리기(5m/s) × 2
const BERSERK_AHEAD := 42.0
const BERSERK_LOCK := 8.0
const POUNCE_AT := [120.0, 235.0, 360.0, 470.0, 610.0, 700.0]   # 마지막 매복은 740 → 700m (끝의 광전사 둘과 겹치지 않게)
# 끝 반전 (2026-09-30 "다 깼다 싶을 때"): 남은 32m 에서 왼쪽 광전사 → 0.7초 뒤 오른쪽 광전사. 시간차가 있어 하나씩 피할 수 있다
const FINALE_AT := 718.0
const FINALE_GAP := 0.7
const FINALE_AHEAD := 26.0
const FINALE_SIDE := 10.0
const FINALE_LOCK := 6.0
# 최후의 반전 (2026-09-30 "안심할 때쯤 바닥에서"): 끝의 광전사 둘이 지나가면 바로 앞 6.5m 땅속에서 튀어나와 약 1초 만에 덮친다
# 피할 수 없다 — 쏘면 살고, 못 쏘면 칼로 벗어나고, 칼도 없으면 죽는다
const BURST_AT := 738.0                       # 늦어도 여기서는 튀어나온다 (둘을 먼저 지나치면 그 즉시)
const BURST_AHEAD := 6.5
const BURST_SPEED := 1.5                      # 나(5m/s)와 합쳐 초당 6.5m → 약 1초                      # 끝의 둘은 6m 앞에서 방향 고정 → 비킬 틈 약 0.4초, 피해도 아슬아슬하게 스친다
const POUNCE_AHEAD := 8.5
# 다리 밑 매복 (2026-10-01 "다리 건널 때 재밌는 요소"): 다리 위 왼쪽에 버려진 차 → 오른쪽 틈으로만 지나간다.
#   그 오른쪽 난간 밑에서 손이 먼저 올라와 매달리고(경고) → 기어올라 → 틈을 막듯 덮친다.
#   피할 길: 매달린 동안 쏘거나 · 덮치기 직전 차 쪽(왼쪽)으로 바짝 붙거나 · 칼
const UNDER_D := StageBuilderV2.RIVER_Z0 + 13.0      # 좀비가 올라오는 곳 (다리 위 차 바로 앞, 오른쪽 가장자리)
const UNDER_AHEAD := 9.0                              # 이만큼 앞에 왔을 때 손이 올라온다 (너무 멀면 총에 가려 안 보인다)
const UNDER_HANG := 0.75                              # 매달려 기어오르는 시간 (경고 시간)
# (차 안 좀비 낚시는 2026-10-01 시험 후 뺐다 — 낮은 폐차라 지붕 위로 머리가 튀어나와 버그처럼 보였다)
const CAR_D := StageBuilderV2.RIVER_Z0 + 10.0         # 다리 위 차 (stage_builder_v2 _build_obstacles: x -1.4, 8도)
# 다리 입구 왼쪽 무리 (2026-10-01 "왼쪽이 너무 비어 보인다"): [종류, 스타일, 차 기준 거리(+앞), x]
#   11마리 → "너무 많다, 2/3 덜어내" → 4마리. "가운데 몰리지 말고 좌우로 퍼지게 · 경찰 좀비(워커)가 멍청해 보인다"
#   → 강가는 좌우 양쪽에 · 각자 자기 줄(x)을 지키며 다가온다 · 워커는 어슬렁·뜯어먹기 대신 팔 뻗고 뛰어온다
#   "다리 들어서는 왼쪽에 한 마리 더 · 차 뒤 셋 중 하나 빼" → 다리 입구 왼쪽 서 있다 다가오는 하나 추가, 차 뒤는 둘 (멀리서 오던 일반 좀비는 치운다)
const BRIDGE_LEFT_CROWD := [["walker", "jog", -13.0, -5.6], ["runner", "jog", -8.0, 5.2],
	["ambusher", "idle", -8.0, -2.6], ["ambusher", "crawl", 6.0, -1.6], ["walker", "jog", 14.0, -2.9]]   # 차 뒤에는 이 둘만
const CUT_MISS := 1.1                                 # 다리 입구 그 좀비가 내 줄에서 비껴 드는 폭 (m) — 스치면 어깨빵, 잡히지는 않는다
const CAR_BLOCK := 1.5                                # 다리 위 좀비는 차 중심에서 이만큼 뒤에서 멈춘다 (차 폭 절반 + 여유)
const BRIDGE_LANES := [-3.2, -0.8]                   # 다리 위 다른 좀비가 다니는 줄의 범위 (왼쪽 난간 ~ 차 오른쪽 끝 앞) — 오른쪽 틈은 비운다
const UNDER_SPEED := 3.5                              # 올라온 뒤 덮치는 속도
const POUNCE_LOCK := 4.0
# 동작 팩 (Scary Zombie Pack, Mixamo): 동작만 담은 파일 하나를 4종 모두에 입힌다 (tools/assets/pack_zombie_anims.py)
const ANIM_PACK := "res://assets/models/zombie_anims.glb"
const PACK_HIPS := 96.29514                   # 팩 뼈대의 엉덩이 높이 (뼈대 좌표, cm) — 좀비마다 키 비율로 맞춘다
const PACK_LOOPS := ["p_walk", "p_run", "p_crawl", "p_crawl_run", "p_idle", "p_bite", "p_bite2", "p_neck_bite", "p_attack"]
# 붙잡은 뒤 무는 동작: 머리가 얼굴 높이(1.3-1.5m)에 머무는 것만 (2026-09-30 측정 — p_bite·p_bite2 는 바닥의 시체를 뜯는 동작이라 feed 스타일에 쓴다)
const BITE_ANIMS := ["bite", "pack/p_neck_bite"]
const FEED_ANIMS := ["pack/p_bite", "pack/p_bite2"]
const GRAB_TIME := 0.6                        # 붙잡는 동작을 보여 주는 시간 (그다음 문다) — 0.9 → 0.6 (2026-09-30 "루즈하다")
const BITE_SPEED := 1.3                       # 무는 동작 빠르기
const DEATH_ANIMS := ["death", "pack/p_death", "pack/p_dying"]
const BLEND := 0.25                           # 동작이 바뀔 때 섞는 시간 (초) — 뚝 바뀌면 몸이 순간 튀어 끊겨 보인다 (2026-09-30)
const HOMING_LOCK := 3.0                      # 이만큼 가까워지면 더는 방향을 틀지 않는다 → 옆으로 비키면 피할 수 있다
const HP := {"walker": 1, "runner": 1, "tank": 2, "ambusher": 1}   # 탱커 4 → 2발 (2026-09-30 "너무 세다")

signal caught(zombie: Node3D)                 # 칼 없이 잡혔다 → 사망 연출 (stage_preview)
signal knifed                                 # (옛 즉시 칼) — 지금은 melee_start 로 합을 맞춘다
signal melee_start(zombie: Node3D)            # 칼 근접전 시작: 멈춰 서서 좀비와 마주 본다 (stage_preview 가 칼 동작·카메라)
signal brushed(side: float)
signal quake(amp: float, dur: float)         # 다리 흔들림 (2026-10-01): 화면이 이만큼 세게 · 이 시간 동안 덜덜 떨린다
signal burst                                  # 마지막 좀비가 바닥에서 튀어나왔다 → 화면 덜컥                   # 좀비와 스쳤다 → 어깨빵 (side: 좀비가 있는 쪽 -1 왼쪽 / +1 오른쪽)
signal tripped                                # 기는 좀비가 발목을 잡았다 → 잠깐 휘청 (풀에 묻혀 안 보이니 죽이지는 않는다)

var events: Array = []                        # [시각, 소리 이름] — 영상에 소리 입힐 때 씀
var catching := false                         # 플레이 테스트: 좀비가 플레이어를 잡을 수 있다
var service_gun_kills := 0
var service_grabs := 0
var service_knife_used := false
var service_invulnerable := false              # Only the debug adapter may enable this; normal rules stay unchanged.
# 잡힘 규칙 (2026-09-30): 좀비는 앞에서만 덮친다. 내 앞에서 몸을 절반 이상 가린 채 닿으면 잡힌다.
# 비켜서 스쳐 지나가면 그걸로 끝 — 뒤돌아 쫓아오거나 뒤에서 잡지 않는다
# 잡기 판정 (2026-09-30 "탱커가 못 잡는다 / 좀 더 붙잡게"): 덩치별로 팔이 닿는 폭·거리를 따로
const REACH := 0.9                            # 앞뒤로 이만큼 붙으면 "닿음" (0.8 → 0.9)
const ZOMBIE_W := 1.2                         # 좀비 몸+뻗은 팔 폭 (0.9 → 1.2)
const TANK_REACH := 1.3                       # 탱커는 팔이 길고 덩치가 크다
const TANK_W := 1.8
const LUNGE_WARN := 0.45                      # 반반 확률로: 부딪히기 이만큼(초) 전에 비명·팔 뻗기로 예고 → 그때 비키면 피한다
const PLAYER_SPEED := 5.0                     # 플레이어 달리기 속도 (stage_preview RUN_SPEED 와 같게)
const BRUSH_EXTRA := 0.6                      # 잡히진 않았지만 이만큼 안으로 스치면 어깨빵
const PLAYER_W := 0.7                         # 플레이어 몸 폭
const COVER_TO_GRAB := 0.5                    # 내 몸을 이만큼(절반) 이상 가리면 잡힘
const KNIVES := 1                             # 칼은 한 스테이지에 한 번 (PRD 칼 규칙)
var _knife_left := KNIVES
const KNIFE_GRACE := 1.5                      # 칼로 벗어난 직후 이 시간은 다시 잡히지 않는다 (연달아 잡히던 문제)
var _grace_t := 0.0
# ── 팩 아이템 (2026-09-30, scripts/stage/inventory.gd · run_items_ui.gd) ──
signal danger(side: int)                      # 위험 감지: 매복·광전사가 오는 쪽 (-1 왼쪽 / 0 앞 / 1 오른쪽)
var danger_sense := false                     # 이번 판에 위험 감지를 가져왔다
var run_used := {}                            # 이번 판에 쓴 달리는 중 아이템 (한 판에 종류별 1번)
var _frenzy_t := 0.0                          # 광란의 15초 남은 시간 (총알 무한 · 재장전 없음)
var _adren_t := 0.0                           # 아드레날린 남은 시간 (빨리 달리기 · 좌우로 재빨리)
var _grab_e: Dictionary = {}                  # 나를 붙잡아 문 좀비 (부활하면 쓰러뜨린다)
var _warned_pounce := -1
var _under_done := false
var _bridge_cleared := false
var _bridge_crowd := false
var _knife_n: Label                           # 칼이 2자루면 칼 아이콘 옆 ×2
const FRENZY_TIME := 15.0                       # 30 → 10 → 15초 (2026-10-01)
const ADREN_TIME := 8.0                         # 아드레날린 시간 (5 → 8초, 2026-10-01 "좀 짧다")
const ADREN_DODGE := 0.3                        # 아드레날린 중 잡힐 순간 이 확률로 몸을 틀어 빠져나간다 (회피 30% 증강, 2026-10-01)
const START_AMMO_PACK := 7
const FLARE_AHEAD := 32.0
const REVIVE_GRACE := 2.0                     # 부활 뒤 이만큼은 잡히지 않는다 (칼로 빠져나올 때와 같은 시간 — 사용자 수정 2026-10-01)
const GOLD_TINT := Color(1.0, 0.76, 0.33)
var _melee_e: Dictionary = {}                 # 칼 근접전 상대
var _hud_knife: TextureRect
var auto_fire := true                         # 영상·통과 검사: 가까이 온 좀비를 알아서 쏜다 / 플레이 테스트: fire() 로 직접
var live_audio := false                       # 플레이 테스트: 소리를 실제로 낸다 (영상은 events.json 으로 나중에 입힌다)
const SFX_DB := -7.94                         # 효과음: 절반(-6dB) → 거기서 20% 더 줄임(×0.8 = -1.94dB) (2026-09-30 "아직 크다")
const BGM_DB := -13.94                        # 배경음도 같은 비율로 (-12 → -13.94)
const SFX_TRIM := {"sfx_pistol_dry": -6.02, "sfx_glock_shot": -4.0, "sfx_glock_reload": 4.0}   # 소리별 추가 조정 (dB): 총소리만 절반 더 (×0.5 = -6.02dB, 2026-09-30 "총소리가 크다") · 글록 총성·재장전 (2026-10-01)
const WAV_SFX := ["sfx_glock_shot", "sfx_glock_reload"]   # .ogg 가 아니라 .wav 인 효과음 (Pixabay 원본을 잘라 다듬은 것, ASSETS_LICENSE 사운드)
const FIRE_RANGE := 15.0                      # 직접 쏠 때 닿는 거리 (30 → 15m, 2026-09-30 "사정거리가 너무 길다" — 멀리서 다 쏘지 말고 피하게)
const AIM_WIDTH := 0.9                        # 화면 가운데 조준선에서 옆으로 이만큼(+거리 × 0.06) 안에 있으면 맞는다
var _builder: StageBuilderV2
var _camera: Camera3D
var _pistol: Node3D
var _vm: ViewmodelMotion
const VM_OFFSET := Vector3(0.005, -0.013, 0.055)   # 총을 살짝 뒤(카메라 쪽)·아래로 → 오른쪽 소매가 덜 보인다 (2026-09-30)
const GUN_SCALE := 1.18                       # 권총만 18% 크게 (손·팔은 그대로, 2026-09-30)
const VM_RELOAD_LEN := 1.21                   # 권총 재장전 동작의 원래 길이 (초) — 게임 재장전 시간에 맞춰 늘린다
var _zombies: Array = []                      # {node, ap, kind, hp, state, x, d, t}
var _crates: Array = []                       # {node, d, x, y, landed, taken, smoke}
var _plan: Array = []                         # [나타날 지점(달린 거리), 종류]
var _next_wave := 0
var _next_crate := 0
var _next_green := 0
var _next_event := EVENT_FROM
var _next_berserk := 0
var _next_pounce := 0
var _finale := 0                              # 0 아직 / 1 왼쪽 나옴 (오른쪽 기다림) / 2 끝
var _finale_t := 0.0
static var _libs := {}                        # 종류 → 동작 라이브러리 (한 번만 만든다)
static var _pack_animations: Dictionary = {}
var _mag := START_MAG                         # 탄창에 든 총알
var _mag_cap := START_MAG                     # 지금 총의 탄창 크기
var _reserve := 0                             # 예비탄
var _gun_name := "권총"
var _reload_left := 0.0                       # 재장전 남은 시간 (0 이면 재장전 중 아님)
var _reload_total := 0.0
var _shot_cd := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _hud_layer: CanvasLayer
var _hud_bullets: Control
var _hud_reserve: Label
var _hud_gun: Label
var _hud_pistol: TextureRect
var _hud_dist: Label
var _hud_line_done: ColorRect                 # 진행 실선: 지나온 쪽 (조금 밝게)
var _hud_tick: ColorRect                      # 진행 작대기
var _gun_toast_t := 0.0
var _tex_pistol: Texture2D


func setup(builder: StageBuilderV2, camera: Camera3D, hud_holder: Node) -> void:
	_builder = builder
	_camera = camera
	_rng.seed = 7
	var bag: Array = []
	for i in ZOMBIE_COUNT:
		bag.append(KINDS[i % KINDS.size()])
	for i in bag.size():                               # 섞되 같은 씨앗이면 늘 같은 순서
		var j := _rng.randi_range(i, bag.size() - 1)
		var t = bag[i]
		bag[i] = bag[j]
		bag[j] = t
	_intro_order(bag)
	_next_event = EVENT_FROM + _rng.randf_range(0.0, 20.0)
	for i in ZOMBIE_COUNT:
		var gap := (StageBuilderV2.STAGE_LENGTH - 20.0 - FIRST_ZOMBIE) / ZOMBIE_COUNT
		_plan.append([FIRST_ZOMBIE + i * gap + _rng.randf_range(-0.3, 0.3) * gap, bag[i]])
	for w in _plan:                                     # 다리 위는 비운다 → 다리 밑 매복이 또렷이 보이게 (그 수만큼 다리 건너편으로 옮긴다, 총 마릿수는 그대로)
		if w[0] > UNDER_D - 16.0 and w[0] < UNDER_D + 34.0:   # (+26 → +40: 옮긴 좀비가 내가 차를 지나기 전에 차 뒤로 몰려오지 않게)
			w[0] += _rng.randf_range(40.0, 75.0)            # 한 덩어리로 몰려오지 않게 흩어 놓는다 ("똑같은 셋이 패턴처럼 뛰어온다")
	_plan.sort_custom(func(p, q): return p[0] < q[0])
	_prewarm()
	_build_zombie_light(camera)
	# 1인칭 권총: 팀원 권총 동작 (scripts/stage/viewmodel_motion.gd) — 손 달린 권총, 반동·슬라이드·재장전(탄창 빼기 → 왼손 새 탄창 → 슬라이드)
	_vm = ViewmodelMotion.new()
	_vm.rest_offset = VM_OFFSET
	_vm.gun_scale = GUN_SCALE
	_vm.model_path = "res://assets/models/weapon_pistol_hd.glb"   # 텍스처 디벨롭 버전 (tools/assets/texture_pistol.py — 원본은 그대로)
	_vm.process_mode = Node.PROCESS_MODE_PAUSABLE          # 카메라는 일시정지 중에도 도는 노드 아래 → 권총은 따로 멈추게 (2026-09-30 "일시정지해도 손이 움직인다")
	camera.add_child(_vm)
	_pistol = _vm
	if Inventory.has("gold_pistol"):
		run_used["gold_pistol"] = true
		_gold_pistol()
	_build_hud(hud_holder)


func _icon(name: String) -> Texture2D:
	if not HUD_ICON_FILES.has(name):
		push_error("Unknown HUD icon: " + name)
		return null
	var path: String = UI_DIR + name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Editor pre-import tests can read the raw source; exports use imported resources.
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("HUD icon unavailable: " + path)
		return null
	return ImageTexture.create_from_image(img)


func _build_hud(holder: Node) -> void:
	var layer := CanvasLayer.new()
	holder.add_child(layer)
	_hud_layer = layer
	var w := 1560.0
	# HUD (2026-09-30 "인투더데드2 처럼 깔끔한 흰색"): 어두운 상자 없이 흰색만. 가운데 위 = 장전된 총알 줄 | 예비탄,
	# 그 아래 = 권총·칼 흰 실루엣. 왼쪽 위 = 남은 거리(m) + 바로 아래 진행 실선. 굵고 좁은 글꼴 하나로 통일
	var heavy: Font = load("res://assets/fonts/Anton-Regular.ttf")   # Impact 같은 굵고 좁은 글꼴을 게임에 넣어 둔다 (OFL, assets/fonts — 폰에는 Impact 가 없어 다르게 나왔다)
	var heavy_sys := SystemFont.new()                     # Anton 에 없는 글자는 기기 글꼴로
	heavy_sys.font_names = PackedStringArray(["Impact", "Arial Black", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	heavy_sys.font_weight = 800
	heavy.fallbacks = [heavy_sys]
	_hud_bullets = Control.new()                       # 총알 줄 (쏠 때마다 하나씩 사라진다 — _draw_bullets)
	_hud_bullets.position = Vector2(w / 2 - 300, HUD_TOP)   # 2026-10-01: 조금 내리고(22 → 48) 크게(×1.2), 총알 줄 + 예비탄 묶음을 화면 가운데로 (_refresh_ammo)
	_hud_bullets.size = Vector2(600, 54)
	_hud_bullets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_bullets.draw.connect(_draw_bullets)
	layer.add_child(_hud_bullets)
	_hud_reserve = Label.new()                         # 예비탄 숫자 (총알 줄 오른쪽, 세로줄 뒤)
	_hud_reserve.add_theme_font_override("font", heavy)
	_hud_reserve.add_theme_font_size_override("font_size", 60)
	_white_label(_hud_reserve)
	layer.add_child(_hud_reserve)
	_tex_pistol = _white_icon("icon_pistol.png")
	_hud_pistol = TextureRect.new()
	_hud_pistol.texture = _tex_pistol
	_hud_pistol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud_pistol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hud_pistol.position = Vector2(w / 2 - 84, HUD_TOP + 60)
	_hud_pistol.size = Vector2(90, 64)
	layer.add_child(_hud_pistol)
	var knife := TextureRect.new()
	knife.texture = _white_icon("icon_knife.png")
	knife.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knife.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knife.position = Vector2(w / 2 + 26, HUD_TOP + 64)
	knife.size = Vector2(60, 55)
	layer.add_child(knife)
	_hud_knife = knife
	_hud_gun = Label.new()                             # 새 총을 주웠을 때만 잠깐 뜬다 (무기 아이콘 아래)
	_hud_gun.position = Vector2(w / 2 - 150, HUD_TOP + 128)
	_hud_gun.size = Vector2(300, 28)
	_hud_gun.modulate.a = 0.0
	_hud_gun.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_gun.add_theme_font_size_override("font_size", 20)
	_white_label(_hud_gun)
	layer.add_child(_hud_gun)
	# 남은 거리 (m): 왼쪽 위
	_hud_dist = Label.new()
	_hud_dist.position = Vector2(44, 14)
	_hud_dist.add_theme_font_override("font", heavy)
	_hud_dist.add_theme_font_size_override("font_size", 66)
	_white_label(_hud_dist)
	layer.add_child(_hud_dist)
	# 진행: 거리 숫자 바로 아래 가는 실선 + 작대기
	var line := ColorRect.new()
	line.position = Vector2(48, 98)
	line.size = Vector2(LINE_W, 2)
	line.color = Color(1, 1, 1, 0.3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(line)
	_hud_line_done = ColorRect.new()
	_hud_line_done.size = Vector2(0, 2)
	_hud_line_done.color = Color(1, 1, 1, 0.75)
	line.add_child(_hud_line_done)
	_hud_tick = ColorRect.new()
	_hud_tick.size = Vector2(3, 14)
	_hud_tick.position = Vector2(-1.5, -6)
	_hud_tick.color = Color(1, 1, 1, 0.95)
	line.add_child(_hud_tick)
	_refresh_ammo()


# ── 팩 아이템 효과 ───────────────────────────────────────────
# 출발 준비에서 켠 아이템 (inventory 에서는 이미 1개씩 뺐다)
func apply_loadout(picks: Dictionary) -> void:
	for item in picks:
		run_used[item] = true # Local test provenance only, never server ownership.
	if picks.has("knife_plus"):
		_knife_left = mini(_knife_left + 1, 2)
		_refresh_knife()
	if picks.has("ammo_start_pack"):
		_reserve += START_AMMO_PACK
		_refresh_ammo()
	danger_sense = picks.has("danger_sense")
	print("[items] 출발: %s" % [picks.keys()])


# 모닥불: d 지점부터 시작 — 그 앞의 좀비·보급·반전은 건너뛴다
func skip_to(d: float) -> void:
	var sc := StageBuilderV2.STAGE_LENGTH / 750.0
	while _next_wave < _plan.size() and _plan[_next_wave][0] < d + 8.0:
		_next_wave += 1
	while _next_crate < SUPPLY_PLAN.size() and SUPPLY_PLAN[_next_crate][0] * sc < d + 5.0:
		_next_crate += 1
	while _next_berserk < BERSERK_AT.size() and BERSERK_AT[_next_berserk] * sc < d + 5.0:
		_next_berserk += 1
	while _next_pounce < POUNCE_AT.size() and POUNCE_AT[_next_pounce] * sc - POUNCE_AHEAD < d + 5.0:
		_next_pounce += 1
	_next_event = maxf(_next_event, d + 40.0)
	print("[items] 모닥불: %.0fm 부터" % d)


# 광란의 15초 (한 판 1번)
func use_frenzy() -> bool:
	if run_used.has("frenzy_30") or not Inventory.use("frenzy_30"):
		return false
	run_used["frenzy_30"] = true
	_frenzy_t = FRENZY_TIME
	_reload_left = 0.0
	_refresh_ammo()
	_sfx("sfx_zombie_scream")
	print("[items] 광란의 15초")
	return true


# 아이템 칸을 빛나게 할 때 (지금 쓰면 좋다): 광란 = 총알이 다 떨어졌거나 끝 반전 · 신호탄 = 총알 3발 이하
func item_hints(dist: float) -> Dictionary:
	var h := {}
	if (_mag + _reserve <= 0) or (_finale >= 1 and _finale < 3) or dist >= FINALE_AT * StageBuilderV2.STAGE_LENGTH / 750.0 - 10.0:
		h["frenzy_30"] = true
	if _mag + _reserve <= 3:
		h["flare_supply"] = true
	if _finale >= 1 and _finale < 3:                   # 끝 반전: 광전사가 쫓아온다 → 달려서 따돌리기
		h["adrenaline"] = true
	return h


func frenzy_left() -> float:
	return maxf(_frenzy_t, 0.0)


# 아드레날린 (한 판 1번): 몇 초 동안 더 빨리 달리고 좌우로 재빨리 비킨다 (속도는 stage_preview 가 적용)
func use_adrenaline() -> bool:
	if run_used.has("adrenaline") or not Inventory.use("adrenaline"):
		return false
	run_used["adrenaline"] = true
	_adren_t = ADREN_TIME
	_sfx("sfx_breath")
	print("[items] 아드레날린")
	return true


func adrenaline_left() -> float:
	return maxf(_adren_t, 0.0)


# 보급 신호탄 (한 판 1번): 앞 32m 에 초록 불빛 보급이 떨어진다
func use_flare(dist: float) -> bool:
	if run_used.has("flare_supply") or not Inventory.use("flare_supply"):
		return false
	run_used["flare_supply"] = true
	_drop_crate(dist + FLARE_AHEAD, true)
	_sfx("sfx_supply_pickup")
	print("[items] 보급 신호탄 %.0fm" % (dist + FLARE_AHEAD))
	return true


# 부활: 나를 문 좀비는 쓰러지고, 잠깐 잡히지 않는다
func revive() -> void:
	if not _grab_e.is_empty():
		var e := _grab_e
		e["passed"] = true
		e["state"] = "dead"
		e["ap"].speed_scale = 1.0
		e["ap"].play("death", 0.15)
		_grab_e = {}
	_grace_t = REVIVE_GRACE
	_hud_layer.visible = true
	_pistol.visible = true
	print("[items] 부활 (%.0f초 무적)" % REVIVE_GRACE)


func _refresh_knife() -> void:
	if _hud_knife == null:
		return
	_hud_knife.modulate = Color(1, 1, 1, 1.0 if _knife_left > 0 else 0.2)
	if _knife_n == null:
		_knife_n = Label.new()
		_knife_n.position = Vector2(46, 18)
		_knife_n.add_theme_font_size_override("font_size", 22)
		_white_label(_knife_n)
		_hud_knife.add_child(_knife_n)
	_knife_n.text = "×%d" % _knife_left if _knife_left > 1 else ""


# 황금 권총 (영구): 총 부품만 황금빛 금속으로 (손·팔은 그대로)
func _gold_pistol() -> void:
	for part in ["Frame", "Slide", "Magazine", "Trigger"]:
		for n in _vm.find_children(part, "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i) as BaseMaterial3D
				if src == null:
					continue
				var m := src.duplicate() as BaseMaterial3D
				m.albedo_texture = null
				m.albedo_color = GOLD_TINT
				m.metallic = 0.95
				m.metallic_texture = null
				m.roughness = 0.3
				mi.set_surface_override_material(i, m)


func _refresh_ammo() -> void:
	_hud_bullets.queue_redraw()
	_hud_reserve.text = "∞" if (INFINITE_AMMO or _frenzy_t > 0.0) else str(_reserve)   # 광란 중에는 무한대
	_hud_reserve.add_theme_color_override("font_color", Color(1.0, 0.36, 0.26) if _frenzy_t > 0.0 else HUD_WHITE)
	var row_w := _bullet_row_width(_mag_cap)
	var rw: float = _hud_reserve.get_theme_font("font").get_string_size(_hud_reserve.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x
	var group := row_w + 22.0 + rw                       # 총알 줄 + 세로줄 + 예비탄 숫자 — 이 묶음을 화면 가운데로
	var x0 := (_hud_bullets.size.x - row_w) * 0.5
	_hud_bullets.position.x = 1560.0 * 0.5 - group * 0.5 - x0
	_hud_reserve.position = Vector2(_hud_bullets.position.x + x0 + row_w + 22.0, HUD_TOP + _hud_bullets.size.y * 0.5 - 44.0)
	_hud_gun.text = "%s  %d발 탄창" % [_gun_name, _mag_cap]
	_hud_pistol.modulate.a = 1.0 if (_mag + _reserve > 0 or INFINITE_AMMO) else 0.3   # 총알이 하나도 없으면 흐리게


# 총알 줄: 탄창 크기가 클수록 촘촘하게 (6발 = 굵게, 30발 = 가늘게)
func _bullet_dims(cap: int) -> Vector2:
	return (Vector2(10.0, 34.0) if cap <= 12 else (Vector2(8.0, 30.0) if cap <= 20 else Vector2(6.0, 26.0))) * HUD_K


func _bullet_row_width(cap: int) -> float:
	var d := _bullet_dims(cap)
	return cap * (d.x + d.x * 0.55) - d.x * 0.55


# 장전된 총알만 그린다 (쏘면 하나씩 사라진다). 재장전 중에는 하나씩 다시 채워진다
func _draw_bullets() -> void:
	var shown := _mag
	if _reload_left > 0.0:
		var take := mini(_mag_cap - _mag, _reserve)
		shown = _mag + int(take * clampf(1.0 - _reload_left / _reload_total, 0.0, 1.0))
	var d := _bullet_dims(_mag_cap)
	var gap := d.x * 0.55
	var row_w := _bullet_row_width(_mag_cap)
	var x0 := (_hud_bullets.size.x - row_w) * 0.5
	var y0 := (_hud_bullets.size.y - d.y) * 0.5
	var col := HUD_WHITE
	if _frenzy_t > 0.0:                                   # 광란: 탄창이 가득 찬 채 붉게 빛난다
		shown = _mag_cap
		col = Color(1.0, 0.32, 0.22).lerp(Color(1.0, 0.8, 0.6), 0.5 + 0.5 * sin(_time * 12.0))
	for i in shown:
		var x := x0 + i * (d.x + gap)
		_bullet_shape(Vector2(x + 2, y0 + 2), d, Color(0, 0, 0, 0.35))   # 그림자
		_bullet_shape(Vector2(x, y0), d, col)
	var bar_x := x0 + row_w + 9.0                        # 예비탄 앞 가는 세로줄
	_hud_bullets.draw_rect(Rect2(bar_x, y0 - 2, 2, d.y + 4), Color(1, 1, 1, 0.55))


# 총알 하나: 둥근 탄두 + 탄피, 사이에 가는 홈 한 줄
func _bullet_shape(at: Vector2, d: Vector2, c: Color) -> void:
	var r := d.x * 0.5
	var tip_h := d.y * 0.36
	_hud_bullets.draw_circle(at + Vector2(r, r), r, c)
	_hud_bullets.draw_rect(Rect2(at + Vector2(0, r), Vector2(d.x, tip_h - r)), c)
	_hud_bullets.draw_rect(Rect2(at + Vector2(0, tip_h + 1.5), Vector2(d.x, d.y - tip_h - 1.5)), c)


func _white_label(l: Label) -> void:
	l.add_theme_color_override("font_color", HUD_WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)


# 아이콘을 흰 실루엣으로 (모양은 그대로, 색만 흰색)
func _white_icon(name: String) -> Texture2D:
	var texture := _icon(name)
	if texture == null:
		return null
	var img := texture.get_image()
	if img == null or img.is_empty():
		push_error("HUD icon has no image: " + name)
		return null
	if img.is_compressed() and img.decompress() != OK:
		push_error("HUD icon decompression failed: " + name)
		return null
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(HUD_WHITE.r, HUD_WHITE.g, HUD_WHITE.b, a))
	return ImageTexture.create_from_image(img)


# 재장전 (탄창이 비면 저절로 · R 키 · RELOAD 버튼): 시간이 걸리고 그동안 못 쏜다
func reload() -> void:
	if _frenzy_t > 0.0:
		return                                           # 광란 중에는 재장전하지 않는다
	if INFINITE_AMMO or _reload_left > 0.0 or _mag >= _mag_cap or _reserve <= 0:
		return
	_reload_total = RELOAD_TIME + RELOAD_PER_ROUND * _mag_cap
	_reload_left = _reload_total
	_refresh_ammo()
	_vm.speed = VM_RELOAD_LEN / _reload_total            # 탄창 빼기·끼우기·슬라이드가 재장전 시간 동안 이어지게
	_vm.reload()
	_sfx("sfx_glock_reload")                             # 글록 재장전: 탄창 빼기 → 끼우기 → 슬라이드 (재장전 시간에 맞춰 1.66초로 줄임, 2026-10-01)
	print("[reload] 시작 %.1f초 (탄창 %d / 예비 %d)" % [_reload_total, _mag, _reserve])


func _update_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		if _mag <= 0 and _reserve > 0 and _frenzy_t <= 0.0 and _melee_e.is_empty():
			reload()                                     # 탄창이 비면 저절로 재장전 (2026-10-01 "리로드는 자동으로" — 폰 RELOAD 버튼 없앰)
		return
	_reload_left -= delta
	_hud_bullets.queue_redraw()
	if _reload_left <= 0.0:
		var take := mini(_mag_cap - _mag, _reserve)
		_mag += take
		_reserve -= take
		_refresh_ammo()
		print("[reload] 끝 → 탄창 %d / 예비 %d" % [_mag, _reserve])


# 효과음 (stage_preview 가 부딪힘 소리에 쓴다)
func sfx(name: String) -> void:
	_sfx(name)


# 매 걸음: 달린 거리 dist, 카메라 x, 경과 시간
func update(dist: float, cam_x: float, delta: float) -> void:
	_time += delta
	if _warm and _time > 0.3:                              # 미리 그리기 끝: 풀 좀비는 숨겨서 남기고 나머지는 지운다
		for kind in _pool:
			for z in _pool[kind]:
				z.reparent(self, false)
				z.visible = false
				z.position = Vector3(0, -50, 0)
				(z.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).stop()
		_warm.queue_free()
		_warm = null
	elif _warm:
		_warm.position = Vector3(cam_x, -2.2, -dist - 14.0)   # 카메라를 따라가며 화면 안(땅 밑)에 둔다
	_hud_dist.text = "%dm" % StageBuilderV2.remaining(dist)
	var k := clampf(dist / StageBuilderV2.STAGE_LENGTH, 0.0, 1.0)
	_hud_line_done.size.x = LINE_W * k
	_hud_tick.position.x = LINE_W * k - 1.5
	_gun_toast_t -= delta
	_hud_gun.modulate.a = clampf(_gun_toast_t / 0.5, 0.0, 1.0)   # 2.5초 떠 있다가 마지막 0.5초에 사라진다
	while _next_wave < _plan.size() and dist >= _plan[_next_wave][0] - SPAWN_AHEAD:
		_spawn(_plan[_next_wave][1], "", _plan[_next_wave][0] - dist, NAN, dist, cam_x)
		_next_wave += 1
	var sc750 := StageBuilderV2.STAGE_LENGTH / 750.0
	while _next_berserk < BERSERK_AT.size() and dist >= BERSERK_AT[_next_berserk] * sc750:
		_berserker(dist, cam_x)
		_next_berserk += 1
	if danger_sense and _next_pounce < POUNCE_AT.size() and _warned_pounce < _next_pounce and dist >= POUNCE_AT[_next_pounce] * sc750 - POUNCE_AHEAD - PLAYER_SPEED * 1.0:
		_warned_pounce = _next_pounce                    # 위험 감지: 길목 매복 1초 전
		danger.emit(0)
	_adren_t -= delta
	if _frenzy_t > 0.0:
		_frenzy_t -= delta
		_hud_bullets.queue_redraw()
		if _frenzy_t <= 0.0:
			_refresh_ammo()
	while _next_pounce < POUNCE_AT.size() and dist >= POUNCE_AT[_next_pounce] * sc750 - POUNCE_AHEAD:
		_pouncer(dist, cam_x)
		_next_pounce += 1
	if not _bridge_crowd and dist >= CAR_D - 48.0:          # 왼쪽이 비어 보이지 않게: 다리 입구 왼쪽 강가 + 다리 위 왼쪽 줄에 몇 마리 더 (멀리 안개 속에서 나타난다, 오른쪽 틈으로는 안 온다)
		_bridge_crowd = true
		for g in BRIDGE_LEFT_CROWD:
			var e := _spawn(g[0], g[1], CAR_D + g[2] - dist, g[3], dist, cam_x)
			e["x"] = g[3] + _rng.randf_range(-0.2, 0.2)      # 다리 위 자동 줄 대신 정해 둔 자리
			e["lane_x"] = e["x"]
			if g[1] == "idle":                            # 다리 입구 왼쪽 그 좀비 (2026-10-01 "멍청하다, 유저한테 다가와라"): 줄을 지키지 않고 나를 향해 뛰어온다
				e.erase("lane_x")
				e["spd"] = 4.0
				e["wake"] = 12.0                          # 왼쪽에 서 있다가 가까워지면(12m) 옆으로 뛰어들어 내 줄을 막는다
				e["lock"] = 3.0                           # 3m 앞까지 나를 따라 방향을 튼다 (그 뒤로는 직진 — 마지막 순간 비키면 산다)
				e["cut_in"] = true                        # 내 줄로 가로질러 들어와 앞을 막는다 (가만히 달리면 정면에서 만난다 — 비키거나 쏘면 산다)
			_place(e)
		print("[bridge] %.0fm 다리 왼쪽 무리 %d마리" % [dist, BRIDGE_LEFT_CROWD.size()])
	if not _bridge_cleared and dist >= CAR_D - 26.0:       # 다리에 들어서기 전: 다리 쪽으로 오던 좀비들을 왼쪽 줄로 비킨다
		_bridge_cleared = true
		for o in _zombies:
			if o["d"] > dist and o["d"] < UNDER_D + 30.0 and o["style"] != "pounce" and o["state"] != "dead":
				if o.has("lane_x") or o.has("cut_in"):
					continue
				if o["d"] - dist > 22.0:                      # 다리 위로 오던 일반 좀비 중 멀리(안개 속) 있는 건 치운다 → 차 뒤에는 두 마리 정도만
					_despawn(o)
					continue
				o["lane_x"] = _bridge_lane()
				if o["state"] != "move" and o["d"] - dist > 14.0:   # 누워 있거나 서 있는 좀비는 안개 속(멀리)에서 자리를 옮긴다
					o["x"] = o["lane_x"]
					_place(o)
	if not _under_done and dist >= UNDER_D - UNDER_AHEAD and dist < UNDER_D:
		_under_done = true
		_bridge_climber(dist, cam_x)
	if _finale == 0 and dist >= FINALE_AT * sc750:
		_finale = 1
		_finale_t = FINALE_GAP
		_berserker(dist, cam_x, -FINALE_SIDE, FINALE_AHEAD)
		_zombies[-1]["lock"] = FINALE_LOCK
		print("[finale] %.0fm 끝 반전 — 왼쪽 광전사" % dist)
	elif _finale == 2 and (dist >= BURST_AT * sc750 or _finale_clear(dist)):
		_finale = 3
		_ground_burst(dist, cam_x)
	elif _finale == 1:
		_finale_t -= delta
		if _finale_t <= 0.0:
			_finale = 2
			_berserker(dist, cam_x, FINALE_SIDE, FINALE_AHEAD - 2.0)
			_zombies[-1]["lock"] = FINALE_LOCK
			print("[finale] %.0fm 오른쪽 광전사" % dist)
	if dist >= _next_event and dist < StageBuilderV2.STAGE_LENGTH - 60.0:
		_sprint_event(dist, cam_x)
		_next_event += _rng.randf_range(EVENT_GAP[0], EVENT_GAP[1])
	while _next_crate < SUPPLY_PLAN.size() and dist >= SUPPLY_PLAN[_next_crate][0] * StageBuilderV2.STAGE_LENGTH / 750.0 - DROP_AHEAD:
		_drop_crate(SUPPLY_PLAN[_next_crate][0] * StageBuilderV2.STAGE_LENGTH / 750.0, SUPPLY_PLAN[_next_crate][1])
		_next_crate += 1
	_update_crates(dist, cam_x, delta)
	_update_zombies(dist, cam_x, delta)
	_shot_cd -= delta
	_grace_t -= delta
	_update_reload(delta)
	if _mag == 0 and _reserve > 0:
		reload()                                         # 탄창이 비고 예비탄이 있으면 저절로 재장전 (2026-09-30 피드백 — 게이지 없이 총을 내렸다 올리는 동작만)


# 좀비 한 마리: kind 모델, style 행동 (비우면 무작위), ahead 앞 거리, x 가로 위치 (NAN 이면 내 근처 무작위)
func _spawn(kind: String, style: String, ahead: float, x: float, dist: float, cam_x: float) -> Dictionary:
	if style.is_empty():
		style = _pick_style(kind)
	var z := _take(kind)
	var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
	for n in ["walk", "run", "idle"]:                    # 가져온 동작은 한 번만 재생하고 멈춘다 → 반복으로 (굳은 채 미끄러져 오던 버그)
		if ap.has_animation(n):
			ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if is_nan(x):
		x = _rng.randf_range(-6.5, 6.5)                  # 달리는 폭 ±8m 안 어디서나 (2026-10-01 "가운데 몰려 보인다" — 예전엔 내 자리 ±4m)
		if style == "sprint":
			x = (-1.0 if _rng.randf() < 0.5 else 1.0) * _rng.randf_range(11.0, 14.0)   # 옆에서 대각선으로 (F-41)
	var e := {"node": z, "ap": ap, "kind": kind, "style": style, "hp": HP[kind], "state": "move", "x": x, "d": dist + ahead, "t": 0.0,
		"spd": _rng.randf_range(STYLE_SPEED[style][0], STYLE_SPEED[style][1]), "low": style.begins_with("crawl")}
	e["walk"] = "walk" if _rng.randf() < 0.5 else "pack/p_walk"       # 같은 스타일이라도 걸음걸이·뛰는 폼을 섞는다
	e["run"] = "run" if ap.has_animation("run") and _rng.randf() < 0.5 else "pack/p_run"
	match style:
		"rise":
			ap.play("getup" if ap.has_animation("getup") else "pack/getup")   # 땅에 누운 자세로 멈춰 둔다
			ap.seek(0.0, true)
			ap.pause()
			e["state"] = "lie"
		"feed":
			var fa: String = FEED_ANIMS[_rng.randi() % FEED_ANIMS.size()]
			ap.get_animation(fa).loop_mode = Animation.LOOP_LINEAR
			ap.play(fa)
			ap.seek(_rng.randf() * 2.0, true)
			e["state"] = "feed"
			e["wake"] = _rng.randf_range(14.0, 18.0)
			x = clampf(x + (1.0 if x >= 0.0 else -1.0) * 2.5, -7.5, 7.5)   # 길 가장자리 쪽에서 뜯어먹는다
			e["x"] = x
		"idle":
			ap.play("pack/p_idle")
			ap.speed_scale = _rng.randf_range(0.8, 1.2)
			ap.seek(_rng.randf() * 3.0, true)
			e["state"] = "idle"
			e["wake"] = _rng.randf_range(IDLE_WAKE[0], IDLE_WAKE[1])
		_:
			_move_anim(e)
			ap.seek(_rng.randf() * 0.8, true)             # 무리가 똑같이 걷지 않게 시작 시점을 흩뜨린다
	if style != "pounce" and e["d"] > CAR_D - 12.0 and e["d"] < UNDER_D + 12.0 and dist < UNDER_D:
		e["lane_x"] = _bridge_lane()                      # 다리 위는 왼쪽 절반에서 저마다 다른 줄로 (오른쪽 난간 밑 매복이 가려지지 않게)
		e["x"] = e["lane_x"]
	_zombies.append(e)
	_place(e)
	return e


# 풀에서 한 마리 꺼낸다 (없으면 새로 만든다)
func _take(kind: String) -> Node3D:
	var list: Array = _pool.get(kind, [])
	var z: Node3D = list.pop_back() if not list.is_empty() else _make_zombie(kind)
	if z.get_parent() != self:
		z.reparent(self, false)
	z.visible = true
	z.rotation = Vector3.ZERO
	return z


func _make_zombie(kind: String) -> Node3D:
	var z: Node3D = load("res://assets/models/zombie_%s.glb" % kind).instantiate()
	add_child(z)
	_dress_zombie(z)
	var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
	ap.add_animation_library("pack", _lib_for(kind, z.find_children("*", "Skeleton3D", true, false)[0]))
	return z


# 다 쓴 좀비는 지우지 않고 숨겨서 풀에 돌려놓는다
func _despawn(e: Dictionary) -> void:
	e["gone"] = true
	var z: Node3D = e["node"]
	z.visible = false
	z.position = Vector3(0, -50, 0)
	var ap: AnimationPlayer = e["ap"]
	ap.stop()
	ap.speed_scale = 1.0
	if not _pool.has(e["kind"]):
		_pool[e["kind"]] = []
	_pool[e["kind"]].append(z)


func _pick_style(kind: String) -> String:
	var total := 0
	for st in STYLES[kind]:
		total += st[1]
	var r := _rng.randi() % total
	for st in STYLES[kind]:
		r -= st[1]
		if r < 0:
			return st[0]
	return STYLES[kind][0][0]


# 미리 불러오기 (2026-09-30 "프레임 끊긴다"): 좀비 4종 모델·동작 라이브러리·이펙트 그림을 스테이지를 만들 때 준비해 둔다
# → 처음 나오는 순간 불러오느라 멈칫하던 것(첫 좀비 32ms, 처음 보는 것 50ms)을 없앤다
# 좀비 풀 (2026-09-30 "프레임 끊긴다"): 나올 때마다 모델을 새로 만들고 지나가면 지우면, 만드는 순간 멈칫한다 (폰은 더 크게)
# → 종류별로 미리 만들어 두고 숨겼다 꺼내 쓴다. 모자라면 그때만 새로 만든다
const POOL_PER_KIND := 10
var _pool := {}                               # 종류 → 숨겨 둔 좀비 노드들
var _warm: Node3D                             # 미리 그려 두는 것들 (시작 직후 몇 프레임만 땅 밑에 있다가 지워진다)


func _prewarm() -> void:
	# 파일만 읽어 두면 처음 화면에 나올 때 그래픽 셰이더를 만드느라 멈칫한다 → 카메라 앞 땅 밑(보이지 않는 곳)에서 한 번 실제로 그린다
	_warm = Node3D.new()
	add_child(_warm)
	_warm.position = Vector3(0, -2.2, -14.0)
	var i := 0
	for kind in KINDS:
		_pool[kind] = []
		for k in POOL_PER_KIND:
			var z := _make_zombie(kind)
			z.reparent(_warm, false)
			z.position = Vector3(-4.0 + i * 0.6, 0, -k * 0.3)
			var ap: AnimationPlayer = z.find_children("*", "AnimationPlayer", true, false)[0]
			ap.play("pack/p_run")
			_pool[kind].append(z)
		i += 3
	CardFX.flare(_warm, true)
	CardFX.flare(_warm, false)
	CardFX.blood_splash(_warm, _warm.global_position)
	CardFX.blood_pool(_warm, _warm.global_position)
	BulletHitFX.spawn(_warm, _warm.global_position, Vector3.FORWARD)
	var crate: Node3D = load("res://assets/models/prop_supply_crate.glb").instantiate()
	_warm.add_child(crate)
	CardFX.muzzle(_warm)
	for n in ["sfx_glock_shot", "sfx_glock_reload", "sfx_zombie_scream", "sfx_zombie_groan", "sfx_bite", "sfx_knife", "sfx_supply_pickup", "sfx_empty_click", "sfx_ui_click", "sfx_hit_obstacle"]:
		load(_sfx_path(n))


# 앞질러 달려들 자리: 나(초속 RUN_SPEED 로 앞으로)와 속도 spd 인 좀비가 만나는 곳
# (spd² - u²)T² - 2u·dD·T - (dx² + dD²) = 0 을 T 에 대해 푼다 (dD = 내 거리 - 좀비 거리, 음수)
func _intercept(z: Vector2, me: Vector2, spd: float) -> Vector2:
	var u := PLAYER_SPEED
	var dx := me.x - z.x
	var dd := me.y - z.y
	var a := spd * spd - u * u
	if a <= 0.01:
		return me
	var disc := 4.0 * u * u * dd * dd + 4.0 * a * (dx * dx + dd * dd)
	var tt := (2.0 * u * dd + sqrt(disc)) / (2.0 * a)
	return Vector2(me.x, me.y + u * maxf(tt, 0.0))


# 끝의 광전사 둘이 모두 지나갔거나 쓰러졌나
func _finale_clear(dist: float) -> bool:
	var n := 0
	for e in _zombies:
		if e["style"] == "berserk" and e.get("lock", 0.0) == FINALE_LOCK and not e.get("passed", false) and e["state"] != "dead":
			n += 1
	return n == 0 and dist >= FINALE_AT * StageBuilderV2.STAGE_LENGTH / 750.0 + 8.0


# 바닥에서 튀어나오는 마지막 좀비: 땅속(y -1.4)에서 솟아오르며 비명 → 곧장 덮친다
func _ground_burst(dist: float, cam_x: float) -> void:
	var e := _spawn("ambusher", "pounce", BURST_AHEAD, cam_x, dist, cam_x)
	e["spd"] = BURST_SPEED
	e["lock"] = 0.0                                       # 끝까지 나를 따라온다 (비켜도 소용없다)
	e["unavoidable"] = true
	e["y"] = -1.4
	e["burst"] = true
	var ap: AnimationPlayer = e["ap"]
	if ap.has_animation("crouch_rise"):
		ap.play("crouch_rise")
		ap.speed_scale = 3.0
	e["rise_t"] = 0.4
	_sfx("sfx_zombie_scream")
	_sfx("sfx_hit_obstacle")
	burst.emit()
	if danger_sense:
		danger.emit(0)
	print("[burst] %.0fm 바닥에서 튀어나옴" % dist)


# 광전사: 42m 앞 길 안쪽에서 비명 → 초속 10m 돌진 (8m 앞부터 방향 고정)
func _berserker(dist: float, cam_x: float, x := NAN, ahead := BERSERK_AHEAD) -> void:
	if is_nan(x):
		x = clampf(cam_x + _rng.randf_range(-4.0, 4.0), -6.5, 6.5)
	var e := _spawn("runner", "berserk", ahead, x, dist, cam_x)
	if danger_sense:
		danger.emit(int(signf(x - cam_x)) if absf(x - cam_x) > 2.0 else 0)
	e["lock"] = BERSERK_LOCK
	e["state"] = "scream"
	e["after"] = "berserk"
	e["t"] = 0.25                                         # 비명은 짧게 (0.65초)
	var ap: AnimationPlayer = e["ap"]
	ap.play("pack/p_scream")
	ap.speed_scale = 1.3
	_sfx("sfx_zombie_scream")
	print("[berserk] %.0fm 광전사 (초속 %.0fm)" % [dist, BERSERK_SPEED])


# 길목 매복: 내가 달리는 줄 바로 앞 8.5m 풀숲에서 벌떡 일어나 덮친다
func _pouncer(dist: float, cam_x: float) -> void:
	var e := _spawn("ambusher", "pounce", POUNCE_AHEAD, clampf(cam_x + _rng.randf_range(-0.3, 0.3), -7.0, 7.0), dist, cam_x)
	e["lock"] = POUNCE_LOCK
	var ap: AnimationPlayer = e["ap"]
	if ap.has_animation("crouch_rise"):
		ap.play("crouch_rise")                            # 쭈그린 채 → 벌떡 (팀원 동작, 원래 1.2초 → 약 0.45초)
		ap.speed_scale = 2.6
	e["rise_t"] = 0.45
	_sfx("sfx_zombie_scream")
	print("[pounce] %.0fm 길목 매복 x=%.1f" % [dist, e["x"]])


func _bridge_lane() -> float:
	return _rng.randf_range(BRIDGE_LANES[0], BRIDGE_LANES[1])


# 다리 밑 매복: 오른쪽 난간 밖 강 위에 매달려 있다가(머리·팔만 보인다) 기어올라 덮친다
func _bridge_climber(dist: float, cam_x: float) -> void:
	var e := _spawn("ambusher", "pounce", UNDER_D - dist, StageBuilderV2.BRIDGE_HALF + 0.3, dist, cam_x)
	e["spd"] = UNDER_SPEED
	e["lock"] = POUNCE_LOCK
	e["y"] = -0.7
	e["climb_t"] = UNDER_HANG
	var ap: AnimationPlayer = e["ap"]
	if ap.has_animation("grab"):                         # 팔을 뻗은 채 난간을 붙잡고 버둥거린다
		ap.play("grab")
		ap.speed_scale = 0.7
	_place(e)
	_sfx("sfx_zombie_groan")
	_sfx("sfx_hit_obstacle", 0.5)                         # 쿵 — 난간을 붙잡자 다리가 울린다
	quake.emit(0.6, 0.9)
	if danger_sense:
		danger.emit(1)
	print("[under] %.0fm 다리 밑에서 손이 올라옴" % dist)


# 사이드 질주: 양옆 멀리(8-11m)에서 2-3마리가 비명을 지르고 대각선으로 달려든다
func _sprint_event(dist: float, cam_x: float) -> void:
	var n := _rng.randi_range(2, 3)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	for i in n:
		var sx := side if i < 2 else -side                  # 셋째는 반대쪽에서
		var e := _spawn("runner" if _rng.randf() < 0.6 else "walker", "event", EVENT_AHEAD + i * 2.5 + _rng.randf_range(-1.0, 1.0),
			sx * _rng.randf_range(10.0, 13.0), dist, cam_x)
		var ap: AnimationPlayer = e["ap"]
		ap.play("pack/p_scream")
		ap.speed_scale = 1.0
		e["state"] = "scream"
		e["t"] = -i * 0.25                                   # 한 마리씩 차례로 비명
	_sfx("sfx_zombie_scream")
	if danger_sense:
		danger.emit(int(side))
	print("[event] %.0fm 옆에서 %d마리 질주" % [dist, n])


# 동작 라이브러리: 팩 동작(뼈 이름 mixamorig10_ → mixamorig_)을 이 좀비 키에 맞춰 제자리 동작으로 바꾼다
# + 매복 모델에만 있던 getup 을 다른 좀비도 쓰게 넣는다. 종류마다 한 번만 만든다
func _lib_for(kind: String, sk: Skeleton3D) -> AnimationLibrary:
	if _libs.has(kind):
		return _libs[kind]
	if _pack_animations.is_empty():
		var holder: Node3D = load(ANIM_PACK).instantiate()
		var pack_player: AnimationPlayer = holder.find_children("*", "AnimationPlayer", true, false)[0]
		for animation_name in pack_player.get_animation_list():
			_pack_animations[animation_name] = pack_player.get_animation(animation_name)
		holder.free() # Cache Resources, not an orphaned scene tree, across retries.
	var hips := absf(sk.get_bone_rest(0).origin.z)
	var lib := AnimationLibrary.new()
	for n in _pack_animations:
		lib.add_animation(n, _retarget(_pack_animations[n], hips / PACK_HIPS, "mixamorig10_", n in PACK_LOOPS))
	if kind != "ambusher":
		var amb: Node3D = load("res://assets/models/zombie_ambusher.glb").instantiate()
		var amb_ap: AnimationPlayer = amb.find_children("*", "AnimationPlayer", true, false)[0]
		var amb_sk: Skeleton3D = amb.find_children("*", "Skeleton3D", true, false)[0]
		lib.add_animation("getup", _retarget(amb_ap.get_animation("getup"), hips / absf(amb_sk.get_bone_rest(0).origin.z), "mixamorig_", false))
		amb.free()
	_libs[kind] = lib
	return lib


# 동작 한 개 옮기기: 엉덩이만 위치를 남기고(키 비율로), 앞뒤·좌우로 가는 움직임은 지운다 (게임이 직접 옮긴다)
# 다른 뼈의 위치·크기 트랙은 버린다 — 뼈 길이가 팩 캐릭터 것으로 바뀌어 몸이 일그러지지 않게
func _retarget(src: Animation, ratio: float, prefix: String, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = src.length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for t in src.get_track_count():
		var typ := src.track_get_type(t)
		var path := str(src.track_get_path(t)).replace(prefix, "mixamorig_")
		var hip := path.ends_with(":mixamorig_Hips")
		if typ == Animation.TYPE_SCALE_3D or (typ == Animation.TYPE_POSITION_3D and not hip):
			continue
		var nt := a.add_track(typ)
		a.track_set_path(nt, NodePath(path))
		a.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		var first: Vector3 = src.track_get_key_value(t, 0) if typ == Animation.TYPE_POSITION_3D else Vector3.ZERO
		for k in src.track_get_key_count(t):
			var v = src.track_get_key_value(t, k)
			if typ == Animation.TYPE_POSITION_3D:
				v = Vector3(first.x * ratio, first.y * ratio, v.z * ratio)   # 뼈대 좌표: z 가 높이, x·y 는 바닥 방향
			a.track_insert_key(nt, src.track_get_key_time(t, k), v)
	return a


# 좀비 조명·재질 (2026-09-30 2차 "테두리 말고 스펙을 살려 풀에 묻히지 않게"): 가장자리 테두리 효과는 뺐다.
# ① 좀비만 비추는 조명(ZOMBIE_LIGHT_LAYER) — 카메라에서 앞으로 은은하게, 풀·나무는 비추지 않는다
# ② 재질을 조금 번들거리게 (거칠기 낮춤·반사 올림) → 빛을 받으면 피부·옷에 반짝임이 살아 풀 사이에서 몸이 읽힌다
const ZOMBIE_LIGHT_LAYER := 2                 # 렌더 레이어 2번 (좀비 전용 조명의 cull_mask)
# 3차 (같은 날 "스펙을 너무 올렸다 — 약간만, 채도 조금, 톤은 분위기에"): 광택은 원래 값에서 조금만, 색은 살짝 진하게, 조명은 노을빛
const ZOMBIE_ROUGH_MIX := 0.3                 # 거칠기를 원래 값에서 0.55 쪽으로 이만큼만 당긴다
const ZOMBIE_SPEC := 0.6
const ZOMBIE_TINT := Color(1.1, 1.0, 0.94)    # 채도·붉은 기를 살짝 (피부·피가 조금 더 진하게)
var _dressed := {}                            # 이미 손본 재질 (같은 모델끼리 재질을 같이 쓴다)


func _dress_zombie(z: Node3D) -> void:
	for mi in z.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.layers = 1 | ZOMBIE_LIGHT_LAYER
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat and not _dressed.has(mat):
				_dressed[mat] = true
				mat.roughness = lerpf(mat.roughness, minf(mat.roughness, 0.55), ZOMBIE_ROUGH_MIX)
				mat.metallic_specular = ZOMBIE_SPEC
				mat.albedo_color = mat.albedo_color * ZOMBIE_TINT


func _build_zombie_light(camera: Camera3D) -> void:
	var l := SpotLight3D.new()
	l.light_cull_mask = ZOMBIE_LIGHT_LAYER               # 좀비만
	l.light_color = Color(1.0, 0.84, 0.8)                # 노을빛 (배경 하늘 톤에 맞춤)
	l.light_energy = 1.4
	l.light_specular = 0.8                               # 반짝임은 약하게
	l.spot_range = 34.0
	l.spot_angle = 42.0
	l.spot_attenuation = 0.6
	l.shadow_enabled = false
	l.position = Vector3(0.0, 0.6, 0.4)                  # 머리 위 살짝 뒤에서 내려 비춘다
	l.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	camera.add_child(l)


# 첫 좀비는 눈에 잘 띄는 워커, 처음 INTRO_SAFE 마리에는 매복이 없게 순서만 바꾼다 (종류별 25마리는 그대로)
func _intro_order(bag: Array) -> void:
	var w := bag.find("walker")
	if w > 0:
		bag[w] = bag[0]
		bag[0] = "walker"
	for i in INTRO_SAFE:
		if bag[i] == "ambusher":
			for j in range(INTRO_SAFE, bag.size()):
				if bag[j] != "ambusher":
					bag[i] = bag[j]
					bag[j] = "ambusher"
					break


# 스타일·속도에 맞는 동작 — 재생 속도도 발이 미끄러져 보이지 않게 맞춘다
func _move_anim(e: Dictionary, spd := -1.0) -> void:
	var ap: AnimationPlayer = e["ap"]
	if spd < 0.0:
		spd = e["spd"]
	match e["style"]:
		"crawl":
			ap.play("pack/p_crawl", BLEND)
			ap.speed_scale = clampf(spd / 1.1, 0.7, 1.6)
		"crawl_run":
			ap.play("pack/p_crawl_run", BLEND)
			ap.speed_scale = clampf(spd / 2.6, 0.7, 1.4)
		_:
			if spd >= 2.5 and (e["kind"] != "tank"):
				ap.play(e["run"], BLEND)
				ap.speed_scale = clampf(spd / 4.8, 0.6, 2.1 if e["style"] in ["berserk", "pounce"] else 1.35)
			else:
				ap.play(e["walk"], BLEND)
				ap.speed_scale = clampf(spd / 1.2, 0.8, 2.2)


func _place(e: Dictionary) -> void:
	var z: Node3D = e["node"]
	z.position = Vector3(e["x"], e.get("y", 0.0), -e["d"])   # y: 바닥에서 튀어나오는 좀비만 땅속에서 올라온다
	var to_cam := _camera.global_position - z.global_position
	z.rotation.y = atan2(-to_cam.x, -to_cam.z)            # 정면(-Z)이 카메라를 본다 → 손 뻗고 다가온다


func _update_zombies(dist: float, cam_x: float, delta: float) -> void:
	_zombies = _zombies.filter(func(q): return not q.get("gone", false))   # 풀로 돌아간 좀비는 목록에서 뺀다 (뒤로 갈수록 느려지지 않게)
	for e in _zombies:
		if not is_instance_valid(e["node"]):
			continue
		var z: Node3D = e["node"]
		var ahead: float = e["d"] - dist
		var ap: AnimationPlayer = e["ap"]
		e["t"] += delta
		match e["state"]:
			"lie":                                         # 누워 있다가 멀리서(28m) 일어난다 → 달려온다
				_place(e)
				if ahead < RISE_AT:
					e["state"] = "getup"
					e["t"] = 0.0
					ap.play(ap.assigned_animation)
					ap.speed_scale = 1.9
					ap.seek(ap.current_animation_length * 0.3, true)   # 가장 느린 앞부분은 건너뛴다
					_sfx("sfx_zombie_groan")
				elif ahead < -2.0:
					_despawn(e)
			"getup":
				_place(e)
				if ap.current_animation_position > ap.current_animation_length * 0.93 or not ap.is_playing():
					e["state"] = "move"
					e["style"] = "sprint"
					_move_anim(e)
					_sfx("sfx_zombie_scream")
			"idle":                                        # 서서 두리번거리다가 가까워지면 출발
				_place(e)
				if ahead < e["wake"]:
					e["state"] = "move"
					e["style"] = "shamble" if e["spd"] < 2.6 else "jog"
					_move_anim(e)
					if _rng.randf() < 0.4:
						_sfx("sfx_zombie_groan")
			"feed":                                        # 뜯어먹다가 가까워지면 고개를 들고 비명 → 달려온다
				_place(e)
				if ahead < e["wake"]:
					e["state"] = "scream"
					e["t"] = 0.0
					e["after"] = "jog"
					ap.play("pack/p_scream", BLEND)
					ap.speed_scale = 1.0
					_sfx("sfx_zombie_scream")
				elif ahead < -2.0:
					_despawn(e)
			"scream":                                      # 사이드 질주 전·뜯어먹다 일어날 때: 멈춰서 비명
				_place(e)
				if e["t"] > SCREAM_TIME:
					e["state"] = "move"
					e["style"] = e.get("after", "sprint")
					_move_anim(e)
			"roar":                                        # 탱커 돌진 전 포효
				_place(e)
				if e["t"] > 0.8:
					e["state"] = "move"
					_move_anim(e, e["spd"] * TANK_CHARGE)
			"stagger":                                     # 한 발 맞고 휘청 (탱커)
				if e["t"] > 0.45:
					e["state"] = "move"
					_move_anim(e, e["spd"] * (TANK_CHARGE if e.get("charging", false) else 1.0))
			"move":
				var spd: float = e["spd"]
				if e["style"] == "stomp" and ahead < 16.0 and not e.get("charging", false):   # 탱커 돌진 (PRD F-42): 포효하고 달려든다
					e["charging"] = true
					e["state"] = "roar"
					e["t"] = 0.0
					ap.play("pack/p_scream", BLEND)
					ap.speed_scale = 1.4
					_sfx("sfx_zombie_groan")
					continue
				if e.get("charging", false):
					spd *= TANK_CHARGE
				if e.get("passed", false):                 # 지나친 좀비: 더는 쫓지 않고 가던 방향으로 계속 간다 (뒤돌지 않는다)
					var dir: Vector2 = e.get("dir", Vector2(0, -1))
					e["x"] += dir.x * spd * delta
					e["d"] += dir.y * spd * delta
					z.position = Vector3(e["x"], 0, -e["d"])
					if ahead < -10.0:
						_despawn(e)
					continue
				if e.has("climb_t"):                         # 다리 밑 매복: 매달린 채 기어오른다 (앞으로는 안 온다 — 이 동안 쏘면 산다)
					e["climb_t"] -= delta
					var k := 1.0 - clampf(e["climb_t"] / UNDER_HANG, 0.0, 1.0)
					e["y"] = lerpf(-0.7, 0.0, k * k)
					e["x"] = lerpf(StageBuilderV2.BRIDGE_HALF + 0.3, StageBuilderV2.BRIDGE_HALF - 1.0, smoothstep(0.5, 1.0, k))
					_place(e)
					if e["climb_t"] <= 0.0:
						e.erase("climb_t")
						e["y"] = 0.0
						if ap.has_animation("crouch_rise"):
							ap.play("crouch_rise")
							ap.speed_scale = 2.8
						e["rise_t"] = 0.3
						_sfx("sfx_zombie_scream")
						_sfx("sfx_hit_obstacle", 0.6)             # 상판에 올라서며 쾅
						quake.emit(1.0, 0.45)
					continue
				if e.has("burst") and e["y"] < 0.0:           # 땅속에서 솟아오른다 (0.3초)
					e["y"] = minf(0.0, e["y"] + delta * 1.4 / 0.3)
				if e.has("rise_t"):                          # 길목 매복: 벌떡 일어나는 동작이 끝나면 달리기로
					e["rise_t"] -= delta
					if e["rise_t"] <= 0.0:
						e.erase("rise_t")
						_move_anim(e)
				if ahead > e.get("lock", HOMING_LOCK) or not e.has("dir"):  # 멀리서는 나를 향해 방향을 튼다. 가까워지면 그 방향 그대로 (비키면 피한다)
					var target := Vector2(cam_x, dist)
					if e.has("lane_x"):                        # 다리 앞뒤: 자기 줄을 지키며 다가온다 — 오른쪽 틈을 비우고 가운데로 몰리지 않게 (매복을 지나면 풀린다)
						if dist < UNDER_D + 2.0:
							target.x = e["lane_x"]
						else:
							e.erase("lane_x")
					var here := Vector2(e["x"], e["d"])
					if e.has("cut_in"):                        # 다리 입구 그 좀비: 내 줄로 옆걸음질쳐 들어와 앞을 막는다 (앞으로는 조금만)
						target = Vector2(cam_x - CUT_MISS, e["d"] - 1.2)   # 내 줄 바로 옆을 노린다 → 가만히 달려도 어깨를 스치며 비껴간다 (길을 다 막지 않게)
					elif e["style"] == "berserk":                # 광전사: 지금 자리가 아니라 내가 곧 도착할 자리로 가로질러 달려든다 (가만히 있으면 맞는다)
						target = _intercept(here, target, spd)
					e["dir"] = (target - here).normalized()
				var step: Vector2 = e["dir"] * spd * delta
				e["x"] += step.x
				e["d"] += step.y
				if e.has("lane_x") and e["d"] < CAR_D + CAR_BLOCK and e["d"] > CAR_D - 2.0 and e["x"] < 1.0:
					e["d"] = CAR_D + CAR_BLOCK                 # 다리 위 차에 막힌다 (차를 뚫고 지나가지 않게): 차 뒤에서 팔을 뻗고 버둥거린다
					if not e.has("blocked"):
						e["blocked"] = true
						if ap.has_animation("grab"):
							ap.play("grab", 0.2)
							ap.seek(_rng.randf() * 1.0, true)
							ap.speed_scale = _rng.randf_range(0.7, 1.15)   # 저마다 다른 박자로 버둥
				_place(e)
				ahead = e["d"] - dist
				var big: bool = e["kind"] == "tank"
				var reach: float = TANK_REACH if big else REACH
				var zw: float = TANK_W if big else ZOMBIE_W
				var dx0 := absf(e["x"] - cam_x)
				# 반반 예고: 부딪히기 LUNGE_WARN 초 전쯤, 내 앞을 막고 있으면 절반은 비명·팔 뻗기로 알린다 (그때 비키면 산다)
				if not e.has("lunge") and ahead < reach + (PLAYER_SPEED + spd) * LUNGE_WARN and ahead > reach and dx0 < zw * 0.5 + PLAYER_W * 0.5:
					e["lunge"] = _rng.randf() < 0.5
					if e["lunge"] and not e.get("low", false):
						ap.play("grab", 0.1)
						ap.speed_scale = 1.6
						_sfx("sfx_zombie_groan")
				if ahead < reach and ahead > 0.05:          # 내 앞에서 닿음 → 몸을 절반 이상 가리면 잡힌다
					var dx := dx0
					var cover := clampf((zw * 0.5 + PLAYER_W * 0.5 - dx) / PLAYER_W, 0.0, 1.0)
					if e.get("unavoidable", false):
						cover = 1.0                            # 바닥에서 튀어나온 마지막 좀비: 쏘지 못하면 잡힌다
					if catching and cover < COVER_TO_GRAB and dx < zw * 0.5 + PLAYER_W * 0.5 + BRUSH_EXTRA and not e.get("brushed", false):
						e["brushed"] = true                    # 스쳐 지나감 → 어깨빵
						brushed.emit(signf(e["x"] - cam_x))
						_sfx("sfx_hit_obstacle")
					if catching and cover >= COVER_TO_GRAB and _grace_t <= 0.0:
						if service_invulnerable:
							e["passed"] = true
							continue
						if e.get("low", false):                # 기는 좀비: 풀에 묻혀 잘 안 보인다 → 발목만 잡고 휘청하게 (사망 없음)
							service_grabs += 1
							e["passed"] = true
							_grace_t = 0.8
							_sfx("sfx_bite")
							tripped.emit()
							continue
						if _adren_t > 0.0 and not e.get("unavoidable", false) and _rng.randf() < ADREN_DODGE:
							e["passed"] = true                 # 아드레날린 회피: 붙잡히기 직전 몸을 틀어 스쳐 지나간다 (어깨빵)
							_grace_t = 0.6
							brushed.emit(signf(e["x"] - cam_x))
							_sfx("sfx_hit_obstacle")
							print("[items] 아드레날린 회피")
							continue
						_grab(e, dist, cam_x)
						continue
					if cover <= 0.0:
						e["passed"] = true                 # 비켜서 스쳐 지나감
				elif ahead <= 0.05:
					e["passed"] = true                     # 옆·뒤로 넘어갔다 → 끝 (뒤에서는 잡지 않는다)
				if auto_fire and ahead < SHOOT_RANGE and ahead > 1.5 and (_mag > 0 or INFINITE_AMMO) and _reload_left <= 0.0 and _shot_cd <= 0.0:
					_shoot(e)
			"dead":
				if e.has("pool_t"):
					e["pool_t"] -= delta
					if e["pool_t"] <= 0.0:
						e.erase("pool_t")
						CardFX.blood_pool(self, Vector3(z.global_position.x, 0.0, z.global_position.z), _rng.randf_range(1.3, 1.9))
				if ahead < -4.0:
					_despawn(e)
			"grab":                                        # 사망 연출: 붙잡았다가 → 문다
				_place(e)
				if e["t"] > GRAB_TIME and not e.get("biting", false):
					e["biting"] = true
					var b: String = e["bite"]
					if ap.has_animation(b):
						ap.get_animation(b).loop_mode = Animation.LOOP_LINEAR
						ap.play(b, 0.2)
						ap.speed_scale = BITE_SPEED
					_sfx("sfx_bite")
					var mouth: Vector3 = z.global_position + Vector3(0, 1.45, 0)
					CardFX.blood_splash(self, _camera.global_position.lerp(mouth, 0.55) + Vector3(0.18, -0.25, 0), 0.7)
			"melee":                                       # 칼 근접전: 코앞에서 붙잡으려 한다 (칼에 찔리면 melee_hit)
				_place(e)


# 잡혔다: 칼이 남았으면 칼로 죽이고 벗어난다, 없으면 사망 (stage_preview 가 카메라 연출)
func _grab(e: Dictionary, dist: float, cam_x: float) -> void:
	if service_invulnerable:
		e["passed"] = true
		return
	service_grabs += 1
	var z: Node3D = e["node"]
	var ap: AnimationPlayer = e["ap"]
	ap.speed_scale = 1.0
	if _knife_left > 0:
		service_knife_used = true
		_knife_left -= 1
		_refresh_knife()
		# 칼 근접전 (2026-09-30 "멈춰서 좀비와 합을 맞춰야"): 좀비가 코앞에서 붙잡으려는 사이 칼이 천천히 올라와 목을 찌른다
		e["state"] = "melee"
		e["d"] = dist + (1.35 if e["kind"] == "tank" else 1.0)
		e["x"] = cam_x
		e["low"] = false
		_place(e)
		ap.play("grab", 0.15)
		_melee_e = e
		_grace_t = 99.0                                     # 근접전 중에는 다른 좀비가 잡지 않는다
		_sfx("sfx_zombie_scream")
		print("[knife] %.0fm 칼 근접전 (%s)" % [dist, e["kind"]])
		melee_start.emit(z)
		return
	e["state"] = "grab"
	e["t"] = 0.0
	_grab_e = e
	e["d"] = dist + (1.1 if e["kind"] == "tank" else 0.8)   # 코앞에 붙는다 (2026-09-30 "더 붙어서 얼굴이 혐오스럽게") — 카메라도 얼굴 쪽으로 끌려간다 (stage_preview)
	_pistol.visible = false                                # 쓰러질 때 총이 허공에 떠 보이지 않게
	_hud_layer.visible = false                             # 사망 연출에는 HUD 를 치운다 (블랙아웃 + DEAD 만)
	e["x"] = cam_x
	_place(e)
	# 물어뜯기 (2026-09-30 "잘 안 보인다"): ① 붙잡기(0.9초) → ② 물어뜯기 (_update_zombies 의 grab). 피는 무는 순간에
	ap.play("grab", 0.15)
	e["bite"] = BITE_ANIMS[_rng.randi() % BITE_ANIMS.size()]
	e["low"] = false
	_sfx("sfx_zombie_scream")
	print("[caught] %.0fm %s 에게 잡힘 (칼 없음)" % [dist, e["kind"]])
	caught.emit(z)


# 좀비 머리의 실제 위치 (동작에 따라 숙이거나 기울어도 따라간다) — 사망·근접전 카메라가 얼굴을 놓치지 않게
func head_pos(z: Node3D) -> Vector3:
	var sk: Skeleton3D = z.get_meta("sk") if z.has_meta("sk") else null
	if sk == null:
		sk = z.find_children("*", "Skeleton3D", true, false)[0]
		z.set_meta("sk", sk)
		z.set_meta("head", sk.find_bone("mixamorig_Head"))
	var i: int = z.get_meta("head")
	if i < 0:
		return z.global_position + Vector3(0, 1.4, 0)
	return sk.global_transform * sk.get_bone_global_pose(i).origin


# 칼이 목에 박힌 순간 (stage_preview 의 칼 동작 hit): 피 + 죽는 동작
func melee_hit() -> void:
	if _melee_e.is_empty():
		return
	var z: Node3D = _melee_e["node"]
	var neck := head_pos(z) + Vector3(0, -0.15, 0)
	_sfx("sfx_knife")
	BulletHitFX.spawn(self, neck, neck - _camera.global_position, 1.4)
	_kill(_melee_e, neck, 1.1)
	_melee_e["passed"] = true


# 칼을 거두고 다시 달린다
func melee_end() -> void:
	_melee_e = {}
	_grace_t = KNIFE_GRACE


# 플레이 테스트 사격 (스페이스바·FIRE 버튼): 화면 가운데 조준선 앞의 가장 가까운 좀비를 쏜다. 없으면 허공에 쏜다
func fire() -> void:
	if _shot_cd > 0.0 or _reload_left > 0.0 or not _melee_e.is_empty():
		return
	if _mag <= 0 and not INFINITE_AMMO and _frenzy_t <= 0.0:
		_shot_cd = 0.3
		if _reserve > 0:
			reload()                                     # 빈 탄창으로 쏘면 저절로 재장전
		else:
			_sfx("sfx_empty_click")                      # 빈 총 소리 (예비탄도 없음)
		return
	var cam := _camera.global_position
	var best: Dictionary = {}
	var best_d := INF
	for e in _zombies:
		if e.get("gone", false) or e["state"] == "dead":
			continue
		var rel: Vector3 = (e["node"] as Node3D).global_position - cam
		var ahead := -rel.z
		if ahead < 1.0 or ahead > FIRE_RANGE:
			continue
		if absf(rel.x) < AIM_WIDTH + ahead * 0.06 and ahead < best_d:
			best_d = ahead
			best = e
	_shoot(best)


func _sfx_path(name: String) -> String:
	return "res://assets/audio/%s.%s" % [name, "wav" if name in WAV_SFX else "ogg"]


func _sfx(name: String, pitch := 1.0) -> void:
	events.append([_time, name])
	if not live_audio:
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(_sfx_path(name))
	p.volume_db = SFX_DB + SFX_TRIM.get(name, 0.0)
	p.pitch_scale = pitch
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# 배경음 (플레이 테스트)
func start_bgm() -> void:
	var p := AudioStreamPlayer.new()
	var st: AudioStream = load("res://assets/audio/bgm_field.ogg")
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p.stream = st
	p.volume_db = BGM_DB
	if AudioServer.get_bus_index("BGM") >= 0:
		p.bus = "BGM"
	add_child(p)
	p.play()


func _shoot(e: Dictionary) -> void:
	_shot_cd = SHOT_GAP
	if not INFINITE_AMMO and _frenzy_t <= 0.0:
		_mag -= 1
	_refresh_ammo()
	_sfx("sfx_glock_shot")                               # 글록 19 총성 (2026-10-01 "총소리가 맘에 안 든다")
	CardFX.muzzle(_vm.muzzle)                            # 총구 불꽃 카드 (scenes/fx/card_fx.gd) — 손 달린 권총의 총구 (make_pistol.py)
	_vm.fire()                                           # 반동 + 슬라이드가 뒤로
	if e.is_empty():
		return                                            # 빗나감 (조준선 앞에 좀비 없음)
	var z: Node3D = e["node"]
	# 착탄 섬광·불똥 + 핏방울·피 안개 (엔진에서 만든 이펙트, scenes/fx/bullet_hit.gd)
	var hy: float = 0.35 if e.get("low", false) else (1.75 if e["kind"] == "tank" else 1.35)   # 기는 좀비는 낮게 맞는다
	var hit_at := z.global_position + Vector3(_rng.randf_range(-0.12, 0.12), hy + _rng.randf_range(-0.15, 0.15), 0)
	BulletHitFX.spawn(self, hit_at, hit_at - _camera.global_position, 1.3 if e["kind"] == "tank" else 1.0)
	var near_k := clampf(hit_at.distance_to(_camera.global_position) / 6.0, 0.35, 1.0)   # 코앞이면 작게 (화면을 붉은 원이 덮지 않게)
	CardFX.blood_splash(self, hit_at, (1.5 if e["kind"] == "tank" else 1.1) * near_k)   # 피 튐 카드 (2026-09-30 "피가 안 보인다")
	e["hp"] -= 1
	if e["hp"] <= 0:
		if e["state"] != "dead":
			service_gun_kills += 1
		_kill(e, hit_at, 1.0)
	elif e["state"] == "move":
		e["state"] = "stagger"                             # 탱커 첫 발: 휘청
		e["t"] = 0.0
		if e["ap"].has_animation("hit"):
			e["ap"].play("hit", 0.1)
			e["ap"].speed_scale = 1.6


# 쓰러뜨림: 죽는 동작 3가지 중 하나 + 큰 피 튐 + 잠깐 뒤 바닥 핏자국 (몇 초 뒤 사라진다)
func _kill(e: Dictionary, at: Vector3, k: float) -> void:
	var z: Node3D = e["node"]
	var ap: AnimationPlayer = e["ap"]
	e["state"] = "dead"
	ap.speed_scale = 1.0
	var dn: String = "death" if e.get("low", false) else DEATH_ANIMS[_rng.randi() % DEATH_ANIMS.size()]
	ap.play(dn if ap.has_animation(dn) else "death", 0.15)
	CardFX.blood_splash(self, at + Vector3(0, 0.1, 0), 1.7 * k)
	e["pool_t"] = 0.9                                      # 쓰러지고 나서 바닥에 핏자국 (_update_zombies 의 dead)


# 보급 상자 (2026-09-30): 풀(1m)에 묻혀 안 보이던 0.6m 상자를 2배(1.2m)로 → 땅에 놓이면 박스가 보인다. 충돌 없음 (그냥 지나가며 줍는다)
# 연기·불꽃은 카드 시퀀스 신호탄 (scenes/fx/card_fx.gd) — 떨어지는 동안부터 불똥을 뿜는다. 밑에 깔리던 검은 원판(옛 연기 장면)은 뺐다
const CRATE_SCALE := 2.0


func _drop_crate(d: float, green: bool) -> void:
	var c: Node3D = load("res://assets/models/prop_supply_crate.glb").instantiate()
	add_child(c)
	c.scale = Vector3.ONE * CRATE_SCALE
	var x := _free_x(d)
	var e := {"node": c, "d": d, "x": x, "y": DROP_HEIGHT, "landed": false, "taken": false, "green": green, "smoke": null}
	c.position = Vector3(x, DROP_HEIGHT, -d)
	var fx := CardFX.flare(c, green)
	fx.scale = Vector3.ONE / CRATE_SCALE                  # 상자 크기와 상관없이 이펙트는 제 크기
	e["smoke"] = fx
	_crates.append(e)


# 차·소품이 없는 자리에 떨어뜨린다 (상자가 차 속에 박히지 않게)
func _free_x(d: float) -> float:
	var picks: Array = []
	var x := -6.5
	while x <= 6.5:
		var ok := true
		for ob in _builder.obstacles:
			if absf(ob["z"] - d) < ob.get("half_depth", 1.0) + 1.5 and absf(ob["x"] - x) < ob["half_width"] + 1.0:
				ok = false
				break
		if ok:
			picks.append(x)
		x += 0.5
	return picks[_rng.randi() % picks.size()] if not picks.is_empty() else 0.0


func _update_crates(dist: float, cam_x: float, delta: float) -> void:
	for c in _crates:
		if c["taken"] or not is_instance_valid(c["node"]):
			continue                                    # 주운 상자는 지워졌으니 건드리지 않는다
		var n: Node3D = c["node"]
		if not c["landed"]:
			c["y"] = maxf(0.0, c["y"] - DROP_SPEED * delta)   # 낙하산으로 천천히 내려온다
			n.position.y = c["y"]
			n.rotation.y += delta * 0.4
			if c["y"] <= 0.0:
				c["landed"] = true
				var chute := n.find_child("Parachute", true, false)
				if chute:
					chute.visible = false                  # 착지하면 낙하산만 숨긴다 (TECH_SPEC 13.3.1)
		# 땅에 놓인 상자 앞(옆 PICK_X 안)을 지나가면 줍는다 → 권총 한 정 (탄창 크기 무작위). 멀리 비켜 가면 못 줍는다
		elif absf(c["d"] - dist) < PICK_Z and absf(c["x"] - cam_x) < PICK_X:
			c["taken"] = true
			_pick_pistol()
			_sfx("sfx_supply_pickup")
			print("[supply] %s %.0fm 줍기 → %s 탄창 %d / 예비 %d" % ["초록" if c["green"] else "빨강", c["d"], _gun_name, _mag, _reserve])
			n.queue_free()


# 보급 권총: 그 모델로 바꿔 든다. 탄창 크기가 바뀌고, 탄창 하나 분량이 예비탄으로 들어온다
# (지금 탄창에 새 탄창보다 많이 들어 있으면 넘치는 만큼은 예비탄으로)
func _pick_pistol() -> void:
	var g: Array = PISTOLS[_rng.randi() % PISTOLS.size()]
	_gun_name = g[0]
	_mag_cap = g[1]
	if _mag > _mag_cap:
		_reserve += _mag - _mag_cap
		_mag = _mag_cap
	_reserve += _mag_cap
	_gun_toast_t = 2.5                                   # 주운 총 이름을 잠깐 보여 준다
	_refresh_ammo()


# 자동 달리기(영상·통과 검사)용: 앞 25m 안에 땅에 놓인 상자가 있으면 그 x (없으면 NAN)
func crate_x(dist: float) -> float:
	for c in _crates:
		if c["landed"] and not c["taken"] and is_instance_valid(c["node"]) and c["d"] - dist > 0.5 and c["d"] - dist < 25.0:
			return c["x"]
	return NAN
