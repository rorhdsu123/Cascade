extends SceneTree
# 계측 배선 검증 — 실제 판을 봇으로 굴려 P0 이벤트가 JSONL에 남는지 확인한다(Phase V W1 ④).
#   실행: godot --path . --script tools/analytics_probe.gd      ⚠창 모드로 돌린다
#   (--headless면 AnalyticsService가 스스로 꺼진다 = 설계대로. 그래서 검증은 창 모드 몫.)
#
# 무엇을 보나: ①P0 이벤트가 실제 플레이 경로에서 나오나 ②공통 좌표(session_id·run_id·mode)가 붙나
#   ③택소노미 밖 이름이 섞이지 않았나(unknown_event). 값의 '해석'은 tools/analytics_report.gd 몫.

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
	#    (끝까지 두면 봇이 깨버려 부활 분기가 안 열린다 — 시드가 매판 달라 결과가 흔들리므로 강제.)
	g._start_stage(0)
	await process_frame
	var placed: int = _play_until_end(15)
	if not (g.game_over or g.game_clear):
		_force_core_death()
	print("── 캠페인 1차 종료: 배치 %d · clear=%s over=%s" % [placed, g.game_clear, g.game_over])

	# 부활 수락(revive_taken) → 이어서 같은 판을 마저 죽인다. 부활 뒤 이벤트도 같은 run_id여야 한다.
	if g.game_over and not g.revive_used:
		g._revive()
		await process_frame
		_play_until_end(15)
		if not (g.game_over or g.game_clear):
			_force_core_death()

	# ── 무한 1런: 다른 기둥(mode=endless) 좌표 + endless_run_ended + 부활 거절
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
	# 튜토리얼 퍼널 — 박자1·2는 봇이 실제로 통과한다(박자3=첫 누수는 판 흐름에 달려 있어 참고만).
	var beats: Dictionary = {}
	for e in evs:
		var de: Dictionary = e as Dictionary
		if String(de.get("event", "")) == "tutorial_beat_completed":
			beats[int(de.get("beat", 0))] = true
	_check("tutorial_beat_completed 박자1", beats.has(1))
	_check("tutorial_beat_completed 박자2", beats.has(2))
	print("   박자3(첫 누수 캡션) 발화: %s" % ("예" if beats.has(3) else "이번 판엔 누수 없음 — 참고"))

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
