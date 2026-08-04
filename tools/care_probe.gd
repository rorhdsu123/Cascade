extends SceneTree
# care_probe.gd — 실패 케어(연속 실패 구제)의 효과 측정. 조각 풀 완화 폭을 정하기 위한 스윕.
#
# 재는 것: "같은 판을 연속으로 진 사람에게 5바를 더 주면 승률이 얼마나 오르나".
#   base : DDA off · 기본 풀             = 기준선(campaign_probe와 동형 조건)
#   god  : DDA on  · fail_streak=2       = 현행 갓 모드(줄 낼 수 있는 조각 재추첨)만
#   T##  : DDA on  · fail_streak=3 · 케어 풀(5바 비중을 ##%로) = 제안하는 3패 케어
#
# ⚠비행기는 이 프로브로 못 잰다. 그리디 봇은 비행기를 쏘지 않는다 = 여기 승률은 늘 비행기 OFF 값이다.
#   plane_cd 완화의 효과는 tools/plane_verify.gd(AB=1) 경로로 따로 재야 한다.
#
# ⚠A/B라서 조건마다 시드를 되감는다(짝지은 비교). 한 스트림으로 연달아 돌리면 앞 조건의 draw 수가
#   뒤 조건을 통째로 밀어 조건 차이와 시드 노이즈가 섞인다(analytics_probe·regress 교훈).
#
# 실행:
#   godot --headless --path . --script tools/care_probe.gd
#   TRIALS=60 STAGE_IDX=4,5,6,7 SHARES=34,41 PROBE_SEED=20260804 godot --headless ... (좁혀 볼 때)

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 60
	var base_seed: int = int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 20260804
	# 재볼 5바 비중(%). 32=ONBOARD 수준(출시 검증됨) / 41=RICH 수준 / 47=C109서 유저가 잡아낸 값.
	var shares: Array = [34, 41]
	var sh_env: String = OS.get_environment("SHARES")
	if sh_env != "":
		shares = []
		for tok in sh_env.split(","):
			shares.append(int(tok))

	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.set("persist_enabled", false)   # ⚠_ready가 켜둔다 — 안 끄면 봇의 클리어가 실유저 진행도에 각인된다
	g.cleared[0] = true               # 튜토리얼 비활성(si=0 첫 시행이 스크립트 판이 되는 것 방지)

	var only: Array = []
	var only_env: String = OS.get_environment("STAGE_IDX")
	if only_env != "":
		for tok in only_env.split(","):
			only.append(int(tok))

	# 조건 목록 = [라벨, dda, fail_streak, 5바 목표비중(0=기본 풀)]
	var conds: Array = [["base", false, 0, 0.0], ["god", true, 2, 0.0]]
	for s in shares:
		conds.append(["T%d" % int(s), true, 3, float(s) / 100.0])

	print("(seed=%d TRIALS=%d)" % [base_seed, TRIALS])
	var head: String = "idx | 5바%  "
	for c in conds:
		head += "| %-6s " % String(c[0])
	head += "| 이름키"
	print(head)
	print("----+-------" + "+--------".repeat(conds.size()) + "+-------")

	for si in range(g.STAGES.size()):
		if not only.is_empty() and not only.has(si):
			continue
		var base_pool: Dictionary = g.STAGES[si].get("pool", {})
		var row: String = " %2d | %4.1f%% " % [si + 1, 100.0 * _i5_share(base_pool)]
		var wins: Array = []
		for c in conds:
			# 시드 되감기 = 조건들이 같은 난수 스트림을 본다(짝지은 비교).
			seed(base_seed + si * 1000)
			g.seed_game(base_seed + si * 1000)
			var pool: Dictionary = {}
			if float(c[3]) > 0.0:
				pool = _care_pool(base_pool, float(c[3]))
			var w: int = _run(g, si, bool(c[1]), int(c[2]), pool, TRIALS)
			wins.append(w)
			row += "| %5.1f%% " % [100.0 * float(w) / float(TRIALS)]
		row += "| %s" % String(g.STAGES[si]["name"])
		print(row)
	quit()

# 5바(I5h+I5v)가 배급에서 차지하는 비중. 유저가 눈으로 잡아내는 그 숫자 = 완화 폭의 상한 단위.
func _i5_share(w: Dictionary) -> float:
	if w.is_empty():
		return 0.0
	var total: int = 0
	var i5: int = 0
	for k in w:
		total += int(w[k])
		if k == "I5h" or k == "I5v":
			i5 += int(w[k])
	if total <= 0:
		return 0.0
	return float(i5) / float(total)

# 케어 풀 = 5바 비중만 목표까지 끌어올린 사본. 나머지 조각의 상대 비율은 그대로 둔다
#   (작은 조각을 늘리는 개입은 실측상 역효과 — Main._make_piece 주석 참조).
#   h:v 비율은 원본 유지 = 판마다 저작된 가로/세로 성격을 안 뭉갠다.
func _care_pool(base: Dictionary, target: float) -> Dictionary:
	if base.is_empty() or not base.has("I5h") or not base.has("I5v"):
		return {}
	var total: int = 0
	var i5: int = 0
	for k in base:
		total += int(base[k])
		if k == "I5h" or k == "I5v":
			i5 += int(base[k])
	if i5 <= 0 or target <= 0.0 or target >= 1.0:
		return {}
	var rest: int = total - i5
	var want: float = target * float(rest) / (1.0 - target)   # 목표 비중을 만드는 새 I5 합
	if want <= float(i5):
		return {}    # 이미 목표 이상 = 완화 없음(그 판은 케어가 조각으로 안 걸린다)
	var scale: float = want / float(i5)
	var out: Dictionary = base.duplicate()
	out["I5h"] = maxi(1, int(round(float(base["I5h"]) * scale)))
	out["I5v"] = maxi(1, int(round(float(base["I5v"]) * scale)))
	return out

func _run(g: Node, si: int, dda: bool, streak: int, pool: Dictionary, trials: int) -> int:
	var wins: int = 0
	for t in range(trials):
		g.dda_enabled = dda
		g.fail_streak[si] = streak
		g._start_stage(si)
		# ⚠_start_stage 뒤에 덮는다 — _init_game이 CARE_I5_SHARE로 이미 계산해 둔 값을 스윕 값으로 바꾼다.
		#   실제 코드 경로(Main.care_pool)를 그대로 타므로 프로브와 게임이 어긋나지 않는다.
		#   부작용: 첫 트레이 3장은 기본 풀로 뽑힌 뒤다 = 케어 효과가 아주 살짝 과소평가된다.
		#   조건 전체에 똑같이 걸리므로 A/B 비교 자체는 성립한다(방향·순위 불변).
		g.care_pool = pool
		if _play(g):
			wins += 1
	return wins

func _play(g: Node) -> bool:
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
		g._place_piece()
		var s3: int = 0
		while g.resolving and s3 < 400:
			g._process(0.05)
			s3 += 1
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return g.game_clear

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
