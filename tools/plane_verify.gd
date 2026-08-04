extends SceneTree
# 비행기 아이템 검증 — 등장/획득/발사/누락이 실제로 돌아가는지 + 회계 불변식이 깨지지 않는지.
#   ① 수집·튜토리얼 판엔 0마리 등장(게이트 확인)
#   ② 세상에 한 대 불변식: 보드 위 픽업 + 보유 + 획득비행 중 ≤ 1  (매 배치 검사)
#   ③ 웨이브 회계: spawned == killed + leaked + 온보드 위협수  (픽업·보석은 카운터 밖)
#   ④ 판당 사용 횟수가 plane_cd 배정과 맞는지(설계 목표: 초반 ~2회 → 후반 ~1회)
#   ⑤ AB=1: 판마다 같은 시드로 대조군(비행기 없음)을 함께 돌려 스테이지별 Δ 곡선을 낸다.
#      ⚠평균 Δ보다 곡선이 중요하다 — 확정 처치의 값어치는 판이 어려울수록 커져 후반만 부푼다.
#   봇 정책 = 들자마자 즉시 발사(= 사용 횟수 상한. 아껴 쓰면 이보다 적다).
#   실행: PROBE_SEED=20260731 TRIALS=20 godot --headless --path . --script tools/plane_verify.gd
#         AB=1 PROBE_SEED=20260731 TRIALS=60 godot --headless --path . --script tools/plane_verify.gd

var fails: Array = []

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 20
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	var sd: String = OS.get_environment("PROBE_SEED")
	var base_seed: int = int(sd) if sd != "" else 20260731
	# AB=1이면 판마다 같은 시드로 '비행기 없음(대조군)'을 한 번 더 돌려 Δ 곡선을 낸다.
	#   대조군은 plane_cd_left를 사실상 무한대로 눌러 만든다(스폰 경로만 막고 나머지는 그대로)
	#   — STAGES는 const라 런타임 오버라이드가 불가하고, 이 방식이 코드 경로를 안 건드린다.
	var AB: bool = OS.get_environment("AB") != ""
	print("(seed=%s TRIALS=%d%s)" % [sd if sd != "" else "none", TRIALS, "  AB=on" if AB else ""])
	g.cleared[0] = true   # 튜토리얼 비활성 (stage 0의 '튜토리얼 아닌' 재플레이를 본다)

	if AB:
		print("idx | cd | 사용/판 | 무비행기 | 비행기 |   Δ    | 이름키")
		print("----+----+---------+----------+--------+--------+-------")
	else:
		print("idx | cd | 등장  | 획득  | 발사  | 누락  | 사용/판 | 승률   | 이름키")
		print("----+----+-------+-------+-------+-------+---------+--------+-------")
	# STAGE_IDX="1,5,12"면 그 배열 위치만 (campaign_probe와 같은 규약) — 특정 판을 큰 N으로 좁힐 때.
	var only: Array = []
	var only_env: String = OS.get_environment("STAGE_IDX")
	if only_env != "":
		for tok in only_env.split(","):
			only.append(int(tok))
	var sum_off: float = 0.0
	var sum_on: float = 0.0
	var n_ab: int = 0
	for si in range(g.STAGES.size()):
		if not only.is_empty() and not only.has(si):
			continue
		var st: Dictionary = g.STAGES[si]
		var sp: float = 0.0
		var gr: float = 0.0
		var fi: float = 0.0
		var lk: float = 0.0
		var wins: float = 0.0
		var wins_off: float = 0.0
		for t in range(TRIALS):
			# ⚠판·시행마다 독립 시드 — 한 번만 시드하면 비행기가 소비한 randi 수만큼 하류 스테이지의
			#   난수 스트림이 통째로 밀려, 비행기가 안 나오는 판(수집)까지 승률이 흔들린다(A/B 오염).
			var sseed: int = base_seed + si * 100003 + t
			if AB:
				seed(sseed)
				g.seed_game(sseed)
				if bool(_play(g, si, true)["win"]):
					wins_off += 1.0
			seed(sseed)
			g.seed_game(sseed)
			var r: Dictionary = _play(g, si)
			sp += float(r["spawn"])
			gr += float(r["grab"])
			fi += float(r["fire"])
			lk += float(r["leak"])
			if bool(r["win"]):
				wins += 1.0
		var n: float = float(TRIALS)
		var cd: String = str(int(st["plane_cd"])) if st.has("plane_cd") else "—"
		if AB:
			var w_off: float = 100.0 * wins_off / n
			var w_on: float = 100.0 * wins / n
			sum_off += w_off
			sum_on += w_on
			n_ab += 1
			print(" %2d | %2s |  %5.2f  |  %5.1f%%  | %5.1f%% | %+6.1f | %s" % [
				si + 1, cd, fi / n, w_off, w_on, w_on - w_off, String(st["name"])])
		else:
			print(" %2d | %2s | %5.2f | %5.2f | %5.2f | %5.2f |  %5.2f  | %5.1f%% | %s" % [
				si + 1, cd, sp / n, gr / n, fi / n, lk / n, fi / n, 100.0 * wins / n, String(st["name"])])
		# ① 게이트: 수집 판엔 절대 안 나온다
		if bool(st.get("collect", false)) and sp > 0.0:
			fails.append("스테이지 %d(수집)에 비행기가 %d회 등장" % [si + 1, int(sp)])

	# 튜토리얼 게이트는 따로 — cleared[0]을 지워 진짜 튜토리얼 상태로 stage 0을 돌린다
	#   (STAGE_IDX로 구간을 좁혀 돌 땐 건너뛴다 — 밸런스 반복에서 매번 낼 필요가 없다)
	var tut_spawn: int = 0
	for t2 in range(0 if not only.is_empty() else TRIALS):
		seed(base_seed + 999983 + t2)
		g.seed_game(base_seed + 999983 + t2)
		g.cleared.erase(0)   # ⚠매 판 지운다 — 한 판 이기면 cleared[0]이 켜져 그 뒤론 튜토리얼이 아니다
		var rt: Dictionary = _play(g, 0)
		tut_spawn += int(rt["spawn"])
	print("")
	print("튜토리얼(stage 0 초회) 등장 = %d마리  (기대 0)" % tut_spawn)
	if tut_spawn > 0:
		fails.append("튜토리얼 판에 비행기가 %d회 등장" % tut_spawn)

	if n_ab > 0:
		print("")
		print("── 평균(전 %d판) 무비행기 %.1f%% → 비행기 %.1f%%  (Δ %+.1fpt) ──" % [
			n_ab, sum_off / float(n_ab), sum_on / float(n_ab), (sum_on - sum_off) / float(n_ab)])

	print("")
	if fails.is_empty():
		print("✅ 전부 통과 — 게이트·불변식·회계 이상 없음")
	else:
		print("❌ 실패 %d건:" % fails.size())
		for f in fails:
			print("   - " + String(f))
	quit()

func _play(g: Node, si: int, plane_off: bool = false) -> Dictionary:
	# CARE=1이면 실패 케어(S1) 3패 상태로 돌린다 — 배급이 실제로 늘어나는지, 그리고 늘려도
	#   '세상에 한 대'(불변식 ②)가 그대로인지를 본다. 기본은 off = 기존 측정과 같은 조건.
	var care: bool = OS.get_environment("CARE") != ""
	g.dda_enabled = care
	if care:
		g.fail_streak[si] = g.CARE_MAX_FAILS
	g._start_stage(si)
	if plane_off:
		g.plane_cd_left = 1 << 30   # 대조군: 쿨다운이 안 끝나 픽업이 영영 안 떨어진다
	# CORE_HP=n이면 그 값으로 덮어써서 감도(누수 여유 1칸 = 승률 몇 pt인가)를 잰다.
	#   STAGES는 const라 런타임 수정이 막혀 있어 시작값을 직접 넣는다 — randi를 안 건드리니 스트림 보존.
	var chp: String = OS.get_environment("CORE_HP")
	if chp != "":
		g.core_hp = int(chp)
		g.core_hp_vis = float(int(chp))
	var guard: int = 0
	var seen: Dictionary = {}      # 등장한 픽업 id
	var n_grab: int = 0
	var n_fire: int = 0
	var held_prev: bool = false
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		_pump(g)
		if g.game_over or g.game_clear:
			break
		# 들고 있으면 즉시 발사 (사용 횟수 상한 측정)
		if bool(g.plane_held):
			var before: bool = bool(g.plane_held)
			g._fire_plane()
			if before and not bool(g.plane_held):
				n_fire += 1
			_pump(g)
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		_pump(g)
		# 등장 집계 + 불변식 검사
		var on_board: int = 0
		var threats: int = 0
		for e in g.enemies:
			var et: String = String(e["etype"])
			if et == "plane":
				on_board += 1
				seen[int(e["id"])] = true
			elif et != "gem":
				threats += 1
		# ② 세상에 한 대
		var world: int = on_board + (1 if bool(g.plane_held) else 0) + (g.plane_flights as Array).size()
		if world > 1:
			fails.append("스테이지 %d: 비행기가 세상에 %d대(보드%d·보유%s·비행%d)" % [
				si + 1, world, on_board, str(bool(g.plane_held)), (g.plane_flights as Array).size()])
		# ③ 웨이브 회계 — 픽업·보석은 카운터 밖이므로 위협만 세어 맞아야 한다
		if int(g.spawned) != int(g.killed) + int(g.leaked) + threats:
			var twins: int = 0
			for e2 in g.enemies:
				if String(e2["etype"]) == "split" and int(e2.get("gen", 0)) == 1:
					twins += 1
			if int(g.spawned) != int(g.killed) + int(g.leaked) + threats - twins:
				fails.append("스테이지 %d: 회계 불일치 spawned=%d killed=%d leaked=%d onboard=%d" % [
					si + 1, int(g.spawned), int(g.killed), int(g.leaked), threats])
		# 획득 = 보유가 false→true로 바뀐 순간
		if bool(g.plane_held) and not held_prev:
			n_grab += 1
		held_prev = bool(g.plane_held)
	_pump(g)
	var spawn_n: int = seen.size()
	return {"spawn": spawn_n, "grab": n_grab, "fire": n_fire, "leak": maxi(0, spawn_n - n_grab),
			"win": bool(g.game_clear)}

# resolve + 아이템 타이머가 다 소진될 때까지 프레임을 돌린다(획득 비행 0.42s, 발사 0.34s)
func _pump(g: Node) -> void:
	var s: int = 0
	while (g.resolving or not (g.plane_flights as Array).is_empty() or not (g.plane_shots as Array).is_empty()) and s < 400:
		g._process(0.05)
		s += 1

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
