extends SceneTree
# 조각 풀 = 스테이지 난이도 손잡이 가설 검증.
#   적은 전부 basic으로 고정 → 오직 '조각 분포'만 변수. 풀별 승률·패배사유·누수·콤보 비교.
#   핵심 질문:
#     Q1. 작은-조각 풀(small-tempo)이 '빠른 적' 없이 템포 압박(누수·거점사)을 만드나?
#     Q2. 삐뚤 풀(awkward)이 막힘사(stuck)를 실제로 올리나? (퍼즐 사망문 겨냥)
#     Q3. 일자없음(no-straights)이 줄 완성을 굶겨 거점사를 올리나?
#     Q4. 각 풀이 core_hp를 조일 때 단조롭게 어려워지나? (step_every 절벽·spawn_every 비단조 재판 방지)
#   실행: godot --headless --path . --script tools/pool_probe.gd

const PoolGame = preload("res://Main.gd")   # 실코드 경로 직접 구동(_random_piece가 st["pool"]을 읽음)
const StageMode = preload("res://modes/stage_mode.gd")
const TRIALS: int = 120

# ── 실험 풀 정의(조각 키는 Main.PIECES 기준) ──
# 혼합 풀 스윕(C51 ⑥): small-tempo(=5% 벽)에 line-maker(I5)를 비율로 섞어
#   승률을 벽→dial로 끌어올릴 수 있나 검증. small 기본 가중합=35, I5 총가중 lm으로
#   line-maker 비율 p = lm/(35+lm). 양끝 앵커(clean=76% 천장, small=5% 바닥) 유지.
const SMK: Array = ["1","D2h","D2v","I3h","I3v","L3a","L3b","L3c","L3d"]
const SMK5: Array = ["1","D2h","D2v","I3h","I3v","L3a","L3b","L3c","L3d","I5h","I5v"]
const POOLS: Array = [
	{"name": "clean       ", "keys": ["1","D2h","D2v","I3h","I3v","L3a","L3b","L3c","L3d","O","I","Iv","T","S","Z","L","J","I5h","I5v","R32","R23","R33"],
		"w": {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4,"O":6,"I":4,"Iv":4,"T":4,"S":3,"Z":3,"L":4,"J":4,"I5h":10,"I5v":10,"R32":7,"R23":7,"R33":1}},
	{"name": "small  (0%) ", "keys": SMK,
		"w": {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4}},
	{"name": "sm+I5  10%  ", "keys": SMK5,   # lm=4  → p≈0.103
		"w": {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4,"I5h":2,"I5v":2}},
	{"name": "sm+I5  19%  ", "keys": SMK5,   # lm=8  → p≈0.186
		"w": {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4,"I5h":4,"I5v":4}},
	{"name": "sm+I5  34%  ", "keys": SMK5,   # lm=18 → p≈0.340
		"w": {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4,"I5h":9,"I5v":9}},
	{"name": "sm+I5  50%  ", "keys": SMK5,   # lm=35 → p=0.500
		"w": {"1":1,"D2h":3,"D2v":3,"I3h":6,"I3v":6,"L3a":4,"L3b":4,"L3c":4,"L3d":4,"I5h":17,"I5v":18}},
]

func _make_st(core_hp: int) -> Dictionary:
	# basic-only, 서지 없음. 조각 외 변수 제거.
	return {
		"total": 30, "core_hp": core_hp,
		"base_hp": 30, "hp_ramp": 0.0, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 999, "floor": 5, "surge_at": 0.0,
		"weights": {"basic": 100, "fast": 0, "tank": 0, "swarm": 0},
	}

func _init() -> void:
	print("── POOL PROBE (basic-only, total=30, step=3, N=%d) ──" % TRIALS)
	print("적은 전부 basic. 오직 조각 풀만 변수. Q1=템포 Q2=막힘 Q3=줄굶김 Q4=단조성")
	for core_hp in [3, 2]:
		print("\n######## core_hp=%d (허용 누수 %d회) ########" % [core_hp, core_hp - 1])
		print("pool         | 승률   | 누수/판 | 거점사 | 막힘사 | 배치/판 | 최대콤보 | 클리어율")
		print("-------------+--------+---------+--------+--------+---------+----------+---------")
		for pool in POOLS:
			_run_pool(pool, core_hp)
	quit()

func _run_pool(pool: Dictionary, core_hp: int) -> void:
	var g = PoolGame.new()
	root.add_child(g)          # _ready
	g.dda_enabled = false
	var wd: Dictionary = {}    # keys 순서 보존(추첨 iteration 순서 = 재현성)
	for k in pool["keys"]:
		wd[k] = int(pool["w"].get(k, 1))
	var st: Dictionary = _make_st(core_hp)
	st["pool"] = wd

	var wins: int = 0
	var leak_sum: int = 0
	var dead_core: int = 0
	var dead_stuck: int = 0
	var place_sum: int = 0
	var clear_sum: int = 0
	var maxcombo_sum: int = 0
	seed(90210)                # 풀 간 동일 시드(초기 스폰 정렬; 조각 소비로 곧 desync되나 재현성 확보)
	for t in range(TRIALS):
		var r: Dictionary = _play(g, st)
		if r["win"]:
			wins += 1
		leak_sum += r["leaked"]
		place_sum += r["places"]
		clear_sum += r["clears"]
		maxcombo_sum += r["maxcombo"]
		if r["dead_core"]:
			dead_core += 1
		if r["dead_stuck"]:
			dead_stuck += 1
	var n: float = float(TRIALS)
	var crate: float = 0.0 if place_sum == 0 else 100.0 * float(clear_sum) / float(place_sum)
	print("%s | %5.1f%% |  %5.2f  |  %4.1f%% |  %4.1f%% |  %5.1f  |   %4.2f   |  %4.1f%%" % [
		pool["name"], 100.0 * float(wins) / n, float(leak_sum) / n,
		100.0 * float(dead_core) / n, 100.0 * float(dead_stuck) / n,
		float(place_sum) / n, float(maxcombo_sum) / n, crate])
	g.free()

func _play(g, st: Dictionary) -> Dictionary:
	g.st = st                  # _random_piece가 읽는 실 스테이지 정의(pool 포함)
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
		"win": g.game_clear, "leaked": g.leaked, "places": places, "clears": clears,
		"maxcombo": maxcombo,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# ───────── 그리디 봇 (sim.gd에서 복제, g의 public 표면만 읽음) ─────────
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
