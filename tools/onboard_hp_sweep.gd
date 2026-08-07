extends SceneTree
# 온보딩 절벽 스윕 — 판 하나 × core_hp 하나를 N판 돌려 한 줄만 출력하고 종료.
#   `godot --headless --script tools/onboard_hp_sweep.gd -- <stage_idx0> <core_hp> [trials]`
#   개별 프로세스라 quit() 즉시 flush(버퍼링 회피) + 교착 격리(한 config가 걸려도 나머지 진행).
#   봇/스코어는 campaign_probe와 동형(인라인 복사). guard 500(롱게임 교착 상한 축소).

const GUARD: int = 500

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var si: int = int(a[0])
	var hp: int = int(a[1])
	var trials: int = int(a[2]) if a.size() > 2 else 80
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	# ⚠_ready가 persist_enabled를 켠다. 이 하네스는 판을 이기므로 안 끄면 실유저 진행도에 각인된다
	#   (regress에서 실제로 겪은 사고와 같은 경로 — S1에서 그쪽은 막았고 여기가 남아 있었다).
	g.set("persist_enabled", false)
	g.dda_enabled = false   # 실패 케어(S4)도 이 스위치에 물려 있다 → 순수 난이도만 잰다
	var wins: int = 0
	var dead_core: int = 0
	var dead_stuck: int = 0
	for t in range(trials):
		var r: Dictionary = _play(g, si, hp)
		if r["win"]:
			wins += 1
		if r["dead_core"]:
			dead_core += 1
		if r["dead_stuck"]:
			dead_stuck += 1
	var n: float = float(trials)
	print(" %d |    %d    | %5.1f%% |  %3d   | %3d" % [
		si + 1, hp, 100.0 * float(wins) / n, dead_core, dead_stuck])
	quit()

func _play(g: Node, si: int, hp: int) -> Dictionary:
	g._start_stage(si)
	g.core_hp = hp            # STAGES는 const라 런타임 변수를 덮어씀(누수사 판정이 쓰는 값). st["core_hp"]는 DDA off·헤드리스라 무영향
	g.core_hp_vis = float(hp)
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < GUARD:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		var s3: int = 0
		while g.resolving and s3 < 400:
			g._process(0.05)
			s3 += 1
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

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
		var fc: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				fc = false
				break
		if fc:
			full_cols.append(c)
	var lines: int = full_rows.size() + full_cols.size()
	var score: float = 0.0
	score += 500.0 * float(lines)
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
		for e in g.enemies:
			for fc3 in full_cols:
				if int(e["col"]) == int(fc3):
					score += 8.0 * float(e["row"])
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
	var touch: int = 0
	for ci2 in cells:
		var cv2: Vector2i = ci2 as Vector2i
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cv2.x + d.x
			var ny: int = cv2.y + d.y
			if nx < 0 or nx >= g.COLS or ny < 0 or ny >= g.ROWS:
				touch += 1
			elif g.board[ny][nx] != "":
				touch += 1
	score += 4.0 * float(touch)
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
