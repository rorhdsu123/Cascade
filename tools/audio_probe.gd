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
#   ⑦ 어휘 목록이 설계와 일치하나
#
# ⚠시드 고정: 합/불을 내는 프로브는 반드시 시드를 박는다(analytics_probe의 교훈).
const SEED_CAMPAIGN: int = 20250123
const PLACES: int = 14

const IDLE_HUMAN: int = 108      # 1/60 프레임 = 1.8초/수(사람 템포). 안 넣으면 '초당 발화수'가 무의미해진다
const IDLE_STRESS: int = 1       # 인간이 불가능한 최고 속도 = 상한 시험

# 단어별 물리 길이(초) — 겹침 계산용. pitch_scale이 올라가면 실제론 더 짧게 끝나므로 보수적 상한이다.
#   ⚠UI 탭 셋은 tap과 **같은 파형**이고 base(음정)만 다르다 → 길이가 그만큼 갈린다:
#   tap_go(+7) 0.13×2^(−7/12)≈0.09 · tap_back(−5) ≈0.18 · tap_off(−8) ≈0.21.
# ⚠**손으로 적던 표를 버렸다**(R18). 파형을 바꾸면 길이가 통째로 달라지는데(폭죽 터짐은 0.10 →
#   0.53초) 이 표는 안 따라와서, 겹침 측정이 조용히 틀린 값을 내고 있었다. 지금은 **뱅크에서 실제
#   스트림 길이를 재고** 음정만큼 나눈다(pitch_scale이 올라가면 그만큼 짧게 끝난다).
#   fallback은 뱅크에 없는 이름(있으면 안 되지만, 0.1초로 세면 겹침을 **과소평가**하므로 크게 잡는다).
const WORD_DUR_FALLBACK: float = 0.20
const MAX_VOICES: int = 8
const MAX_MUSIC_VOICES: int = 12         # 지속음 전용 풀(Main.MUSIC_VOICES) — 타격 풀과 안 섞인다
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

# 블라스트 연출 창 [시작, 끝] 목록 — §17③의 '창 양 끝이 비었다'를 계속 감시하기 위한 것.
#   R14의 목표가 총 발화수가 아니라 **분포**였으므로, 총량만 보면 고쳤는지 알 수 없다.
var windows: Array = []

# 연출이 끝날 때까지 굴린다 — 연쇄(순차 피격)가 전부 재생돼야 사다리가 로그에 남는다.
func _settle() -> void:
	var s: int = 0
	var t0: float = g._sfx_t
	var was: bool = g.resolving
	while g.resolving and s < 1200:
		g._process(1.0 / 60.0)
		s += 1
	if was:
		windows.append([t0, g._sfx_t])

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
func _is_music(kind: String) -> bool:
	return bool(((g.SFX_WORDS as Dictionary).get(kind, {}) as Dictionary).get("music", false))

# 파형 지문 — 같은 소리가 다른 파일 이름으로 들어와도 같은 값이 나온다(길이 + 성긴 체크섬).
func _fp(st) -> String:
	var d: PackedByteArray = st.data
	var sum: int = 0
	var i: int = 0
	while i < d.size():
		sum = (sum * 31 + d[i]) & 0x7fffffff
		i += 97
	return "%d:%d" % [d.size(), sum]

# 어휘 한 발이 실제로 몇 초 우는가 — 파형 길이 ÷ 재생 음정. 뱅크·SFX_WORDS에서 직접 읽는다.
func _dur(kind: String, semi: int) -> float:
	var st = g._sfx_bank.get(kind, null)
	if st == null:
		return WORD_DUR_FALLBACK
	var base: int = int((g.SFX_WORDS[kind] as Dictionary).get("base", 0)) if (g.SFX_WORDS as Dictionary).has(kind) else 0
	return float(st.get_length()) / pow(2.0, float(base + semi) / 12.0)

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
	# ⚠**두 풀을 따로 센다**(R19). 지속음(music)은 전용 풀에 있어서 타격음을 절대 안 뺏는다 —
	#   합쳐 세면 화음 하나 얹을 때마다 상한을 넘긴 것처럼 보이고, 정작 진짜 위험(타격음이 서로를
	#   잡아먹는 것)은 그 숫자 뒤에 숨는다.
	var max_voices: int = 0
	var max_music: int = 0
	var max_fires: int = 0
	var min_gap: float = 999.0
	for i in range(fires.size()):
		var ti: float = float(fires[i]["t"])
		var live: int = 0
		var livem: int = 0
		for j in range(fires.size()):
			var tj: float = float(fires[j]["t"])
			if tj > ti:
				break
			if tj + _dur(String(fires[j]["kind"]), int(fires[j]["semi"])) > ti:
				if _is_music(String(fires[j]["kind"])):
					livem += 1
				else:
					live += 1
		max_voices = maxi(max_voices, live)
		max_music = maxi(max_music, livem)
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
		"max_voices": max_voices, "max_music": max_music, "max_fires_1s": max_fires,
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
		# 다운비트 = 삭제 타격. ⚠B안에선 `clear`가 안 울리고 `clear_hit`이 그 자리다 —
		#   여기 이름을 안 고치면 런이 절대 안 끊겨서 사다리 되돌림이 전부 '역행'으로 읽힌다.
		if k == "clear" or k == "clear_hit":
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
	print("     동시 보이스 최대 %d(선율 %d)  |  롤링 1초 최대 %d발  |  최소 간격 %.3fs"
			% [int(m["max_voices"]), int(m["max_music"]), int(m["max_fires_1s"]), float(m["min_gap"])])

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
	windows = []
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
	# 점수 틱 배선 — 캠페인은 clear_score()가 0이라 롤업이 안 돌고 봇 패스에선 score가 한 발도
	#   안 나온다. 표시 점수와 실제 점수를 벌려 놓고 _process를 굴려 **롤업 경로**를 태운다.
	g.endless_score = 400
	g.endless_score_shown = 0.0
	_idle(30)
	g.endless_score = 0
	g.endless_score_shown = 0.0
	_idle(6)
	# 실패 배선 — 봇은 14수 안에 안 죽어서 fail이 안 울린다. **실제 게임오버 경로**를 태운다.
	#   ⚠pending_core_dead를 직접 세우면 안 된다 — _end_turn 안의 advance_step이
	#   `pending_core_dead = core_hp <= 0`으로 **재계산**해 그 플래그를 덮는다(실측으로 드러남).
	#   거점 체력을 0으로 만들어 진짜로 죽게 해야 한다.
	g.core_hp = 0
	g._end_turn()
	_idle(6)
	g._start_stage(0)
	_idle(2)
	g._fb("finish")          # 아르페지오 4음(0/+4/+7/+12)
	_idle(48)                # 0.80초 = 마지막 예약 음(+0.30초)까지 흐른다
	g._fb("finish")          # 판당 1회 → 드롭되어야 한다
	_idle(30)
	g._start_stage(0)        # 판 경계 = _init_game이 _sfx_reset을 부르나(배선 검사)
	_idle(2)
	g._fb("finish")          # 새 판이므로 다시 허용
	_idle(60)
	return g._sfx_log.duplicate(true)

# 패스 E — UI 탭 배선(R13). **어휘를 직접 때리지 않고 진짜 입력 이벤트를 _input에 먹인다.**
#   봇 패스(A~D)는 버튼을 한 번도 안 누르므로, 여기서 안 재면 호출부가 통째로 빠져 있어도 초록이다
#   (grab·score·fail에서 이미 겪은 함정과 같은 종류).
func _click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g._input(ev)
	_idle(6)          # 발화 간 최소 간격(0.05s)보다 길게 — 안 그러면 뒤 탭이 gap으로 드롭된다

func _pass_ui() -> Array:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	var out: Array = []
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	g.intro_t = -1.0          # ⚠인트로 카드가 떠 있으면 첫 클릭이 '스킵'으로 삼켜진다(판 입력 차단 구간)
	_idle(2)
	# ① 기어 = 설정 열기(플레이 중 가장 잦은 UI 탭)
	_click((g.gear_rect as Rect2).get_center())
	out.append(["기어", g.settings_open])
	# ② 설정 모달 닫기(×)
	var lay: Dictionary = g._settings_layout()
	_click((lay["close"] as Rect2).get_center())
	out.append(["닫기", not g.settings_open])
	# ③ 잠긴 Classic — 화면은 무반응이고 소리만 난다. 잠금을 확실히 세워 둔다(실유저 세이브 영향 제거).
	g.mode = "menu"
	g.cleared = {}
	g.dev_unlock_all = false
	g.endless_best = 0
	var dy: Vector2 = Vector2(0.0, g._ui_dy())
	_click((g.MENU_CLASSIC_BTN as Rect2).get_center() + dy)
	out.append(["잠김", g.mode == "menu"])       # 잠겼으면 화면은 그대로여야 한다
	# ④ Adventure = 진행 화면 진입
	_click((g.MENU_ADV_BTN as Rect2).get_center() + dy)
	out.append(["진입", g.mode == "select"])
	# ⑤ 뒤로 = 허브 복귀
	_click((g.BACK_BTN as Rect2).get_center() + dy)
	out.append(["뒤로", g.mode == "menu"])
	return [g._sfx_log.duplicate(true), out]

# 패스 F — 블라스트 창 beat 배선(R14). 전멸·비행기 픽업·누수는 봇 패스에서 안 나오거나(전멸)
#   다른 사건과 섞여(픽업의 chain) 구분이 안 된다 → **단계마다 로그를 비워** 따로 센다.
func _count(kind: String) -> int:
	var n: int = 0
	for e0 in g._sfx_log:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) == "" and String(e["kind"]) == kind:
			n += 1
	return n

func _pass_fx() -> Dictionary:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	g.intro_t = -1.0
	_idle(2)
	var out: Dictionary = {}
	# ① 전멸 + 칭찬 — 플테 '8'키와 같은 강제 경로(바닥 한 줄 + 콤보5)로 실제 _begin_resolve를 태운다.
	var row: int = g.ROWS - 2
	for c in range(g.COLS):
		g.board[row][c] = g.COLORS[c % g.COLORS.size()]
	g.last_color = g.COLORS[0]
	g.combo = 5
	g._sfx_log = []
	g._begin_resolve([row], [])
	_settle()
	_idle(30)
	out["climax"] = _count("climax")
	out["praise"] = _count("praise")
	out["clear2"] = _count("clear2")     # B안: 삭제는 광택을 안 쏜다 → 전멸 3층의 2발뿐
	# ② 비행기 픽업 — 실제 _apply_hit 경로. chain이 다른 처치와 안 섞이게 로그를 비우고 센다.
	g._spawn_plane(0)
	var pid: int = -1
	for e in g.enemies:
		if String(e["etype"]) == "plane":
			pid = int(e["id"])
	g._sfx_log = []
	if pid >= 0:
		g._apply_hit({"id": pid, "dmg": 1, "kb": 0})
	_idle(10)
	out["plane"] = _count("chain")
	# ③ 누수 — **3열 동시**로 세워 한 발만 나는지 본다(열마다 울면 진흙).
	g._sfx_log = []
	g.pending_leaks = [0, 1, 2]
	g._reveal_leaks()
	_idle(10)
	out["leak"] = _count("leak")
	return out

# 패스 G — 클리어 축하 무대(R17). 봇은 14수 예산 안에 스테이지를 못 깨므로 **무대는 패스 A~F에
#   한 프레임도 안 나온다** → 여기서 안 재면 배선이 통째로 빠져 있어도 프로브가 조용히 초록이 된다
#   (grab·score·fail·전멸에서 이미 네 번 겪은 함정).
# ⚠어휘를 직접 때리지 않는다. `clear_stage_shot`·`clear_movie`와 **같은 강제 경로**로 진짜 무대를
#   열고 _process를 끝까지 굴린다 — 소리가 화면 타이머에서 나오므로 그 타이머를 돌려야 재는 의미가 있다.
func _pass_clear() -> Dictionary:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	g.intro_t = -1.0
	# ⚠12프레임을 흘린다(2가 아니라) — 진입 카드의 예약 음(goal_in 2·3번째, +0.085·0.17초)이
	#   아래 로그 초기화 **뒤에** 떨어지면 무대 로그에 섞여 '무대 안 무음'이 실제보다 작게 나온다.
	_idle(12)
	# 보드에 블록을 깔아 둔다 — 스윕은 **블록이 있는 행만** 울리므로 빈 판이면 0발이 정상이 되어
	#   검사가 공허해진다. 아래 세 행 + 맨 윗행(= 스윕 종료 타격의 조건)을 채운다.
	# ⚠**보드를 먼저 비운다.** _start_stage(0)가 남기는 판은 앞 패스와 **유저 세이브**에 따라 달라진다
	#   — 튜토리얼이 살아 있으면 _tut_setup_beat1이 십자를 미리 깔아 두기 때문(실측으로 드러났다).
	#   그 위에 채우면 이 검사가 기계마다 다른 수를 세게 된다.
	for r0 in range(g.ROWS):
		for c0 in range(g.COLS):
			g.board[r0][c0] = ""
	var rows: Array = [0, g.ROWS - 3, g.ROWS - 2, g.ROWS - 1]
	for r in rows:
		for c in range(g.COLS):
			g.board[r][c] = g.COLORS[c % g.COLORS.size()]
	g._sfx_log = []
	var t0: float = g._sfx_t
	g.game_over = false
	g.game_clear = true
	g._plan_clear_fx()
	g.clear_show_t = -float(g.CLEAR_HOLD)
	g._fb("finish")
	# 무대 + 폭죽 잔여 수명까지 전부 흘려보낸다(마지막 터짐이 CLEAR_FX_END 근처다)
	_idle(int(ceil((float(g.CLEAR_FX_END) + float(g.CLEAR_HOLD) + 0.5) * 60.0)))
	# 로그를 '무대 시각'(clear_show_t와 같은 축)으로 옮겨 담는다 — 구멍을 화면 사건과 대조하려면
	#   같은 자를 써야 한다. 0 = 무대가 열리는 순간(암전 시작), 음수 = 프리롤(스윕).
	var ev: Array = []
	for e0 in g._sfx_log:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "":
			continue
		ev.append({"t": float(e["t"]) - t0 - float(g.CLEAR_HOLD), "kind": String(e["kind"]), "semi": int(e["semi"])})
	return {"ev": ev, "rows": rows.size(), "log": g._sfx_log.duplicate(true)}

# 패스 H — 결과 팝업 개봉(R22 · §22 B-15). 봇 패스(A~C)에서도 팝업은 뜨지만 거기선 **개봉이
#   한 번뿐**이라 이 자리의 진짜 위험이 안 드러난다: `result_t`는 팝업이 닫힐 때까지 계속 오르므로
#   경계가 아니라 값으로 조건을 쓰면 **매 프레임 운다**. 그래서 개봉 뒤를 2.5초 더 굴려 총 발화를 센다.
# ⚠승·패를 따로 세운다 — 어휘가 갈리는 자리라 한쪽만 재면 반대쪽 배선이 빠져도 초록이다.
func _pass_result(win: bool) -> Dictionary:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	g._start_stage(0)
	g.intro_t = -1.0
	g.result_t = -1.0
	_idle(2)
	if win:
		# 축하 무대를 실제로 태운다(팝업은 무대가 끝나야 뜬다). 보드는 비워 둔다 — 스윕 발수는
		#   여기 관심이 아니고, 판이 앞 패스·유저 세이브에 따라 달라지는 걸 막는다(패스 G의 교훈).
		for r0 in range(g.ROWS):
			for c0 in range(g.COLS):
				g.board[r0][c0] = ""
		g.game_over = false
		g.game_clear = true
		g._plan_clear_fx()
		g.clear_show_t = -float(g.CLEAR_HOLD)
		g._fb("finish")
	else:
		# ⚠`pending_core_dead = true`로 세우면 안 된다 — `_end_turn` 안의 `advance_step`이
		#   `core_hp <= 0`으로 **재계산해 덮는다**(R11에서 이 함정에 한 번 걸렸다).
		g.core_hp = 0
		g._end_turn()
	# 팝업이 열릴 때까지 굴린다(죽음 연출·축하 무대가 끝나야 뜬다).
	var t0: float = -1.0
	for _i in range(int(15.0 * 60.0)):
		g._process(1.0 / 60.0)
		if g.result_t >= 0.0:
			t0 = g._sfx_t
			break
	_idle(150)          # 개봉 뒤 2.5초 — 매 프레임 발화라면 여기서 150발로 터진다
	var ev: Array = []
	var ring: float = t0
	var hole: float = 0.0
	for e0 in g._sfx_log:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "" or t0 < 0.0 or float(e["t"]) < t0 - 0.001:
			continue
		var t: float = float(e["t"])
		if t - ring > hole:
			hole = t - ring
		ring = maxf(ring, t + _dur(String(e["kind"]), int(e["semi"])))
		ev.append({"t": t - t0, "kind": String(e["kind"])})
	return {"open": t0, "ev": ev, "hole": hole, "cover": ring - t0}

# 패스 I — 판 진입 목표 카드(R23 · §31). 인트로는 **캠페인 진입에서만** 켜지는데 다른 패스는
#   전부 `intro_t = -1.0`으로 꺼 두고 재므로(카드가 떠 있으면 첫 클릭이 스킵으로 삼켜진다),
#   3박(등장 3발 · 홀드 무음 · 안착 1발)이 제대로 갈리는지는 여기서만 드러난다.
func _pass_intro(skip: bool) -> Dictionary:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	var t0: float = g._sfx_t
	g._start_stage(0)          # ← 여기서 goal_in이 나간다(호출부 배선 검사)
	if skip:
		_idle(15)              # 0.25초 뒤 아무 키나 = 스킵(도킹을 건너뛴다)
		var ev0 := InputEventKey.new()
		ev0.keycode = KEY_SPACE
		ev0.pressed = true
		g._input(ev0)
	_idle(int((float(g.INTRO_TOTAL) + 0.5) * 60.0))
	var ev: Array = []
	for e0 in g._sfx_log:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "":
			continue
		ev.append({"t": float(e["t"]) - t0, "kind": String(e["kind"]), "semi": int(e["semi"])})
	return {"ev": ev}

# 패스 J — 보석 카운터 도착(R24 · §22 B-2). **수집 스테이지에서만** 나는 소리라 봇 패스(스테이지 1)엔
#   한 발도 안 나온다 — 여기서 안 재면 배선이 통째로 빠져 있어도 초록이다(grab·score·fail에서
#   네 번 겪은 함정). 잡기(_apply_hit)부터 도착(_process의 gem_flights 만료)까지 **실제 경로**를 태운다.
func _pass_gem() -> Dictionary:
	g.sfx_log_on = true
	g.sound_on = true
	g._sfx_log = []
	g._sfx_t = 0.0
	seed(SEED_CAMPAIGN)
	g.seed_game(SEED_CAMPAIGN)
	# ⚠**스테이지 번호를 박지 않는다** — 수집판의 위치는 밸런스 작업마다 바뀐다(지금은 5번째지만
	#   이름은 st9다). 박아 두면 순서가 바뀐 날 검사가 조용히 '보석 0발'로 초록이 된다.
	var sidx: int = -1
	for si in range((g.STAGES as Array).size()):
		if not (g.STAGES[si] as Dictionary).get("collect_targets", []).is_empty():
			sidx = si
			break
	if sidx < 0:
		return {"n": -1, "target": -1, "semis": [], "got": -1}
	g._start_stage(sidx)
	g.intro_t = -1.0
	_idle(12)
	var tgt: int = int((g.st.get("collect_targets", [1]) as Array)[0])
	var semis: Array = []
	var arrivals: int = 0
	for i in range(tgt):
		for c0 in range(int(g.COLS)):
			g.board[0][c0] = ""          # 맨 윗줄을 비워 둔다 — 차 있으면 _spawn_gem이 조용히 보류한다
		g._spawn_gem(i % int(g.COLS))
		var gid: int = -1
		for e0 in g.enemies:
			if String((e0 as Dictionary)["etype"]) == "gem":
				gid = int((e0 as Dictionary)["id"])
		if gid < 0:
			continue
		g._sfx_log = []
		g._apply_hit({"id": gid, "dmg": 1, "kb": 0})   # 낚아챔 → 비행 시작(여기선 chain이 운다)
		_idle(36)                                       # 비행 0.42초보다 길게 = 도착까지
		for e1 in g._sfx_log:
			var e: Dictionary = e1 as Dictionary
			if String(e["drop"]) == "" and String(e["kind"]) == "collect":
				arrivals += 1
				semis.append(int(e["semi"]))
	# ② **동시 도착** — 한 블라스트에서 여러 개가 같은 프레임에 닿을 수 있다. 간격으로 눌리면
	#   화면 카운터는 +5인데 소리는 한 발이 된다(진행 신호를 삼킴) → 다 울리는지, 그리고 그때
	#   지속음 풀이 넘치지 않는지 같이 본다.
	g._sfx_log = []
	for _k in range(5):
		g.gem_flights.append({"from": Vector2.ZERO, "to": Vector2.ZERO, "t": 0.0, "dur": 0.05,
				"gtype": 0, "color": Color.WHITE})
	_idle(10)
	var burst: int = 0
	var burst_drop: int = 0
	for e2 in g._sfx_log:
		var e3: Dictionary = e2 as Dictionary
		if String(e3["kind"]) != "collect":
			continue
		if String(e3["drop"]) == "":
			burst += 1
		else:
			burst_drop += 1
	var mgm: Dictionary = _analyze(g._sfx_log)
	return {"n": arrivals, "target": tgt, "semis": semis, "burst": burst, "burst_drop": burst_drop,
			"music": int(mgm["max_music"]),
			"got": int(g.collected_by_type[0]) if (g.collected_by_type as Array).size() > 0 else -1}

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	# ⚠실유저 진행도 보호 — Main.tscn을 띄우면 _ready가 persist_enabled=true로 만든다.
	g.set("persist_enabled", false)
	# ⚠**A/B가 없어진다**(R20). R16~R19 동안 프로브는 `clear_ab=0`으로 **A안**을 재고 있었고,
	#   그래서 아래 셋이 A 기준으로 쓰여 있었다 — B 확정과 함께 전부 B로 다시 썼다:
	#     ④ 연쇄 사다리 — 런을 끊는 다운비트가 `clear`가 아니라 `clear_hit`이다
	#     ⑮ 전멸 광택 — B는 삭제가 clear2를 안 쏘므로 3발이 아니라 **2발**이다
	#   **어휘를 바꾸면 검사도 같이 바꿔야 한다**(R9·R18에서 이미 두 번 깨졌다).
	await process_frame

	print("=== 오디오 프로브 (시드 %d) ===" % SEED_CAMPAIGN)

	var ra: Array = _pass(IDLE_HUMAN)
	var log_a: Array = ra[0]
	var placed_a: int = int(ra[1])
	var ma: Dictionary = _analyze(log_a)
	_report("사람 템포", ma)
	var win_a: Array = windows.duplicate(true)

	var rb: Array = _pass(IDLE_STRESS)
	var mb: Dictionary = _analyze(rb[0])
	_report("스트레스", mb)

	var rc: Array = _pass(IDLE_HUMAN)      # 결정성 — A 재현
	var log_c: Array = rc[0]

	# ── 블라스트 창 분포(§17③ 재측정) — 이번 라운드가 고치려 한 바로 그 지표.
	#   ⚠총 발화수로는 판정이 안 된다. 이미 있는 소리를 붐비는 자리에 더 쌓아도 총량은 오르기 때문.
	var worst_lead: float = 0.0
	var worst_trail: float = 0.0
	var worst_hole: float = 0.0
	var lines: Array = []
	for w0 in win_a:
		var w: Array = w0 as Array
		var t0: float = float(w[0])
		var t1: float = float(w[1])
		if t1 - t0 < 0.3:
			continue                     # 삭제 없는 짧은 정산은 창이 아니다
		var ts: Array = []
		for e0 in log_a:
			var e: Dictionary = e0 as Dictionary
			if String(e["drop"]) != "":
				continue
			var t: float = float(e["t"])
			# ⚠**경계의 배치음은 뺀다.** _place_piece와 _settle 사이에 프레임이 안 흐르므로 place가
			#   창 시작과 정확히 같은 시각에 찍힌다 → 그걸 세면 '앞침묵 0.00'이라는 가짜 합격이 나온다.
			#   §17③이 잰 앞침묵은 **충전 구간의 침묵**이다. 자를 먼저 의심할 것.
			if t > t0 and t <= t1:
				ts.append(t - t0)
		var lead: float = float(ts[0]) if ts.size() > 0 else (t1 - t0)
		var trail: float = ((t1 - t0) - float(ts[ts.size() - 1])) if ts.size() > 0 else (t1 - t0)
		var hole: float = 0.0
		for i in range(1, ts.size()):
			hole = maxf(hole, float(ts[i]) - float(ts[i - 1]))
		worst_lead = maxf(worst_lead, lead)
		worst_trail = maxf(worst_trail, trail)
		worst_hole = maxf(worst_hole, hole)
		lines.append("     창 %.2fs · %d발 · 앞침묵 %.2f · 뒤침묵 %.2f · 최대구멍 %.2f"
				% [t1 - t0, ts.size(), lead, trail, hole])
	print("── 블라스트 창 분포 (레퍼런스 대비: 앞·뒤가 비면 '소리가 적다'로 느껴진다)")
	for ln in lines:
		print(ln)
	print("     최악 — 앞침묵 %.2fs · 뒤침묵 %.2fs · 중간구멍 %.2fs" % [worst_lead, worst_trail, worst_hole])

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

	# fanfare = 아르페지오 4음(R12부터 자기 이름으로 남는다). tap_* 셋은 R13 UI 탭(같은 파형·다른 음정).
	# ⚠축하 무대 다섯(R17)이 여기 나오는 건 정상이다 — **봇이 실제로 스테이지1을 깬다**(실측).
	#   패스 D의 옛 주석("봇은 14수 안에 못 깬다")은 밸런스가 바뀌기 전 이야기다. 다만 패스 A는
	#   승리 후 1초만 더 굴리므로 무대의 앞부분(스윕·글자)까지만 잡힌다 → 전체는 패스 G가 잰다.
	# ⚠B안 확정(R20)으로 판 안의 삭제음이 `clear_hit` + `clear_note` 두 어휘가 됐고, 로켓이
	#   실제로 울린다(옛 A 경로에선 clear/clear2였다). 목록을 안 고치면 정상 동작이 FAIL로 나온다.
	var allowed: Array = ["grab", "place", "clear2", "chain", "score", "fail",
			"tap", "tap_go", "tap_back", "tap_off", "fanfare", "climax", "praise", "leak",
			"sweep", "clear_hit", "clear_note", "rocket", "letter", "chord", "logo",
			"fw_rise", "fw_pop",
			# 결과 팝업(R22) — 패스 A에는 **아직 안 나온다**(승리 후 1초만 더 굴리는데 팝업은 죽음
			#   연출 1.6초·축하 무대 3.6초 뒤에 뜬다). 그래도 설계표에 있으니 여기 적어 둔다 —
			#   나중에 패스 A를 더 길게 굴리면 정상 동작이 FAIL로 나오는 자리다.
			"result_win", "result_lose", "result_cta",
			# 목표 카드(R23) — 이건 패스 A에도 **나온다**(캠페인 진입에서 켜지므로 봇 패스의 첫 소리다).
			"goal_in", "goal_dock",
			# 보석 도착(R24) — 수집 스테이지 전용이라 패스 A(스테이지 1)엔 안 나온다. 패스 J가 잰다.
			"collect"]
	var unexpected: Array = []
	for k in kinds_a.keys():
		if not allowed.has(String(k)):
			unexpected.append(k)
	_check("⑦ 어휘는 설계표(29) 안", unexpected.is_empty(),
			"예상 밖: %s" % str(unexpected))

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
		# ⚠**어휘를 바꾸면 이 검사도 같이 갱신해야 한다** — R9에서 이름 의존 때문에 한 번 FAIL했다.
		#   R12부터 아르페지오는 `fanfare` 이름으로 남는다(파형은 clear와 같은 낮은 칩).
		if String(e["kind"]) == "fanfare":
			fan_notes += 1
			semis.append(int(e["semi"]))
	var grabs: int = 0
	for e0 in log_d:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) == "" and String(e["kind"]) == "grab":
			grabs += 1
	print("── 어휘: fanfare 음 %d발 · 드롭 %s · 음정 %s · grab %d발" % [fan_notes, str(fan_drops), str(semis), grabs])
	_check("⑧ 집기 배선(_pick_up → grab)", grabs == 1, "%d발" % grabs)
	# ⚠배선 검사를 어휘 직접 타격으로 대신하면 안 된다 — grab·score·fail 셋 다 봇 패스(A~C)에선
	#   한 발도 안 울려서, 호출부가 통째로 빠져 있어도 프로브가 조용히 초록이 된다.
	var n_score: int = 0
	var n_fail: int = 0
	for e0 in log_d:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "":
			continue
		if String(e["kind"]) == "score":
			n_score += 1
		elif String(e["kind"]) == "fail":
			n_fail += 1
	_check("⑨ 점수 틱 배선(롤업 → score)", n_score >= 3, "%d발" % n_score)
	_check("⑩ 실패 배선(_end_turn 거점사 → fail)", n_fail == 1, "%d발" % n_fail)
	_check("⑤ fanfare = 4음 아르페지오 ×2판", fan_notes == 8, "%d발 · %s" % [fan_notes, str(semis)])
	_check("⑤ 같은 판 두 번째 fanfare = 드롭", fan_drops.has("once"), "드롭 %s" % str(fan_drops))

	# ── 패스 E: UI 탭 배선(진짜 입력 이벤트)
	var re: Array = _pass_ui()
	var log_e: Array = re[0]
	var nav: Array = re[1]
	var ui: Dictionary = {}
	for e0 in log_e:
		var e: Dictionary = e0 as Dictionary
		if String(e["drop"]) != "":
			continue
		var k: String = String(e["kind"])
		if k.begins_with("tap"):
			ui[k] = int(ui.get(k, 0)) + 1
	var nav_ok: bool = true
	var nav_bad: Array = []
	for n in nav:
		if not bool((n as Array)[1]):
			nav_ok = false
			nav_bad.append((n as Array)[0])
	print("── UI 탭: %s · 화면 전환 %s" % [str(ui), "정상" if nav_ok else str(nav_bad)])
	_check("⑪ 기어·닫기 배선(tap / tap_back)", int(ui.get("tap", 0)) >= 1 and int(ui.get("tap_back", 0)) >= 2,
			"tap %d · tap_back %d" % [int(ui.get("tap", 0)), int(ui.get("tap_back", 0))])
	_check("⑫ 진입 배선(버튼 → tap_go)", int(ui.get("tap_go", 0)) >= 1, "%d발" % int(ui.get("tap_go", 0)))
	_check("⑬ 잠긴 버튼 = tap_off(무음도 경고음도 아님)", int(ui.get("tap_off", 0)) == 1,
			"%d발" % int(ui.get("tap_off", 0)))
	_check("⑭ UI 탭이 화면 전환과 일치", nav_ok, "어긋남: %s" % str(nav_bad))

	# ── 패스 F: 블라스트 창 beat 배선(R14)
	var fx: Dictionary = _pass_fx()
	print("── 창 beat: %s" % str(fx))
	_check("⑮ 전멸 배선(_fire_climax → climax)", int(fx.get("climax", 0)) == 1, "%d발" % int(fx.get("climax", 0)))
	_check("⑮ 전멸 = 3층(광택 2발이 뒤따름)", int(fx.get("clear2", 0)) >= 2,
			"clear2 %d발(전멸 3층의 2·삭제는 B안이라 광택 없음)" % int(fx.get("clear2", 0)))
	_check("⑯ 칭찬 팝인 배선(praise_delay 만료 → praise)", int(fx.get("praise", 0)) == 1,
			"%d발" % int(fx.get("praise", 0)))
	_check("⑰ 비행기 픽업 배선(_apply_hit → chain)", int(fx.get("plane", 0)) == 1, "%d발" % int(fx.get("plane", 0)))
	_check("⑱ 누수 = 3열 동시라도 한 발", int(fx.get("leak", 0)) == 1, "%d발" % int(fx.get("leak", 0)))

	# ── 패스 G: 클리어 축하 무대 배선 + 무음 구간(R17)
	var cs: Dictionary = _pass_clear()
	var ev: Array = cs["ev"]
	var cnt: Dictionary = {}
	var sweep_semis: Array = []
	var letter_semis: Array = []
	for e0 in ev:
		var e: Dictionary = e0 as Dictionary
		var k: String = String(e["kind"])
		cnt[k] = int(cnt.get(k, 0)) + 1
		if k == "sweep":
			sweep_semis.append(int(e["semi"]))
		elif k == "letter":
			letter_semis.append(int(e["semi"]))
	# 무대 안의 최대 무음 — **이번 라운드가 고치려 한 바로 그 지표**(§17③과 같은 자).
	#   총 발화수로는 판정이 안 된다: 붐비는 자리에 더 쌓아도 총량은 오른다.
	# ⚠**온셋 간격이 아니라 '울리는 중인 소리가 하나도 없는 시간'을 잰다**(R19에서 고쳤다).
	#   지속음이 들어오자 옛 자가 거짓말을 하기 시작했다 — 1.4초 우는 음 뒤에 0.4초 공백이 있어도
	#   귀에는 이어져 있는데, 발화 시각만 보면 '무음 0.4초'라고 읽었다. **재료가 바뀌면 자도 바뀐다.**
	var stage_end: float = float(g.CLEAR_SHOW_TOTAL)
	var ring: float = -float(g.CLEAR_HOLD)      # 지금까지 울린 소리가 끝나는 가장 늦은 시각
	var hole: float = 0.0
	var hole_at: float = 0.0
	for e0 in ev:
		var e3: Dictionary = e0 as Dictionary
		var t: float = float(e3["t"])
		if t > stage_end:
			break
		if t - ring > hole:
			hole = t - ring
			hole_at = ring
		ring = maxf(ring, t + _dur(String(e3["kind"]), int(e3["semi"])))
	if stage_end - ring > hole:
		hole = stage_end - ring
		hole_at = ring
	var mg: Dictionary = _analyze(cs["log"])
	print("── 축하 무대: %s" % str(cnt))
	print("     스윕 음정 %s · 글자 음정 %s" % [str(sweep_semis), str(letter_semis)])
	print("     최대 무음 %.2fs (무대시각 %.2f~%.2f) · 보이스 %d/선율 %d · 롤링 1초 %d발"
			% [hole, hole_at, hole_at + hole, int(mg["max_voices"]), int(mg["max_music"]), int(mg["max_fires_1s"])])
	_check("⑲ 스윕 배선 = 블록 있는 행 수", int(cnt.get("sweep", 0)) == int(cs["rows"]),
			"sweep %d발 · 행 %d" % [int(cnt.get("sweep", 0)), int(cs["rows"])])
	var sweep_up: bool = true
	for i in range(1, sweep_semis.size()):
		if int(sweep_semis[i]) <= int(sweep_semis[i - 1]):
			sweep_up = false
	_check("⑲ 스윕은 아래→위로 오른다", sweep_up and int(cnt.get("clear_hit", 0)) == 1,
			"음정 %s · 종료 타격 %d발" % [str(sweep_semis), int(cnt.get("clear_hit", 0))])
	# 로고 = BLOCK 5글자 + CASTLE 1 = 6발이 한 줄로 오른다. 강펀치(logo)는 정확히 한 번.
	_check("⑳ 로고 조립 배선(글자 %d + 정점 1)" % (int(g.WM_L1.length()) + 1),
			int(cnt.get("letter", 0)) == int(g.WM_L1.length()) + 1 and int(cnt.get("logo", 0)) == 1,
			"letter %d · logo %d" % [int(cnt.get("letter", 0)), int(cnt.get("logo", 0))])
	# ⚠**이 검사가 R18에서 통째로 바뀌었다.** 전엔 "로고 강펀치 = 2층(광택이 뒤따름)"을 봤는데,
	#   그 2층 문법(타격 + 45ms 광택)이 **바로 삭제음의 문법**이라 유저가 "폭죽 터질 때 라인 터지는
	#   소리가 들린다"고 잡아냈다. 즉 옛 검사는 결함을 **지키고 있었다.**
	#   지금 보는 것: 무대가 열린 뒤(t≥0) 울리는 소리가 **판 안의 삭제·로켓 파형을 쓰지 않는가.**
	#   ⚠어휘 이름이 아니라 **파형 파일**로 본다 — R18의 발사음은 이름만 `fw_rise`였고 파일은
	#   블라스트 로켓 그 자체였다(이름만 보는 검사는 조용히 통과했다).
	#   ⚠`letter`(=place와 같은 pop_low)는 **일부러 남긴 인용**이다: 로고 글자는 블록이 놓이는
	#   것이니 의미가 같다. 스윕·종료 타격도 프리롤(t<0)이고 '판 전체 줄삭제'라 의미가 같다.
	# ⚠**경로가 아니라 소리로 비교한다.** 처음엔 resource_path로 봤는데, 후보 폴더에 들어 있는
	#   `riseD_current.wav`는 로켓음의 **복사본**이라 경로만 다르고 소리는 같다 → 검사가 조용히
	#   통과했다(일부러 결함을 세워 재 보고 알았다). **자를 만들면 그 자가 실패하는지부터 볼 것.**
	var play_fps: Array = []
	for k in ["clear", "clear2", "clear_hit", "clear_note", "rocket"]:
		var st0 = g._sfx_bank.get(k, null)
		if st0 != null and not play_fps.has(_fp(st0)):
			play_fps.append(_fp(st0))
	var quoted: Array = []
	for e0 in ev:
		var e2: Dictionary = e0 as Dictionary
		if float(e2["t"]) < 0.0:
			continue
		var st1 = g._sfx_bank.get(String(e2["kind"]), null)
		if st1 != null and play_fps.has(_fp(st1)):
			quoted.append("%s(%s)" % [String(e2["kind"]), String(st1.resource_path).get_file()])
	_check("⑳ 무대가 열린 뒤엔 삭제·로켓 파형을 안 쓴다", quoted.is_empty(), "인용: %s" % str(quoted))
	# 선율(R19) — 글자 5 + CASTLE 1이 사다리를 오르고, 정점에서 화음 4음이 **같은 프레임에** 앉는다.
	var chord_ts: Array = []
	for e0 in ev:
		if String((e0 as Dictionary)["kind"]) == "chord":
			chord_ts.append(float((e0 as Dictionary)["t"]))
	var same_frame: bool = chord_ts.size() == int(g.CLEAR_CHORD.size()) \
			and (chord_ts.is_empty() or (float(chord_ts[chord_ts.size() - 1]) - float(chord_ts[0])) < 0.001)
	_check("⑳ 정점 화음 = %d음 동시" % int(g.CLEAR_CHORD.size()), same_frame,
			"%d음 · 시각폭 %.4fs" % [chord_ts.size(),
			(float(chord_ts[chord_ts.size() - 1]) - float(chord_ts[0])) if chord_ts.size() > 1 else 0.0])
	# 선율이 실제로 지속음인가 — 파형 길이로 본다(타격 파형으로 되돌아가면 여기서 잡힌다).
	var note_len: float = 0.0
	var nst = g._sfx_bank.get("letter", null)
	if nst != null:
		note_len = float(nst.get_length())
	_check("⑳ 선율 파형이 지속음(≥0.4s)", note_len >= 0.4, "%.2fs" % note_len)
	_check("㉑ 폭죽 = 발사·터짐 각 %d발" % int(g.CLEAR_ROCKET_N),
			int(cnt.get("fw_rise", 0)) == int(g.CLEAR_ROCKET_N) and int(cnt.get("fw_pop", 0)) == int(g.CLEAR_ROCKET_N),
			"발사 %d · 터짐 %d" % [int(cnt.get("fw_rise", 0)), int(cnt.get("fw_pop", 0))])
	# 무음 상한 0.55s — 레퍼런스 삭제음 한 사건이 0.32s이므로 그 두 배를 넘으면 '끊겼다'로 들린다.
	#   ⚠이 검사는 배선이 빠지면 즉시 크게 터진다(전엔 3.4초였다) = 회귀 감시가 목적이다.
	_check("㉒ 무대 안 최대 무음 ≤ 0.55s", hole <= 0.55, "%.2fs @ %.2f" % [hole, hole_at])
	_check("㉒ 무대 예산(타격 %d · 선율 %d · 롤링 %d)" % [MAX_VOICES, MAX_MUSIC_VOICES, MAX_FIRES_IN_1S],
			int(mg["max_voices"]) <= MAX_VOICES and int(mg["max_music"]) <= MAX_MUSIC_VOICES
					and int(mg["max_fires_1s"]) <= MAX_FIRES_IN_1S,
			"타격 %d · 선율 %d · 1초 %d발" % [int(mg["max_voices"]), int(mg["max_music"]), int(mg["max_fires_1s"])])

	# ── 패스 H: 결과 팝업 개봉(R22 · §22 B-15)
	for win in [true, false]:
		var rs: Dictionary = _pass_result(win)
		var tag: String = "클리어" if win else "실패"
		var rev: Array = rs["ev"]
		var rcnt: Dictionary = {}
		for e0 in rev:
			var k: String = String((e0 as Dictionary)["kind"])
			rcnt[k] = int(rcnt.get(k, 0)) + 1
		var open_word: String = "result_win" if win else "result_lose"
		var cta_t: float = -1.0
		for e0 in rev:
			if String((e0 as Dictionary)["kind"]) == "result_cta":
				cta_t = float((e0 as Dictionary)["t"])
		print("── 결과 팝업(%s): %s · 최대 무음 %.2fs · 소리가 덮는 길이 %.2fs"
				% [tag, str(rcnt), float(rs["hole"]), float(rs["cover"])])
		_check("㉓ 팝업 개봉 배선(%s → %s)" % [tag, open_word],
				int(rcnt.get(open_word, 0)) == 1 and int(rcnt.get("result_win" if not win else "result_lose", 0)) == 0,
				str(rcnt))
		# 버튼 도착 = **상태 변화**다(그 전까지 _input이 팝업을 통째로 막는다) → 시각까지 본다.
		_check("㉓ 버튼 도착 배선(RESULT_BTN_IN=%.2f)" % float(g.RESULT_BTN_IN),
				int(rcnt.get("result_cta", 0)) == 1 and absf(cta_t - float(g.RESULT_BTN_IN)) < 0.05,
				"%d발 · %.3fs" % [int(rcnt.get("result_cta", 0)), cta_t])
		# ⚠**이 검사가 요점이다.** result_t는 팝업이 닫힐 때까지 계속 오르므로 조건을 경계가 아니라
		#   값으로 쓰면 개봉음이 2.5초 동안 150발 난다 — 진흙이 아니라 굉음이다.
		var rn: int = int(rcnt.get("result_win", 0)) + int(rcnt.get("result_lose", 0)) + int(rcnt.get("result_cta", 0))
		_check("㉔ 개봉 뒤 2.5초 동안 정확히 2발(경계에서만)", rn == 2, "%d발" % rn)
		# 개봉 창에 구멍이 없나 — 지속음 한 발이 개봉 3박(카드·내용·버튼 0.30s)을 통째로 덮어야 한다.
		#   ⚠상한이 아니라 **하한**이고, 기준은 0.8초다: 타격 파형으로 되돌리면 0.1초쯤에서 끊기므로
		#   여기서 즉시 터진다. 승·패가 0.93 / 1.87초로 갈리는 건 음정 차(같은 파형을 +7 / −5로 쓴다).
		_check("㉔ 개봉 창을 소리가 ≥0.8초 덮는다", float(rs["cover"]) >= 0.8, "%.2fs" % float(rs["cover"]))

	# ── 패스 I: 판 진입 목표 카드(R23 · §31)
	var it: Dictionary = _pass_intro(false)
	var iev: Array = it["ev"]
	var in_semis: Array = []
	var dock_t: float = -1.0
	var hold_hits: Array = []
	for e0 in iev:
		var e4: Dictionary = e0 as Dictionary
		var k4: String = String(e4["kind"])
		if k4 == "goal_in":
			in_semis.append(int(e4["semi"]))
		elif k4 == "goal_dock":
			dock_t = float(e4["t"])
		# 홀드 구간(등장 끝 ~ 도킹 시작)은 **일부러 비운 자리**다(레퍼런스도 0.35초 무음).
		if float(e4["t"]) > float(g.INTRO_APPEAR) and float(e4["t"]) < float(g.INTRO_APPEAR) + float(g.INTRO_HOLD):
			hold_hits.append(k4)
	print("── 목표 카드: %s · 등장 음정 %s · 안착 %.2fs(INTRO_TOTAL %.2f)"
			% [str(iev.size()) + "발", str(in_semis), dock_t, float(g.INTRO_TOTAL)])
	_check("㉕ 카드 등장 배선(_start_stage → goal_in 3발 상승)",
			in_semis == [0, 4, 7], str(in_semis))
	_check("㉕ 도킹 안착 배선(INTRO_TOTAL → goal_dock)",
			dock_t >= 0.0 and absf(dock_t - float(g.INTRO_TOTAL)) < 0.05, "%.3fs" % dock_t)
	# ⚠홀드는 '아직 안 붙인 자리'가 아니라 **비운 자리**다 — 나중에 여기 뭘 붙이면 이 검사가 먼저 묻는다.
	_check("㉕ 홀드 구간(%.2fs)은 무음" % float(g.INTRO_HOLD), hold_hits.is_empty(), str(hold_hits))
	# 스킵 — 도킹 연출을 건너뛰었으면 안착음도 없어야 한다(소리가 화면에 없는 사건을 말하면 안 된다).
	var it2: Dictionary = _pass_intro(true)
	var skipped: Dictionary = {}
	for e0 in it2["ev"]:
		var k5: String = String((e0 as Dictionary)["kind"])
		skipped[k5] = int(skipped.get(k5, 0)) + 1
	_check("㉖ 인트로 스킵 = 닫기음만(안착음 없음)",
			int(skipped.get("goal_dock", 0)) == 0 and int(skipped.get("tap_back", 0)) == 1, str(skipped))

	# ── 패스 J: 보석 카운터 도착(R24 · §22 B-2)
	var gm: Dictionary = _pass_gem()
	print("── 보석 도착: %d발 / quota %d · 수집 %d · 음정 %s"
			% [int(gm["n"]), int(gm["target"]), int(gm["got"]), str(gm["semis"])])
	_check("㉗ 도착 배선 = 보석 하나에 한 발", int(gm["n"]) == int(gm["target"]),
			"%d발 / %d개" % [int(gm["n"]), int(gm["target"])])
	# 음정이 진행도를 나르는가 — 첫 발은 사다리 바닥, 마지막 발은 꼭대기, 그리고 **되돌아가지 않는다.**
	var gs: Array = gm["semis"]
	var mono: bool = true
	for i in range(1, gs.size()):
		if int(gs[i]) < int(gs[i - 1]):
			mono = false
	_check("㉗ 음정이 진행도를 나른다(바닥→꼭대기·역행 0)",
			mono and gs.size() > 0 and int(gs[0]) == 0 and int(gs[gs.size() - 1]) == 7, str(gs))
	# 동시 도착 — 카운터가 +5면 소리도 5발이어야 한다(간격으로 눌리면 진행 신호를 삼킨다).
	_check("㉘ 동시 도착 5개 = 5발(드롭 0) · 선율 풀 %d 이내" % MAX_MUSIC_VOICES,
			int(gm["burst"]) == 5 and int(gm["burst_drop"]) == 0 and int(gm["music"]) <= MAX_MUSIC_VOICES,
			"%d발 · 드롭 %d · 선율 %d" % [int(gm["burst"]), int(gm["burst_drop"]), int(gm["music"])])

	print("=== %s (실패 %d) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
