extends SceneTree
# 안드로이드 뒤로가기 사다리 검증 — NOTIFICATION_WM_GO_BACK_REQUEST을 화면별로 쏘고 상태 전이를 확인한다.
#   godot --path . --script tools/back_probe.gd
var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _back() -> void:
	g.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame

func _check(tag: String, got: String, want: String) -> void:
	var ok: bool = got == want
	if not ok:
		fails += 1
	print("%s %s: %s (기대 %s)" % ["OK  " if ok else "FAIL", tag, got, want])

func _state() -> String:
	return "settings" if bool(g.get("settings_open")) else String(g.get("mode"))

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	# 플레이 중 뒤로 = 일시정지(설정) — 앱 종료도, 판 이탈도 아니다
	g.call("_start_stage", 0)
	await process_frame
	await _back()
	_check("플레이 중", _state(), "settings")

	# 설정 열린 상태에서 뒤로 = 모달만 닫힘(판 유지)
	await _back()
	_check("설정 모달", _state(), "play")

	# 결과 팝업에서 뒤로 = 홈
	g.set("game_over", true)
	await _back()
	_check("결과 팝업", _state(), "menu")

	# 스테이지 선택 → 허브
	g.set("game_over", false)
	g.set("mode", "select")
	await _back()
	_check("스테이지 선택", _state(), "menu")

	# 리더보드 → 허브
	g.set("mode", "leaderboard")
	await _back()
	_check("리더보드", _state(), "menu")

	# 허브에서 뒤로 = 앱 종료(quit이 예약되면 다음 프레임에 루프가 끝난다)
	print("허브에서 뒤로 → 종료 예약(아래에 DONE이 안 찍히면 정상 종료)")
	print("RESULT: %s (실패 %d)" % ["PASS" if fails == 0 else "FAIL", fails])
	await _back()
	print("DONE(종료 안 됨 = FAIL)")
	quit()
