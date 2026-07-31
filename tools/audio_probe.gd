extends SceneTree
# 오디오 진흙·예산 감사 (R1 · 정본: AUDIO_PLAN.md)
#   실행: godot --path . --script tools/audio_probe.gd      ⚠창 모드(--headless는 렌더 텍스처 null)
#
# 왜 이게 필요한가: 소리도 프레임에 안 남는다. "캐스케이드에서 소리가 진흙이 되는가"는 귀로만
#   알 수 있고 귀는 자동화가 안 되므로, 믹서가 남기는 로그(_sfx_log — 발화도 드롭도 이유와 함께)를
#   떠서 **겹침·예산·사다리**를 기계적으로 감사한다. 음색 판정은 tools/audio_bake.gd 몫(사람 귀).
#
# 무엇을 보나:
#   ① 착지음이 실제로 매 배치에 하나씩 나가나(조용히 삼켜지지 않나)
#   ② 동시에 울리는 보이스가 상한(8)을 넘지 않나  ← 진흙의 직접 지표
#   ③ 초당 발화가 예산 안인가
#   ④ 연쇄 사다리가 판 안에서 단조 상승하고 상한(16반음)에서 멈추나
#   ⑤ fanfare가 판당 1회를 넘지 않나
#   ⑥ 같은 시드 두 패스 = 로그가 완전히 동일한가(오디오 경로에 RNG가 새면 회귀 골든이 시프트한다)
#   ⑦ 어휘는 다섯뿐인가
#
# ⚠시드 고정: 합/불을 내는 프로브는 반드시 시드를 박는다(analytics_probe의 교훈).
const SEED_CAMPAIGN: int = 20250123
const PLACES: int = 14

const IDLE_HUMAN: int = 108      # 1/60 프레임 = 1.8초/수(사람 템포). 안 넣으면 '초당 발화수'가 무의미해진다
const IDLE_STRESS: int = 1       # 인간이 불가능한 최고 속도 = 상한 시험

# 단어별 물리 길이(초) — 겹침 계산용. pitch_scale이 올라가면 실제론 더 짧게 끝나므로 보수적 상한이다.
const WORD_DUR: Dictionary = {"grab": 0.075, "place": 0.09, "clear": 0.34, "chain": 0.19, "tap": 0.06}
const MAX_VOICES: int = 8
const MAX_FIRES_IN_1S: int = 15         # 예산 14/초 + 회복 여유 1
const LADDER_MAX_SEMI: int = 16

var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("%s %s%s" % ["OK  " if ok else "FAIL", tag, ("  — " + detail) if detail != "" else ""])

# 최소 봇 — 줄이 되는 수를 우선(삭제·연쇄 어휘를 실제로 뽑기 위해). 튜토리얼 잠금 중엔 목표 칸 안에만.
func _bot_move() -> Dictionary:
	var fallback: Dictionary = {}
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
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS or g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				if bool(g.tut_lock):
					var inside: bool = true
					for cc2 in cells:
						if not (g.tut_cells as Array).has(cc2):
							inside = false
							break
					if not inside:
						continue
				var mv: Dictionary = {"slot": slot, "col": c, "row": r}
				if g._would_clear(cells):
					return mv
				if fallback.is_empty():
					fallback = mv
	return fallback

func _idle(frames: int) -> void:
	for _i in range(frames):
		g._process(1.0 / 60.0)

# 연출이 끝날 때까지 굴린다 — 연쇄(순차 피격)가 전부 재생돼야 사다리가 로그에 남는다.
func _settle() -> void:
	var s: int = 0
	while g.resolving and s < 1200:
		g._process(1.0 / 60.0)
		s += 1

func _play(max_places: int, idle: int) -> int:
	var places: int = 0
	while not g.game_over and not g.game_clear and places < max_places:
		_settle()
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _bot_move()
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		g._place_piece()
		places += 1
		_settle()
		_idle(idle)
	_settle()
	_idle(60)            # 판 끝 예약 음(fanfare 아르페지오 0.30초)까지 흘려보낸다
	return places

# ── 로그 해석 ────────────────────────────────────────────────────────────────
func _analyze(log: Array) -> Dictionary:
	var fires: Array = []
	var drops: Dictionary = {}
	var kinds: Dictionary = {}
	for e0 in log:
		var e: Dictionary = e0 as Dictionary
		var d: String = String(e["drop"])
		if d != "":
			drops[d] = int(drops.get(d, 0)) + 1
			continue
		fires.append(e)
		var k: String = String(e["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	# 동시 보이스 — 각 발화 시점에서 '아직 울리고 있는' 소리 수를 센다(진흙의 직접 지표).
	var max_voices: int = 0
	var max_fires: int = 0
	var min_gap: float = 999.0
	for i in range(fires.size()):
		var ti: float = float(fires[i]["t"])
		var live: int = 0
		for j in range(fires.size()):
			var tj: float = float(fires[j]["t"])
			if tj > ti:
				break
			if tj + float(WORD_DUR.get(String(fires[j]["kind"]), 0.1)) > ti:
				live += 1
		max_voices = maxi(max_voices, live)
		var n: int = 0
		for j2 in range(i, fires.size()):
			if float(fires[j2]["t"]) - ti > 1.0:
				break
			n += 1
		max_fires = maxi(max_fires, n)
		if i > 0:
			min_gap = minf(min_gap, ti - float(fires[i - 1]["t"]))
	var span: float = 0.0
	if fires.size() >= 2:
		span = float(fires[fires.size() - 1]["t"]) - float(fires[0]["t"])
	return {
		"fires": fires.size(), "kinds": kinds, "drops": drops, "span": span,
		"per_sec": (float(fires.size()) / span) if span > 0.0 else 0.0,
		"max_voices": max_voices, "max_fires_1s": max_fires,
		"min_gap": (min_gap if min_gap < 999.0 else 0.0),
	}

# 연쇄 사다리 검사 — clear 다운비트가 0으로 되돌리고, 그 뒤 chain이 한 계단씩 오른다.
#   되돌림이 안 되면(사다리가 판 내내 누적되면) 두 번째 연쇄부터 전부 천장에 붙어 '오르는 맛'이 죽는다.
func _ladder(log: Array) -> Dictionary:
	var runs: Array = []
	var cur: Array = []
	var bad_order: int = 0
	var over: int = 0
	for e0 in log:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "":
			continue
		var k: String = String(e["kind"])
		if k == "clear":
			if cur.size() > 0:
				runs.append(cur)
			cur = []
		elif k == "chain":
			var s: int = int(e["semi"])
			if s > LADDER_MAX_SEMI:
				over += 1
			if cur.size() > 0 and s < int(cur[cur.size() - 1]):
				bad_order += 1
			cur.append(s)
	if cur.size() > 0:
		runs.append(cur)
	var longest: Array = []
	for r in runs:
		if (r as Array).size() > longest.size():
			longest = r as Array
	return {"runs": runs.size(), "bad_order": bad_order, "over": over, "longest": longest}

func _report(tag: String, m: Dictionary) -> void:
	print("── %s: 발화 %d발 / %.1f초 = 초당 %.2f · 어휘 %s · 드롭 %s"
			% [tag, int(m["fires"]), float(m["span"]), float(m["per_sec"]), str(m["kinds"]), str(m["drops"])])
	print("     동시 보이스 최대 %d  |  롤링 1초 최대 %d발  |  최소 간격 %.3fs"
			% [int(m["max_voices"]), int(m["max_fires_1s"]), float(m["min_gap"])])

func _sig(log: Array) -> Array:
	var out: Array = []
	var t0: float = 0.0
	if log.size() > 0:
		t0 = float((log[0] as Dictionary)["t"])
	for e0 in log:
		var e: Dictionary = e0 as Dictionary
		out.append("%.4f|%s|%d|%s" % [float(e["t"]) - t0, e["kind"], int(e["semi"]), e["drop"]])
	return out

# 한 패스 = 캠페인 스테이지1을 같은 시드로. 로그·시간축을 패스마다 0으로 되돌려 비교 가능하게.
func _pass(idle: int) -> Array:
	g.sfx_log_on = true
	g.sound_on = true      # ⚠유저 settings.save에 소리 off가 들어 있으면 프로브가 조용히 0발을 재게 된다
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	var placed: int = _play(PLACES, idle)
	return [g._sfx_log.duplicate(true), placed]

# 패스 D — 어휘를 직접 때린다. 봇은 14수 예산 안에 스테이지를 못 깨서 fanfare가 한 번도 실행되지
#   않고 검사가 공허하게 초록이 된다(haptic_probe에서 실측으로 드러난 함정).
func _pass_vocab() -> Array:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	_idle(2)
	# 집기 배선 — 어휘를 직접 때리지 않고 **실제 입력 경로**(_pick_up)를 탄다. 봇은 _place_piece를
	#   바로 부르므로 패스 A~C에선 grab이 한 번도 안 울린다 → 여기서 안 재면 배선이 끊겨도 초록이다.
	var slot_c: Vector2 = (g._tray_slot_rect(0) as Rect2).get_center()
	if g._pick_up(slot_c):
		g.dragging = false
		g.drag_slot = -1
	_idle(6)
	g._fb("finish")          # 아르페지오 4음(0/+4/+7/+12)
	_idle(48)                # 0.80초 = 마지막 예약 음(+0.30초)까지 흐른다
	g._fb("finish")          # 판당 1회 → 드롭되어야 한다
	_idle(30)
	g._start_stage(0)        # 판 경계 = _init_game이 _sfx_reset을 부르나(배선 검사)
	_idle(2)
	g._fb("finish")          # 새 판이므로 다시 허용
	_idle(60)
	return g._sfx_log.duplicate(true)

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	# ⚠실유저 진행도 보호 — Main.tscn을 띄우면 _ready가 persist_enabled=true로 만든다.
	g.set("persist_enabled", false)
	await process_frame

	print("=== 오디오 프로브 (시드 %d) ===" % SEED_CAMPAIGN)

	var ra: Array = _pass(IDLE_HUMAN)
	var log_a: Array = ra[0]
	var placed_a: int = int(ra[1])
	var ma: Dictionary = _analyze(log_a)
	_report("사람 템포", ma)

	var rb: Array = _pass(IDLE_STRESS)
	var mb: Dictionary = _analyze(rb[0])
	_report("스트레스", mb)

	var rc: Array = _pass(IDLE_HUMAN)      # 결정성 — A 재현
	var log_c: Array = rc[0]

	print("── 판정")
	var kinds_a: Dictionary = ma["kinds"]
	var places: int = int(kinds_a.get("place", 0))
	_check("① 착지음 = 배치 수", places == placed_a, "place %d · 배치 %d" % [places, placed_a])

	_check("② 동시 보이스 ≤ %d — 사람" % MAX_VOICES, int(ma["max_voices"]) <= MAX_VOICES,
			"최대 %d" % int(ma["max_voices"]))
	_check("② 동시 보이스 ≤ %d — 스트레스" % MAX_VOICES, int(mb["max_voices"]) <= MAX_VOICES,
			"최대 %d" % int(mb["max_voices"]))

	_check("③ 롤링 1초 ≤ %d발 — 스트레스" % MAX_FIRES_IN_1S, int(mb["max_fires_1s"]) <= MAX_FIRES_IN_1S,
			"최대 %d발" % int(mb["max_fires_1s"]))

	var la: Dictionary = _ladder(log_a)
	_check("④ 연쇄 사다리 단조 상승", int(la["bad_order"]) == 0,
			"역행 %d회 · 연쇄 %d회 · 최장 런 %s" % [int(la["bad_order"]), int(la["runs"]), str(la["longest"])])
	_check("④ 사다리 상한 %d반음" % LADDER_MAX_SEMI, int(la["over"]) == 0, "초과 %d회" % int(la["over"]))

	var sig_a: Array = _sig(log_a)
	var sig_c: Array = _sig(log_c)
	_check("⑥ 같은 시드 = 같은 로그(RNG 미사용)", sig_a == sig_c,
			"A %d줄 · C %d줄" % [sig_a.size(), sig_c.size()])

	var allowed: Array = ["grab", "place", "clear", "chain", "tap"]   # fanfare는 clear로 펼쳐져 로그에 남는다
	var unexpected: Array = []
	for k in kinds_a.keys():
		if not allowed.has(String(k)):
			unexpected.append(k)
	_check("⑦ 어휘는 여섯뿐", unexpected.is_empty(), "예상 밖: %s" % str(unexpected))

	# ── 패스 D: 어휘 직접 타격(fanfare 1회 상한·판 경계 리셋)
	var log_d: Array = _pass_vocab()
	var fan_notes: int = 0
	var fan_drops: Array = []
	var semis: Array = []
	for e0 in log_d:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "":
			fan_drops.append(String(e["drop"]))
			continue
		if String(e["kind"]) == "clear":
			fan_notes += 1
			semis.append(int(e["semi"]))
	var grabs: int = 0
	for e0 in log_d:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) == "" and String(e["kind"]) == "grab":
			grabs += 1
	print("── 어휘: fanfare 음 %d발 · 드롭 %s · 음정 %s · grab %d발" % [fan_notes, str(fan_drops), str(semis), grabs])
	_check("⑧ 집기 배선(_pick_up → grab)", grabs == 1, "%d발" % grabs)
	_check("⑤ fanfare = 4음 아르페지오 ×2판", fan_notes == 8, "%d발 · %s" % [fan_notes, str(semis)])
	_check("⑤ 같은 판 두 번째 fanfare = 드롭", fan_drops.has("once"), "드롭 %s" % str(fan_drops))

	print("=== %s (실패 %d) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
