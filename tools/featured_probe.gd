extends SceneTree

# featured 결정적 트랙 검증(헤드리스 봇, 일회성).
# 목적 ① ★결정성 증명: 같은 시드를 서로 다른 봇(약≠강)으로 플레이 → 보드·처치수가 갈려도
#     piece[i]/spawn[d] 시퀀스(track_log)가 byte-identical인가. = "전원 동일 판"의 코어 계약.
# 목적 ② 난이도 밴드: featured가 프리 무한과 비슷한 사망 프로필인가(즉사 남발·자명함 배제).
#     fit 필터를 껐으니 막힘사 비중이 프리보다 오를 것(C53 ⑤ 의도) — 얼마나 오르는지 실측.
# 실행: godot --headless --path . --script tools/featured_probe.gd

const SEEDS: Array = [20260719, 20260720, 20260721, 424242, 7]
const TRIALS: int = 200
const GUARD: int = 3000

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)   # _ready

	print("\n########  featured 결정적 트랙 검증  ########")

	# ── ① 결정성: 같은 시드 · 다른 봇 → track_log 동일 ──
	print("\n[①] 결정성 증명 — 같은 시드를 약봇 vs 강봇으로 (track_log byte-identical?)")
	print("seed      | 약:깊이 | 강:깊이 | 공통 log | 첫 불일치 | 판정")
	print("----------+---------+---------+----------+-----------+------")
	var all_ok: bool = true
	for sd in SEEDS:
		var a: Dictionary = _play(g, 0, int(sd), true)   # 약봇, 기록 on
		var b: Dictionary = _play(g, 2, int(sd), true)   # 강봇, 기록 on
		var la: Array = a["log"]
		var lb: Array = b["log"]
		var n: int = mini(la.size(), lb.size())
		var mismatch: int = -1
		for i in range(n):
			if str(la[i]) != str(lb[i]):
				mismatch = i
				break
		var ok: bool = (mismatch == -1) and n > 0
		all_ok = all_ok and ok
		print("%9d | %7d | %7d | %8d | %9s | %s" % [
			int(sd), a["depth"], b["depth"], n,
			("-" if mismatch == -1 else str(mismatch)),
			("✅ 동일" if ok else "❌ 갈림")])
	print("→ 결정성: %s" % ("✅ 전 시드 byte-identical (전원 동일 판 성립)" if all_ok else "❌ 시드별 desync 발생"))

	# ── ② 난이도 밴드 (기록 off, N판/시드 평균) ──
	print("\n[②] 난이도 프로필 — DDA off · %d판/시드/실력" % TRIALS)
	print("실력 | 죽는깊이 |  중앙 | 스타일 | 콤보 | 거점% | 막힘% | 밴드축")
	print("-----+----------+-------+--------+------+-------+-------+-------")
	var skill_name: Array = ["약", "중", "강"]
	var mean_by_skill: Array = []
	for skill in [0, 1, 2]:
		var depths: Array = []
		var style_sum: float = 0.0
		var combo_sum: int = 0
		var dc: int = 0
		var ds: int = 0
		for t in range(TRIALS):
			var seed: int = 900000 + t   # 시드 다양화(트랙 여러 개 평균)
			var r: Dictionary = _play(g, skill, seed, false)
			depths.append(r["depth"])
			style_sum += r["style"]
			combo_sum += r["maxcombo"]
			if r["dead_core"]:
				dc += 1
			if r["dead_stuck"]:
				ds += 1
		depths.sort()
		var nn: float = float(TRIALS)
		var mean: float = 0.0
		for d in depths:
			mean += float(d)
		mean /= nn
		mean_by_skill.append(mean)
		print("  %s  |  %6.1f  | %5d | %6.0f | %4.1f | %4.1f%% | %4.1f%% |" % [
			skill_name[skill], mean, int(depths[int(nn * 0.5)]),
			style_sum / nn, float(combo_sum) / nn,
			100.0 * float(dc) / nn, 100.0 * float(ds) / nn])
	var band: float = 0.0 if mean_by_skill[0] <= 0.0 else mean_by_skill[2] / mean_by_skill[0]
	print("→ 표현 밴드(강÷약) = %.2f×  (1.4× 위면 실력이 깊이를 벌린다)" % band)
	quit()

func _play(g: Node, skill: int, seed: int, record: bool) -> Dictionary:
	g.track_record = record
	g._start_featured(seed)   # 실제 진입 경로(FeaturedMode + 인덱스-주소 조각/스폰)
	g.dda_enabled = false
	return _drive(g, skill, GUARD)

# 이미 시작된 게임을 봇으로 끝까지 구동(스윕 재사용). 시작/시드 세팅은 호출자 몫.
func _drive(g: Node, skill: int, guard_max: int) -> Dictionary:
	var maxcombo: int = 0
	var style: float = 0.0
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < guard_max:
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
		if g.resolving:
			var s2: int = 0
			while g.resolving and s2 < 400:
				g._process(0.05)
				s2 += 1
			style += float(g.killed - kbefore) * float(g.combo)
	var s3: int = 0
	while g.resolving and s3 < 400:
		g._process(0.05)
		s3 += 1
	return {
		"depth": g.place_count, "style": style, "maxcombo": maxcombo,
		"log": g.track_log.duplicate(),
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
		return score

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
