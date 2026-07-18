extends SceneTree

# 무한모드 램프 검증용 헤드리스 봇 (일회성 — 검증 후 삭제).
# 목적 ①: 죽는 깊이(place_count) 분포 = 코지 플래토/조르기/종말이 실제로 그 순서로 오는가.
# 목적 ②: ★표현 밴드 — 봇 실력 사다리(약/중/강)의 죽는 깊이가 '벌어지는가'.
#   벌어지면 무한이 산다(실력이 점수를 만든다). 뭉치면 모두 같은 벽 = 사실상 유한 모드.
# 점수 모델(#1 결정): 스타일 점수 = Σ(폭발 처치수 × 그때 콤보). 리더보드 정렬 기준.

const TRIALS: int = 300
const GUARD: int = 3000
var ENDLESS: GDScript = load("res://modes/endless_mode.gd")

# CORE_HP 스윕: 거점사 75% 창을 찾는다(닳는 마진 유지하며 막힘→거점 뒤집힘 지점).
const HP_SWEEP: Array = [14]   # 확정값 확인
const SKILLS: Array = [0, 1, 2]
const SKILL_NAME: Array = ["약", "중", "강"]

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)   # _ready

	print("\n########  무한모드 CORE_HP 스윕  (DDA off · %d판/셀)  ########" % TRIALS)
	print("과녁: 중 실력 기준 거점사 ≈75%%. + 판 길이(세션/광고 카덴스) + 밴드 유지 확인.")
	print("HP | 실력 | 죽는깊이 |  중앙 | 스타일 | 콤보 | 거점% (거점/막힘)")
	print("---+------+----------+-------+--------+------+-------------------")
	for hp in HP_SWEEP:
		var mean_by_skill: Array = []
		for skill in SKILLS:
			var m: Dictionary = _run(g, skill, hp)
			mean_by_skill.append(m["depth_mean"])
		var band: float = 0.0 if mean_by_skill[0] <= 0.0 else mean_by_skill[mean_by_skill.size() - 1] / mean_by_skill[0]
		print("   |      |          |       |        |      |  밴드(강÷약)=%.2f×" % band)
		print("---+------+----------+-------+--------+------+-------------------")
	quit()

func _run(g: Node, skill: int, hp: int) -> Dictionary:
	var depths: Array = []
	var style_sum: float = 0.0
	var maxcombo_sum: int = 0
	var dead_core: int = 0
	var dead_stuck: int = 0
	for t in range(TRIALS):
		g.seed_game(1000 + t)   # 게임 스트림 시드(셀 간 같은 시드 = 공정 비교; 코스메틱 분리)
		var r: Dictionary = _play(g, skill, hp)
		depths.append(r["depth"])
		style_sum += r["style"]
		maxcombo_sum += r["maxcombo"]
		if r["dead_core"]:
			dead_core += 1
		if r["dead_stuck"]:
			dead_stuck += 1
	depths.sort()
	var n: float = float(TRIALS)
	var mean: float = 0.0
	for d in depths:
		mean += float(d)
	mean /= n
	var core_pct: float = 100.0 * float(dead_core) / n
	print("%2d |  %s  |  %6.1f  | %5d | %6.0f | %4.1f | %4.1f%% (%3d/%3d)" % [
		hp, SKILL_NAME[skill], mean, int(depths[int(n * 0.5)]),
		style_sum / n, float(maxcombo_sum) / n, core_pct, dead_core, dead_stuck])
	return {"depth_mean": mean}

func _play(g: Node, skill: int, core_hp: int) -> Dictionary:
	var dir: Object = ENDLESS.new()
	dir.CORE_HP = core_hp
	g.director = dir
	g.mode = "play"
	g.stage_idx = 0
	g.surge_enabled = true
	g.floor_enabled = true
	g.dda_enabled = false   # 리더보드 공정성
	g._init_game()

	var maxcombo: int = 0
	var style: float = 0.0
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < GUARD:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _best_move(g, skill)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		var kbefore: int = g.killed
		g._place_piece()
		if g.combo > maxcombo:
			maxcombo = g.combo
		# 폭발 소화 후 스타일 점수: 이 배치가 잡은 적 × 그때 콤보
		if g.resolving:
			var s2: int = 0
			while g.resolving and s2 < 400:
				g._process(0.05)
				s2 += 1
			style += float(g.killed - kbefore) * float(g.combo)
	# 잔여 resolve 소화
	var s3: int = 0
	while g.resolving and s3 < 400:
		g._process(0.05)
		s3 += 1
	return {
		"depth": g.place_count, "style": style, "maxcombo": maxcombo, "killed": g.killed,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

func _best_move(g: Node, skill: int) -> Dictionary:
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
				var sc: float = _score(g, cells, slot, skill)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best

func _score(g: Node, cells: Array, slot: int, skill: int) -> float:
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
	var score: float = 500.0 * float(lines)

	# 생존(전 실력 공통): 남은 트레이 조각이 놓일 곳 사라지면 치명
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

	if skill == 0:
		return score   # 약: 줄완성+자기막힘회피만 (정돈·조준 없음)

	# 중·강 공통: 보드 정돈(채움 억제 + 고립 구멍 페널티 + 밀집)
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

	if skill == 1:
		return score   # 중: 정돈까지, 적 레인 조준 없음

	# 강: 완성 줄이 실제로 적을 잡는가(밀집 레인 선호) + 거점 가까운 적 우선
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
