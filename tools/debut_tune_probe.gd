extends SceneTree
# 도입판 튜닝 프로브 — 시작 적을 신규 타입으로 고정한 뒤(S10) 남은 두 질문을 한 번에 잰다.
#   ① 폭탄 도입판의 가중치: 첫 마리는 확정됐지만 **두 번째가 언제 오나**. 승률만 보면 이 축이 안 보인다.
#   ② S10이 치른 도입판 승률 −4~−8pt를 core_hp로 되살까: 판마다 무릎이 다르므로 후보를 짝지어 잰다.
#   두 변경이 같은 판들에 겹쳐 얹히므로 따로 재면 두 번 흔들린다 = 한 하네스에서 같이 잰다.
#
# 봇·스코어는 campaign_probe와 동형(그리디 인라인 복사, 폭탄 우선항 포함 — 이 저장소 관례).
#   ⚠campaign_probe의 봇은 비행기를 안 쏜다 = 여기 승률도 항상 비행기 OFF 값이다(체감치는 더 높음).
#   ⚠조건 사이에 시드를 되감아 **짝지은 비교**로 만든다(care_probe와 동형). 안 그러면 조건이 아니라
#     난수 스트림 차이를 재게 된다. 시드베이스 2개로 재현될 때까지 결과를 믿지 말 것.
#
# 폭탄 지표(폭탄 스테이지에서만 의미 있음):
#   폭탄/판 = 그 판에 실제로 나온 폭탄 수 · 2번째 = 두 번째 폭탄이 나온 배치 시점(중앙값, -1=안 나옴)
#   해체/폭발 = 도화선 0 전에 걷어낸 수 / 터진 수. '가르치는 판'은 폭발이 0이면 안 배운다.
#
#   SWEEP=bombw  godot --headless --path . --script tools/debut_tune_probe.gd   # ① 폭탄 밀도
#   SWEEP=corehp ...                                                            # ② 승률 되사기
#   SWEEP=both   ...                                                            # 확정 후보 합본
#   PROBE_SEED=20260806 TRIALS=100 (시드베이스는 SEED2=1이면 +7717로 한 벌 더)

const SM: GDScript = preload("res://modes/stage_mode.gd")

# 스윕 정의 — [라벨, 배열idx, 판데이터 오버라이드]
#   폭탄 가중치는 basic과 짝으로 움직인다(합 100 유지 = 다른 축이 안 딸려 들어옴).
func _sweeps(name: String) -> Array:
	match name:
		"bombw":
			return [
				["폭탄15%(현재)", 5, {}],
				["폭탄22%", 5, {"weights": {"basic": 78, "bomb": 22}}],
				["폭탄30%", 5, {"weights": {"basic": 70, "bomb": 30}}],
				["폭탄38%", 5, {"weights": {"basic": 62, "bomb": 38}}],
			]
		"corehp":
			return [
				["st3 hp4(현재)", 2, {}],
				["st3 hp5", 2, {"core_hp": 5}],
				["st7 hp4(현재)", 8, {}],
				["st7 hp5", 8, {"core_hp": 5}],
				["st11 hp6(현재)", 5, {}],
				["st11 hp7", 5, {"core_hp": 7}],
			]
		# 밀도를 올리되 여유로 되사기 — "폭탄을 더 자주 보되 더 관대하게"가 가르치는 판의 모양이다.
		#   가중치만 올리면 승률이 12~26pt 빠지지만(bombw), 그 빚을 core_hp로 갚으면 난이도는 제자리에
		#   두고 폭탄 경험량만 늘릴 수 있다. 값이 맞는지가 이 스윕의 질문.
		"bombw2":
			return [
				["15% hp6(현재)", 5, {}],
				["22% hp7", 5, {"weights": {"basic": 78, "bomb": 22}, "core_hp": 7}],
				["22% hp8", 5, {"weights": {"basic": 78, "bomb": 22}, "core_hp": 8}],
				["30% hp9", 5, {"weights": {"basic": 70, "bomb": 30}, "core_hp": 9}],
			]
		# st3(속공 도입)는 core_hp가 레버로 너무 굵다(+19pt로 −8pt 손실을 지나쳐 되산다).
		#   더 가는 눈금 후보 = total(적 수, 기준 ⑤). 판 길이도 같이 줄어드는 게 값이다.
		"st3":
			return [
				["hp4 total34(현재)", 2, {}],
				["total 32", 2, {"total": 32}],
				["total 30", 2, {"total": 30}],
				["hp5 total 40", 2, {"core_hp": 5, "total": 40}],
			]
		_:
			return []

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 100
	var base_seed: int = int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 20260806
	if OS.get_environment("SEED2") != "":
		base_seed += 7717
	var sweep: String = OS.get_environment("SWEEP") if OS.get_environment("SWEEP") != "" else "bombw"
	var conds: Array = _sweeps(sweep)
	if conds.is_empty():
		print("SWEEP=bombw|corehp 중 하나를 줄 것")
		quit()
		return
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.cleared[0] = true   # 튜토리얼 비활성(봇 통계 오염 방지)
	g.dda_enabled = false
	print("(sweep=%s seed=%d TRIALS=%d)" % [sweep, base_seed, TRIALS])
	print("판 | 조건            | 승률   | 거점사 | 막힘사 | 배치  | 폭탄/판 | 2번째 | 해체 | 폭발")
	print("---+-----------------+--------+--------+--------+-------+---------+-------+------+-----")
	for c in conds:
		var si: int = int(c[1])
		# 시드 되감기 = 모든 조건이 같은 난수 스트림을 본다(짝지은 비교, care_probe와 동형)
		seed(base_seed + si * 1000)
		g.seed_game(base_seed + si * 1000)
		_run(g, si, String(c[0]), c[2] as Dictionary, TRIALS)
	quit()

func _run(g: Node, si: int, label: String, ov: Dictionary, TRIALS: int) -> void:
	var wins: int = 0
	var dc: int = 0
	var ds: int = 0
	var places: float = 0.0
	var bombs: float = 0.0
	var deton: float = 0.0
	var defuse: float = 0.0
	var seconds: Array = []
	for t in range(TRIALS):
		var r: Dictionary = _play(g, si, ov)
		if r["win"]:
			wins += 1
		if r["dead_core"]:
			dc += 1
		if r["dead_stuck"]:
			ds += 1
		places += float(r["places"])
		bombs += float(r["bombs"])
		deton += float(r["deton"])
		defuse += float(r["defuse"])
		if int(r["second"]) >= 0:
			seconds.append(int(r["second"]))
	var n: float = float(TRIALS)
	seconds.sort()
	# 중앙값은 '두 번째가 나온 판'들 안에서만 — 안 나온 판은 미등장률로 따로 읽는다.
	var med2: String = "%3d" % int(seconds[seconds.size() / 2]) if not seconds.is_empty() else " — "
	var miss2: int = TRIALS - seconds.size()
	print("%2d | %-15s | %5.1f%% | %5.1f%% | %5.1f%% | %5.1f | %7.2f | %s%s | %4.2f | %4.2f" % [
		si + 1, label, 100.0 * float(wins) / n, 100.0 * float(dc) / n, 100.0 * float(ds) / n,
		places / n, bombs / n, med2, ("(미%d)" % miss2) if miss2 > 0 else "     ",
		defuse / n, deton / n])

# 판 데이터를 덮어쓴 사본으로 한 판. _start_stage를 손수 재현해 st·director를 _init_game **앞에서**
#   갈아끼운다(care_probe와 동형) — 뒤에서 바꾸면 시작 적이 이미 원래 값으로 스폰된 뒤다.
#   ⚠기준선 조건(오버라이드 빈 사전)도 **같은 경로**로 돈다 — 기준선만 _start_stage를 타면 조건 사이에
#     코드 경로가 갈려, 재는 게 조건 차이인지 경로 차이인지 못 가린다.
func _start(g: Node, si: int, ov: Dictionary) -> void:
	var mod: Dictionary = (g.STAGES[si] as Dictionary).duplicate(true)
	for k in ov:
		mod[k] = ov[k]
	g.endless = false
	g.featured = false
	g.stage_idx = si
	g.st = mod
	g.director = SM.new(mod)
	g.mode = "play"
	g._init_game()
	g.intro_t = 0.0

func _play(g: Node, si: int, ov: Dictionary) -> Dictionary:
	_start(g, si, ov)
	var guard: int = 0
	var places: int = 0
	var deton: int = 0
	var defuse: int = 0
	var seen_bombs: Dictionary = {}   # 폭탄 id -> 처음 본 배치 시점
	var second: int = -1
	var order: Array = []
	# 시작 적이 폭탄이면 배치 0에 이미 서 있다(S10) — 판이 열린 직후 한 번 훑어 그걸 1번째로 등록한다.
	for e in g.enemies:
		if String(e["etype"]) == "bomb":
			seen_bombs[int(e["id"])] = 0
			order.append(int(e["id"]))
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
			if String(e["etype"]) == "bomb":
				pre[int(e["id"])] = int(e.get("fuse", 99))
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		places += 1
		var s3: int = 0
		while g.resolving and s3 < 400:
			g._process(0.05)
			s3 += 1
		# 사라진 폭탄 = 도화선 1 이하면 터진 것(폭발), 아니면 걷어낸 것(해체) — campaign_probe와 동형
		var post: Dictionary = {}
		for e in g.enemies:
			if String(e["etype"]) == "bomb":
				post[int(e["id"])] = true
		for id in pre.keys():
			if not post.has(id):
				if int(pre[id]) <= 1:
					deton += 1
				else:
					defuse += 1
		# 새로 나온 폭탄 기록(두 번째가 언제 오나 = 이 판의 핵심 질문)
		for e in g.enemies:
			if String(e["etype"]) != "bomb":
				continue
			var eid: int = int(e["id"])
			if seen_bombs.has(eid):
				continue
			seen_bombs[eid] = int(g.place_count)
			order.append(eid)
			if order.size() == 2 and second < 0:
				second = int(g.place_count)
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "places": places, "bombs": seen_bombs.size(),
		"second": second, "deton": deton, "defuse": defuse,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# ── 그리디 봇 (campaign_probe에서 복사, 폭탄 우선항 포함) ──
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
