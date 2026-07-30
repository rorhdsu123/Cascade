extends SceneTree
# 리팩터 회귀 하네스 — 시드 고정 byte-identical A/B.
#   봇(_best_move/_score)은 randi를 안 쓰고 게임만 쓴다 → seed() 고정 시 전 과정 결정적.
#   randi 호출 순서·횟수가 보존되면 아래 per-game 서명이 리팩터 전/후 완전 동일.
#   실행: PROBE_SEED=20260718 REGRESS_N=20 godot --headless --path . --script tools/regress.gd
#   비교: 리팩터 전 출력을 골든으로 저장 → 매 단계 후 diff. 첫 diff = randi 순서 깨짐 or 동작 변화.
#   골든: tools/regress.golden.txt (seed=20260718 N=20). 재베이스 이력:
#     · 거점사>클리어 우선 수정 반영
#     · C101 겹침 금지(한 칸에 유닛 하나) — 전 줄 시프트. 기전 변경이라 골든 대조로는 판정 불가여서
#       campaign_probe 시드고정 A/B로 대신 검증했다(밸런스 상수는 무수정):
#         전 14스테이지 N=100: 평균 승률 60.8%→61.4%
#         깔때기·난관 8스테이지(STAGE_IDX=0,1,2,3,6,7,8,9) N=300: 평균 52.8%→52.9%(Δ +0.18pp),
#           스테이지별 Δ 전부 95%CI(±5~8pp) 안 = 유의한 이동 0건 → 난이도 곡선 보존.
#         ⚠남는 한계: 스테이지 하나짜리 ~5pp 미만 효과는 이 표본으로 분해 못 한다(사람 플테 몫).
#   재생성/대조:
#     ⚠구 골든(C58)은 마지막 적 누수가 total을 채우며 동시에 core_hp를 0으로 만든 게임 19건을
#       'W1+dc1'(승리이면서 거점사)로 잘못 기록. _end_turn서 거점사를 _check_win보다 먼저 판정해
#       W0(거점사 패배)로 교정 → 그 19줄만 W1→W0, 나머지 randi 스트림 전부 불변.
#     PROBE_SEED=20260718 REGRESS_N=20 godot --headless --path . --script tools/regress.gd 2>/dev/null \
#       | grep -E "^(──|s[0-9])" | diff tools/regress.golden.txt -
#   ⚠의도적 동작 변경(기전 개편) 후엔 골든을 다시 떠서 커밋한다 — 안 그러면 의도된 차이가 노이즈로 섞임.

func _init() -> void:
	var sd: String = OS.get_environment("PROBE_SEED")
	seed(int(sd) if sd != "" else 20260718)
	var N: int = int(OS.get_environment("REGRESS_N")) if OS.get_environment("REGRESS_N") != "" else 20

	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.dda_enabled = false
	g.seed_game(int(sd) if sd != "" else 20260718)   # 게임 스트림 시드(코스메틱 전역 RNG와 분리)
	print("── REGRESS (seed=%s N=%d) ──" % [sd if sd != "" else "20260718", N])
	for pass_i in range(2):
		g.surge_enabled = (pass_i == 1)
		for si in range(g.STAGES.size()):
			for t in range(N):
				var r: Dictionary = _play(g, si)
				print("s%d u%d #%02d: W%d sp%d k%d lk%d pl%d cl%d dc%d ds%d" % [
					si, 1 if g.surge_enabled else 0, t,
					1 if r["win"] else 0, r["spawned"], r["killed"], r["leaked"],
					r["places"], r["clears"],
					1 if r["dead_core"] else 0, 1 if r["dead_stuck"] else 0,
				])
	quit()

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
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
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "leaked": g.leaked, "spawned": g.spawned, "killed": g.killed,
		"places": places, "clears": clears,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# ───────── 그리디 봇 (surge_probe.gd에서 복제, g의 public 표면만 읽음) ─────────
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
