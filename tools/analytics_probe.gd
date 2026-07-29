extends SceneTree
# 계측 배선 검증 — 실제 판을 봇으로 굴려 P0 이벤트가 JSONL에 남는지 확인한다(Phase V W1 ④).
#   실행: godot --path . --script tools/analytics_probe.gd      ⚠창 모드로 돌린다
#   (--headless면 AnalyticsService가 스스로 꺼진다 = 설계대로. 그래서 검증은 창 모드 몫.)
#
# 무엇을 보나: ①P0 이벤트가 실제 플레이 경로에서 나오나 ②공통 좌표(session_id·run_id·mode)가 붙나
#   ③택소노미 밖 이름이 섞이지 않았나(unknown_event). 값의 '해석'은 tools/analytics_report.gd 몫.

# ── 결정성: 봇에게 매번 '같은 판'을 물린다 ──────────────────────────────────
# 시드를 안 박으면 Main._ready의 game_rng.randomize()가 실행마다 다른 판을 만들어, 같은 코드가
#   FAIL(24이벤트)·FAIL(25)·PASS(27)로 갈린다(2026-07-29 실측). 튜토리얼 박자2는 봇이 줄로 적을
#   실제로 잡아야 발화하는데, 그게 되는 판이 있고 안 되는 판이 있기 때문. 점검기가 원래 흔들리면
#   진짜 계측 파손도 "또 플레이크겠지"로 넘어간다 → 아래 두 시드는 튜토리얼 3박자가 전부 나오는
#   판으로 골라 박은 값이다. 게임 기전(조각 풀·스폰·튜토리얼)을 바꾸면 재탐색해야 한다:
#     PROBE_SEED=<후보> godot --path . --script tools/analytics_probe.gd   ← 캠페인 시드만 덮어씀
const CAMPAIGN_SEED: int = 20250101
const ENDLESS_SEED: int = 20250102

# 캠페인 구간 배치 예산 — 누수(박자3)가 나기 전에 봇이 판을 닫아버리지 않을 만큼은 둔다.
# 끝까지 두면 봇이 스테이지를 깨서 부활 분기가 안 열리므로, 예산 소진 후엔 거점사로 강제 종료한다.
const CAMPAIGN_PLACES: int = 15

# 위 시드로 나오는 정확한 집계(28이벤트). 개수까지 박아야 '조용한 누락'이 잡힌다 —
#   예: 부활 배선이 끊겨 revive_taken이 0이 돼도 '≥1' 검사만 있으면 다른 검사들이 초록이라 묻힌다.
const GOLDEN_EVENTS: Dictionary = {
	"app_opened": 1, "session_ended": 1,
	"run_started": 2, "run_failed": 3, "stage_failed": 2, "combo_peak": 3,
	"first_line_cleared": 1, "endless_run_ended": 1,
	"tutorial_beat_completed": 3,                      # 박자 1·2·3 전부
	"revive_offered": 2, "revive_taken": 1, "revive_declined": 1,
	"ad_requested": 2, "ad_filled": 2, "ad_shown": 1, "ad_rewarded": 1, "ad_closed": 1,
}

const LOG_PATH: String = "user://analytics.jsonl"
const META_PATH: String = "user://analytics.meta"
const CAMPAIGN_SAVE: String = "user://campaign.save"   # 튜토리얼을 켜려면 '스테이지1 미클리어' 상태여야 한다

var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("%s %s%s" % ["OK  " if ok else "FAIL", tag, ("  — " + detail) if detail != "" else ""])

# 첫 유효 배치를 찾는 최소 봇 — 줄이 되는 수를 우선한다(콤보·첫 줄 이벤트를 실제로 뽑기 위해).
#   튜토리얼 잠금(tut_lock) 중엔 목표 칸(tut_cells) 안에만 놓을 수 있다 → 그 수만 후보로 본다.
#   (안 그러면 봇이 거부당하는 수를 반복해 박자1이 영영 안 끝난다.)
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
					return mv          # 줄이 되는 수 = 즉시 채택
				if fallback.is_empty():
					fallback = mv
	return fallback

func _settle() -> void:
	var s: int = 0
	while g.resolving and s < 400:
		g._process(0.05)
		s += 1

func _play_until_end(max_places: int) -> int:
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
	return places

# 거점사 강제 — 실제 판정 경로(_end_turn의 pending_core_dead 분기)를 그대로 탄다.
func _force_core_death() -> void:
	g.core_hp = 0
	g.pending_core_dead = true
	g._end_turn()
	_settle()

func _read_log() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(LOG_PATH):
		return out
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line == "":
			continue
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary:
			out.append(v)
	f.close()
	return out

func _names(evs: Array) -> Dictionary:
	var n: Dictionary = {}
	for e in evs:
		var k: String = String((e as Dictionary).get("event", "?"))
		n[k] = int(n.get(k, 0)) + 1
	return n

func _run() -> void:
	# 깨끗한 출발 — 이전 실행의 로그·메타를 지운다(is_first_session도 다시 참).
	for p in [LOG_PATH, META_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# 튜토리얼 퍼널을 재려면 '첫 실행' 상태여야 한다 → 캠페인 세이브를 잠시 치우고 끝나면 되돌린다
	#   (개발기의 실제 진행도를 날리지 않는다).
	var campaign_backup: PackedByteArray = PackedByteArray()
	var had_campaign: bool = FileAccess.file_exists(CAMPAIGN_SAVE)
	if had_campaign:
		var cf := FileAccess.open(CAMPAIGN_SAVE, FileAccess.READ)
		if cf != null:
			campaign_backup = cf.get_buffer(cf.get_length())
			cf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMPAIGN_SAVE))

	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	# ── 캠페인 1판: 봇이 실제로 놓고 지우다가, 부활 경로를 타게 중간에 거점사로 닫는다.
	#    (끝까지 두면 봇이 깨버려 부활 분기가 안 열린다.)
	var cseed: int = CAMPAIGN_SEED
	var seed_override: String = OS.get_environment("PROBE_SEED")
	if seed_override != "":
		cseed = int(seed_override)
		print("── ⚠시드 오버라이드: 캠페인 %d (탐색 모드)" % cseed)
	seed(cseed)          # 코스메틱 전역 스트림
	g.seed_game(cseed)   # 게임 스트림(조각·스폰) — _ready의 randomize()를 덮어쓴다
	g._start_stage(0)
	await process_frame
	var placed: int = _play_until_end(CAMPAIGN_PLACES)
	if not (g.game_over or g.game_clear):
		_force_core_death()
	print("── 캠페인 1차 종료: 배치 %d · clear=%s over=%s" % [placed, g.game_clear, g.game_over])

	# 부활 수락(revive_taken) → 이어서 같은 판을 마저 죽인다. 부활 뒤 이벤트도 같은 run_id여야 한다.
	#   ⚠_revive()를 직접 부르지 않는다 — W2부터 플레이어 경로는 광고 게이트를 지나므로(_request_revive_ad),
	#     여기서 문을 건너뛰면 사람이 못 가는 길을 재는 셈이 된다. 페이크 광고는 즉시 보상으로 해소된다.
	if g.game_over and not g.revive_used:
		g._request_revive_ad()
		await process_frame
		_play_until_end(CAMPAIGN_PLACES)
		if not (g.game_over or g.game_clear):
			_force_core_death()

	# ── 무한 1런: 다른 기둥(mode=endless) 좌표 + endless_run_ended + 부활 거절
	#   ⚠캠페인과 다른 시드로 다시 박는다 — 한 번만 박으면 두 구간이 한 스트림에 묶여, 캠페인 쪽을
	#     한 줄만 고쳐도 무한 구간의 판이 통째로 바뀐다(회귀 골든이 하류로 시프트하는 것과 같은 함정).
	seed(ENDLESS_SEED)
	g.seed_game(ENDLESS_SEED)
	g._start_endless()
	await process_frame
	_play_until_end(40)
	if not g.game_over:
		_force_core_death()
	# 거절 — 결과 팝업에서 뒤로가기(실제 입력 경로를 그대로 탄다)
	g.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame

	g._analytics.session_end()

	# 캠페인 세이브 원복(프로브가 개발기 진행도를 건드리지 않게)
	if had_campaign:
		var rf := FileAccess.open(CAMPAIGN_SAVE, FileAccess.WRITE)
		if rf != null:
			rf.store_buffer(campaign_backup)
			rf.close()

	# ── 검증
	var evs: Array = _read_log()
	var n: Dictionary = _names(evs)
	print("── 이벤트 집계 ──")
	var keys: Array = n.keys()
	keys.sort()
	for k in keys:
		print("   %-24s %d" % [k, n[k]])

	# ── 집계 골든: 고정 시드라 개수가 정확히 재현된다. 아래 의미 검사들이 '무엇이 깨졌나'를 말해주고,
	#   이 골든이 '뭔가 달라졌다'를 하나도 안 놓치고 잡는다(회귀 골든과 같은 계약).
	#   ⚠의도적 변경(이벤트 추가·튜토리얼 개편) 뒤엔 여기를 다시 떠서 커밋한다 — 안 그러면 의도된 차이가 노이즈로 남는다.
	if seed_override == "":
		var extra: Array = []
		var short: Array = []
		for k2 in GOLDEN_EVENTS.keys():
			if int(n.get(k2, 0)) != int(GOLDEN_EVENTS[k2]):
				short.append("%s %d≠%d" % [k2, int(n.get(k2, 0)), int(GOLDEN_EVENTS[k2])])
		for k3 in n.keys():
			if not GOLDEN_EVENTS.has(k3):
				extra.append("%s %d" % [k3, int(n[k3])])
		_check("집계 골든 일치", short.is_empty() and extra.is_empty(),
				"불일치 %s · 골든에 없는 이름 %s" % [str(short), str(extra)])
	else:
		print("   (시드 오버라이드 — 집계 골든 검사 건너뜀)")

	_check("app_opened 1회", int(n.get("app_opened", 0)) == 1, "실제 %d" % int(n.get("app_opened", 0)))
	_check("session_ended 1회", int(n.get("session_ended", 0)) == 1)
	_check("run_started ≥2 (캠페인+무한)", int(n.get("run_started", 0)) >= 2, "실제 %d" % int(n.get("run_started", 0)))
	_check("판 종료 이벤트 존재", int(n.get("run_failed", 0)) + int(n.get("stage_cleared", 0)) >= 2)
	_check("combo_peak = 판 종료 수", int(n.get("combo_peak", 0)) == int(n.get("run_failed", 0)) + int(n.get("stage_cleared", 0)),
			"peak %d vs 종료 %d" % [int(n.get("combo_peak", 0)), int(n.get("run_failed", 0)) + int(n.get("stage_cleared", 0))])
	_check("first_line_cleared 최대 1회(세션 게이트)", int(n.get("first_line_cleared", 0)) <= 1)
	_check("endless_run_ended ≥1", int(n.get("endless_run_ended", 0)) >= 1)
	_check("revive_offered ≥1", int(n.get("revive_offered", 0)) >= 1)
	_check("revive_taken ≥1", int(n.get("revive_taken", 0)) >= 1)
	_check("revive_declined ≥1", int(n.get("revive_declined", 0)) >= 1)
	# 튜토리얼 퍼널 — 고정 시드 판에서 봇이 3박자를 전부 실제로 밟는다(박자3 = 첫 누수 캡션).
	#   예전엔 판이 매번 달라 박자2·3이 되기도 안 되기도 해서 박자3을 '참고'로 뺐었다 — 시드 고정으로 해소.
	var beats: Dictionary = {}
	for e in evs:
		var de: Dictionary = e as Dictionary
		if String(de.get("event", "")) == "tutorial_beat_completed":
			beats[int(de.get("beat", 0))] = true
	_check("tutorial_beat_completed 박자1", beats.has(1))
	_check("tutorial_beat_completed 박자2", beats.has(2))
	_check("tutorial_beat_completed 박자3", beats.has(3), "첫 누수가 안 났다 — 시드/배치예산 재탐색 필요")

	# 공통 좌표(§2) — 판 안에서 난 이벤트엔 mode/run_id가 반드시 붙는다
	var missing_coord: int = 0
	var unknown: int = 0
	var no_session: int = 0
	var run_scoped: Array = ["run_started", "run_failed", "stage_cleared", "stage_failed", "combo_peak", "endless_run_ended", "revive_offered", "revive_taken"]
	for e in evs:
		var d: Dictionary = e as Dictionary
		if String(d.get("session_id", "")) == "":
			no_session += 1
		if bool(d.get("unknown_event", false)):
			unknown += 1
			print("   ⚠택소노미 밖 이름: %s" % String(d.get("event", "?")))
		if run_scoped.has(String(d.get("event", ""))) and (not d.has("run_id") or not d.has("mode")):
			missing_coord += 1
			print("   ⚠좌표 누락: %s" % String(d.get("event", "?")))
	_check("모든 이벤트에 session_id", no_session == 0, "누락 %d" % no_session)
	_check("판 이벤트에 run_id·mode", missing_coord == 0, "누락 %d" % missing_coord)
	_check("택소노미 밖 이름 0", unknown == 0, "발견 %d" % unknown)

	# 죽음의 질(cause)이 실제로 실리나 — 이 스프린트의 핵심 질문이 조립 가능한지 확인
	var causes: Dictionary = {}
	for e in evs:
		var d2: Dictionary = e as Dictionary
		if String(d2.get("event", "")) == "run_failed":
			var c: String = String(d2.get("cause", "?"))
			causes[c] = int(causes.get(c, 0)) + 1
	print("   run_failed cause 분포: %s" % str(causes))
	_check("run_failed에 cause 필수", not causes.has("?"))

	print("── %s (%d개 이벤트, 실패 %d) ──" % ["PASS" if fails == 0 else "FAIL", evs.size(), fails])
	quit(1 if fails > 0 else 0)
