extends SceneTree
# 밀도 실측 — "보드가 얼마나 희박한가 + 터뜨릴 때 표적이 얼마나 있나"를 봇 플레이로 계측.
# 콤보 재정의 논의(연쇄/커버리지가 성립하려면 표적 밀도가 받쳐줘야 함)의 사실 근거.
# 실행: godot --path . --script tools/density_probe.gd  (헤드리스 OK — 렌더 안 함, 로직만)
#
# 측정:
#  - 평균 동시 적 수: 매 턴(배치 직전) g.enemies.size() 평균 + 분포
#  - 터뜨릴 때 적수: 줄 완성(_begin_resolve 발동) 순간 보드 위 적 수
#  - 명중 적수: 그 폭발이 실제로 맞히는 적 수 (g.resolve_hits.size())
#  - 발사 레인 / 빈 레인: g.resolve_rocket_plan 중 적이 0인 레인 = 눈에 보이는 헛방

const TRIALS: int = 200

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.dda_enabled = false
	print("── 밀도 실측: 동시 적 · 무표적 발동 · 빈 레인 (밀도 하한 floor A/B) ──")
	for pass_i in range(2):
		g.floor_enabled = (pass_i == 1)
		print("")
		print("[ floor %s ]" % ("ON (after)" if g.floor_enabled else "OFF (before)"))
		print("stage | 평균적 | 최대적 | 무표적발동% | 빈레인% | 밴드명중 | 클라막스 | 밴드+처치%")
		print("------+--------+--------+------------+---------+----------+----------+-----------")
		for si in range(g.STAGES.size()):
			_run_stage(g, si)
	quit()

func _run_stage(g: Node, si: int) -> void:
	var turn_enemy_sum: float = 0.0
	var turn_count: int = 0
	var max_concurrent: int = 0
	# 비-클라이맥스 발동만: 밴드 제거 시 처치 손실 계측
	var nc_count: int = 0
	var nc_band_sum: float = 0.0       # 밴드(현재) 명중 적
	var nc_lineonly_sum: float = 0.0   # 완성 줄만 명중 적
	var nc_bandadds: int = 0           # 밴드가 줄만보다 1마리 이상 더 잡은 발동
	var nc_notarget: int = 0           # 무표적 발동: 줄 완성했는데 0마리 명중
	var lane_sum: int = 0              # 총 발사 레인(로켓 계획)
	var empty_lane_sum: int = 0        # 그 중 적 0인 빈 레인
	var climax_count: int = 0
	var games: int = 0

	for t in range(TRIALS):
		games += 1
		g._start_stage(si)
		var guard: int = 0
		while not g.game_over and not g.game_clear and guard < 3000:
			guard += 1
			var s: int = 0
			while g.resolving and s < 400:
				g._process(0.05)
				s += 1
			if g.game_over or g.game_clear:
				break
			# 매 턴(배치 직전) 동시 적 수 표본
			var ec: int = g.enemies.size()
			turn_enemy_sum += float(ec)
			turn_count += 1
			if ec > max_concurrent:
				max_concurrent = ec
			var mv: Dictionary = _best_move(g)
			if mv.is_empty():
				break
			g.sel = mv["slot"]
			g.hover_col = mv["col"]
			g.hover_row = mv["row"]
			g._place_piece()
			# 방금 배치가 줄을 완성해 발동했나 → resolve 계획이 갓 잡힌 상태
			if g.resolving and (g.resolve_hits.size() > 0 or g.resolve_rocket_plan.size() > 0):
				if g.flash_climax:
					climax_count += 1
					continue   # 클라이맥스(전멸)는 그대로 유지 → 밴드 제거 비교 대상 아님
				nc_count += 1
				var band_hits: int = g.resolve_hits.size()   # 현재(밴드) 명중
				# 완성 줄만 명중 = 적의 row가 완성 행이거나 col이 완성 열
				var lineonly: int = 0
				for e in g.enemies:
					if g.clear_rows.has(int(e["row"])) or g.clear_cols.has(int(e["col"])):
						lineonly += 1
				nc_band_sum += float(band_hits)
				nc_lineonly_sum += float(lineonly)
				if band_hits > lineonly:
					nc_bandadds += 1
				if band_hits == 0:
					nc_notarget += 1
				# 빈 레인: 로켓 계획 레인 중 적이 0인 것
				for rp in g.resolve_rocket_plan:
					lane_sum += 1
					var occ_lane: bool = false
					for e2 in g.enemies:
						if rp["dir"] == "col" and int(e2["col"]) == int(rp["idx"]):
							occ_lane = true
							break
						if rp["dir"] == "row" and int(e2["row"]) == int(rp["idx"]):
							occ_lane = true
							break
					if not occ_lane:
						empty_lane_sum += 1
		# 마지막 resolve 소화
		var s2: int = 0
		while g.resolving and s2 < 400:
			g._process(0.05)
			s2 += 1

	var nc: float = maxf(1.0, float(nc_count))
	print("  %d   | %5.2f | %5.2f |   %5.1f%%   |  %5.1f%%  |  %5.2f  |  %5.2f  |  %5.1f%%" % [
		si + 1,
		turn_enemy_sum / float(maxi(1, turn_count)),   # 평균 동시 적
		float(max_concurrent),                          # 최대 동시 적
		100.0 * float(nc_notarget) / nc,                # 무표적 발동%
		100.0 * float(empty_lane_sum) / float(maxi(1, lane_sum)),  # 빈 레인%
		nc_band_sum / nc,                               # 밴드 명중/발동
		float(climax_count) / float(maxi(1, games)),    # 클라이맥스/판
		100.0 * float(nc_bandadds) / nc,                # 밴드가 +처치한 발동%
	])

# ───────── 그리디 봇 (tools/sim.gd에서 복제) ─────────
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
