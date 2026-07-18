extends SceneTree
# 무한모드 UI/점수 검증. 두 갈래:
#   ① 로직(점수) = 헤드리스로 봇 실플레이(창 OS 이벤트 간섭 없음 = 안정): godot --headless --script ...
#   ② 렌더(HUD·팝업) = 창 모드 + 상태 직접 세팅 후 스샷(전 판 구동은 창 OS 이벤트로 flaky): godot --script ...
# [[godot-pixel-verify-needs-window]] 렌더는 창 필수. 로직은 헤드리스 OK.

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-endless/d9711f36-7ab4-476a-9118-046b10970466/scratchpad/"

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

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	# ── ① 로직: 봇 실플레이로 점수 형성 확인(헤드리스에서 신뢰) ──
	g.call("_start_endless")
	await process_frame
	var guard: int = 0
	while not g.get("game_over") and guard < 600:
		guard += 1
		var s: int = 0
		while g.get("resolving") and s < 400:
			g.call("_process", 0.05)
			s += 1
		if g.get("game_over"):
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.set("sel", mv["slot"])
		g.set("hover_col", mv["col"])
		g.set("hover_row", mv["row"])
		g.call("_place_piece")
	var s3: int = 0
	while g.get("resolving") and s3 < 400:
		g.call("_process", 0.05)
		s3 += 1
	print("PLAY: score=%d depth=%d killed=%d best=%d new_best=%s over=%s stuck=%s" % [
		g.get("endless_score"), g.get("place_count"), g.get("killed"), g.get("endless_best"),
		str(g.get("endless_new_best")), str(g.get("game_over")), str(g.get("stuck"))])

	# ── ② 렌더: 상태 직접 세팅 후 스샷(창 모드에서만 저장) ──
	# 2a) 셀렉트 + '최고' 후크
	g.set("mode", "select")
	g.set("endless_best", 12340)
	g.call("queue_redraw")
	await _shot("ui_select.png")

	# 2b) 인게임 HUD — 최고 갱신(금색) 상태
	g.call("_start_endless")
	await process_frame
	g.set("endless_best", 8000)
	g.set("endless_score", 15230)
	g.set("endless_beat_best", true)   # score>best → 금색 '최고 갱신!'
	g.set("place_count", 52)
	g.set("combo", 4)
	g.set("mode", "play")
	g.call("queue_redraw")
	await _shot("ui_hud_beat.png")

	# 2c) 결과 팝업 — 신기록 + 델타
	g.set("game_over", true)
	g.set("stuck", true)
	g.set("stuck_t", g.call("_stuck_total"))
	g.set("endless_score", 15230)
	g.set("endless_best", 15230)
	g.set("endless_prev_best", 8000)
	g.set("endless_new_best", true)
	g.set("mode", "play")
	g.call("queue_redraw")
	await _shot("ui_result_best.png")
	print("DONE")
	quit()

# ── 그리디 봇 (regress.gd 복제) ──
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
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS:
						ok = false
						break
					if g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var sc: float = _score(g, cells, slot)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best

func _score(g: Node, cells: Array, slot: int) -> float:
	var occ: Array = []
	for r in range(g.ROWS):
		var row: Array = []
		for c in range(g.COLS):
			row.append(g.board[r][c] != "")
		occ.append(row)
	for ci in cells:
		var cv: Vector2i = ci as Vector2i
		occ[cv.y][cv.x] = true
	var full_rows: Array = []
	var full_cols: Array = []
	for r in range(g.ROWS):
		var fr: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				fr = false
				break
		if fr:
			full_rows.append(r)
	for c in range(g.COLS):
		var fcx: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				fcx = false
				break
		if fcx:
			full_cols.append(c)
	var lines: int = full_rows.size() + full_cols.size()
	var score: float = 500.0 * float(lines)
	var after: Array = []
	for r2 in range(g.ROWS):
		var row2: Array = []
		for c2 in range(g.COLS):
			var f: bool = occ[r2][c2]
			if full_rows.has(r2) or full_cols.has(c2):
				f = false
			row2.append(f)
		after.append(row2)
	var others: int = 0
	for slot2 in range(3):
		if slot2 == slot or g.tray[slot2].is_empty():
			continue
		others += 1
		if not _fits_anywhere(g, after, g.tray[slot2]["offsets"]):
			score -= 900.0
	if others == 0:
		var free: int = 0
		for r3 in range(g.ROWS):
			for c3 in range(g.COLS):
				if not after[r3][c3]:
					free += 1
		if free < 12:
			score -= 300.0
	if lines > 0:
		var lanes: int = maxi(1, g.combo + 1)
		var hit: int = 0
		for e in g.enemies:
			var in_band: bool = false
			for fc2 in full_cols:
				if absi(int(e["col"]) - int(fc2)) < lanes:
					in_band = true
			for fr2 in full_rows:
				if absi(int(e["row"]) - int(fr2)) < lanes:
					in_band = true
			if in_band:
				hit += 1
		score += 120.0 * float(hit)
	var filled: int = 0
	var holes: int = 0
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if occ[r][c]:
				filled += 1
			else:
				var nb: int = 0
				if r == 0 or occ[r - 1][c]:
					nb += 1
				if r == g.ROWS - 1 or occ[r + 1][c]:
					nb += 1
				if c == 0 or occ[r][c - 1]:
					nb += 1
				if c == g.COLS - 1 or occ[r][c + 1]:
					nb += 1
				if nb == 4:
					holes += 1
	var fill_frac: float = float(filled) / float(g.ROWS * g.COLS)
	score -= 60.0 * fill_frac * fill_frac * float(g.ROWS * g.COLS) / 10.0
	score -= 70.0 * float(holes)
	return score

func _fits_anywhere(g: Node, occ: Array, offsets: Array) -> bool:
	for r in range(g.ROWS):
		for c in range(g.COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var x: int = c + ov.x
				var y: int = r + ov.y
				if x < 0 or x >= g.COLS or y < 0 or y >= g.ROWS or occ[y][x]:
					ok = false
					break
			if ok:
				return true
	return false
