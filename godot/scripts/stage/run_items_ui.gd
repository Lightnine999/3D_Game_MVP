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
func open_loadout() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.025, 0.03, 0.9)
	sb.border_color = Color8(90, 20, 18)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(40)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(760, 0)
	_panel.add_child(v)
	v.add_child(_label("출발 준비", 56, BONE, _roman, true))
	v.add_child(_label("이번 판에 가지고 갈 것을 고르세요 — 가져가면 1개씩 줄어듭니다", 20, DIM))
	for item in START_ITEMS:
		var row := HBoxContainer.new()
		var c := CheckButton.new()
		c.text = "  " + Inventory.item_name(item) + "  —  " + _desc(item)
		c.add_theme_font_size_override("font_size", 26)
		c.add_theme_color_override("font_color", BONE)
		c.add_theme_color_override("font_disabled_color", DIM)
		c.focus_mode = Control.FOCUS_NONE
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
		var n := _label("", 26, GOLD)
		row.add_child(n)
		v.add_child(row)
		_checks[item] = c
		_counts[item] = n
	_info = _label("", 20, DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_info)
	var go := Button.new()
	go.text = "출발"
	go.add_theme_font_override("font", _roman)
	go.add_theme_font_size_override("font_size", 40)
	go.add_theme_color_override("font_color", BONE)
	go.add_theme_color_override("font_hover_color", Color.WHITE)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color8(150, 18, 16)
	gs.set_content_margin_all(14)
	go.add_theme_stylebox_override("normal", gs)
	var gh := gs.duplicate() as StyleBoxFlat
	gh.bg_color = Color8(190, 28, 22)
	go.add_theme_stylebox_override("hover", gh)
	go.add_theme_stylebox_override("focus", gh)
	go.pressed.connect(_go)
	v.add_child(go)
	var test := HBoxContainer.new()                        # 결제 연결 전 테스트 지급 (PRD 4.15 테스트 모드)
	test.add_theme_constant_override("separation", 10)
	test.add_child(_label("[테스트 지급]", 18, DIM))
	for pack in Inventory.PACKS:
		var b := Button.new()
		b.text = Inventory.PACKS[pack]["name"]
		b.add_theme_font_size_override("font_size", 18)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): Inventory.grant_pack(pack); _refresh())
		test.add_child(b)
	v.add_child(test)
	_refresh()
	go.grab_focus()


func _desc(item: String) -> String:
	return {"knife_plus": "칼 +1 (최대 2)", "ammo_start_pack": "예비탄 7발", "bonfire": "375m 부터 시작", "danger_sense": "매복·광전사 1초 전 경고"}.get(item, "")


func _refresh() -> void:
	for item in _checks:
		var n := Inventory.count(item)
		_counts[item].text = "×%d" % n
		_checks[item].disabled = n <= 0
		if n <= 0:
			_checks[item].button_pressed = false
	_info.text = "달리는 중:  1 광란의 10초 ×%d   ·   2 보급 신호탄 ×%d          YOU DIED 화면:  부활 ×%d" % [
		Inventory.count("frenzy_30"), Inventory.count("flare_supply"), Inventory.count("revive")]
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
