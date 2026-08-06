extends SceneTree
# care_probe.gd — 실패 케어(연속 실패 구제)의 효과 측정.
#
#   base : DDA off · 구제 없음            = 기준선(campaign_probe와 동형 조건)
#   god  : DDA on  · fail_streak=2       = **출고 중인 2패 케어**(줄-완성 조각 우선 배급)
#   T##  : 거기에 5바 비중 ##%를 얹은 실험 조건(pool_override) — 기각된 레버라 참고용이다
#   POOLS=onboard,rich,lean → 프리셋을 통째로 끼운 실험 조건
#
# ⚠**FULL=1로 사인별을 볼 것.** 승률만 보면 케어가 '어느 죽음을 고쳤나'를 못 본다. S3에서
#   5바 늘리기가 거점사를 줄이고 막힘사를 늘리는 걸 승률(+)만 보다 놓칠 뻔했다 — 그런데 실유저의
#   죽음은 막힘사였다. 우리 실패 경로가 둘인 한, 승률 한 줄은 늘 반쪽짜리 답이다.
#
# ⚠비행기는 이 프로브로 못 잰다. 그리디 봇은 비행기를 쏘지 않는다 = 여기 승률은 늘 비행기 OFF 값이다.
#   plane_cd 완화의 효과는 tools/plane_verify.gd(AB=1) 경로로 따로 재야 한다.
#
# ⚠A/B라서 조건마다 시드를 되감는다(짝지은 비교). 한 스트림으로 연달아 돌리면 앞 조건의 draw 수가
#   뒤 조건을 통째로 밀어 조건 차이와 시드 노이즈가 섞인다(analytics_probe·regress 교훈).
#
# 실행:
#   godot --headless --path . --script tools/care_probe.gd
#   TRIALS=60 STAGE_IDX=4,5,6,7 SHARES=34,41 PROBE_SEED=20260804 godot --headless ... (좁혀 볼 때)

func _init() -> void:
	var TRIALS: int = int(OS.get_environment("TRIALS")) if OS.get_environment("TRIALS") != "" else 60
	var base_seed: int = int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 20260804
	# 재볼 5바 비중(%). 32=ONBOARD 수준(출시 검증됨) / 41=RICH 수준 / 47=C109서 유저가 잡아낸 값.
	var shares: Array = [34, 41]
	var sh_env: String = OS.get_environment("SHARES")
	if sh_env != "":
		shares = []
		for tok in sh_env.split(","):
			if int(tok) > 0:
				shares.append(int(tok))   # SHARES=0 = 5바 조건 통째로 빼기(기각된 레버라 대개 안 본다)

	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.set("persist_enabled", false)   # ⚠_ready가 켜둔다 — 안 끄면 봇의 클리어가 실유저 진행도에 각인된다
	g.cleared[0] = true               # 튜토리얼 비활성(si=0 첫 시행이 스크립트 판이 되는 것 방지)

	var only: Array = []
	var only_env: String = OS.get_environment("STAGE_IDX")
	if only_env != "":
		for tok in only_env.split(","):
			only.append(int(tok))

	# T## 조건이 걸리는 연속 실패 수. 기본 3(=출고 사다리의 3패 칸: 줄-완성 배급 + 비행기 완화).
	#   ⚠2로 낮추면 god과 fail_streak이 같아져 **차이가 조각 풀 하나로 좁혀진다** — 비행기 픽업은
	#   보드에 실제로 떨어지는 물체라 봇이 안 쏴도 스폰·점유·RNG를 건드린다(3패 조건은 두 개가 겹친 값).
	var t_streak: int = int(OS.get_environment("T_STREAK")) if OS.get_environment("T_STREAK") != "" else 3
	# 조건 목록 = [라벨, dda, fail_streak, 5바 목표비중(0=기본 풀), 풀 통째 교체(비면 없음)]
	#   god3 = 3패 케어의 **대조군**. 이게 없으면 T##(3패+5바)를 god(2패)과 비교하게 되어
	#   비행기 완화의 몫이 5바의 공으로 딸려 들어간다.
	var conds: Array = [["base", false, 0, 0.0, {}], ["god", true, 2, 0.0, {}], ["god3", true, 3, 0.0, {}]]
	for s in shares:
		conds.append(["T%d" % int(s), true, t_streak, float(s) / 100.0, {}])
	# POOLS=onboard,lean,rich → 그 프리셋을 통째로 끼운 조건을 덧붙인다. '조각을 큼직하게'가
	#   막힘사를 줄이는지 보려면 5바 비중이 아니라 **조각 크기 분포 자체**를 바꿔 봐야 한다.
	var SD: GDScript = load("res://stage_data.gd")
	var preset_env: String = OS.get_environment("POOLS")
	if preset_env != "":
		for tok in preset_env.split(","):
			var key: String = tok.strip_edges().to_upper()
			var p: Dictionary = SD.get("POOL_" + key)
			if p == null or p.is_empty():
				print("(알 수 없는 풀: %s — 건너뜀)" % key)
				continue
			conds.append([key.substr(0, 5).to_lower(), true, 2, 0.0, p])
	# LEVERS="step_every=4|core_hp=5,step_every=4" → 각 토막이 조건 하나(필드는 쉼표로 겹쳐 쌓기).
	#   케어 사다리 위에 **판 데이터를 눅이는 레버**를 얹어 본다. 기준선은 T##과 같은 칸
	#   (3패 케어 + LEVER_SHARE% 5바)이라 차이가 그 레버 하나로 좁혀진다.
	#   ⚠여기서 좋게 나온 값은 '케어 레버 후보'일 뿐이다 — 판 데이터를 그대로 바꾸는 뜻이 아니다.
	var lv_share: float = float(int(OS.get_environment("LEVER_SHARE")) if OS.get_environment("LEVER_SHARE") != "" else 41) / 100.0
	var lv_env: String = OS.get_environment("LEVERS")
	if lv_env != "":
		for chunk in lv_env.split("|"):
			var ov: Dictionary = {}
			var label: String = ""
			for kv in String(chunk).split(","):
				var parts: PackedStringArray = String(kv).strip_edges().split("=")
				if parts.size() != 2:
					continue
				var key2: String = String(parts[0]).strip_edges()
				var val: String = String(parts[1]).strip_edges()
				ov[key2] = float(val) if val.contains(".") else int(val)
				label += ("+" if label != "" else "") + key2.substr(0, 4) + val
			if ov.is_empty():
				continue
			conds.append([label.substr(0, 12), true, t_streak, lv_share, {}, ov])
	# CARE_AB=1 → 3패 칸에서 밴드 완화만 꺼본다. 같은 칸에 배급·비행기 완화가 같이 있어서,
	#   켜둔 채로는 밴드가 낸 승률과 나머지가 낸 승률이 안 갈린다.
	if OS.get_environment("CARE_AB") != "":
		conds.append(["3패-밴드off", true, 3, 0.0, {}, {}, {"care_band_enabled": false}])
		conds.append(["3패-밴드on", true, 3, 0.0, {}, {}, {"care_band_enabled": true}])

	print("(seed=%d TRIALS=%d)" % [base_seed, TRIALS])
	# FULL=1 = 승률 대신 사인별 분해. '케어가 어느 죽음을 고쳤나'를 봐야 막힘사에 듣는지 알 수 있다.
	if OS.get_environment("FULL") != "":
		print("판 | 조건         | 승률   | 막힘사 | 거점사 | 배치  | 선택지 | 동시2 | 동시3 | 콤보 | 처치/클리어")
		print("---+--------------+--------+--------+--------+-------+--------+-------+-------+------+-----------")
		for si in range(g.STAGES.size()):
			if not only.is_empty() and not only.has(si):
				continue
			var bp: Dictionary = g.STAGES[si].get("pool", {})
			for c in conds:
				seed(base_seed + si * 1000)
				g.seed_game(base_seed + si * 1000)
				var pl: Dictionary = {}
				if not (c[4] as Dictionary).is_empty():
					pl = c[4]                       # 프리셋 통째 교체
				elif float(c[3]) > 0.0:
					pl = _care_pool(bp, float(c[3]))
				_apply_props(g, c)
				var r: Dictionary = _run_full(g, si, bool(c[1]), int(c[2]), pl, TRIALS, _ov(c))
				print("%2d | %-12s | %5.1f%% | %5.1f%% | %5.1f%% | %5.1f | %6.1f | %5.2f | %5.2f | %4.1f | %6.2f" % [
					si + 1, String(c[0]), r["win"], r["stuck"], r["core"], r["places"], r["opts"],
					r["m2"], r["m3"], r["combo"], r["kpc"]])
		quit()
		return   # ⚠quit()는 프레임 끝에 걸리는 예약이라 아래 승률 표까지 한 번 더 돈다(= 실행시간 2배)
	var head: String = "idx | 5바%  "
	for c in conds:
		head += "| %-6s " % String(c[0])
	head += "| 이름키"
	print(head)
	print("----+-------" + "+--------".repeat(conds.size()) + "+-------")

	for si in range(g.STAGES.size()):
		if not only.is_empty() and not only.has(si):
			continue
		var base_pool: Dictionary = g.STAGES[si].get("pool", {})
		var row: String = " %2d | %4.1f%% " % [si + 1, 100.0 * _i5_share(base_pool)]
		var wins: Array = []
		for c in conds:
			# 시드 되감기 = 조건들이 같은 난수 스트림을 본다(짝지은 비교).
			seed(base_seed + si * 1000)
			g.seed_game(base_seed + si * 1000)
			var pool: Dictionary = {}
			if float(c[3]) > 0.0:
				pool = _care_pool(base_pool, float(c[3]))
			_apply_props(g, c)
			var w: int = _run(g, si, bool(c[1]), int(c[2]), pool, TRIALS, _ov(c))
			wins.append(w)
			row += "| %5.1f%% " % [100.0 * float(w) / float(TRIALS)]
		row += "| %s" % String(g.STAGES[si]["name"])
		print(row)
	quit()

const SM: GDScript = preload("res://modes/stage_mode.gd")

# 조건의 판-데이터 오버라이드(6번째 원소). 없는 조건은 빈 사전.
func _ov(c: Array) -> Dictionary:
	return (c[5] as Dictionary) if c.size() > 5 else {}

# 조건의 Main 속성 오버라이드(7번째 원소) = 케어 레버 A/B 노브. 안 준 조건은 게임 기본값(둘 다 ON)으로
#   되돌린다 — 조건 사이에 노브가 새면 앞 조건이 뒤 조건을 오염시킨다.
func _apply_props(g: Node, c: Array) -> void:
	g.care_band_enabled = true
	if c.size() > 6:
		for k in (c[6] as Dictionary):
			g.set(String(k), (c[6] as Dictionary)[k])

# 판 데이터를 눅인 사본으로 스테이지를 시작한다. STAGES는 const(런타임 읽기전용)라 원본을 못 고치므로
#   **_start_stage를 손수 재현**해 st·director를 _init_game **앞에서** 갈아끼운다 —
#   뒤에서 바꾸면 온보딩 적이 이미 원래 값으로 스폰돼 조건이 반만 걸린다.
func _start(g: Node, si: int, ov: Dictionary) -> void:
	if ov.is_empty():
		g._start_stage(si)
		return
	var mod: Dictionary = (g.STAGES[si] as Dictionary).duplicate(true)
	for k in ov:
		mod[k] = ov[k]
	g.endless = false
	g.featured = false
	g.stage_idx = si
	g.st = mod
	g.director = SM.new(mod)
	g.mode = "play"
	g._init_game()
	g.intro_t = 0.0

# 5바(I5h+I5v)가 배급에서 차지하는 비중. 유저가 눈으로 잡아내는 그 숫자 = 완화 폭의 상한 단위.
func _i5_share(w: Dictionary) -> float:
	if w.is_empty():
		return 0.0
	var total: int = 0
	var i5: int = 0
	for k in w:
		total += int(w[k])
		if k == "I5h" or k == "I5v":
			i5 += int(w[k])
	if total <= 0:
		return 0.0
	return float(i5) / float(total)

# 케어 풀 = 5바 비중만 목표까지 끌어올린 사본. 나머지 조각의 상대 비율은 그대로 둔다
#   (작은 조각을 늘리는 개입은 실측상 역효과 — Main._make_piece 주석 참조).
#   h:v 비율은 원본 유지 = 판마다 저작된 가로/세로 성격을 안 뭉갠다.
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
	var want: float = target * float(rest) / (1.0 - target)   # 목표 비중을 만드는 새 I5 합
	if want <= float(i5):
		return {}    # 이미 목표 이상 = 완화 없음(그 판은 케어가 조각으로 안 걸린다)
	var scale: float = want / float(i5)
	var out: Dictionary = base.duplicate()
	out["I5h"] = maxi(1, int(round(float(base["I5h"]) * scale)))
	out["I5v"] = maxi(1, int(round(float(base["I5v"]) * scale)))
	return out

# 승률만 보면 케어가 '어느 죽음을 고쳤나'를 못 본다. 우리 실패 경로는 둘이고(누수사·막힘사),
#   5바를 더 주는 개입은 줄을 늘리는 대신 조각을 크게 만들어 **막힘을 악화시킬 수 있다**.
#   그래서 사인별·선택지 수까지 같이 낸다. opts = 매 턴 트레이 3장의 합법 배치 수 평균
#   = '놓을 곳이 얼마나 많은가' = 유저가 말한 결정 스트레스의 대리 지표.
func _run_full(g: Node, si: int, dda: bool, streak: int, pool: Dictionary, trials: int, ov: Dictionary = {}) -> Dictionary:
	var wins: int = 0
	var stuck: int = 0
	var core: int = 0
	var places: float = 0.0
	var opts: float = 0.0
	var opt_n: float = 0.0
	var m2: float = 0.0
	var m3: float = 0.0
	var combo: float = 0.0
	var kpc: float = 0.0
	for t in range(trials):
		g.dda_enabled = dda
		g.fail_streak[si] = streak
		_start(g, si, ov)
		g.pool_override = pool
		var r: Dictionary = _play_full(g)
		if bool(r["win"]):
			wins += 1
		if bool(r["stuck"]):
			stuck += 1
		elif not bool(r["win"]):
			core += 1
		places += float(r["places"])
		opts += float(r["opts"])
		opt_n += float(r["opt_n"])
		m2 += float(r["m2"])
		m3 += float(r["m3"])
		combo += float(r["combo"])
		kpc += float(r["kpc"])
	var n: float = float(trials)
	return {
		"win": 100.0 * float(wins) / n, "stuck": 100.0 * float(stuck) / n,
		"core": 100.0 * float(core) / n, "places": places / n,
		"opts": (opts / opt_n) if opt_n > 0.0 else 0.0,
		"m2": m2 / n, "m3": m3 / n, "combo": combo / n, "kpc": kpc / n,
	}

func _play_full(g: Node) -> Dictionary:
	var guard: int = 0
	var places: int = 0
	var opts: float = 0.0
	var opt_n: float = 0.0
	# 스펙터클 = '한 배치로 몇 줄을 한꺼번에 지웠나'. 승률·막힘사와 별개 축이고, 케어가 '팡팡 터지는
	#   구제'인지 '조용히 이기게 해주는 구제'인지를 가르는 유일한 지표다(유저 지적, 2026-08-04).
	var m2: int = 0
	var m3: int = 0
	# 밴드(콤보=청소 범위) 레버는 '줄을 몇 개 냈나'가 아니라 '한 클리어가 몇 마리를 잡았나'를 움직인다.
	#   동시2·3만 보면 그 레버의 효과가 통계에서 통째로 사라진다 — S6에서 콤보만 보다 겪은 것과 같은 함정.
	var clears: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		opts += float(_legal_placements(g))
		opt_n += 1.0
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		var nl: int = _lines_of(g, mv)   # 놓기 전에 센다 = 엔진 훅 없이 정확(campaign_probe와 동형)
		g._place_piece()
		places += 1
		if nl >= 1:
			clears += 1
		if nl >= 2:
			m2 += 1
		if nl >= 3:
			m3 += 1
		var s3: int = 0
		while g.resolving and s3 < 400:
			g._process(0.05)
			s3 += 1
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {"win": g.game_clear, "stuck": g.game_over and g.stuck, "places": places,
		"opts": opts, "opt_n": opt_n, "m2": m2, "m3": m3, "combo": g.run_max_combo,
		"kpc": (float(g.killed) / float(clears)) if clears > 0 else 0.0}

# 이 수가 완성시키는 행+열 수 (campaign_probe에서 복사 — 이 저장소 관례대로 인라인)
func _lines_of(g: Node, mv: Dictionary) -> int:
	var offsets: Array = g.tray[int(mv["slot"])]["offsets"]
	var occ: Array = []
	for r in range(g.ROWS):
		var row: Array = []
		for c in range(g.COLS):
			row.append(g.board[r][c] != "")
		occ.append(row)
	for o in offsets:
		var ov: Vector2i = o as Vector2i
		occ[int(mv["row"]) + ov.y][int(mv["col"]) + ov.x] = true
	var n: int = 0
	for r in range(g.ROWS):
		var ok: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				ok = false
				break
		if ok:
			n += 1
	for c in range(g.COLS):
		var ok2: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				ok2 = false
				break
		if ok2:
			n += 1
	return n

# 지금 트레이 3장을 놓을 수 있는 자리의 총 개수. 많을수록 '고를 게 많다' = 결정 부하.
func _legal_placements(g: Node) -> int:
	var n: int = 0
	for slot in range(3):
		if g.tray[slot].is_empty():
			continue
		var offsets: Array = g.tray[slot]["offsets"]
		for r in range(g.ROWS):
			for c in range(g.COLS):
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var x: int = c + ov.x
					var y: int = r + ov.y
					if x < 0 or x >= g.COLS or y < 0 or y >= g.ROWS or g.board[y][x] != "":
						ok = false
						break
				if ok:
					n += 1
	return n

func _run(g: Node, si: int, dda: bool, streak: int, pool: Dictionary, trials: int, ov: Dictionary = {}) -> int:
	var wins: int = 0
	for t in range(trials):
		g.dda_enabled = dda
		g.fail_streak[si] = streak
		_start(g, si, ov)
		# ⚠_start_stage 뒤에 덮는다 — _init_game이 CARE_I5_SHARE로 이미 계산해 둔 값을 스윕 값으로 바꾼다.
		#   실제 코드 경로(Main.care_pool)를 그대로 타므로 프로브와 게임이 어긋나지 않는다.
		#   부작용: 첫 트레이 3장은 기본 풀로 뽑힌 뒤다 = 케어 효과가 아주 살짝 과소평가된다.
		#   조건 전체에 똑같이 걸리므로 A/B 비교 자체는 성립한다(방향·순위 불변).
		g.pool_override = pool
		if _play(g):
			wins += 1
	return wins

func _play(g: Node) -> bool:
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
	return g.game_clear

# ── 그리디 봇 (sim.gd에서 복사, 폭탄 우선항 포함) ──
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
				if String(e.get("etype", "")) == "bomb":
					var fuse: int = int(e.get("fuse", 99))
					score += 250.0 * float(maxi(1, 9 - mini(fuse, 8)))
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
