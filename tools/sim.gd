extends SceneTree

# 밸런스 검증용 헤드리스 봇 (일회성 — 검증 후 삭제)
# 그리디 AI로 각 스테이지를 N판 돌려 승률·누수·콤보 분포를 뽑는다.

const TRIALS: int = 300

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)   # _ready 호출

	for mode in [false, true]:
		g.dda_enabled = mode
		print("\n########  DDA %s  ########" % ("ON" if mode else "OFF"))
		print("stage | 승률   | 평균누수 | 평균처치 | 최대콤보 | 전멸/판 | 클리어율 | 패배사유(거점/막힘)")
		print("------+--------+----------+----------+----------+---------+----------+--------------------")
		_run_all(g)
	quit()

func _run_all(g: Node) -> void:
	for si in range(g.STAGES.size()):
		var wins: int = 0
		var leak_sum: int = 0
		var kill_sum: int = 0
		var maxcombo_sum: int = 0
		var climax_sum: int = 0
		var dead_core: int = 0
		var dead_stuck: int = 0
		var place_sum: int = 0
		var clear_sum: int = 0
		var stuck_fulltray: int = 0
		var stuck_fill_sum: int = 0
		for t in range(TRIALS):
			var r: Dictionary = _play(g, si)
			if r["win"]:
				wins += 1
			leak_sum += r["leaked"]
			kill_sum += r["killed"]
			maxcombo_sum += r["maxcombo"]
			climax_sum += r["climax"]
			place_sum += r["places"]
			clear_sum += r["clears"]
			if r["dead_core"]:
				dead_core += 1
			if r["dead_stuck"]:
				dead_stuck += 1
				stuck_fill_sum += r["fill_at_end"]
				if r["tray_at_end"] >= 3:
					stuck_fulltray += 1
		var n: float = float(TRIALS)
		var rate: float = 0.0 if place_sum == 0 else 100.0 * float(clear_sum) / float(place_sum)
		var ft: float = 0.0 if dead_stuck == 0 else 100.0 * float(stuck_fulltray) / float(dead_stuck)
		var af: float = 0.0 if dead_stuck == 0 else float(stuck_fill_sum) / float(dead_stuck)
		print("  %d   | %5.1f%% |   %4.2f   |   %4.1f   |   %4.2f   |  %4.2f   |  %4.1f%%   |  %3d / %3d  | 풀트레이즉사 %4.1f%% · 죽을때보드 %4.1f/%d" % [
			si + 1, 100.0 * float(wins) / n, float(leak_sum) / n, float(kill_sum) / n,
			float(maxcombo_sum) / n, float(climax_sum) / n, rate, dead_core, dead_stuck, ft, af,
			g.ROWS * g.COLS])

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
	var maxcombo: int = 0
	var climax: int = 0
	var places: int = 0
	var clears: int = 0
	var tray_at_end: int = 0
	var fill_at_end: int = 0
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		# resolve 연출 재생을 시간 진행시켜 소화(데미지·사망이 이 안에서 반영됨)
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break   # 놓을 곳 없음(다음 _end_turn에서 stuck 처리됨)
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		var before: int = g.combo
		g._place_piece()
		places += 1
		if g.resolving or g.combo > before:
			clears += 1        # 이 배치가 줄을 지웠나
		if g.combo > maxcombo:
			maxcombo = g.combo
		if g.combo >= g.CLIMAX_COMBO:
			climax += 1
	# 마지막 resolve 소화
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	# 사망 '시점'의 상태 기록: 트레이 3개 꽉 찬 채 막혔다면 = 딜 사고(불가항력), 아니면 스스로 몰린 것
	for sl in range(3):
		if not g.tray[sl].is_empty():
			tray_at_end += 1
	for br in range(g.ROWS):
		for bc in range(g.COLS):
			if g.board[br][bc] != "":
				fill_at_end += 1
	return {
		"win": g.game_clear, "leaked": g.leaked, "killed": g.killed,
		"maxcombo": maxcombo, "climax": climax, "places": places, "clears": clears,
		"tray_at_end": tray_at_end, "fill_at_end": fill_at_end,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# 그리디: 줄 완성(특히 적 있는 레인)을 최우선, 그다음 보드 정돈
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
	# 가상 배치
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

	# 생존성: 이 배치 후 트레이의 남은 조각이 하나라도 못 놓이게 되면 치명(막힘 직행)
	# ※ 완성 줄은 배치 후 즉시 비워지므로 그걸 반영한 보드로 검사
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
		# 이 배치로 트레이가 비면 새 3조각이 리필된다 — 보드가 빡빡하면 리필이 곧 죽음
		var free: int = 0
		for r3 in range(g.ROWS):
			for c3 in range(g.COLS):
				if not after[r3][c3]:
					free += 1
		if free < 12:
			score -= 300.0

	# 완성 줄이 적을 실제로 잡는가 (열 완성 = 그 레인 전체 청소 → 적 밀집 레인 선호)
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
		# 거점에 가까운 적을 먼저 (누수 방지)
		for e in g.enemies:
			for fc3 in full_cols:
				if int(e["col"]) == int(fc3):
					score += 8.0 * float(e["row"])

	# 보드 정돈: 채워진 칸 수는 줄이고(=줄 완성 유도), 고립 구멍 페널티
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
	# 보드가 찰수록 가파르게 페널티(빡빡함이 곧 사망) + 고립 구멍 강한 페널티
	var fill_frac: float = float(filled) / float(g.ROWS * g.COLS)
	score -= 60.0 * fill_frac * fill_frac * float(g.ROWS * g.COLS) / 10.0
	score -= 70.0 * float(holes)

	# 밀집도: 기존 블록·벽에 붙여 놓기(파편화 방지)
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

# 주어진 보드(occ)에 offsets 조각이 놓일 자리가 하나라도 있나
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
