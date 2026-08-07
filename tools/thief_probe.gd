extends SceneTree
# Protect(도둑) 스테이지 프로브 — 도둑-인지 봇으로 승률·패배사유·금고 잔량을 뽑는다.
#   campaign_probe의 봇에 '도둑 저지/회수' 우선항만 얹은 사본(다른 스테이지엔 영향 0 — 도둑 없음).
#   실행: godot --headless --path . --script tools/thief_probe.gd
#   ⚠이 판은 2026-07-31 캠페인에서 빠졌다(재설계 대상) → STAGES 인덱스가 아니라
#     stage_data.PARKED_PROTECT를 직접 열어 돌았다. **S27에 캠페인 복귀** → 이제 STAGES 안에 있고,
#     SD.first_protect_idx()로 찾는다(하드코딩 인덱스 금지 — 배열은 계속 움직인다).
#     직접 세우는 경로는 유지한다: thief_hp_mult 스윕이 복제본에 값을 먹여야 하기 때문.
#   스윕: HP_MULTS="0.35,0.6,0.9"로 thief_hp_mult를 런타임 오버라이드해 값별로 한 줄씩 찍는다
#     (STAGES는 const지만 안의 Dictionary는 쓸 수 있다 — [[balance-corehp-lever-and-probe-gotchas]]).
#   ⚠A/B는 반드시 시드 고정: PROBE_SEED=20260718 (배치마다 같은 시드로 리셋 = 짝지은 비교).
#     안 그러면 레버 효과가 시드 노이즈에 묻힌다([[compare-only-finished-probe-output]]의 형제 함정).

const SD = preload("res://stage_data.gd")

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 80
	var sd: String = OS.get_environment("PROBE_SEED")
	var mults: Array = []
	var me: String = OS.get_environment("HP_MULTS")
	if me != "":
		for tok in me.split(","):
			mults.append(float(tok))
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.dda_enabled = false
	var vault_start: int = int(SD.STAGES[SD.first_protect_idx()].get("vault_start", 0))
	print("Protect [파킹: 캠페인 밖] (vault_start %d, N %d%s)" % [
		vault_start, TRIALS, (", seed=" + sd) if sd != "" else ""])
	if mults.is_empty():
		_batch(g, TRIALS, sd, vault_start, -1.0)
		quit()
		return
	print("hp_mult | 승률   | 거점사 | 금고전소 | 막힘 | 평균금고 | 낚/회/탈(판당)")
	print("--------+--------+--------+----------+------+----------+----------------")
	for m in mults:
		_batch(g, TRIALS, sd, vault_start, float(m))
	quit()

func _batch(g: Node, TRIALS: int, sd: String, vault_start: int, mult: float) -> void:
	if sd != "":
		seed(int(sd))
		g.seed_game(int(sd))   # 배치마다 같은 스트림에서 출발 = 레버만 변수
	var wins: int = 0
	var dead_core: int = 0
	var dead_vault: int = 0
	var dead_stuck: int = 0
	var vault_sum: int = 0
	var grab_sum: int = 0
	var recover_sum: int = 0
	var escape_sum: int = 0
	for t in range(TRIALS):
		var r: Dictionary = _play(g, mult)
		if r["win"]:
			wins += 1
		if r["dead_core"]:
			dead_core += 1
		if r["dead_vault"]:
			dead_vault += 1
		if r["dead_stuck"]:
			dead_stuck += 1
		vault_sum += int(r["vault"])
		grab_sum += int(r["grab"])
		recover_sum += int(r["recover"])
		escape_sum += int(r["escape"])
	var n: float = float(TRIALS)
	if mult <= 0.0:
		print("  승률      : %.1f%%" % [100.0 * float(wins) / n])
		print("  거점사    : %d" % dead_core)
		print("  금고전소  : %d" % dead_vault)
		print("  막힘      : %d" % dead_stuck)
		print("  평균 금고 : %.2f / %d" % [float(vault_sum) / n, vault_start])
		print("  낚아채기/회수/탈출(판당): %.2f / %.2f / %.2f" % [
			float(grab_sum) / n, float(recover_sum) / n, float(escape_sum) / n])
		return
	print("  %.2f  | %5.1f%% |  %3d   |   %3d    | %3d  |   %.2f   | %.2f / %.2f / %.2f" % [
		mult, 100.0 * float(wins) / n, dead_core, dead_vault, dead_stuck,
		float(vault_sum) / n, float(grab_sum) / n, float(recover_sum) / n, float(escape_sum) / n])

# 파킹된 판은 _start_stage(idx) 경로가 없다 → st·감독을 직접 세우고 _init_game만 태운다
#   (STAGES const는 안의 Dictionary까지 read-only라 어차피 복제본이 필요하다 — 스윕도 여기서 먹인다).
func _play(g: Node, mult: float = -1.0) -> Dictionary:
	var d: Dictionary = SD.STAGES[SD.first_protect_idx()].duplicate(true)
	if mult > 0.0:
		d["thief_hp_mult"] = mult
	g.endless = false
	g.featured = false
	g.stage_idx = -1              # 캠페인 판이 아니다 = 진행도(cleared)와 무관
	g.st = d
	g.director = load("res://modes/stage_mode.gd").new(d)
	g.mode = "play"
	g._init_game()
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
	return {
		"win": g.game_clear, "vault": g.vault,
		"grab": g.dbg_grab, "recover": g.dbg_recover, "escape": g.dbg_escape,
		"dead_core": g.game_over and not g.stuck and g.core_hp <= 0,
		"dead_vault": g.game_over and not g.stuck and g.core_hp > 0 and g.vault <= 0,
		"dead_stuck": g.game_over and g.stuck,
	}

# ── 그리디 봇 (campaign_probe 사본 + 도둑 우선항) ──
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
				var et: String = String(e.get("etype", ""))
				if et == "bomb":
					var fuse: int = int(e.get("fuse", 99))
					score += 250.0 * float(maxi(1, 9 - mini(fuse, 8)))
				elif et == "thief":
					# 도둑 회수(carrying)는 최우선(금고 되돌림). 접근 중이면 깊을수록 급함(곧 grab).
					if bool(e.get("carrying", false)):
						score += 450.0
					else:
						score += 60.0 + 34.0 * float(int(e["row"]))
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
