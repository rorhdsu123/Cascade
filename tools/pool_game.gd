extends "res://Main.gd"
# 조각 풀 실험용 서브클래스 — Main.gd는 무수정. _random_piece만 실험 풀로 제한한다.
#   목적: 스테이지 난이도를 '조각 분포'로 만들 수 있는지 sim으로 검증(디펜스 축 → 퍼즐 축 전환 가설).
#   공정성: 원본과 동일하게 '지금 보드에 최소 1칸 놓이는 조각'만 배급(강제 즉사 draw 배제).
#   ⚠ dda_enabled=false로 쓸 것 — _make_piece가 이 override를 그대로 통과시킨다.

var test_pool: Array = []      # 허용 조각 키 목록
var test_w: Dictionary = {}    # 키 → 가중치(없으면 1)

func _random_piece() -> Dictionary:
	var fit: Array = []
	for t in test_pool:
		if _piece_fits_at_least(PIECES[t], 1):
			fit.append(t)
	if fit.is_empty():
		fit = test_pool   # 아무것도 안 맞음 → 다음 턴 막힘 판정(정당한 stuck 사망)
	var total: int = 0
	for t in fit:
		total += int(test_w.get(t, 1))
	var r: int = randi() % maxi(1, total)
	var ty: String = fit[fit.size() - 1]
	for t in fit:
		r -= int(test_w.get(t, 1))
		if r < 0:
			ty = t
			break
	var c: String = COLORS[randi() % COLORS.size()]
	return {"type": ty, "color": c, "offsets": (PIECES[ty] as Array).duplicate()}
