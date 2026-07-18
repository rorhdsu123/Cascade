extends SceneTree
# 무한모드 UI 배선 검증 — 창 모드 필수(headless는 렌더텍스처 null, [[godot-pixel-verify-needs-window]]).
# 셀렉트(무한 버튼)·인게임 HUD(점수·깊이)·결과 팝업(점수·베스트) 3장 스크린샷 + 봇 실플레이로 점수 증가 확인.
# 실행: godot --path . --script tools/endless_ui_probe.gd

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-endless/d9711f36-7ab4-476a-9118-046b10970466/scratchpad/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(DIR + name)

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	# ① 셀렉트 화면(기본) — 무한 버튼 렌더 확인
	g.call("queue_redraw")
	await _shot("ui_select.png")

	# ② 무한 시작 후 봇으로 실플레이 — 점수/깊이 증가 확인
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
		# HUD 스냅샷 한 번(중반, 점수 쌓였을 때)
		if guard == 40:
			var s2: int = 0
			while g.get("resolving") and s2 < 400:
				g.call("_process", 0.05)
				s2 += 1
			g.call("queue_redraw")
			await _shot("ui_hud.png")
			print("MID: score=%d depth=%d killed=%d combo=%d" % [
				g.get("endless_score"), g.get("place_count"), g.get("killed"), g.get("combo")])
	# 잔여 resolve 소화
	var s3: int = 0
	while g.get("resolving") and s3 < 400:
		g.call("_process", 0.05)
		s3 += 1
	# 죽음 연출 스킵 + 팝업 표시 강제(창 모드 OS 이벤트가 mode를 흔들 수 있어 probe에서 고정)
	if g.get("stuck"):
		g.set("stuck_t", g.call("_stuck_total"))
	else:
		g.set("core_t", g.call("_core_total"))
	g.set("mode", "play")
	await process_frame
	g.set("mode", "play")   # 창 모드 OS 이벤트가 mode를 흔들 수 있어 재고정(실플레이 무관)
	g.call("queue_redraw")
	await _shot("ui_result.png")
	print("END: score=%d depth=%d best=%d new_best=%s over=%s stuck=%s" % [
		g.get("endless_score"), g.get("place_count"), g.get("endless_best"),
		str(g.get("endless_new_best")), str(g.get("game_over")), str(g.get("stuck"))])
	print("DONE")
	quit()

# ── 그리디 봇 (regress.gd에서 복제, public 표면만 읽음) ──
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
