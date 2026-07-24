extends SceneTree
# 부활 소프트락 수정 확인 (일회성) — 거점사마다 _revive() 호출 후:
#   ① 불변식 spawned==killed+leaked+onboard(gen0) 유지되나
#   ② 부활 뒤 게임이 정상 종료(win/loss)되나 = 소프트락(guard 소진) 없나
# 부활은 판당 1회라, 부활 후 또 죽으면 그냥 진행(정상 패배 가능). 소프트락이면 guard가 소진된다.

const TRIALS: int = 800
const STAGE: int = 3

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	var revived: int = 0
	var softlocks: int = 0
	var inv_breaks: int = 0
	var wins: int = 0
	for t in range(TRIALS):
		var r: Dictionary = _play(g)
		if r["revived"]: revived += 1
		if r["softlock"]: softlocks += 1
		if r["inv_break"]: inv_breaks += 1
		if r["win"]: wins += 1
	print("부활 발생 %d판 | 소프트락 %d | 불변식위반 %d | 승 %d / %d" % [revived, softlocks, inv_breaks, wins, TRIALS])
	if softlocks == 0 and inv_breaks == 0 and revived > 0:
		print("✅ 부활 %d판 모두 소프트락·불변식위반 0 — 수정 확인" % revived)
	quit()

func _inv_break(g: Node) -> bool:
	var onboard: int = 0
	for e in g.enemies:
		if int(e.get("gen", 0)) == 0:
			onboard += 1
	return g.spawned != g.killed + g.leaked + onboard

func _play(g: Node) -> Dictionary:
	g._start_stage(STAGE)
	var guard: int = 0
	var revived: bool = false
	var inv_break: bool = false
	while guard < 2000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05); s += 1
		if _inv_break(g): inv_break = true
		if g.game_over:
			# 거점사(막힘 아님)면서 부활 미사용 → 이어하기
			if not g.stuck and not g.revive_used:
				g._revive()
				revived = true
				continue
			break   # 막힘사 or 이미 부활함 → 정상 종료
		if g.game_clear:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			# 놓을 곳 없음 → 다음 배치서 stuck 처리되게 한 번 더 진행 시도, 아니면 종료
			break
		g.sel = mv["slot"]; g.hover_col = mv["col"]; g.hover_row = mv["row"]
		g._place_piece()
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05); s2 += 1
	if _inv_break(g): inv_break = true
	var softlock: bool = (not g.game_over) and (not g.game_clear) and guard >= 2000
	return {"revived": revived, "softlock": softlock, "inv_break": inv_break, "win": g.game_clear}

func _best_move(g: Node) -> Dictionary:
	var best: Dictionary = {}
	var bs: float = -1e9
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
						ok = false; break
					if g.board[cc.y][cc.x] != "":
						ok = false; break
					cells.append(cc)
				if not ok:
					continue
				var sc: float = _score(g, cells, slot)
				if sc > bs:
					bs = sc; best = {"slot": slot, "col": c, "row": r}
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
			if not occ[r][c]: fr = false; break
		if fr: full_rows.append(r)
	for c in range(g.COLS):
		var fc: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]: fc = false; break
		if fc: full_cols.append(c)
	var lines: int = full_rows.size() + full_cols.size()
	var score: float = 500.0 * float(lines)
	var after: Array = []
	for r2 in range(g.ROWS):
		var row2: Array = []
		for c2 in range(g.COLS):
			var f: bool = occ[r2][c2]
			if full_rows.has(r2) or full_cols.has(c2): f = false
			row2.append(f)
		after.append(row2)
	for slot2 in range(3):
		if slot2 == slot or g.tray[slot2].is_empty(): continue
		if not _fits(g, after, g.tray[slot2]["offsets"]): score -= 900.0
	if lines > 0:
		var lanes: int = maxi(1, g.combo + 1)
		for e in g.enemies:
			for fc in full_cols:
				if absi(int(e["col"]) - int(fc)) < lanes: score += 120.0
			for fr in full_rows:
				if absi(int(e["row"]) - int(fr)) < lanes: score += 120.0
			for fc3 in full_cols:
				if int(e["col"]) == int(fc3): score += 8.0 * float(e["row"])
	var filled: int = 0
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if occ[r][c]: filled += 1
	score -= 2.0 * float(filled)
	return score

func _fits(g: Node, occ: Array, offsets: Array) -> bool:
	for r in range(g.ROWS):
		for c in range(g.COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
				if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS:
					ok = false; break
				if occ[cc.y][cc.x]:
					ok = false; break
			if ok: return true
	return false
