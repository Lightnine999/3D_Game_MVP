class_name RunItemsUI
extends CanvasLayer
## 팩 아이템 화면 (2026-09-30) — 주인 A. stage_preview 가 붙인다.
##  ① 출발 준비: 이번 판에 가지고 갈 아이템(예비 칼·시작 탄약 팩·모닥불·위험 감지)을 켜고 출발. [테스트] 팩 받기 버튼 (결제 연결 전)
##  ② 달리는 중 아이템 칸: 1 광란의 10초 · 2 보급 신호탄 (PC 는 숫자 키, 폰은 칸을 누른다)
##  ③ 위험 감지: 매복·광전사가 오는 쪽 화면 가장자리가 붉게 번쩍
## 모양은 YOU DIED 와 같은 톤 (어두운 판 · 뼈색 글자 · 핏빛 강조)

signal start_run(picks: Dictionary)          # 출발 — 켠 아이템 {item: true}
signal use_item(item: String)                # 달리는 중 아이템 칸을 눌렀다

const START_ITEMS := ["knife_plus", "ammo_start_pack", "bonfire", "danger_sense"]
const RUN_ITEMS := [["frenzy_30", "1"], ["flare_supply", "2"]]
const BONE := Color8(222, 212, 196)
const DIM := Color8(120, 112, 102)
const RED := Color8(196, 32, 26)
const GOLD := Color8(226, 178, 74)

var _panel: Control
var _checks := {}
var _counts := {}
var _slots := {}
var _edges := {}                              # -1 왼쪽 / 0 가운데 / 1 오른쪽 붉은 가장자리
var _edge_t := {}
var _roman: Font
var _info: Label


func _ready() -> void:
	layer = 6
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino", "Baskerville", "Times New Roman", "Noto Serif", "serif"])
	_roman = f
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
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.028, 0.032, 0.94)
	sb.border_color = Color8(110, 26, 22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(36)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(820, 0)
	_panel.add_child(v)
	v.add_child(_label("출발 준비", 58, BONE, _roman, true))
	var rule := ColorRect.new()                           # 제목 아래 가는 핏빛 줄
	rule.color = Color8(120, 24, 20)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	v.add_child(_label("이번 판에 가져갈 아이템을 눌러 켜세요 · 가져가면 1개씩 줄어듭니다", 20, DIM, null, true))
	for item in START_ITEMS:
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(0, 92)
		card.add_theme_stylebox_override("normal", _card_style(CARD_BG, CARD_LINE, 1))
		card.add_theme_stylebox_override("hover", _card_style(Color8(32, 26, 28), Color8(120, 96, 84), 1))
		card.add_theme_stylebox_override("pressed", _card_style(CARD_ON, ON_RED, 3))
		card.add_theme_stylebox_override("hover_pressed", _card_style(Color8(54, 20, 20), Color8(220, 40, 32), 3))
		card.add_theme_stylebox_override("disabled", _card_style(Color8(18, 16, 17), Color8(40, 36, 36), 1))
		card.draw.connect(_draw_card.bind(card, item))
		card.toggled.connect(func(_on): card.queue_redraw())
		var name := _label(Inventory.item_name(item), 30, BONE)
		name.position = Vector2(104, 14)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name)
		var desc := _label(_desc(item), 20, DIM)
		desc.position = Vector2(106, 54)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		var n := _label("", 26, GOLD)
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
	var keys := Control.new()                             # 달리는 중 키 안내: [1] 광란의 10초 ×N  [2] 보급 신호탄 ×N   YOU DIED: 부활 ×N
	keys.custom_minimum_size = Vector2(0, 46)
	keys.draw.connect(_draw_keys.bind(keys))
	v.add_child(keys)
	_keys = keys
	var go := Button.new()
	go.text = "출발"
	go.add_theme_font_override("font", _roman)
	go.add_theme_font_size_override("font_size", 44)
	go.add_theme_color_override("font_color", BONE)
	go.add_theme_color_override("font_hover_color", Color.WHITE)
	go.add_theme_color_override("font_focus_color", Color.WHITE)
	go.add_theme_stylebox_override("normal", _card_style(Color8(150, 18, 16), Color8(200, 40, 30), 2))
	go.add_theme_stylebox_override("hover", _card_style(Color8(186, 26, 20), Color8(240, 80, 60), 2))
	go.add_theme_stylebox_override("focus", _card_style(Color8(186, 26, 20), Color8(240, 80, 60), 2))
	go.add_theme_stylebox_override("pressed", _card_style(Color8(120, 14, 12), Color8(200, 40, 30), 2))
	go.custom_minimum_size = Vector2(0, 78)
	go.pressed.connect(_go)
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


func _card_style(bg: Color, line: Color, w: int, pad := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = line
	st.set_border_width_all(w)
	st.set_corner_radius_all(6)
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
	card.draw_rect(box, Color8(14, 12, 13))
	card.draw_rect(box, (ON_RED if on else CARD_LINE), false, 2.0)
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
	var f := card.get_theme_default_font()
	card.draw_string(f, Vector2(p.x - 110, h * 0.5 + 34), word, HORIZONTAL_ALIGNMENT_RIGHT, 100, 16, (ON_RED if on else DIM))


func _pill(c: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(22)
	return st


# 아이콘 (선·면만으로 그린다 — 외부 그림 없음)
func _draw_icon(c: Control, item: String, o: Vector2, col: Color) -> void:
	match item:
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


# 키캡 안내 줄
func _draw_keys(c: Control) -> void:
	var f := c.get_theme_default_font()
	var x := 6.0
	var y := c.size.y * 0.5
	for pair in [["1", "광란의 10초", Inventory.count("frenzy_30")], ["2", "보급 신호탄", Inventory.count("flare_supply")]]:
		var r := Rect2(Vector2(x, y - 16), Vector2(32, 32))
		c.draw_style_box(_card_style(Color8(36, 32, 32), Color8(150, 138, 124), 1), r)
		c.draw_string(f, Vector2(x, y + 7), pair[0], HORIZONTAL_ALIGNMENT_CENTER, 32, 20, BONE)
		var t := "%s ×%d" % [pair[1], pair[2]]
		c.draw_string(f, Vector2(x + 42, y + 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, (BONE if pair[2] > 0 else DIM))
		x += 42 + f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 28
	var t2 := "달리는 중에 누르기   ·   YOU DIED 화면  부활 ×%d" % Inventory.count("revive")
	c.draw_string(f, Vector2(x, y + 7), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)


func _desc(item: String) -> String:
	return {"knife_plus": "칼 +1 (최대 2)", "ammo_start_pack": "예비탄 7발", "bonfire": "375m 부터 시작", "danger_sense": "매복·광전사 1초 전 경고"}.get(item, "")


func _refresh() -> void:
	for item in _checks:
		var n := Inventory.count(item)
		_counts[item].text = "×%d" % n
		_checks[item].disabled = n <= 0
		if n <= 0:
			_checks[item].button_pressed = false
	if _keys:
		_keys.queue_redraw()
	for item in _checks:
		_checks[item].queue_redraw()
	refresh_slots({})


func is_open() -> bool:
	return _panel != null and is_instance_valid(_panel) and _panel.visible


func confirm() -> void:
	if is_open():
		_go()


func _go() -> void:
	var picks := {}
	for item in _checks:
		if _checks[item].button_pressed and Inventory.use(item):
			picks[item] = true
	_panel.queue_free()
	_panel = null
	start_run.emit(picks)


# ── ② 달리는 중 아이템 칸 (오른쪽 위, 일시정지 아래) ───────────────
func _build_slots() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -300
	box.offset_right = -36
	box.offset_top = 112
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	for pair in RUN_ITEMS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		var none := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, none)
		b.add_theme_color_override("font_color", BONE)
		b.add_theme_color_override("font_disabled_color", Color(DIM, 0.5))
		b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		b.add_theme_constant_override("shadow_offset_y", 2)
		var item: String = pair[0]
		b.pressed.connect(func(): use_item.emit(item))
		box.add_child(b)
		_slots[item] = [b, pair[1]]
	refresh_slots({})


func refresh_slots(used: Dictionary, frenzy_left := 0.0) -> void:
	for item in _slots:
		var b: Button = _slots[item][0]
		var n := Inventory.count(item)
		var tail := ""
		if item == "frenzy_30" and frenzy_left > 0.0:
			tail = "  %d초" % int(ceil(frenzy_left))
		b.text = "%s  %s ×%d%s" % [_slots[item][1], Inventory.item_name(item), n, tail]
		b.disabled = n <= 0 or used.has(item)
		b.add_theme_color_override("font_color", RED if tail != "" else BONE)
		b.visible = n > 0 or used.has(item)


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
