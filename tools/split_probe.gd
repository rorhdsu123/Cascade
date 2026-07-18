extends SceneTree
# 분열(split) 적 난이도-형태 검증 (일회성 — 검증 후 삭제).
#   질문:
#     Q1. split 비율↑ → 승률 단조 하강? (baseline=0% split 대비 절대 안 쉬워져야 = swarm 함정 회피)
#     Q2. split이 방어축(거점사)으로 압박하나? (자식이 거점 코앞에서 갈라져 누수)
#     Q3. core_hp를 조일 때도 단조 유지? (레버로 성립)
#   설계: 자식(gen1)은 spawned/killed/leaked 카운터 밖 = 순수 추가 위협 → 웨이브 총량 불변.
#   실행: godot --headless --path . --script tools/split_probe.gd

const SplitGame = preload("res://Main.gd")
const StageMode = preload("res://modes/stage_mode.gd")
const TRIALS: int = 200

# clean 풀(pool_probe에서 복제) — 조각은 상수, 오직 적 믹스만 변수.
const PKEYS: Array = ["1","D2h","D2v","I3h","I3v","L3a","L3b","L3c","L3d","O","I","Iv","T","S","Z","L","J","I5h","I5v","R32","R23","R33"]
const PW: Dictionary = {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4,"O":6,"I":4,"Iv":4,"T":4,"S":3,"Z":3,"L":4,"J":4,"I5h":10,"I5v":10,"R32":7,"R23":7,"R33":1}

# split 비율 스윕: basic을 split으로 점진 대체(총 100 유지 = 다른 변수 불변).
const MIXES: Array = [
	{"name": "split  0% (baseline)", "basic": 100, "split": 0},
	{"name": "split 25%           ", "basic": 75,  "split": 25},
	{"name": "split 50%           ", "basic": 50,  "split": 50},
	{"name": "split 75%           ", "basic": 25,  "split": 75},
	{"name": "split 100%          ", "basic": 0,   "split": 100},
]

func _make_st(core_hp: int, mix: Dictionary) -> Dictionary:
	var pool: Dictionary = {}
	for k in PKEYS:
		pool[k] = int(PW.get(k, 1))
	return {
		"total": 30, "core_hp": core_hp,
		"base_hp": 30, "hp_ramp": 0.3, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 4, "floor": 5, "surge_at": 0.0,
		"weights": {"basic": int(mix["basic"]), "fast": 0, "tank": 0, "swarm": 0, "split": int(mix["split"])},
		"pool": pool,
	}

func _init() -> void:
	print("── SPLIT PROBE (clean pool, total=30, step=3, N=%d) ──" % TRIALS)
	print("적 = basic↔split 대체만 변수. Q1=단조 Q2=방어축(거점사) Q3=core_hp 단조")
	for core_hp in [3, 2]:
		print("\n######## core_hp=%d (허용 누수 %d회) ########" % [core_hp, core_hp - 1])
		print("mix                  | 승률   | 누수/판 | 거점사 | 막힘사 | 처치/판 | 최대콤보 | 클리어율")
		print("---------------------+--------+---------+--------+--------+---------+----------+---------")
		for mix in MIXES:
			_run_mix(mix, core_hp)
	quit()

func _run_mix(mix: Dictionary, core_hp: int) -> void:
	var g = SplitGame.new()
	root.add_child(g)
	g.dda_enabled = false
	var st: Dictionary = _make_st(core_hp, mix)

	var wins: int = 0
	var leak_sum: int = 0
	var dead_core: int = 0
	var dead_stuck: int = 0
	var place_sum: int = 0
	var clear_sum: int = 0
	var kill_sum: int = 0
	var maxcombo_sum: int = 0
	seed(90210)
	for t in range(TRIALS):
		var r: Dictionary = _play(g, st)
		if r["win"]:
			wins += 1
		leak_sum += r["leaked"]
		place_sum += r["places"]
		clear_sum += r["clears"]
		kill_sum += r["killed"]
		maxcombo_sum += r["maxcombo"]
		if r["dead_core"]:
			dead_core += 1
		if r["dead_stuck"]:
			dead_stuck += 1
	var n: float = float(TRIALS)
	var crate: float = 0.0 if place_sum == 0 else 100.0 * float(clear_sum) / float(place_sum)
	print("%s | %5.1f%% |  %5.2f  |  %4.1f%% |  %4.1f%% |  %5.1f  |   %4.2f   |  %4.1f%%" % [
		mix["name"], 100.0 * float(wins) / n, float(leak_sum) / n,
		100.0 * float(dead_core) / n, 100.0 * float(dead_stuck) / n,
		float(kill_sum) / n, float(maxcombo_sum) / n, crate])
	g.free()

func _play(g, st: Dictionary) -> Dictionary:
	g.st = st
	g.director = StageMode.new(st)
	g.mode = "play"
	g._init_game()
	var maxcombo: int = 0
	var places: int = 0
	var clears: int = 0
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
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
		var before: int = g.combo
		g._place_piece()
		places += 1
		if g.resolving or g.combo > before:
			clears += 1
		if g.combo > maxcombo:
			maxcombo = g.combo
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "leaked": g.leaked, "killed": g.killed, "places": places, "clears": clears,
		"maxcombo": maxcombo,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# ───────── 그리디 봇 (pool_probe.gd에서 복제, g의 public 표면만 읽음) ─────────
func _best_move(g) -> Dictionary:
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

func _score(g, cells: Array, slot: int) -> float:
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

func _fits_anywhere(g, occ: Array, offsets: Array) -> bool:
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
