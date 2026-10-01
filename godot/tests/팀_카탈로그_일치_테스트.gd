extends SceneTree
const Catalog = preload("res://scripts/services/게임_상품_표시.gd")
func _initialize() -> void:
	var failed := false
	for id in Inventory.PACKS:
		if Catalog.COMPONENTS.get(id) != Inventory.PACKS[id].items or Catalog.product(id).price != Inventory.PACKS[id].price:
			printerr("FAIL team recipe: ", id)
			failed = true
	if Catalog.ITEM_NAMES.size() != Inventory.ITEMS.size() or Catalog.ITEM_NAMES.get("frenzy_30") != "광란의 15초":
		printerr("FAIL canonical IDs/name")
		failed = true
	print("TEAM_CATALOG: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
