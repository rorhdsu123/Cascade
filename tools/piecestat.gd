extends SceneTree

# 조각 분포 계측 — 그리디 봇으로 실제 플레이하며 '실제로 손에 들어온 조각'을 집계.
# ⚠가중치 표를 손으로 읽어 비율을 짐작하지 말 것: _pool_piece의 fit-guard가 '지금 안 들어가는 조각'을
#   후보에서 빼므로 실제 배급은 가중치 비율과 다르다(R33처럼 큰 조각일수록 크게 벌어진다).
#   그리고 봇 지표(승률·동시삭제)는 단조로움을 못 잡는다 — 사람은 같은 조각이 반복되면 질린다.
#   실행: PROBE_SEED=20260801 TRIALS=60 STAGE_IDX=0 godot --headless --path . --script tools/piecestat.gd

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 60
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.set("persist_enabled", false)   # ⚠add_child가 _ready를 돌려 true로 켠다 — 안 끄면 봇의 클리어가
	                                  #   실유저 진행도에 각인된다(다른 프로브 전부 이 가드가 있다)
	var sd: String = OS.get_environment("PROBE_SEED")
	if sd != "":
		seed(int(sd))
		g.seed_game(int(sd))
	g.cleared[0] = true   # 튜토리얼 비활성 — 스크립트 트레이가 통계에 섞이면 안 된다
	# 케어가 걸린 상태의 배급도 재려고 둔 손잡이(care_probe의 조건과 짝을 맞춘다).
	#   CARE_STREAK=3 SHARE=41 → 3패 케어 + 5바 가중 41% 사본. 둘 다 0/빈값이면 기본 배급.
	#   ⚠'가중치 41%'가 손에 들어오는 비율로 몇 %인지는 fit-guard 때문에 따로 재야 한다(파일 머리 주석).
	var care_streak: int = int(OS.get_environment("CARE_STREAK")) if OS.get_environment("CARE_STREAK") != "" else 0
	var share: float = (float(OS.get_environment("SHARE")) / 100.0) if OS.get_environment("SHARE") != "" else 0.0
	var only: Array = []
	var only_env: String = OS.get_environment("STAGE_IDX")
	if only_env != "":
		for tok in only_env.split(","):
			only.append(int(tok))

	var count: Dictionary = {}
	var cells_sum: float = 0.0
	var n: float = 0.0
	var f_hist: Array = [0, 0, 0, 0, 0]   # f<0.3, <0.45, <0.6, <0.75, >=0.75
	var tier: Dictionary = {"SMALL": 0, "MID": 0, "BIG": 0}

	var n_stage: int = 0
	for si in range(g.STAGES.size()):
		if not only.is_empty() and not only.has(si):
			continue
		n_stage += 1
		for t in range(TRIALS):
			g.dda_enabled = care_streak > 0
			g.fail_streak[si] = care_streak
			g._start_stage(si)
			if share > 0.0:
				g.pool_override = _care_pool(g.STAGES[si].get("pool", {}), share)   # ⚠_start_stage 뒤에 덮는다
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
				# 이 배치 시점의 보드 여유
				var free: int = 0
				for br in range(g.ROWS):
					for bc in range(g.COLS):
						if g.board[br][bc] == "":
							free += 1
				var f: float = float(free) / float(g.ROWS * g.COLS)
				var bi: int = 0
				if f >= 0.75: bi = 4
				elif f >= 0.6: bi = 3
				elif f >= 0.45: bi = 2
				elif f >= 0.3: bi = 1
				f_hist[bi] += 1

				var ty: String = g.tray[mv["slot"]]["type"]
				count[ty] = int(count.get(ty, 0)) + 1
				cells_sum += float((g.PIECES[ty] as Array).size())
				n += 1.0
				if g.SMALL_POOL.has(ty): tier["SMALL"] += 1
				elif g.MID_POOL.has(ty): tier["MID"] += 1
				else: tier["BIG"] += 1

				g.sel = mv["slot"]
				g.hover_col = mv["col"]
				g.hover_row = mv["row"]
				g._place_piece()

	print("\n===== 실제 플레이 중 조각 분포 (%d판, 조각 %d개) =====" % [TRIALS * n_stage, int(n)])
	var keys: Array = count.keys()
	keys.sort_custom(func(a, b): return int(count[a]) > int(count[b]))
	for k in keys:
		var pct: float = 100.0 * float(count[k]) / n
		print("  %-4s (%d칸) : %5.2f%%  %s" % [k, (g.PIECES[k] as Array).size(), pct, "#".repeat(int(pct))])
	print("\n티어별:  SMALL %5.2f%%   MID %5.2f%%   BIG(3x3) %5.2f%%" % [
		100.0 * float(tier["SMALL"]) / n, 100.0 * float(tier["MID"]) / n, 100.0 * float(tier["BIG"]) / n])
	print("평균 조각 크기: %.2f칸" % (cells_sum / n))
	var fh: float = 0.0
	for v in f_hist:
		fh += float(v)
	print("배치 시점 보드 여유 f 분포:  <0.30 %4.1f%% | <0.45 %4.1f%% | <0.60 %4.1f%% | <0.75 %4.1f%% | >=0.75 %4.1f%%" % [
		100.0 * float(f_hist[0]) / fh, 100.0 * float(f_hist[1]) / fh, 100.0 * float(f_hist[2]) / fh,
		100.0 * float(f_hist[3]) / fh, 100.0 * float(f_hist[4]) / fh])
	var i5: float = 100.0 * float(int(count.get("I5h", 0)) + int(count.get("I5v", 0))) / n
	print("5바(I5h+I5v) 실배급: %.2f%%   (CARE_STREAK=%d SHARE=%s)" % [
		i5, care_streak, ("기본" if share <= 0.0 else "%d%%" % int(round(share * 100.0)))])
	quit()

# 5바 비중만 목표까지 끌어올린 사본 (tools/care_probe.gd에서 복사 — 이 저장소 관례대로 인라인)
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
	var want: float = target * float(rest) / (1.0 - target)
	if want <= float(i5):
		return {}
	var scale: float = want / float(i5)
	var out: Dictionary = base.duplicate()
	out["I5h"] = maxi(1, int(round(float(base["I5h"]) * scale)))
	out["I5v"] = maxi(1, int(round(float(base["I5v"]) * scale)))
	return out

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
