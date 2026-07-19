extends SceneTree
# featured 결정적 트랙 창 스모크 — 진입/렌더가 실제 창에서 파싱·런타임 에러 없이 도는가.
#   렌더 경로는 무한 HUD/결과 재사용(C57·C58 픽셀검증 완료)이라 여기선 '깨지지 않고 뜨는가'만 본다.
#   [[godot-pixel-verify-needs-window]] 창 필수: godot --path . --script tools/featured_shot.gd
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

	g.call("_start_featured", 20260719)   # 오늘의 시드로 진입
	await process_frame
	print("ENTER: featured=%s endless=%s mode=%s director=%s hp=%d" % [
		str(g.get("featured")), str(g.get("endless")), g.get("mode"),
		g.get("director").get_script().resource_path.get_file(), g.get("core_hp")])

	# 몇 수 두어 점수·보드·적을 형성(HUD가 채워진 상태로 스샷)
	var placed: int = 0
	while placed < 40 and not g.get("game_over"):
		var s: int = 0
		while g.get("resolving") and s < 200:
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
		placed += 1
	var s3: int = 0
	while g.get("resolving") and s3 < 200:
		g.call("_process", 0.05)
		s3 += 1
	await process_frame
	await _shot("featured_hud.png")
	print("PLAY: featured=%s depth=%d score=%d killed=%d enemies=%d over=%s" % [
		str(g.get("featured")), g.get("place_count"), g.get("endless_score"),
		g.get("killed"), g.get("enemies").size(), str(g.get("game_over"))])
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
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS:
						ok = false
						break
					if g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var lines: int = _count_lines(g, cells)
				var sc: float = 500.0 * float(lines) - 2.0 * float(r + c)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best

func _count_lines(g: Node, cells: Array) -> int:
	var occ: Dictionary = {}
	for ci in cells:
		occ[ci] = true
	var n: int = 0
	for r in range(g.ROWS):
		var fr: bool = true
		for c in range(g.COLS):
			if g.board[r][c] == "" and not occ.has(Vector2i(c, r)):
				fr = false
				break
		if fr:
			n += 1
	for c in range(g.COLS):
		var fc: bool = true
		for r in range(g.ROWS):
			if g.board[r][c] == "" and not occ.has(Vector2i(c, r)):
				fc = false
				break
		if fc:
			n += 1
	return n
