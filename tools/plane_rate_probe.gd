extends SceneTree
# 비행기 픽업 등장률 산정 프로브 — 판당 배치 수 + 행·열 클리어 빈도를 실측한다.
#   목적 ① "판당 N회 획득"을 스폰 쿨다운(배치 수)으로 환산할 근거.
#   목적 ② 하강형이 실제로 잡히는지 검증 — 픽업은 하강 창(ROWS×step_every 배치) 동안
#          '자기 열'(내내 고정) 또는 '지금 밟고 있는 행'이 터지면 획득된다. 그 기대 횟수를 낸다.
#
#   ⚠비행기는 수집(collect)·튜토리얼(stage 0 초회) 판엔 안 나온다 → 산정 대상서 제외.
#   그리디 봇/스코어는 campaign_probe와 동형(인라인 복사 — 이 저장소 관례).
#   실행: PROBE_SEED=20260731 TRIALS=30 godot --headless --path . --script tools/plane_rate_probe.gd

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 30
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	var sd: String = OS.get_environment("PROBE_SEED")
	if sd != "":
		seed(int(sd))
		g.seed_game(int(sd))
	print("(seed=%s TRIALS=%d)" % [sd if sd != "" else "none", TRIALS])
	# 튜토리얼 비활성 — stage 0 초회는 스크립트 판이라 봇 통계에 안 맞고, 어차피 비행기 제외 대상.
	g.cleared[0] = true

	print("idx | 배치수 평균 | 최소~최대 | 행클리어 | 열클리어 | 이름키")
	print("----+-------------+-----------+----------+----------+-------")
	var tot_place: float = 0.0
	var tot_rows: float = 0.0
	var tot_cols: float = 0.0
	var n_stage: int = 0
	for si in range(g.STAGES.size()):
		var st: Dictionary = g.STAGES[si]
		if bool(st.get("collect", false)):
			print(" %2d |     —       |     —     |    —     |    —     | %s (수집 — 제외)" % [si + 1, String(st["name"])])
			continue
		if si == 0:
			print(" %2d |     —       |     —     |    —     |    —     | %s (튜토리얼 — 제외)" % [si + 1, String(st["name"])])
			continue
		var r: Dictionary = _probe_stage(g, si, TRIALS)
		tot_place += float(r["place_avg"])
		tot_rows += float(r["rows_avg"])
		tot_cols += float(r["cols_avg"])
		n_stage += 1
		print(" %2d |    %6.1f   | %3d~%3d   |  %5.1f   |  %5.1f   | %s" % [
			si + 1, float(r["place_avg"]), int(r["place_min"]), int(r["place_max"]),
			float(r["rows_avg"]), float(r["cols_avg"]), String(st["name"])])

	if n_stage == 0:
		quit()
		return
	var P: float = tot_place / float(n_stage)
	var R: float = tot_rows / float(n_stage)
	var C: float = tot_cols / float(n_stage)
	print("")
	print("── 평균 (대상 %d판) ──" % n_stage)
	print("판당 배치 수      P = %.1f" % P)
	print("판당 행 클리어    R = %.1f  (배치당 %.3f)" % [R, R / P])
	print("판당 열 클리어    C = %.1f  (배치당 %.3f)" % [C, C / P])

	# 하강 창 = ROWS × step_every 배치 (전 스테이지 step_every=3 → 24)
	var win: float = float(g.ROWS * 3)
	# 자기 열이 터질 기대 횟수 = (배치당 열클리어 / COLS) × 창
	var exp_col: float = (C / P) / float(g.COLS) * win
	# 밟고 있는 행이 터질 기대 횟수 = (배치당 행클리어 / ROWS) × 창
	var exp_row: float = (R / P) / float(g.ROWS) * win
	print("")
	print("── 하강 창 %d배치 안의 획득 기회(기대값) ──" % int(win))
	print("자기 열 터짐        %.2f회" % exp_col)
	print("밟은 행 터짐        %.2f회" % exp_row)
	print("합계                %.2f회  → 획득 확률 ≈ %.0f%% (푸아송 1-e^-λ)" % [
		exp_col + exp_row, 100.0 * (1.0 - exp(-(exp_col + exp_row)))])

	# 쿨다운 환산.
	#   기회 발생률 rate = λ/창(배치당). 하강형은 창(win)에서 잘리므로
	#   보드 체류 = E[min(T, win)] = (1 - e^-λ)/rate  (푸아송 절단 기대값. 못 잡고 새는 경우 포함)
	#   고정형은 안 잘리므로 체류 = 1/rate, 대신 획득률 100%.
	#   한 사이클 = 체류 + 쿨다운. 판당 사용 = P/사이클 × 획득률.
	var lam: float = exp_col + exp_row
	var rate: float = lam / win
	var p_catch: float = 1.0 - exp(-lam)
	var dwell_fall: float = p_catch / maxf(1e-6, rate)
	var dwell_fix: float = 1.0 / maxf(1e-6, rate)
	print("")
	print("── 보드 체류(획득 or 누락까지) ──")
	print("하강형  %.1f배치 × 획득률 %.0f%%" % [dwell_fall, 100.0 * p_catch])
	print("고정형  %.1f배치 × 획득률 100%%" % dwell_fix)
	print("")
	print("── 쿨다운별 판당 사용 횟수 ──")
	print("쿨다운 | 하강형 | 고정형")
	print("-------+--------+-------")
	for cd in [0, 5, 10, 15, 20, 30]:
		var u_fall: float = P / (dwell_fall + float(cd)) * p_catch
		var u_fix: float = P / (dwell_fix + float(cd))
		print(" %2d배치 |  %.2f  |  %.2f" % [cd, u_fall, u_fix])
	print("")
	print("(P=%.1f 기준. 초반 판은 P가 작아 이보다 낮게 나온다 — 스테이지별 표 참조)" % P)
	quit()

func _probe_stage(g: Node, si: int, TRIALS: int) -> Dictionary:
	g.dda_enabled = false
	var sum_p: float = 0.0
	var sum_r: float = 0.0
	var sum_c: float = 0.0
	var mn: int = 1 << 30
	var mx: int = 0
	for t in range(TRIALS):
		var r: Dictionary = _play(g, si)
		var p: int = int(r["places"])
		sum_p += float(p)
		sum_r += float(r["rows"])
		sum_c += float(r["cols"])
		mn = mini(mn, p)
		mx = maxi(mx, p)
	var n: float = float(TRIALS)
	return {"place_avg": sum_p / n, "rows_avg": sum_r / n, "cols_avg": sum_c / n,
			"place_min": mn, "place_max": mx}

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
	var guard: int = 0
	var n_rows: int = 0
	var n_cols: int = 0
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
		# 이 수가 무엇을 터뜨리는지 미리 계산(엔진 훅 없이 정확) — 봇 점수 계산과 같은 방식.
		var lines: Dictionary = _lines_of(g, mv)
		n_rows += int(lines["rows"])
		n_cols += int(lines["cols"])
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
	return {"places": g.place_count, "rows": n_rows, "cols": n_cols}

# 선택된 수가 완성시키는 행·열 수
func _lines_of(g: Node, mv: Dictionary) -> Dictionary:
	var offsets: Array = g.tray[int(mv["slot"])]["offsets"]
	var occ: Array = []
	for r in range(g.ROWS):
		var row: Array = []
		for c in range(g.COLS):
			row.append(g.board[r][c] != "")
		occ.append(row)
	for o in offsets:
		var ov: Vector2i = o as Vector2i
		occ[int(mv["row"]) + ov.y][int(mv["col"]) + ov.x] = true
	var fr: int = 0
	var fc: int = 0
	for r in range(g.ROWS):
		var ok: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				ok = false
				break
		if ok:
			fr += 1
	for c in range(g.COLS):
		var ok2: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				ok2 = false
				break
		if ok2:
			fc += 1
	return {"rows": fr, "cols": fc}

# ── 그리디 봇 (campaign_probe에서 복사) ──
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
				if String(e.get("etype", "")) == "bomb":
					var fuse: int = int(e.get("fuse", 99))
					score += 250.0 * float(maxi(1, 9 - mini(fuse, 8)))
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
