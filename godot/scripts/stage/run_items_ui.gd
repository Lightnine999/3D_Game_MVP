class_name RunItemsUI
extends CanvasLayer
## 팩 아이템 화면 (2026-09-30) — 주인 A. stage_preview 가 붙인다.
##  ① 출발 준비: 이번 판에 가지고 갈 아이템(예비 칼·시작 탄약 팩·모닥불·위험 감지)을 켜고 출발. [테스트] 팩 받기 버튼 (결제 연결 전)
##  ② 달리는 중 아이템 칸: 1 광란의 15초 · 2 보급 신호탄 (PC 는 숫자 키, 폰은 칸을 누른다)
##  ③ 위험 감지: 매복·광전사가 오는 쪽 화면 가장자리가 붉게 번쩍
## 모양은 YOU DIED 와 같은 톤 (어두운 판 · 뼈색 글자 · 핏빛 강조)

signal pistol_upgraded                        # 출발 준비에서 권총을 강화했다 → 이번 판 시작 탄창에도 바로 반영
signal start_run(picks: Dictionary)          # 출발 — 켠 아이템 {item: true}
signal use_item(item: String)                # 달리는 중 아이템 칸을 눌렀다

const START_ITEMS := ["knife_plus", "ammo_start_pack", "bonfire", "danger_sense"]
const RUN_ITEMS := [["frenzy_30", "1"], ["flare_supply", "2"], ["adrenaline", "3"]]
const TIMED := {"frenzy_30": 15.0, "adrenaline": 8.0}   # 쓰면 몇 초 동안 켜져 있는 아이템 (칸에 남은 초)
const BONE := Color8(222, 212, 196)
const DIM := Color8(120, 112, 102)
const RED := Color8(196, 32, 26)
const GOLD := Color8(226, 178, 74)

var _panel: Control
var difficulty := ShowcaseDirector.difficulty   # 출발 준비에서 고른 난이도 (hard / normal) — 출발할 때 stage_preview 가 적용
var _diff_btns := {}
var _diff_row: VBoxContainer
var _diff_easy: VBoxContainer                    # EASY 를 누르면: 핏빛 문구 + 뒤로 버튼 (난이도 줄 대신 나온다)
var _go_btn: Button
var _checks := {}
var _counts := {}
var _slots := {}
var _edges := {}                              # -1 왼쪽 / 0 가운데 / 1 오른쪽 붉은 가장자리
var _edge_t := {}
var _roman: Font
var _info: Label


func _ready() -> void:
	layer = 6
	_roman = load("res://assets/fonts/Cinzel-Variable.ttf")   # 게임에 넣어 둔 로마자 글꼴 (OFL, assets/fonts)
	_gothic = _sys_gothic(700)
	_gothic_m = _sys_gothic(500)
	_build_edges()
	_build_slots()


# ── ① 출발 준비 ──────────────────────────────────────────────
# 2차 디자인 (2026-10-01 "켜는 버튼이 너무 작고 심플하다"): 아이템마다 큰 카드 한 줄 (줄 전체를 누른다)
#   왼쪽 아이콘 · 이름·설명 · 수량 · 오른쪽 큰 스위치(켜면 핏빛 "가져감"). 켠 카드는 붉은 테두리, 없는 아이템은 흐리게 "없음"
const CARD_BG := Color8(24, 20, 22)
const CARD_ON := Color8(44, 18, 18)
const CARD_LINE := Color8(70, 56, 52)
const ON_RED := Color8(184, 26, 22)


func open_loadout() -> void:
	_manual = {}
	_blood_seed = 0                                       # 열 때마다 핏자국 새로
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.028, 0.032, 0.94)
	sb.border_color = Color8(110, 26, 22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(36)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var th := Theme.new()                                 # 창 안 글자는 모두 고딕 (2026-10-01)
	th.default_font = _gothic_m
	_panel.theme = th
	add_child(_panel)
	var blood := Control.new()                            # 핏자국 장식 (창 뒤 · 모서리로 번진다)
	blood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blood.draw.connect(_draw_blood.bind(blood))
	_panel.add_child(blood)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(820, 0)
	_panel.add_child(v)
	v.add_child(_label("출발 준비", 52, BONE, _gothic, true))
	var rule := ColorRect.new()                           # 제목 아래 가는 핏빛 줄
	rule.color = Color8(120, 24, 20)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	v.add_child(_label("이번 판에 가져갈 아이템을 눌러 켜세요 · 가져가면 1개씩 줄어듭니다", 20, DIM, null, true))
	_build_difficulty(v)
	_build_stage_card()
	for item in START_ITEMS:
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(0, 82)       # 92 → 82 (2026-10-01 난이도 카드를 크게 넣느라)
		card.add_theme_stylebox_override("normal", _card_style(CARD_BG, CARD_LINE, 1))
		card.add_theme_stylebox_override("hover", _card_style(Color8(32, 26, 28), Color8(120, 96, 84), 1))
		card.add_theme_stylebox_override("pressed", _card_style(CARD_ON, ON_RED, 3))
		card.add_theme_stylebox_override("hover_pressed", _card_style(Color8(54, 20, 20), Color8(220, 40, 32), 3))
		card.add_theme_stylebox_override("disabled", _card_style(Color8(18, 16, 17), Color8(40, 36, 36), 1))
		card.draw.connect(_draw_card.bind(card, item))
		card.toggled.connect(func(_on): card.queue_redraw())
		card.pressed.connect(func(): _manual[item] = true)     # 사용자가 직접 눌렀다 → 그 뒤로는 자동으로 켜지 않는다
		var name := _label(Inventory.item_name(item), 30, BONE, _gothic)
		name.position = Vector2(104, 14)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name)
		var desc := _label(_desc(item), 20, DIM)
		desc.position = Vector2(106, 54)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		var n := _label("", 26, GOLD, _gothic)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.anchor_left = 1.0
		n.anchor_right = 1.0
		n.offset_left = -270
		n.offset_right = -160
		n.offset_top = 28
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card.add_child(n)
		v.add_child(card)
		_checks[item] = card
		_counts[item] = n
	_info = Label.new()                                   # (예전 안내 줄 — 이제 아래 키캡 줄이 대신한다)
	_info.visible = false
	v.add_child(_info)
	var keys := Control.new()                             # 달리는 중 키 안내: [1] 광란의 15초 ×N  [2] 보급 신호탄 ×N   YOU DIED: 부활 ×N
	keys.custom_minimum_size = Vector2(0, 78)
	keys.draw.connect(_draw_keys.bind(keys))
	v.add_child(keys)
	_keys = keys
	var go := Button.new()
	go.text = "출발"
	go.add_theme_font_override("font", _gothic)
	go.add_theme_font_size_override("font_size", 38)
	go.add_theme_color_override("font_color", BONE)
	go.add_theme_color_override("font_hover_color", Color.WHITE)
	go.add_theme_color_override("font_focus_color", Color.WHITE)
	go.add_theme_stylebox_override("normal", _card_style(Color8(150, 18, 16), Color8(200, 40, 30), 2))
	go.add_theme_stylebox_override("hover", _card_style(Color8(186, 26, 20), Color8(240, 80, 60), 2))
	go.add_theme_stylebox_override("focus", _card_style(Color8(186, 26, 20), Color8(240, 80, 60), 2))
	go.add_theme_stylebox_override("pressed", _card_style(Color8(120, 14, 12), Color8(200, 40, 30), 2))
	go.custom_minimum_size = Vector2(0, 78)
	go.pressed.connect(_go)
	_go_btn = go
	v.add_child(go)
	var test := HBoxContainer.new()                        # 결제 연결 전 테스트 지급 (PRD 4.15 테스트 모드)
	test.alignment = BoxContainer.ALIGNMENT_CENTER
	test.add_theme_constant_override("separation", 10)
	test.add_child(_label("테스트 지급", 18, DIM))
	for pack in Inventory.PACKS:
		var b := Button.new()
		b.text = "+ " + Inventory.PACKS[pack]["name"]
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Color8(190, 176, 150))
		b.add_theme_color_override("font_hover_color", GOLD)
		b.add_theme_stylebox_override("normal", _card_style(Color(0, 0, 0, 0), Color8(80, 70, 60), 1, 8))
		b.add_theme_stylebox_override("hover", _card_style(Color8(30, 26, 22), GOLD, 1, 8))
		b.add_theme_stylebox_override("pressed", _card_style(Color8(40, 34, 26), GOLD, 1, 8))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): Inventory.grant_pack(pack); _refresh())
		test.add_child(b)
	v.add_child(test)
	_refresh()
	go.grab_focus()


var _keys: Control


# ── 난이도 (2026-10-01): HARD 지금 그대로 · NORMAL 좀비 20%↓ 보급 20%↑ · EASY 는 없다 ─────────
const DIFFICULTIES := [["hard", "HARD", "지금 그대로"], ["normal", "NORMAL", "좀비 20% ↓ · 보급 20% ↑"], ["easy", "EASY", "…정말요?"]]
# 2차 (2026-10-01 "버튼이 너무 작다, 눈에 띄게"): 셋을 가로로 꽉 채운 큰 카드. 난이도마다 색 — HARD 핏빛 · NORMAL 금빛 · EASY 회색
#   고른 카드는 그 색으로 채우고 굵은 테두리, 안 고른 카드는 어두운 바탕에 그 색 테두리·글자
const DIFF_COLOR := {"hard": Color8(200, 30, 24), "normal": Color8(226, 160, 48), "easy": Color8(120, 112, 102)}


func _build_difficulty(v: VBoxContainer) -> void:
	var locked := ShowcaseDirector.difficulty_locked     # 이미 출발했던 난이도 — 죽어서 RETRY 하기 전에는 못 바꾼다
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label("난이도 선택" if not locked else "난이도  ·  죽으면 다시 고를 수 있어요", 20, DIM, _gothic, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for d in DIFFICULTIES:
		var id: String = d[0]
		if locked and id != difficulty:
			continue                                      # 잠겨 있으면 지금 난이도 하나만 보여 준다
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = id != "easy"
		b.disabled = locked
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 0.7 if id == "easy" else 1.0
		b.custom_minimum_size = Vector2(0, 92)
		var col: Color = DIFF_COLOR[id]
		b.add_theme_stylebox_override("normal", _card_style(Color8(22, 18, 20), col.darkened(0.25), 2))
		b.add_theme_stylebox_override("hover", _card_style(Color8(34, 26, 26), col, 2))
		b.add_theme_stylebox_override("pressed", _card_style(col.darkened(0.45), col.lightened(0.15), 4))
		b.add_theme_stylebox_override("hover_pressed", _card_style(col.darkened(0.38), col.lightened(0.3), 4))
		b.add_theme_stylebox_override("disabled", _card_style(col.darkened(0.45), col.lightened(0.15), 4))   # 잠긴 난이도도 고른 모양 그대로
		var lines := VBoxContainer.new()
		lines.set_anchors_preset(Control.PRESET_FULL_RECT)
		lines.alignment = BoxContainer.ALIGNMENT_CENTER
		lines.add_theme_constant_override("separation", 0)
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := _label(d[1], 38, col.lightened(0.2), _gothic, true)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sub := _label(d[2], 18, BONE, null, true)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(title)
		lines.add_child(sub)
		b.add_child(lines)
		b.pressed.connect(_pick_difficulty.bind(id))
		row.add_child(b)
		_diff_btns[id] = [b, title, col]
	v.add_child(box)
	_diff_row = box
	_diff_easy = VBoxContainer.new()
	_diff_easy.alignment = BoxContainer.ALIGNMENT_CENTER
	_diff_easy.add_theme_constant_override("separation", 10)
	_diff_easy.custom_minimum_size = Vector2(0, 118)    # 난이도 카드 자리와 같은 높이 → 창이 덜컥 줄지 않게
	_diff_easy.visible = false
	_diff_easy.add_child(_label("EASY 를 선택할 거면 게임을 하지 마세요!", 34, Color8(230, 44, 34), _gothic, true))
	var back := Button.new()
	back.text = "←  뒤로  (HARD · NORMAL 고르기)"
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.custom_minimum_size = Vector2(420, 58)
	back.add_theme_font_override("font", _gothic)
	back.add_theme_font_size_override("font_size", 24)
	back.add_theme_color_override("font_color", BONE)
	back.add_theme_stylebox_override("normal", _card_style(CARD_BG, BONE.darkened(0.3), 2, 10))
	back.add_theme_stylebox_override("hover", _card_style(Color8(36, 30, 30), BONE, 2, 10))
	back.add_theme_stylebox_override("pressed", _card_style(Color8(48, 40, 38), BONE, 3, 10))
	back.pressed.connect(_easy_back)
	_diff_easy.add_child(back)
	v.add_child(_diff_easy)
	_show_difficulty()


# EASY: 난이도 줄을 치우고 핏빛 문구 + 뒤로 버튼. 그동안 출발은 막는다
func _pick_difficulty(id: String) -> void:
	if id == "easy":
		_diff_row.visible = false
		_diff_easy.visible = true
		if _go_btn:
			_go_btn.disabled = true
	else:
		difficulty = id
	_show_difficulty()


func _easy_back() -> void:
	_diff_easy.visible = false
	_diff_row.visible = true
	if _go_btn:
		_go_btn.disabled = false
	_show_difficulty()


func _show_difficulty() -> void:
	for id in _diff_btns:
		var b: Button = _diff_btns[id][0]
		var on: bool = id == difficulty
		if id != "easy":
			b.set_pressed_no_signal(on)
		var col: Color = _diff_btns[id][2]
		_diff_btns[id][1].add_theme_color_override("font_color", Color.WHITE if on else col.lightened(0.2))   # 고른 카드 제목은 흰색


func _card_style(bg: Color, line: Color, w: int, pad := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = line
	st.set_border_width_all(w)
	st.set_corner_radius_all(14)
	if pad > 0:
		st.content_margin_left = pad * 2
		st.content_margin_right = pad * 2
		st.content_margin_top = pad
		st.content_margin_bottom = pad
	return st


# 카드 그림: 왼쪽 아이콘 + 오른쪽 큰 스위치
func _draw_card(card: Button, item: String) -> void:
	var h := card.size.y
	var on := card.button_pressed
	var off := card.disabled
	var ic := (ON_RED if on else (Color8(70, 64, 60) if off else BONE))
	var box := Rect2(Vector2(22, h * 0.5 - 30), Vector2(60, 60))   # 아이콘 칸
	card.draw_style_box(_card_style(Color8(14, 12, 13), (ON_RED if on else CARD_LINE), 2), box)
	_draw_icon(card, item, box.get_center(), ic)
	var sw := Vector2(96, 44)                             # 스위치
	var p := Vector2(card.size.x - sw.x - 28, h * 0.5 - sw.y * 0.5)
	var track := (ON_RED if on else Color8(52, 46, 46))
	if off:
		track = Color8(32, 30, 30)
	card.draw_style_box(_pill(track), Rect2(p, sw))
	var knob_x := p.x + (sw.x - 24.0 if on else 24.0)
	card.draw_circle(Vector2(knob_x, p.y + sw.y * 0.5), 17.0, (Color8(250, 238, 222) if on else (Color8(70, 64, 60) if off else Color8(150, 140, 128))))
	var word := ("가져감" if on else ("없음" if off else "두고 감"))
	card.draw_string(_gothic, Vector2(p.x - 110, h * 0.5 + 34), word, HORIZONTAL_ALIGNMENT_RIGHT, 100, 16, (ON_RED if on else DIM))


func _pill(c: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(22)
	return st


# 아이콘 (선·면만으로 그린다 — 외부 그림 없음)
func _draw_icon(c: Control, item: String, o: Vector2, col: Color, zoom := 1.0) -> void:
	if zoom != 1.0:
		c.draw_set_transform(o * (1.0 - zoom), 0.0, Vector2(zoom, zoom))
	match item:
		"frenzy_30":                                       # 광란: 번개 + 총알
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(4, -22), o + Vector2(-10, 2), o + Vector2(-1, 2), o + Vector2(-5, 22), o + Vector2(10, -4), o + Vector2(1, -4)]), col)
		"flare_supply":                                    # 신호탄: 막대 + 불꽃
			c.draw_rect(Rect2(o + Vector2(-5, -4), Vector2(10, 24)), col)
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -24), o + Vector2(7, -10), o + Vector2(3, -5), o + Vector2(-3, -5), o + Vector2(-7, -10)]), col)
			c.draw_line(o + Vector2(-12, -18), o + Vector2(-8, -14), col, 2.0)
			c.draw_line(o + Vector2(12, -18), o + Vector2(8, -14), col, 2.0)
		"adrenaline":                                      # 아드레날린: 주사기
			c.draw_set_transform(o, -0.785, Vector2(zoom, zoom))                       # 45도 눕혀서 (o 기준 좌표로 그린다)
			c.draw_rect(Rect2(Vector2(-6, -12), Vector2(12, 24)), col, false, 2.5)       # 통
			c.draw_rect(Rect2(Vector2(-4, -2), Vector2(8, 12)), col)                     # 약
			c.draw_line(Vector2(0, 12), Vector2(0, 24), col, 2.0)                       # 바늘
			c.draw_line(Vector2(-9, -12), Vector2(9, -12), col, 3.0)                    # 손잡이
			c.draw_line(Vector2(0, -12), Vector2(0, -20), col, 3.0)
			c.draw_line(Vector2(-6, -20), Vector2(6, -20), col, 3.0)
			c.draw_set_transform(o * (1.0 - zoom), 0.0, Vector2(zoom, zoom))          # 원래 확대로 되돌림 (zoom 1 이면 그대로)
		"knife_plus":                                      # 칼: 날 + 손잡이
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(-4, -20), o + Vector2(6, -6), o + Vector2(4, 8), o + Vector2(-4, 8)]), col)
			c.draw_rect(Rect2(o + Vector2(-9, 8), Vector2(18, 4)), col)
			c.draw_rect(Rect2(o + Vector2(-4, 12), Vector2(8, 12)), col)
		"ammo_start_pack":                                 # 총알 세 개
			for i in 3:
				var x := -14.0 + i * 11.0
				c.draw_circle(o + Vector2(x + 4, -8), 4.0, col)
				c.draw_rect(Rect2(o + Vector2(x, -8), Vector2(8, 26)), col)
		"bonfire":                                         # 불꽃 + 장작
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -22), o + Vector2(12, -2), o + Vector2(8, 10), o + Vector2(-8, 10), o + Vector2(-12, -2), o + Vector2(-4, -8)]), col)
			c.draw_line(o + Vector2(-16, 18), o + Vector2(16, 12), col, 4.0)
			c.draw_line(o + Vector2(-16, 12), o + Vector2(16, 18), col, 4.0)
		"danger_sense":                                    # 눈
			var pts := PackedVector2Array()
			for k in 24:
				var a := TAU * k / 24.0
				pts.append(o + Vector2(cos(a) * 22.0, sin(a) * 11.0))
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 3.0)
			c.draw_circle(o, 7.0, col)
	if zoom != 1.0:
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 키캡 안내 (2026-10-01 "창 밖으로 벗어났다"): 윗줄 [1][2][3] 가운데 정렬 · 아랫줄 작은 안내
func _draw_keys(c: Control) -> void:
	var pairs := [["1", "광란의 15초", Inventory.count("frenzy_30")], ["2", "보급 신호탄", Inventory.count("flare_supply")], ["3", "아드레날린", Inventory.count("adrenaline")]]
	var gap := 36.0
	var total := 0.0
	for pair in pairs:
		total += 40.0 + _gothic.get_string_size("%s ×%d" % [pair[1], pair[2]], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	total += gap * (pairs.size() - 1)
	var x := c.size.x * 0.5 - total * 0.5
	var y := 22.0
	for pair in pairs:
		var r := Rect2(Vector2(x, y - 16), Vector2(32, 32))
		var cap := _card_style(Color8(36, 32, 32), Color8(150, 138, 124), 1)
		cap.set_corner_radius_all(7)                      # 키캡은 살짝만 둥글게
		c.draw_style_box(cap, r)
		c.draw_string(_gothic, Vector2(x, y + 7), pair[0], HORIZONTAL_ALIGNMENT_CENTER, 32, 20, BONE)
		var t := "%s ×%d" % [pair[1], pair[2]]
		c.draw_string(_gothic, Vector2(x + 40, y + 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, (BONE if pair[2] > 0 else DIM))
		x += 40.0 + _gothic.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + gap
	var t2 := "달리는 중에 숫자 키를 누르세요   ·   죽으면 YOU DIED 화면에서 부활 ×%d" % Inventory.count("revive")
	c.draw_string(_gothic_m, Vector2(0, y + 44), t2, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 17, DIM)


# 핏자국 장식 (2026-10-01 "귀엽다 → 랜덤하게 → 톤 통일·흘러내림·총 맞은 듯 각지고 찢긴 느낌"): 창을 열 때마다 모양이 바뀐다
#   한 가지 진한 핏빛 · 가시가 날카롭게 찢어진 덩어리 · 바깥으로 뿌려진 세모 파편 · 덩어리·위 가장자리에서 흘러내리는 줄기
const BLOOD := Color(0.4, 0.015, 0.012, 0.96)
var _blood_seed := 0


func _splat(c: Control, rng: RandomNumberGenerator, o: Vector2, r: float) -> void:
	# 외곽점을 (각도, 반지름) 으로 모은 뒤 각도 순으로 이어 붙인다 → 가운데서 본 별 모양이라 선이 꼬이지 않는다
	var rays := []
	var a := 0.0
	while a < TAU - 0.12:
		if rng.randf() < 0.3:                             # 날카로운 가시: 좁은 밑동 → 길고 뾰족한 끝 (끝이 살짝 비틀려 찢긴 느낌)
			var d := rng.randf_range(0.03, 0.08)
			var tip := rng.randf_range(1.4, 2.8)
			rays.append(Vector2(a - d, rng.randf_range(0.75, 0.95)))
			rays.append(Vector2(a + rng.randf_range(-0.5, 0.2) * d, tip))
			if rng.randf() < 0.4:                         # 갈라진 끝
				rays.append(Vector2(a + d * 0.4, tip * rng.randf_range(0.6, 0.8)))
				rays.append(Vector2(a + d * 0.7, tip * rng.randf_range(0.85, 1.0)))
			rays.append(Vector2(a + d, rng.randf_range(0.75, 0.95)))
			a += d + rng.randf_range(0.05, 0.12)
		else:                                             # 들쭉날쭉한 가장자리
			rays.append(Vector2(a, rng.randf_range(0.6, 1.05)))
			a += rng.randf_range(0.08, 0.2)
	rays.sort_custom(func(p, q): return p.x < q.x)
	var turn := rng.randf() * TAU
	var pts := PackedVector2Array()
	for ray in rays:
		pts.append(o + Vector2.from_angle(ray.x + turn) * r * ray.y)
	c.draw_colored_polygon(pts, BLOOD)
	var dir := Vector2.from_angle(rng.randf() * TAU)     # 한쪽으로 뿌려진 세모 파편 (총 맞은 자국처럼)
	for i in rng.randi_range(16, 30):
		var p := o + dir.rotated(rng.randf_range(-0.8, 0.8)) * rng.randf_range(1.2, 3.6) * r
		var along := (p - o).normalized().rotated(rng.randf_range(-0.15, 0.15))
		var sz := rng.randf_range(1.5, 5.0)
		var tail := rng.randf_range(2.0, 6.0) * sz
		var side := along.orthogonal()
		c.draw_colored_polygon(PackedVector2Array([p + along * sz * 0.8, p + side * sz * rng.randf_range(0.5, 1.0), p - along * tail, p - side * sz * rng.randf_range(0.5, 1.0)]), BLOOD)
	for i in rng.randi_range(1, 3):                       # 덩어리 아래로 흘러내림
		_drip(c, rng, o + Vector2(rng.randf_range(-0.6, 0.6) * r, r * 0.5), rng.randf_range(30, 120), rng.randf_range(2.5, 5.5))


# 흘러내리는 줄기: 위가 굵고 아래로 갈수록 가늘다가 끝에 방울이 맺힌다 (살짝 구불구불)
func _drip(c: Control, rng: RandomNumberGenerator, top: Vector2, len: float, tw: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 8
	var x := 0.0
	for i in steps + 1:
		var t := float(i) / steps
		var wdt := tw * lerpf(1.0, 0.35, t) * rng.randf_range(0.85, 1.15)
		var pt := top + Vector2(x, len * t)
		left.append(pt - Vector2(wdt, 0))
		right.append(pt + Vector2(wdt, 0))
		x += rng.randf_range(-1.2, 1.2)
	right.reverse()
	c.draw_colored_polygon(left + right, BLOOD)
	var bulb := PackedVector2Array()
	var end := top + Vector2(x, len + tw * 0.4)
	for k in 14:
		var ang := TAU * k / 14.0
		bulb.append(end + Vector2(cos(ang) * tw * 0.75, sin(ang) * tw * (1.1 if sin(ang) > 0.0 else 0.8)))
	c.draw_colored_polygon(bulb, BLOOD)


func _draw_blood(c: Control) -> void:
	var rng := RandomNumberGenerator.new()
	if _blood_seed == 0:
		_blood_seed = randi() | 1
	rng.seed = _blood_seed
	c.draw_set_transform(Vector2(-36, -36))               # 판 안쪽 여백(36)만큼 밖으로 — 판 가장자리 기준으로 그린다
	var w := c.size.x + 72.0
	var h := c.size.y + 72.0
	var spots := [Vector2(rng.randf_range(34, 110), rng.randf_range(30, 90)), Vector2(w - rng.randf_range(34, 130), h - rng.randf_range(60, 130))]   # 판 안쪽 모서리 (밖 HUD 를 덮지 않게)
	if rng.randf() < 0.7:
		spots.append(Vector2(w - rng.randf_range(34, 150), rng.randf_range(30, 80)))
	if rng.randf() < 0.6:
		spots.append(Vector2(rng.randf_range(30, 90), h - rng.randf_range(80, 220)))
	for o in spots:
		_splat(c, rng, o, rng.randf_range(18, 34))
	for i in rng.randi_range(5, 9):                       # 위 가장자리에서 흘러내림 (제목은 비켜서)
		var x := rng.randf_range(w * 0.04, w * 0.34) if rng.randf() < 0.5 else rng.randf_range(w * 0.66, w * 0.96)
		var tw := rng.randf_range(2.5, 7.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - tw * 2.4, -2), Vector2(x + tw * 2.2, -2), Vector2(x + tw * 0.9, tw * 1.2), Vector2(x - tw, tw)]), BLOOD)
		_drip(c, rng, Vector2(x, 0), rng.randf_range(16, 110), tw)
	c.draw_set_transform(Vector2.ZERO)


func _desc(item: String) -> String:
	return {"knife_plus": "칼 +1 (최대 2)", "ammo_start_pack": "예비탄 7발", "bonfire": "375m 부터 시작", "danger_sense": "매복·광전사 1초 전 경고"}.get(item, "")


func _refresh() -> void:
	for item in _checks:
		var n := Inventory.count(item)
		_counts[item].text = "×%d" % n
		_checks[item].disabled = n <= 0
		if n <= 0:
			_checks[item].button_pressed = false
		elif not _manual.has(item) and item not in AUTO_OFF:
			_checks[item].button_pressed = true           # 가진 아이템은 기본으로 켜서 가져간다 (2026-10-01 "시작은 사용한다로") — 끄고 싶으면 눌러서 끈다
	if _keys:
		_keys.queue_redraw()
	for item in _checks:
		_checks[item].queue_redraw()
	refresh_slots({})


func is_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and _panel.visible


func confirm() -> void:
	if is_open() and not (_go_btn and _go_btn.disabled):   # EASY 문구가 떠 있는 동안에는 Enter 로도 출발하지 않는다
		_go()


func _go() -> void:
	var picks := {}
	for item in _checks:
		if _checks[item].button_pressed and Inventory.use(item):
			picks[item] = true
	_panel.queue_free()
	_panel = null
	if _card:
		_card.queue_free()
		_card = null
	start_run.emit(picks)


# ── ② 달리는 중 아이템 칸 ─────────────────────────────────────
# 2차 (2026-10-01 "1·2 키를 모를 수 있다"): 오른쪽에 큰 아이콘 버튼 두 개 — 아이콘 · 키캡 [1]/[2] · 수량 · 이름
#   폰은 그냥 누른다. 지금 쓰면 좋을 때(총알이 바닥·끝 반전) 금빛으로 깜빡이고, 출발 직후 3초 동안 쓰는 법을 알려 준다
const SLOT := 96.0
var _gothic: SystemFont                       # 굵은 고딕 (HUD 숫자와 같은 결)
var _gothic_m: SystemFont                     # 보통 굵기 고딕 (설명 글)


func _sys_gothic(weight: int) -> SystemFont:
	var g := SystemFont.new()
	g.font_names = PackedStringArray(["Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "Malgun Gothic", "Roboto", "sans-serif"])
	g.font_weight = weight
	return g
var _hint := {}
var _tip: Label
var _toast: Label
const AUTO_OFF := ["bonfire"]                          # 모닥불은 기본 꺼짐 — 켜 두면 매번 절반(375m)부터 시작해 버린다
var _manual := {}                                      # 출발 준비에서 사용자가 직접 켜고 끈 아이템 (자동 켜짐 대상에서 뺀다)
var _toast_t := 0.0
var _card: Control                                     # 스테이지 카드 (출발 준비 창 왼쪽)
var _tip_t := 0.0
var _blink := 0.0
var _timers := {}


func _build_slots() -> void:
	var box := HBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -(SLOT * RUN_ITEMS.size() + 12 * (RUN_ITEMS.size() - 1) + 40)
	box.offset_right = -40
	box.offset_top = 150
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	for pair in RUN_ITEMS:
		var item: String = pair[0]
		var b := Button.new()
		b.custom_minimum_size = Vector2(SLOT, SLOT + 34)
		b.focus_mode = Control.FOCUS_NONE
		var none := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, none)
		b.draw.connect(_draw_slot.bind(b, item, pair[1]))
		b.pressed.connect(func(): use_item.emit(item))
		box.add_child(b)
		_slots[item] = [b, pair[1]]
	_tip = Label.new()                                    # 출발 직후 3초 안내
	_tip.add_theme_font_override("font", _gothic)
	_tip.add_theme_font_size_override("font_size", 24)
	_tip.add_theme_color_override("font_color", BONE)
	_tip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_tip.add_theme_constant_override("shadow_offset_y", 2)
	_tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.offset_left = -520
	_tip.offset_right = 520
	_tip.offset_top = -150
	_tip.offset_bottom = -110
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.modulate.a = 0.0
	add_child(_tip)
	_toast = Label.new()                                  # 미션 달성 알림 (화면 위 가운데, 금빛)
	_toast.add_theme_font_override("font", _gothic)
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_color", GOLD)
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("shadow_offset_y", 3)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -900
	_toast.offset_right = 900
	_toast.offset_top = 150
	_toast.offset_bottom = 200
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)
	refresh_slots({})


# 출발할 때 한 번: 가진 아이템이 있으면 쓰는 법을 알려 준다
# 폰·태블릿 (앱, 또는 폰 브라우저의 웹 빌드) — 숫자 키 안내를 숨긴다
static func is_touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# 미션 달성 알림 — 4초 동안 화면 위에
func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 4.0
	_toast.modulate.a = 1.0
	_sfx_ok()


func _sfx_ok() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/sfx_mission_done.ogg")
	p.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ── 스테이지 카드 (2026-10-01 미션): 출발 준비 창 왼쪽 — 스테이지 · 미션 3개(★) · 코인 · 권총 강화 ─────────
func _build_stage_card() -> void:
	if _card:
		_card.queue_free()
	var card := PanelContainer.new()
	var sb := _card_style(Color(0.035, 0.028, 0.032, 0.94), Color8(110, 26, 22), 2)
	sb.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = 50
	card.offset_right = 610
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var th := Theme.new()
	th.default_font = _gothic_m
	card.theme = th
	add_child(card)
	_card = card
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(_label(MissionTracker.stage_info()["name"], 34, BONE, _gothic))
	var rule := ColorRect.new()
	rule.color = Color8(120, 24, 20)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	v.add_child(_label("미션  ·  3개를 모두 달성하면 다음 스테이지", 18, DIM))
	for line in MissionTracker.mission_lines():
		var done: bool = line[1]
		v.add_child(_label(("★  " if done else "☆  ") + line[0], 26, GOLD if done else BONE, _gothic))
	if not MissionTracker.last_run.is_empty():
		var last := _label("지난 판 달성:  " + " · ".join(MissionTracker.last_run), 18, GOLD)
		last.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(last)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	v.add_child(_label("보유 코인   %d" % MissionTracker.coins(), 28, GOLD, _gothic))
	var pg: Array = MissionTracker.pistol()
	v.add_child(_label("시작 권총   %s  %d발" % [pg[0], pg[1]], 22, BONE))
	var nx: Array = MissionTracker.next_pistol()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_override("font", _gothic)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_stylebox_override("normal", _card_style(Color8(60, 44, 14), GOLD, 2))
	b.add_theme_stylebox_override("hover", _card_style(Color8(80, 58, 18), GOLD.lightened(0.2), 2))
	b.add_theme_stylebox_override("pressed", _card_style(Color8(96, 70, 20), GOLD.lightened(0.3), 3))
	b.add_theme_stylebox_override("disabled", _card_style(CARD_BG, CARD_LINE, 1))
	if nx.is_empty():
		b.text = "권총 강화 완료 (최고 단계)"
		b.disabled = true
	else:
		b.text = "권총 강화 → %s %d발   ·   %d코인" % [nx[0], nx[1], nx[2]]
		b.disabled = MissionTracker.coins() < nx[2]
		b.pressed.connect(func():
			if MissionTracker.buy_pistol():
				pistol_upgraded.emit()
				_build_stage_card())
	v.add_child(b)


func show_tip() -> void:
	var parts := []
	if Inventory.has("frenzy_30"):
		parts.append("[1] 광란의 15초")
	if Inventory.has("flare_supply"):
		parts.append("[2] 보급 신호탄")
	if Inventory.has("adrenaline"):
		parts.append("[3] 아드레날린")
	if parts.is_empty():
		return
	_tip.text = "  ·  ".join(parts) + "   —   키를 누르거나 오른쪽 아이콘을 누르세요"
	_tip_t = 4.0


func refresh_slots(used: Dictionary, timers := {}, hint := {}) -> void:
	_hint = hint
	_timers = timers
	for item in _slots:
		var b: Button = _slots[item][0]
		b.disabled = Inventory.count(item) <= 0 or used.has(item)
		b.visible = Inventory.count(item) > 0 or used.has(item)
		b.set_meta("used", used.has(item))
		b.queue_redraw()


func _draw_slot(b: Button, item: String, key: String) -> void:
	var left: float = _timers.get(item, 0.0)
	var on := left > 0.0
	var dead := b.disabled and not on
	var glow := _hint.has(item) and not b.disabled
	var r := Rect2(Vector2.ZERO, Vector2(SLOT, SLOT))
	if glow:                                              # 지금 쓰면 좋다 → 금빛 고리가 깜빡인다
		var a := 0.45 + 0.45 * sin(_blink * 8.0)
		b.draw_style_box(_card_style(Color(0, 0, 0, 0), Color(GOLD, a), 4), r.grow(6))
	b.draw_style_box(_card_style(Color(0.04, 0.035, 0.04, 0.78), (RED if on else (GOLD if glow else Color8(120, 108, 96))), 2), r)
	_draw_icon(b, item, r.get_center() + Vector2(0, -4), (RED if on else (Color8(80, 74, 70) if dead else BONE)), 1.5)
	if on:                                                # 남은 시간: 칸 아래 줄어드는 붉은 막대 + 숫자
		var k := clampf(left / TIMED.get(item, 1.0), 0.0, 1.0)
		b.draw_rect(Rect2(Vector2(4, SLOT - 6), Vector2((SLOT - 8) * k, 3)), RED)
		b.draw_string(_gothic, Vector2(0, SLOT - 12), "%d" % int(ceil(left)), HORIZONTAL_ALIGNMENT_CENTER, SLOT, 26, Color.WHITE)
	if not is_touch():                                    # 키캡 [1][2][3] 은 PC(키보드)에서만 — 폰에서는 남은 개수로 헷갈린다 (2026-10-01)
		var kr := Rect2(Vector2(-8, -8), Vector2(30, 30))
		b.draw_style_box(_card_style(Color8(30, 26, 26), Color8(190, 176, 150), 1), kr)
		b.draw_string(_gothic, Vector2(-8, 14), key, HORIZONTAL_ALIGNMENT_CENTER, 30, 20, BONE)
	var n := Inventory.count(item)                        # 수량 (오른쪽 위)
	b.draw_string(_gothic, Vector2(SLOT - 46, 22), "×%d" % n, HORIZONTAL_ALIGNMENT_RIGHT, 40, 20, (GOLD if n > 0 else DIM))
	var name := Inventory.item_name(item)
	if b.get_meta("used", false) and not on:
		name = "사용함"
	b.draw_string(_gothic, Vector2(-20, SLOT + 26), name, HORIZONTAL_ALIGNMENT_CENTER, SLOT + 40, 18, (DIM if dead else BONE))


func hide_slots() -> void:
	for item in _slots:
		_slots[item][0].visible = false


# ── ③ 위험 감지: 가장자리 붉은 번쩍임 ───────────────────────────
func _build_edges() -> void:
	for side in [-1, 0, 1]:
		var tr := TextureRect.new()
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(0.75, 0.02, 0.02, 0.85), Color(0.75, 0.02, 0.02, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 128
		gt.height = 8
		if side == 1:
			gt.fill_from = Vector2(1, 0)
			gt.fill_to = Vector2(0, 0)
		elif side == 0:
			gt.fill = GradientTexture2D.FILL_RADIAL
			gt.fill_from = Vector2(0.5, 0.5)
			gt.fill_to = Vector2(1.0, 0.5)
			g.colors = PackedColorArray([Color(0.75, 0.02, 0.02, 0.0), Color(0.75, 0.02, 0.02, 0.7)])
			gt.width = 128
			gt.height = 128
		tr.texture = gt
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side == 0:
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		else:
			tr.anchor_top = 0.0
			tr.anchor_bottom = 1.0
			tr.anchor_left = 0.0 if side < 0 else 1.0
			tr.anchor_right = tr.anchor_left
			tr.offset_left = 0.0 if side < 0 else -260.0
			tr.offset_right = 260.0 if side < 0 else 0.0
		tr.modulate.a = 0.0
		add_child(tr)
		_edges[side] = tr
		_edge_t[side] = 0.0


func warn(side: int) -> void:
	_edge_t[clampi(side, -1, 1)] = 1.0


func _process(delta: float) -> void:
	_blink += delta
	if _tip:
		_tip_t -= delta
		_tip.modulate.a = clampf(_tip_t / 0.6, 0.0, 1.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
	if not _hint.is_empty():
		for item in _slots:
			_slots[item][0].queue_redraw()
	for side in _edges:
		_edge_t[side] = maxf(_edge_t[side] - delta / 0.9, 0.0)
		var t: float = _edge_t[side]
		_edges[side].modulate.a = t * (0.75 + 0.25 * sin(t * 30.0))


func _label(text: String, size: int, col: Color, font: Font = null, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
