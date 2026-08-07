extends SceneTree
# 캠페인 난이도 곡선 프로브 — 전 스테이지를 배열(=캠페인) 순서로 N판 돌려 승률·패배사유만 뽑는다(배치 검증용).
#   그리디 봇/스코어는 bomb_probe와 동형(인라인). sim.gd 전체(300×2)보다 빠르게 곡선만.

#   ⚠합/불(승률)을 내는 프로브는 A/B 할 땐 시드를 고정해야 한다 — 무시드면 기전 변경의 효과가
#     시드 노이즈에 묻힌다(analytics_probe 교훈). PROBE_SEED / TRIALS 환경변수로 고정·조절:
#     PROBE_SEED=20260718 TRIALS=40 godot --headless --path . --script tools/campaign_probe.gd

# 배치 1회 → 사람 실시간 초. 위 표 주석의 실측 계수(중앙값 3.3).
const SEC_PER_PLACE: float = 3.3

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 100
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.set("persist_enabled", false)   # ⚠_ready가 켠다 — 안 끄면 봇의 클리어가 실유저 진행도에 각인된다(regress와 동형 가드)
	var sd: String = OS.get_environment("PROBE_SEED")
	if sd != "":
		seed(int(sd))
		g.seed_game(int(sd))
		print("(seed=%s TRIALS=%d)" % [sd, TRIALS])
	# STAGE_IDX="0,1,2,3"이면 그 배열 위치만 돌린다(비어 있으면 전부) — 특정 구간을 큰 N으로 좁힐 때.
	var only: Array = []
	var only_env: String = OS.get_environment("STAGE_IDX")
	if only_env != "":
		for tok in only_env.split(","):
			only.append(int(tok))
	# 튜토리얼 비활성 — 안 끄면 si=0의 첫 시행만 스크립트 판(tut_lock)이라 봇 통계가 섞인다.
	g.cleared[0] = true
	# 배치·줄 = 판 길이(체감 소요 시간)의 대리 지표. 승률만 보면 '쉽지만 지루한 판'을 못 잡는다.
	# 동시2·3 = 한 배치로 2줄·3줄 이상을 한꺼번에 지운 횟수 = '싹 터지는 맛'의 계측치.
	#   콤보(연속 배치로 이어감)와 다른 축이다 — 맛을 볼 땐 둘 다 봐야 한다.
	# ⚠**'배치'(전체 평균)는 길이 설계의 자로 쓰면 안 된다** — 승·패를 섞은 값이라 승률에 오염된다.
	#   진 판은 일찍 끝나므로 어려운 판일수록 평균이 짧게 나온다(클라이맥스는 승률 28%라 45.5배치로
	#   찍히지만 실제 클리어는 그보다 훨씬 길다). 그래서 두 값을 따로 낸다:
	#     승배치 = 이긴 판의 배치 수 = **클리어 길이**(플레이어가 성공했을 때 쓴 시간)
	#     패배치 = 진 판의 배치 수   = **실패 비용**(원점으로 돌아가며 잃는 시간)
	#   길이 목표는 이 둘에 각각 걸어야 한다. 캐주얼 기준 실패 비용 60~90초.
	# 초 환산 = 배치 × SEC_PER_PLACE. 실플레이 애널리틱스(analytics.jsonl 58시도)와 이 프로브를
	#   13판 전부에서 맞춰 얻은 실측 계수 — 비율이 2.0~4.8에 중앙값 3.3이었다.
	#   ⚠사람 한 명(개발자) 표본이므로 절대치가 아니라 판 간 비교용으로 읽을 것.
	print("idx | 승률   | 거점사 | 막힘 | 배치  | 승배치 | 승초  | 패배치 | 패초  | 줄   | 동시2 | 동시3 | 콤보 | 이름키")
	print("----+--------+--------+------+-------+--------+-------+--------+-------+------+-------+-------+------+-------")
	for si in range(g.STAGES.size()):
		if not only.is_empty() and not only.has(si):
			continue
		_probe_stage(g, si, TRIALS)
	quit()

func _probe_stage(g: Node, si: int, TRIALS: int) -> void:
	g.dda_enabled = false
	var wins: int = 0
	var dead_core: int = 0
	var dead_stuck: int = 0
	var places: float = 0.0
	var win_places: float = 0.0    # 이긴 판의 배치 합 = 클리어 길이
	var lose_places: float = 0.0   # 진 판의 배치 합 = 실패 비용
	var clears: float = 0.0
	var multi2: float = 0.0
	var multi3: float = 0.0
	var maxcombo: float = 0.0
	for t in range(TRIALS):
		var r: Dictionary = _play(g, si)
		if r["win"]:
			wins += 1
			win_places += float(r["places"])
		else:
			lose_places += float(r["places"])
		if r["dead_core"]:
			dead_core += 1
		if r["dead_stuck"]:
			dead_stuck += 1
		places += float(r["places"])
		clears += float(r["clears"])
		multi2 += float(r["multi2"])
		multi3 += float(r["multi3"])
		maxcombo += float(r["maxcombo"])
	var n: float = float(TRIALS)
	var losses: int = TRIALS - wins
	var wp: float = win_places / float(wins) if wins > 0 else 0.0
	var lp: float = lose_places / float(losses) if losses > 0 else 0.0
	print(" %2d | %5.1f%% |  %3d   | %3d  | %5.1f | %6.1f | %4.0fs | %6.1f | %4.0fs | %4.1f | %5.2f | %5.2f | %4.1f | %s" % [
		si + 1, 100.0 * float(wins) / n, dead_core, dead_stuck,
		places / n, wp, wp * SEC_PER_PLACE, lp, lp * SEC_PER_PLACE,
		clears / n, multi2 / n, multi3 / n, maxcombo / n,
		String(g.STAGES[si]["name"])])

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
	var guard: int = 0
	var deton: int = 0
	var defuse: int = 0
	var places: int = 0
	var clears: int = 0   # 판정법은 regress와 동일(resolving 진입 or 콤보 증가)
	var multi2: int = 0
	var multi3: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		var pre: Dictionary = {}
		for e in g.enemies:
			if e["etype"] == "bomb":
				pre[int(e["id"])] = int(e.get("fuse", 99))
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		var combo_before: int = g.combo
		var nlines: int = _lines_of(g, mv)   # 놓기 전에 계산 = 엔진 훅 없이 정확
		g._place_piece()
		places += 1
		if g.resolving or g.combo > combo_before:
			clears += 1
		if nlines >= 2:
			multi2 += 1
		if nlines >= 3:
			multi3 += 1
		var s3: int = 0
		while g.resolving and s3 < 400:
			g._process(0.05)
			s3 += 1
		var post: Dictionary = {}
		for e in g.enemies:
			if e["etype"] == "bomb":
				post[int(e["id"])] = true
		for id in pre.keys():
			if not post.has(id):
				if int(pre[id]) <= 1:
					deton += 1
				else:
					defuse += 1
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "leaked": g.leaked, "killed": g.killed,
		"deton": deton, "defuse": defuse, "places": places, "clears": clears,
		"multi2": multi2, "multi3": multi3, "maxcombo": g.run_max_combo,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# 이 수가 완성시키는 행+열 수 (plane_rate_probe와 동형 — 이 저장소 관례대로 인라인 복사)
func _lines_of(g: Node, mv: Dictionary) -> int:
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
	var n: int = 0
	for r in range(g.ROWS):
		var ok: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				ok = false
				break
		if ok:
			n += 1
	for c in range(g.COLS):
		var ok2: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				ok2 = false
				break
		if ok2:
			n += 1
	return n

# ── 그리디 봇 (sim.gd에서 복사, 폭탄 우선항 포함) ──
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
