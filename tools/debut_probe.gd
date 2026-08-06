extends SceneTree
# 데뷔 프로브 — "새 적이 판 시작 후 몇 번째 배치에 처음 나오나"를 잰다.
#   유저 관측("신규 적이 몇 턴 진행 후 나와서 새로운 느낌이 약하다")의 실측 대응물.
#   도입판 = 그 타입의 weights>0이 배열 순서상 처음 등장하는 판(자동 판별 — 스테이지가 늘어도 따라옴).
#   봇은 campaign_probe와 동형(그리디 인라인 복사, 이 저장소 관례). 배치 지표만 필요해 스코어 항은 최소.
#   PROBE_SEED=20260806 TRIALS=60 godot --headless --path . --script tools/debut_probe.gd

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 60
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	var sd: String = OS.get_environment("PROBE_SEED")
	if sd != "":
		seed(int(sd))
		g.seed_game(int(sd))
	g.cleared[0] = true   # 튜토리얼 비활성(봇 통계 오염 방지)
	print("(seed=%s TRIALS=%d)" % [sd, TRIALS])

	# 도입판 자동 판별
	var seen: Dictionary = {}
	var intros: Array = []
	for si in range(g.STAGES.size()):
		var w: Dictionary = g.STAGES[si].get("weights", {})
		for t in w.keys():
			if int(w[t]) > 0 and t != "basic" and not seen.has(t):
				seen[t] = true
				intros.append({"si": si, "type": String(t), "w": int(w[t])})
	print("idx | 신규   | 가중 | onboard | floor | 첫등장 배치(평균/중앙/p90/최대) | 데뷔전 사망·미등장 | 이름키")
	print("----+--------+------+---------+-------+--------------------------------+--------------------+-------")
	for it in intros:
		_probe(g, it, TRIALS)
	quit()

func _probe(g: Node, it: Dictionary, TRIALS: int) -> void:
	g.dda_enabled = false
	var si: int = int(it["si"])
	var ty: String = String(it["type"])
	var debuts: Array = []
	var never: int = 0
	for t in range(TRIALS):
		var d: int = _play(g, si, ty)
		if d < 0:
			never += 1
		else:
			debuts.append(d)
	debuts.sort()
	var mean: float = 0.0
	for d in debuts:
		mean += float(d)
	if not debuts.is_empty():
		mean /= float(debuts.size())
	var med: int = int(debuts[debuts.size() / 2]) if not debuts.is_empty() else -1
	var p90: int = int(debuts[mini(debuts.size() - 1, int(float(debuts.size()) * 0.9))]) if not debuts.is_empty() else -1
	var mx: int = int(debuts[debuts.size() - 1]) if not debuts.is_empty() else -1
	var st: Dictionary = g.STAGES[si]
	print(" %2d | %-6s | %3d%% |    %d    |   %d   |     %5.1f / %3d / %3d / %3d      |      %2d / %d회      | %s" % [
		si + 1, ty, int(it["w"]), int(st.get("onboard", 0)), int(st.get("floor", 0)),
		mean, med, p90, mx, TRIALS, never, String(st["name"])])

# 반환 = 신규 타입이 처음 스폰된 시점의 배치 수(place_count). 판이 끝날 때까지 안 나오면 -1.
func _play(g: Node, si: int, ty: String) -> int:
	g._start_stage(si)
	var guard: int = 0
	# 0 = 판을 여는 첫 화면에 이미 서 있음(시작 적이 그 타입) — 배치를 한 번도 안 해도 보인다.
	var debut: int = 0 if bool(g.seen_types.get(ty, false)) else -1
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
		if debut < 0 and bool(g.seen_types.get(ty, false)):
			debut = int(g.place_count)
	return debut

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
	var lines: int = 0
	for r in range(g.ROWS):
		var okr: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				okr = false
				break
		if okr:
			lines += 1
	for c in range(g.COLS):
		var okc: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				okc = false
				break
		if okc:
			lines += 1
	var filled: int = 0
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if occ[r][c]:
				filled += 1
	var holes: int = 0
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if not occ[r][c]:
				var nb: int = 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var dv: Vector2i = d as Vector2i
					var nx: int = c + dv.x
					var ny: int = r + dv.y
					if nx < 0 or nx >= g.COLS or ny < 0 or ny >= g.ROWS or occ[ny][nx]:
						nb += 1
				if nb >= 4:
					holes += 1
	var dmg: float = 0.0
	for e in g.enemies:
		for ci2 in cells:
			var cv2: Vector2i = ci2 as Vector2i
			if int(e["col"]) == cv2.x:
				dmg += 0.4
				break
	return float(lines) * 100.0 - float(filled) * 0.6 - float(holes) * 8.0 + dmg
