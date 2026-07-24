extends SceneTree

# 보석 수집판 체감-비율 프로브 (일회성 — 검증 후 삭제)
# 목적: "적이 전경, 보석이 곁다리"가 재튜닝으로 뒤집혔나를 실측.
# 기존 sim.gd 그리디에 '보석 조준'을 얹은 봇으로 collect 스테이지만 N판 돌려:
#   - 공급비율: 스폰된 보석 수 vs 적 수 (전경/배경 = 손잡이 직접 판독)
#   - 결과: 승률·평균턴·수집·누수(놓친 보석)
#   - 처리 분할: 처치(적) vs 수집(보석) — 클리어가 어디로 갔나의 프록시
# 헤드리스 OK(순수 로직, 렌더 없음).

const TRIALS: int = 400

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)   # _ready

	print("stage | 승률   | 평균턴 | 보석스폰 | 적스폰 | 보석/적10 | 수집 | 놓침 | 놓침률 | 처치 | 처치:수집")
	print("------+--------+--------+----------+--------+-----------+------+------+--------+------+---------")
	for si in range(g.STAGES.size()):
		if not bool((g.STAGES[si] as Dictionary).get("collect", false)):
			continue
		_run_stage(g, si)
	quit()

func _run_stage(g: Node, si: int) -> void:
	var wins: int = 0
	var turn_sum: float = 0.0
	var gspawn_sum: float = 0.0
	var espawn_sum: float = 0.0
	var coll_sum: float = 0.0
	var gleak_sum: float = 0.0
	var kill_sum: float = 0.0
	for t in range(TRIALS):
		var r: Dictionary = _play(g, si)
		if r["win"]:
			wins += 1
		turn_sum += float(r["turns"])
		gspawn_sum += float(r["gem_spawned"])
		espawn_sum += float(r["enemy_spawned"])
		coll_sum += float(r["collected"])
		gleak_sum += float(r["gem_leaked"])
		kill_sum += float(r["killed"])
	var n: float = float(TRIALS)
	var gsp: float = gspawn_sum / n
	var esp: float = espawn_sum / n
	var perten: float = 0.0 if esp == 0.0 else 10.0 * gsp / esp
	var gl: float = gleak_sum / n
	var gspawned_avg: float = gsp
	var leakrate: float = 0.0 if gspawned_avg == 0.0 else 100.0 * gl / gspawned_avg
	var kills: float = kill_sum / n
	var coll: float = coll_sum / n
	var k2c: float = 0.0 if coll == 0.0 else kills / coll
	print("  %d   | %5.1f%% | %6.1f |  %6.1f  | %6.1f |   %5.2f   | %4.1f | %4.1f | %5.1f%% | %4.1f |  %4.1f:1" % [
		si + 1, 100.0 * float(wins) / n, turn_sum / n, gsp, esp, perten,
		coll, gl, leakrate, kills, k2c])

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
	var turns: int = 0
	var guard: int = 0
	var gem_ids: Dictionary = {}      # etype==gem으로 본 유니크 id
	var enemy_ids: Dictionary = {}    # 그 외 유니크 id (gen0만: 분열 자식 제외 위해 gtype 없음+gen0 근사)
	while not g.game_over and not g.game_clear and guard < 4000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		_scan(g, gem_ids, enemy_ids)
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		turns += 1
		_scan(g, gem_ids, enemy_ids)
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	_scan(g, gem_ids, enemy_ids)
	# 수집량 = collected_by_type 합 (quota 상한). 놓침 = 스폰 - 수집 - (보드 잔존 보석) - (비행 중)
	var collected: int = 0
	for c in g.collected_by_type:
		collected += int(c)
	var onboard_gem: int = 0
	for e in g.enemies:
		if e["etype"] == "gem":
			onboard_gem += 1
	var inflight: int = g.gem_flights.size()
	var gem_spawned: int = gem_ids.size()
	var gem_leaked: int = maxi(0, gem_spawned - collected - onboard_gem - inflight)
	return {
		"win": g.game_clear, "turns": turns,
		"gem_spawned": gem_spawned, "enemy_spawned": enemy_ids.size(),
		"collected": collected, "gem_leaked": gem_leaked, "killed": g.killed,
	}

func _scan(g: Node, gem_ids: Dictionary, enemy_ids: Dictionary) -> void:
	for e in g.enemies:
		var id: int = int(e["id"])
		if e["etype"] == "gem":
			gem_ids[id] = true
		elif int(e.get("gen", 0)) == 0:
			enemy_ids[id] = true

# ── 그리디 + 보석 조준 ──
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

	# 생존성
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
		# 적: 밀집 레인 선호 + 거점 근접 우선
		var hit: int = 0
		for e in g.enemies:
			if e["etype"] == "gem":
				continue
			var in_band: bool = _in_band(e, full_cols, full_rows, lanes)
			if in_band:
				hit += 1
		score += 120.0 * float(hit)
		for e in g.enemies:
			if e["etype"] == "gem":
				continue
			for fc3 in full_cols:
				if int(e["col"]) == int(fc3):
					score += 8.0 * float(e["row"])
		# 보석: 아직 필요한 타입이면 강하게 조준(수집이 목표). 놓치기 전에 잡도록 row 가중.
		for e in g.enemies:
			if e["etype"] != "gem":
				continue
			if not _gem_needed(g, int(e.get("gtype", 0))):
				continue
			if _in_band(e, full_cols, full_rows, lanes):
				score += 260.0 + 14.0 * float(e["row"])   # 적 처치(120)보다 우선 = 목표 지향 플레이어

	# 보드 정돈
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
				if nb >= 3:
					holes += 1
	score -= 2.0 * float(filled)
	score -= 6.0 * float(holes)
	return score

func _in_band(e: Dictionary, full_cols: Array, full_rows: Array, lanes: int) -> bool:
	for fc in full_cols:
		if absi(int(e["col"]) - int(fc)) < lanes:
			return true
	for fr in full_rows:
		if absi(int(e["row"]) - int(fr)) < lanes:
			return true
	return false

func _gem_needed(g: Node, gt: int) -> bool:
	var tgts: Array = g.st.get("collect_targets", [])
	if gt >= tgts.size() or gt >= g.collected_by_type.size():
		return false
	return int(g.collected_by_type[gt]) < int(tgts[gt])

func _fits_anywhere(g: Node, occ: Array, offsets: Array) -> bool:
	for r in range(g.ROWS):
		for c in range(g.COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
				if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS:
					ok = false
					break
				if occ[cc.y][cc.x]:
					ok = false
					break
			if ok:
				return true
	return false
