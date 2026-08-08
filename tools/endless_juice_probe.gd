extends SceneTree
# 무한모드 **연출 발화 계측** — 폴리싱 전에 "그 비트가 실제 판에서 몇 번 뜨나"를 먼저 잰다.
#   [[inert-indicator-check-value-first]] 안 읽히는 연출은 값부터 — 판당 0회면 폴리싱이 아니라 설계 문제.
# 헤드리스 OK(로직만 — 렌더 안 함). 봇은 endless_sim.gd와 같은 탐욕 봇(중 실력).

const TRIALS: int = 60
const GUARD: int = 3000
var ENDLESS: GDScript = load("res://modes/endless_mode.gd")

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)

	# best=0(첫 판) / best=중앙값(숙련 재도전) 두 갈래 — PB 발화는 best>0서만 산다
	for best_mode in ["첫판(best=0)", "재도전(best=P50)"]:
		var best_val: int = 0
		if best_mode.begins_with("재도전"):
			best_val = _median_score(g)
		_report(g, best_mode, best_val)
	quit()

func _median_score(g: Node) -> int:
	var scores: Array = []
	for t in range(20):
		g.seed_game(9000 + t)
		var r: Dictionary = _play(g, 0)
		scores.append(int(r["score"]))
	scores.sort()
	return int(scores[scores.size() / 2])

func _report(g: Node, label: String, best_val: int) -> void:
	var agg: Dictionary = {}
	var keys: Array = ["score", "depth", "zone_max", "zone_trans", "pb_pop", "clears",
		"praise2", "praise3", "praise4", "praise5", "praise6", "praise7", "praise8up",
		"climax", "core_hits", "revive_ready", "dead_core", "dead_stuck", "secs"]
	for k in keys:
		agg[k] = 0.0
	var zone_hist: Array = [0, 0, 0, 0, 0, 0]
	for t in range(TRIALS):
		g.seed_game(2000 + t)
		var r: Dictionary = _play(g, best_val)
		for k in keys:
			agg[k] = float(agg[k]) + float(r.get(k, 0))
		zone_hist[clampi(int(r["zone_max"]), 0, 5)] += 1

	var n: float = float(TRIALS)
	print("\n════ %s  (N=%d, 중 실력 봇, best=%s) ════" % [label, TRIALS, _comma(best_val)])
	print("판당 평균: 점수 %s · 깊이 %.0f · 줄클리어 %.1f회 · 판길이 ~%.0f초"
		% [_comma(int(float(agg["score"]) / n)), float(agg["depth"]) / n,
		   float(agg["clears"]) / n, float(agg["secs"]) / n])
	print("사인: 거점사 %.0f%% · 막힘사 %.0f%%" % [
		100.0 * float(agg["dead_core"]) / n, 100.0 * float(agg["dead_stuck"]) / n])
	print("── 연출 발화(판당 평균) ──")
	print("  존 전이(밤하늘 계단)  : %5.2f회   도달 최고존 분포 %s" % [float(agg["zone_trans"]) / n, str(zone_hist)])
	print("  PB 돌파 버스트        : %5.2f회" % [float(agg["pb_pop"]) / n])
	print("  전멸(CLIMAX)          : %5.2f회" % [float(agg["climax"]) / n])
	print("  거점 피격(코어 흔들)  : %5.2f회" % [float(agg["core_hits"]) / n])
	print("  칭찬 단어 사다리:")
	var names: Array = ["GOOD(2)", "NICE(3)", "GREAT(4)", "PERFECT(5)", "STRONG(6)", "FANTASTIC(7)", "UNREAL(8+)"]
	var pk: Array = ["praise2", "praise3", "praise4", "praise5", "praise6", "praise7", "praise8up"]
	var ptot: float = 0.0
	for k in pk:
		ptot += float(agg[k])
	for i in range(names.size()):
		var v: float = float(agg[pk[i]])
		var pct: float = 0.0 if ptot <= 0.0 else 100.0 * v / ptot
		print("    %-12s %5.2f회/판  (%4.1f%%)  %s" % [names[i], v / n, pct, "█".repeat(int(pct / 2.0))])

func _play(g: Node, best_val: int) -> Dictionary:
	var dir: Object = ENDLESS.new()
	g.director = dir
	g.mode = "play"
	g.stage_idx = 0
	g.surge_enabled = true
	g.floor_enabled = true
	g.dda_enabled = false
	g.persist_enabled = false
	g._init_game()
	g.endless_best = best_val
	g.endless_prev_best = best_val

	var m: Dictionary = {"zone_trans": 0, "pb_pop": 0, "clears": 0, "climax": 0, "core_hits": 0,
		"praise2": 0, "praise3": 0, "praise4": 0, "praise5": 0, "praise6": 0, "praise7": 0, "praise8up": 0,
		"secs": 0.0}
	var prev_zone: int = 0
	var prev_beat: bool = false
	var prev_core: int = g.core_hp
	var guard: int = 0
	while not g.game_over and guard < GUARD:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			m["secs"] = float(m["secs"]) + 0.05
			s += 1
			_sample(g, m, prev_zone, prev_beat, prev_core)
			prev_zone = g.zone_index
			prev_beat = g.endless_beat_best
			prev_core = g.core_hp
		if g.game_over:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		m["secs"] = float(m["secs"]) + 0.9   # 사람 배치 텀 어림(연출 시간과 별개)
		if g.combo >= 2:
			m["clears"] = int(m["clears"]) + 1
			var c: int = g.combo
			var key: String = "praise8up" if c >= 8 else "praise%d" % c
			m[key] = int(m.get(key, 0)) + 1
		elif g.combo == 1:
			m["clears"] = int(m["clears"]) + 1
		var s2: int = 0
		while g.resolving and s2 < 400:
			g._process(0.05)
			m["secs"] = float(m["secs"]) + 0.05
			s2 += 1
			_sample(g, m, prev_zone, prev_beat, prev_core)
			prev_zone = g.zone_index
			prev_beat = g.endless_beat_best
			prev_core = g.core_hp
	var s3: int = 0
	while g.resolving and s3 < 400:
		g._process(0.05)
		s3 += 1
		_sample(g, m, prev_zone, prev_beat, prev_core)
		prev_zone = g.zone_index
		prev_beat = g.endless_beat_best
		prev_core = g.core_hp

	m["score"] = g.endless_score
	m["depth"] = g.place_count
	m["zone_max"] = g.zone_index
	m["dead_core"] = 1 if (g.game_over and not g.stuck) else 0
	m["dead_stuck"] = 1 if (g.game_over and g.stuck) else 0
	m["revive_ready"] = 1 if not g.revive_used else 0
	return m

func _sample(g: Node, m: Dictionary, prev_zone: int, prev_beat: bool, prev_core: int) -> void:
	if g.zone_index > prev_zone:
		m["zone_trans"] = int(m["zone_trans"]) + 1
	if g.endless_beat_best and not prev_beat:
		m["pb_pop"] = int(m["pb_pop"]) + 1
	if g.core_hp < prev_core:
		m["core_hits"] = int(m["core_hits"]) + 1
	var cx: bool = g.flash_climax
	if cx and not bool(m.get("_prev_cx", false)):
		m["climax"] = int(m["climax"]) + 1
	m["_prev_cx"] = cx

func _comma(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	var cnt: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out

# ── 봇(endless_sim.gd와 동일 탐욕, 중 실력 고정) ──
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
	for slot2 in range(3):
		if slot2 == slot or g.tray[slot2].is_empty():
			continue
		if not _fits_anywhere(g, after, g.tray[slot2]["offsets"]):
			score -= 900.0
	# 적 근처 우선(중 실력): 완성 줄이 적을 덮으면 가산
	for e in g.enemies:
		var er: int = int(e["row"])
		var ec: int = int(e["col"])
		if full_rows.has(er) or full_cols.has(ec):
			score += 120.0
	var holes: int = 0
	for r4 in range(g.ROWS):
		for c4 in range(g.COLS):
			if not after[r4][c4]:
				holes += 1
	score += float(holes) * 2.0
	return score

func _fits_anywhere(g: Node, occ: Array, offsets: Array) -> bool:
	for r in range(g.ROWS):
		for c in range(g.COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
				if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS or occ[cc.y][cc.x]:
					ok = false
					break
			if not ok:
				continue
			return true
	return false
