extends SceneTree
# featured 조각 분포 스윕(일회성). 보드-맹목 고정 트랙이 프리 무한 사망 프로필(거점사 지배)에
#   수렴하는 (p_big, p_mid)를 찾는다. 中봇 기준, 과녁 = 거점사 과반 + 깊이 프리 근처.
const N: int = 200
const GUARD: int = 3000
const P = preload("res://tools/featured_probe.gd")

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	var probe = P.new()
	print("\n#### featured 조각 분포 스윕 (中봇 · %d판/셀) ####" % N)
	print("p_big p_mid p_sml | 깊이  중앙 | 스타일 콤보 | 거점%  막힘%")
	print("------------------+------------+------------+-------------")
	var combos: Array = [
		[0.14, 0.56], [0.06, 0.50], [0.03, 0.42], [0.0, 0.42],
		[0.02, 0.34], [0.0, 0.30], [0.0, 0.22], [0.02, 0.50],
	]
	for cb in combos:
		var pb: float = cb[0]
		var pm: float = cb[1]
		var depths: Array = []
		var style_sum: float = 0.0
		var combo_sum: float = 0.0
		var dc: int = 0
		var ds: int = 0
		for t in range(N):
			g.TRACK_P_BIG = pb
			g.TRACK_P_MID = pm
			g.track_record = false
			g._start_featured(900000 + t)
			g.dda_enabled = false
			var r: Dictionary = probe._drive(g, 1, GUARD)
			depths.append(r["depth"])
			style_sum += r["style"]
			combo_sum += float(r["maxcombo"])
			if r["dead_core"]:
				dc += 1
			if r["dead_stuck"]:
				ds += 1
		depths.sort()
		var nn: float = float(N)
		var mean: float = 0.0
		for d in depths:
			mean += float(d)
		mean /= nn
		print("%.2f  %.2f  %.2f | %5.1f %4d | %6.0f %4.1f | %5.1f%% %5.1f%%" % [
			pb, pm, 1.0 - pb - pm, mean, int(depths[int(nn * 0.5)]),
			style_sum / nn, combo_sum / nn,
			100.0 * float(dc) / nn, 100.0 * float(ds) / nn])
	quit()
