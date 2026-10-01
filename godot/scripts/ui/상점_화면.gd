extends Control

signal back_requested

const Catalog = preload("res://scripts/services/게임_상품_표시.gd")
var _auth: ServiceAuth
var _api: ServiceAPI
var _payment: Node
var _status: Label
var _inventory: Label
var _product_detail: Label
var _checkout_button: Button
var _selected_product := "pack_one_more"
var _cards: GridContainer
var _inventory_request := 0
var _catalog_ready := false
var _buying := false

func setup(auth_client: ServiceAuth, api_client: ServiceAPI, payment_client: Node) -> void:
	_auth = auth_client
	_api = api_client
	_payment = payment_client

func set_catalog_ready(ready: bool) -> void:
	_catalog_ready = ready
	if _payment is ServicePayment:
		_payment.set_catalog_ready(ready)
	if is_node_ready():
		_refresh_purchase_state()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := TextureRect.new()
	background.texture = Catalog.texture("res://assets/ui/로그인_배경.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.012, 0.02, 0.03, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var heading := _label("테스트 상점", 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var back := _button("타이틀로", back_requested.emit)
	back.name = "BackToTitle"
	header.add_child(back)
	var notice := _label("테스트 결제입니다. 실제 돈이 나가지 않습니다", 18)
	notice.name = "TestPaymentNotice"
	layout.add_child(notice)
	var scroll := ScrollContainer.new()
	scroll.name = "ShopScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	column.add_child(_label("구매 없이도 게임을 플레이할 수 있습니다. 구성품의 게임 내 사용·효과 적용은 아직 제공하지 않습니다.", 17))
	_cards = GridContainer.new()
	_cards.name = "PackageCards"
	_cards.columns = 3
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	column.add_child(_cards)
	for product in Catalog.PRODUCTS:
		_add_card(product)
	_product_detail = _label("", 18)
	_product_detail.name = "ProductDetail"
	column.add_child(_product_detail)
	_checkout_button = _button("패키지 테스트 결제 · 서버 배포 대기", _buy_selected)
	_checkout_button.name = "BuySelected"
	column.add_child(_checkout_button)
	_status = _label("", 17)
	_status.name = "ShopStatus"
	column.add_child(_status)
	_inventory = _label("보유 수량 미확인", 17)
	_inventory.name = "InventoryStatus"
	column.add_child(_inventory)
	column.add_child(_button("보유 수량 확인", _refresh_inventory))
	resized.connect(_adapt_layout)
	_adapt_layout()
	_select_product(_selected_product)
	_refresh_purchase_state()
	_refresh_inventory()

func _add_card(product: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = str(product.id)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("30291e") if product.featured else Color("15232a")
	style.border_color = Color("edbd68") if product.featured else Color("52636a")
	style.set_border_width_all(3 if product.featured else 1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	_cards.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	body.add_child(_label("메인 패키지" if product.featured else "패키지", 16))
	body.add_child(_label(product.name, 22))
	var art := TextureRect.new()
	art.name = "PackageArt"
	art.texture = Catalog.texture(product.art)
	art.custom_minimum_size.y = 160
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(art)
	body.add_child(_label(product.contents, 17))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var button := _button(product.price_text + " · 구성 선택", func() -> void: _select_product(product.id))
	button.name = product.button
	body.add_child(button)

func _adapt_layout() -> void:
	if _cards != null:
		_cards.columns = 3 if size.x >= 900 else 1

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("eee3d7"))
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	return button

func _refresh_purchase_state() -> void:
	var valid_key := _payment is ServicePayment and not str(_payment.get("_client_key")).is_empty()
	var blockers := Catalog.purchase_blockers(OS.get_name(), Engine.has_singleton("TossGamePayments"), valid_key, _auth != null and _auth.has_remote_session(), _catalog_ready)
	_checkout_button.disabled = _buying or not blockers.is_empty() or _payment == null or not _payment.can_purchase()
	_checkout_button.text = "패키지 테스트 결제" if _catalog_ready else "패키지 테스트 결제 · 서버 배포 대기"
	_status.text = blockers if not blockers.is_empty() else "Android SDK 테스트 결제 준비됨 · 버튼을 눌러 주문합니다."

func _select_product(product_id: String) -> void:
	var product: Dictionary = Catalog.product(product_id)
	if product.is_empty():
		return
	_selected_product = product_id
	_product_detail.text = "선택: %s · %s\n%s\n구성 안내만 제공하며 보유·지급·게임 적용을 의미하지 않습니다." % [product.name, product.price_text, product.contents]

func _buy_selected() -> void:
	_refresh_purchase_state()
	if _checkout_button.disabled:
		return
	_buying = true
	var owner := _auth.get_user_id()
	var epoch := _auth._session_epoch
	_refresh_purchase_state()
	_status.text = "테스트 결제 확인 중…"
	var result: Dictionary = await _payment.start_purchase(_selected_product)
	_buying = false
	_refresh_purchase_state()
	if owner != _auth.get_user_id() or epoch != _auth._session_epoch or not _auth.has_remote_session():
		_status.text = "계정이 변경되어 결제 결과를 표시하지 않습니다."
		return
	if result.get("ok", false) and result.get("status") == "paid":
		_status.text = "서버 결제 승인·구성품 보유 조회 확인 완료. 게임 내 효과는 적용하지 않습니다."
		await _refresh_inventory()
	else:
		_status.text = "결제 완료 미확인 (%s). 재결제 전 서버 주문 상태를 확인해 주세요." % str(result.get("error", "unknown"))

func _refresh_inventory() -> void:
	_inventory_request += 1
	var request := _inventory_request
	if _auth == null or not _auth.has_remote_session():
		_inventory.text = "보유 수량 미확인 · 온라인 계정이 필요합니다."
		return
	if _api == null:
		_inventory.text = "보유 수량 미확인 · 조회 서비스를 사용할 수 없습니다."
		return
	var owner := _auth.get_user_id()
	var epoch := _auth._session_epoch
	_inventory.text = "서버 구성품 보유 수량 확인 중…"
	var names: Dictionary = Catalog.ITEM_NAMES
	var parts: Array[String] = []
	for item_id in names:
		var response: Dictionary = await _api.fetch_inventory_item(item_id)
		if request != _inventory_request:
			return
		if not _auth.has_remote_session() or owner != _auth.get_user_id() or epoch != _auth._session_epoch:
			_inventory.text = "계정이 변경되어 보유 수량 미확인 · 다시 확인해 주세요."
			return
		var item: Variant = response.get("item", {})
		var quantity: Variant = item.get("quantity") if item is Dictionary else null
		if response.get("ok", false) and item is Dictionary and item.get("item_id") == item_id and typeof(quantity) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(quantity)) and quantity >= 0 and quantity == int(quantity):
			parts.append("%s: %s개" % [names[item_id], int(quantity)])
		else:
			parts.append("%s: 조회 실패 (보유 수량 미확인)" % names[item_id])
	_inventory.text = "서버 구성품 보유 수량 · " + " / ".join(parts) + "\n패키지 소유 수량이나 거래 내역이 아닙니다. 게임 내 사용·효과 적용은 아직 제공하지 않습니다."
