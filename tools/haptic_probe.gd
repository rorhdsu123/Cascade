extends SceneTree
# 햅틱 예산·뭉갬 감사 (R1 · 정본: HAPTIC_PLAN.md)
#   실행: godot --path . --script tools/haptic_probe.gd      ⚠창 모드로 돌린다(--headless는 렌더 텍스처 null)
#
# 왜 이게 필요한가: 햅틱은 프레임에 안 남아서 **눈으로 검증할 방법이 없고**, 실기기가 붙기 전까진
#   "캐스케이드에서 진동이 뭉치는가"를 확인할 다른 수단이 아예 없다. 그래서 믹서가 남기는 로그
#   (_hap_log — 발화도 드롭도 이유와 함께)를 떠서 예산·간격을 기계적으로 감사한다.
#
# 무엇을 보나:
#   ① 착지 tick이 실제로 매 배치에 하나씩 나가나(조용히 삼켜지지 않나)
#   ② 줄 삭제가 링마다 반복되지 않나 — 짧은 창 안 pop 발화 수 상한
#   ③ 폭주 상한이 실제로 작동하나 — 롤링 1초 진동시간·발화수(스트레스 패스)
#   ④ roll(의식)이 판당 1회를 넘지 않나
#   ⑤ 같은 시드 두 번 = 로그가 완전히 동일한가(햅틱 경로에 RNG가 새면 회귀 골든이 시프트한다)
#
# ⚠시드 고정: 합/불을 내는 프로브는 반드시 시드를 박는다(analytics_probe의 교훈 — 안 박으면 같은
#   코드가 실행마다 PASS/FAIL로 갈리고, 그러면 진짜 파손도 "또 플레이크겠지"로 묻힌다).
const SEED_CAMPAIGN: int = 20250123
const PLACES: int = 14

# 사람 템포 — 한 수에 약 1.8초. 봇은 원래 프레임 없이 연달아 놓기 때문에, 이걸 안 넣으면 _hap_t가
#   거의 안 흘러 "초당 발화수"가 무의미해진다(불응기가 전부 드롭시켜 0에 가깝게 나온다).
const IDLE_HUMAN: int = 108      # 1/60 프레임 수 = 1.8초
const IDLE_STRESS: int = 1       # 인간이 불가능한 최고 속도 = 폭주 상한 시험

# 상한(설계 예산). 근거는 HAPTIC_PLAN.md — 평균 초당 2발·롤링 1초 진동시간은 예산+최장 단어 이내.
const MAX_FIRES_PER_SEC_HUMAN: float = 2.0
const MAX_MS_IN_1S: float = 260.0    # 예산 회복 150ms/s + 최장 단어 90ms
const MAX_FIRES_IN_1S: int = 12      # tick 불응기 0.09s → 산술 상한 11.1
const MAX_POP_IN_150MS: int = 2      # 다운비트 + 둘째 박. 3 이상 = 링마다 반복(뭉갬)

var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("%s %s%s" % ["OK  " if ok else "FAIL", tag, ("  — " + detail) if detail != "" else ""])

# 최소 봇 — 줄이 되는 수를 우선(삭제 어휘를 실제로 뽑기 위해). 튜토리얼 잠금 중엔 목표 칸 안에만.
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

# 연출이 끝날 때까지 굴린다(60fps 실시간 축 — 햅틱 예약 박이 실제 타이밍으로 흐르게).
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
		_idle(idle)      # 사람 템포(또는 스트레스 = 1프레임)
	_settle()
	_idle(60)            # 판 끝 예약 박(roll 3박 = 0.24초)까지 흘려보낸다
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
	var max_fires: int = 0
	var max_ms: float = 0.0
	var max_pop: int = 0
	var min_gap: float = 999.0
	for i in range(fires.size()):
		var ti: float = float(fires[i]["t"])
		var n: int = 0
		var s: float = 0.0
		var np: int = 0
		for j in range(i, fires.size()):
			var dt: float = float(fires[j]["t"]) - ti
			if dt > 1.0:
				break
			n += 1
			s += float(fires[j]["ms"])
			if dt <= 0.15 and String(fires[j]["kind"]) == "pop":
				np += 1
		max_fires = maxi(max_fires, n)
		max_ms = maxf(max_ms, s)
		max_pop = maxi(max_pop, np)
		if i > 0:
			min_gap = minf(min_gap, ti - float(fires[i - 1]["t"]))
	var span: float = 0.0
	if fires.size() >= 2:
		span = float(fires[fires.size() - 1]["t"]) - float(fires[0]["t"])
	return {
		"fires": fires.size(), "kinds": kinds, "drops": drops, "span": span,
		"per_sec": (float(fires.size()) / span) if span > 0.0 else 0.0,
		"max_fires_1s": max_fires, "max_ms_1s": max_ms, "max_pop_150ms": max_pop,
		"min_gap": (min_gap if min_gap < 999.0 else 0.0),
	}

func _report(tag: String, m: Dictionary) -> void:
	print("── %s: 발화 %d발 / %.1f초 = 초당 %.2f · 어휘 %s · 드롭 %s"
			% [tag, int(m["fires"]), float(m["span"]), float(m["per_sec"]), str(m["kinds"]), str(m["drops"])])
	print("     롤링 1초 최대: %d발 · %.0fms   |  최소 간격 %.3fs  |  150ms 내 pop 최대 %d"
			% [int(m["max_fires_1s"]), float(m["max_ms_1s"]), float(m["min_gap"]), int(m["max_pop_150ms"])])

# 로그를 비교 가능한 형태로 — 판 경계 오프셋을 뺀 상대 시각으로 직렬화(결정성 검사용).
func _sig(log: Array) -> Array:
	var out: Array = []
	var t0: float = 0.0
	if log.size() > 0:
		t0 = float((log[0] as Dictionary)["t"])
	for e0 in log:
		var e: Dictionary = e0 as Dictionary
		out.append("%.4f|%s|%d|%.3f|%s" % [float(e["t"]) - t0, e["kind"], int(e["ms"]), float(e["amp"]), e["drop"]])
	return out

# 한 패스 = 캠페인 스테이지1을 같은 시드로 굴린다. 로그·시간축을 패스마다 0으로 되돌려 비교 가능하게.
func _pass(idle: int) -> Array:
	g.hap_log_on = true
	g.haptic_on = true      # ⚠유저 settings.save에 진동 off가 들어 있으면 프로브가 조용히 0발을 재게 된다
	g._hap_log = []
	g._hap_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	var placed: int = _play(PLACES, idle)
	print("     (배치 %d · clear=%s over=%s)" % [placed, g.game_clear, g.game_over])
	return [g._hap_log.duplicate(true), placed]

# 패스 D: 어휘 직접 발화 — 봇이 못 닿는 곳을 때린다.
#   봇은 14수 예산 안에 스테이지를 못 깨고 콤보 4도 못 만들어서, 위 두 패스만으론 roll(3박·판당 1회)과
#   pop 둘째 박이 **한 번도 실행되지 않는다** = 그 검사들이 공허하게 초록이 된다. 여기서 직접 부른다.
func _pass_words() -> Array:
	g.hap_log_on = true
	g.haptic_on = true
	g._hap_log = []
	g._hap_t = 0.0
	g._hap_reset()
	g._haptic("pop", 6.0)    # 큰 콤보 = 다운비트 + 둘째 박
	_idle(30)
	g._haptic("roll")        # 짧-짧-김 3박
	# ⚠0.8초는 불응기(roll gap 0.40s)를 넘기려는 값이다. 짧게 두면 두 번째 roll이 '판당 1회'가 아니라
	#   불응기에 먼저 걸려 드롭돼(drop=gap) 정작 once 가드가 검사되지 않는다 — 실측으로 드러난 함정.
	_idle(48)
	g._haptic("roll")        # 판당 1회 → 드롭되어야 한다
	_idle(30)
	g._start_stage(0)        # 판 경계 = _init_game이 _hap_reset을 부르나(배선 검사)
	_idle(2)
	g._haptic("roll")        # 새 판이므로 다시 허용
	_idle(30)
	return g._hap_log.duplicate(true)

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	# ⚠실유저 진행도 보호 — Main.tscn을 띄우면 _ready가 persist_enabled=true로 만든다.
	#   봇이 스테이지를 깨면 그 값이 실제 campaign.save에 각인된다(진행도 자동 전승의 진범).
	g.set("persist_enabled", false)
	await process_frame

	print("=== 햅틱 프로브 (시드 %d) ===" % SEED_CAMPAIGN)

	# ── 패스 A: 사람 템포 — 실제 플레이에서 얼마나 자주 울리나
	var ra: Array = _pass(IDLE_HUMAN)
	var log_a: Array = ra[0]
	var placed_a: int = int(ra[1])
	var ma: Dictionary = _analyze(log_a)
	_report("사람 템포", ma)

	# ── 패스 B: 스트레스 — 인간이 불가능한 속도로 폭주시켜 상한이 실제로 잡히나
	var rb: Array = _pass(IDLE_STRESS)
	var log_b: Array = rb[0]
	var mb: Dictionary = _analyze(log_b)
	_report("스트레스", mb)

	# ── 패스 C: 결정성 — A를 그대로 재현(햅틱 경로에 RNG가 새면 여기서 깨진다)
	var rc: Array = _pass(IDLE_HUMAN)
	var log_c: Array = rc[0]

	print("── 판정")
	var kinds_a: Dictionary = ma["kinds"]
	var ticks: int = int(kinds_a.get("tick", 0))
	# ① 착지는 하나도 안 삼켜진다(사람 템포에선 불응기에 걸릴 이유가 없다)
	_check("① 착지 tick = 배치 수", ticks == placed_a, "tick %d · 배치 %d" % [ticks, placed_a])
	# ② 캐스케이드가 링마다 반복되지 않는다
	_check("② 150ms 내 pop ≤ %d" % MAX_POP_IN_150MS, int(ma["max_pop_150ms"]) <= MAX_POP_IN_150MS
			and int(mb["max_pop_150ms"]) <= MAX_POP_IN_150MS,
			"사람 %d · 스트레스 %d" % [int(ma["max_pop_150ms"]), int(mb["max_pop_150ms"])])
	# ③ 사람 템포 평균 빈도 — '희소 채널' 예산
	_check("③ 사람 템포 초당 ≤ %.1f발" % MAX_FIRES_PER_SEC_HUMAN, float(ma["per_sec"]) <= MAX_FIRES_PER_SEC_HUMAN,
			"%.2f발/초" % float(ma["per_sec"]))
	# ④ 폭주 상한 — 스트레스에서도 롤링 1초가 예산 안
	_check("④ 롤링 1초 ≤ %.0fms" % MAX_MS_IN_1S, float(mb["max_ms_1s"]) <= MAX_MS_IN_1S,
			"스트레스 %.0fms" % float(mb["max_ms_1s"]))
	_check("④ 롤링 1초 ≤ %d발" % MAX_FIRES_IN_1S, int(mb["max_fires_1s"]) <= MAX_FIRES_IN_1S,
			"스트레스 %d발" % int(mb["max_fires_1s"]))
	# ⑤ 의식은 판당 1회(3박 = 발화 3개까지)
	for tag_m in [["사람", ma], ["스트레스", mb]]:
		var kk: Dictionary = (tag_m[1] as Dictionary)["kinds"]
		_check("⑤ roll ≤ 3발(판당 1회) — %s" % tag_m[0], int(kk.get("roll", 0)) <= 3,
				"roll %d발" % int(kk.get("roll", 0)))
	# ⑥ 결정성 — 같은 시드 = 같은 로그
	_check("⑥ 같은 시드 = 같은 로그(RNG 미사용)", _sig(log_a) == _sig(log_c),
			"A %d줄 · C %d줄" % [log_a.size(), log_c.size()])
	# ⑦ 손실엔 아무것도 없다 — 어휘가 셋을 넘지 않는다(호출부가 몰래 늘어난 걸 잡는다)
	var all_kinds: Dictionary = {}
	for k in kinds_a:
		all_kinds[k] = true
	for k in (mb["kinds"] as Dictionary):
		all_kinds[k] = true
	var known: Array = ["tick", "pop", "roll"]
	var extra: Array = []
	for k in all_kinds:
		if not known.has(k):
			extra.append(k)
	_check("⑦ 어휘는 셋뿐", extra.is_empty(), "예상 밖: %s" % str(extra))

	# ── 패스 D: 어휘 자체(봇이 못 닿는 경로)
	var log_d: Array = _pass_words()
	var fires_d: Array = []
	var drops_d: Array = []
	for e0 in log_d:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) == "":
			fires_d.append(e)
		else:
			drops_d.append(String(e["drop"]))
	var pops: Array = []
	var rolls: Array = []
	for e0 in fires_d:
		var e: Dictionary = e0 as Dictionary
		if String(e["kind"]) == "pop":
			pops.append(e)
		elif String(e["kind"]) == "roll":
			rolls.append(e)
	print("── 어휘: pop %d발 · roll %d발 · 드롭 %s" % [pops.size(), rolls.size(), str(drops_d)])
	# ⑧ 큰 콤보 = 2박, 둘째 박은 약 90ms 뒤
	var second_dt: float = (float(pops[1]["t"]) - float(pops[0]["t"])) if pops.size() >= 2 else -1.0
	_check("⑧ 콤보≥4 = pop 2박 (+0.09s)", pops.size() == 2 and second_dt > 0.07 and second_dt < 0.13,
			"%d발 · 간격 %.3fs" % [pops.size(), second_dt])
	# ⑨ roll = 짧-짧-김 3박이고, 같은 판에서 두 번째 호출은 'once'로 버려진다
	var roll_ms: Array = []
	for e0 in rolls:
		roll_ms.append(int((e0 as Dictionary)["ms"]))
	_check("⑨ roll = 18·18·90 3박 ×2판", roll_ms == [18, 18, 90, 18, 18, 90], "ms %s" % str(roll_ms))
	_check("⑨ 같은 판 두 번째 roll = 드롭", drops_d.has("once"), "드롭 %s" % str(drops_d))

	print("=== %s (실패 %d) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
