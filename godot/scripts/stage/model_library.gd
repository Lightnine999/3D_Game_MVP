# 모델 이름 → 파일 경로 찾기 — 주인: A
#
# 비유: 도서관 색인 카드. 책(모델)이 어느 서가(카테고리 폴더)에 있든 제목(이름)만 알면 찾아 준다.
# 그래서 폴더를 다시 정리해도 배치 코드(_spawn("v2_house_a") 등)는 고칠 필요가 없다.
#
# 폴더 규칙 (godot/assets/models/)
#   trees/     나무·그루터기          vehicles/  폐차·버스·트럭
#   house/     폐가·판잣집·폐허       props/     드럼통·상자·잔해·표지판·다리·성벽 등 나머지
class_name ModelLibrary
extends RefCounted

const ROOT := "res://assets/models/"
const CATEGORIES := ["trees", "vehicles", "house", "props"]

static var _cache := {}


static func path(model_name: String) -> String:
	if _cache.has(model_name):
		return _cache[model_name]
	for c in CATEGORIES:
		var p: String = ROOT + c + "/" + model_name + ".glb"
		if ResourceLoader.exists(p):
			_cache[model_name] = p
			return p
	push_error("[ModelLibrary] 모델을 찾을 수 없음: " + model_name)
	return ""
