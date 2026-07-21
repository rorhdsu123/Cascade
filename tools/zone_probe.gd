extends SceneTree
# 절대점수 존('밤하늘 상승') 검증 — 실제 파이프라인:
#   _add_endless_score → _zone_for 엣지 → zone_trans_t 발화 → zone_col 이산 스텝 → 여백·상하단바 전환.
#   존1~4 + 프리스티지의 배경색이 뚜렷이 구분되는지 + 전이 비트(링+숫자)가 뜨는지 창 모드 캡처.
# [[godot-pixel-verify-needs-window]] 렌더는 창 필수.  [[zoom-renders-to-judge-ui]] 확대 크롭으로 판단.

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-endless/0e8b8933-2b28-4c7a-b4cc-198df21b86e0/scratchpad/"

func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _shot(name: String) -> void:
	if _headless():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _tick(g: Node, frames: int) -> void:
	for _i in range(frames):
		g.call("_process", 1.0 / 60.0)
	g.call("queue_redraw")

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	g.call("_start_endless")
	await process_frame
	var guard: int = 0
	while not g.get("game_over") and guard < 30:
		guard += 1
		while g.get("resolving"):
			g.call("_process", 0.05)
		if g.get("game_over"):
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.set("sel", mv["slot"]); g.set("hover_col", mv["col"]); g.set("hover_row", mv["row"])
		g.call("_place_piece")
	while g.get("resolving"):
		g.call("_process", 0.05)

	g.set_process(false)
	g.set_physics_process(false)
	g.set("mode", "play")
	g.set("game_over", false)
	g.set("endless_best", 0)   # 첫 판(발화 없음) — 존은 절대점수라 그래도 계단 밟혀야 함

	var targets: Array = [
		{"n": "zone1_5k",    "score": 5000},
		{"n": "zone2_13k",   "score": 13000},
		{"n": "zone3_31k",   "score": 31000},
		{"n": "zone4_66k",   "score": 66000},
		{"n": "zone5_prest", "score": 131000},
	]
	for t in targets:
		# 리셋 후 실제 가산으로 존 크로싱 발화
		g.set("endless_score", 0)
		g.set("zone_index", 0)
		g.set("zone_mix", 0.0)
		g.set("zone_col", g.get("C_BG_PB"))
		g.set("zone_trans_t", -1.0)
		g.call("_add_endless_score", int(t["score"]))
		# 전이 초입(링+숫자) 캡처
		_tick(g, 7)
		await _shot(t["n"] + "_beat.png")
		# 정착(배경색) 캡처
		_tick(g, 100)
		var mrg = g.get("zone_col")
		print("%s: zone_index=%d zone_mix=%.2f zone_col=%s" % [
			t["n"], g.get("zone_index"), g.get("zone_mix"), str(mrg)])
		await _shot(t["n"] + "_set.png")
	print("DONE")
	quit()

func _best_move(g: Node) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1e9
	for slot in range(3):
		if g.tray[slot].is_empty():
			continue
		var offsets: Array = g.tray[slot]["offsets"]
		for r in range(g.ROWS):
			for c in range(g.COLS):
				var cells: Array = []
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS or g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var filled: int = 0
				for rr in range(g.ROWS):
					for ccx in range(g.COLS):
						if g.board[rr][ccx] != "":
							filled += 1
				var sc: float = -float(filled)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best
