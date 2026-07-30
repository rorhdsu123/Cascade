extends SceneTree
# UI/UX 감사용 전체 화면 캡처. 창 모드 필수([[godot-pixel-verify-needs-window]]).
#   godot --path . --script tools/ux_audit_shot.gd
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/f6002e9b-75fa-490d-83f5-3867bf2d9dec/scratchpad/shots/"

var g: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _shot(name: String) -> void:
	if _headless():
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)
	await process_frame

func _resize(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	await process_frame
	await process_frame

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	# ⚠실유저 진행도 보호(C100 확장): 이 probe는 Main.tscn을 띄우므로 _ready가 돌아
	#   persist_enabled=true가 된다. 아래서 cleared를 주입하거나 봇이 스테이지를 깨면 그 값이
	#   **실제 campaign.save에 각인**된다(전 스테이지 주입 = 16383 = "진행도가 저절로 전승됨"의 진범).
	#   C100은 campaign_flow.gd만 막았고 나머지 창 모드 probe는 새고 있었다 → 여기서 끈다.
	g.set("persist_enabled", false)
	await process_frame
	await process_frame
	await _resize(800, 1280)
	g.set("_locale", "en")

	# ── ① 첫 진입(신규 설치 상태): 진행도 0, 베스트 0 ──
	g.set("cleared", {})
	g.set("endless_best", 0)
	g.set("mode", "menu")
	await _shot("01_menu_first.png")

	# ── ② 복귀 유저 허브: 베스트 있음 + 3스테이지 클리어 ──
	g.set("endless_best", 12480)
	g.set("cleared", {0: true, 1: true, 2: true})
	await _shot("02_menu_return.png")

	# ── ③ 스테이지 선택(진행 중) ──
	var udy: Vector2 = Vector2(0.0, g.call("_ui_dy"))
	await _click((g.get("MENU_ADV_BTN") as Rect2).get_center() + udy)
	await _shot("03_select.png")

	# ── ④ 리더보드 ──
	g.set("mode", "leaderboard")
	await _shot("04_leaderboard.png")

	# ── ⑤ 첫 플레이 = 스테이지1 튜토리얼 박자1 ──
	g.set("cleared", {})
	g.call("_start_stage", 0)
	await process_frame
	await _shot("05_play_stage1_tut.png")

	# ── ⑥ 설정 모달(플레이 중) ──
	g.set("settings_open", true)
	await _shot("06_settings.png")
	g.set("settings_open", false)

	# ── ⑦ 스테이지 진행 중(튜토리얼 지난 상태 흉내: 배치 여러 번) ──
	g.set("cleared", {0: true, 1: true, 2: true})
	g.call("_start_stage", 3)
	await process_frame
	for i in range(6):
		g.call("advance_step")
	g.set("place_count", 12)
	g.set("killed", 3)
	g.set("combo", 2)
	await _shot("07_play_mid.png")

	# ── ⑧ 결과: 스테이지 클리어 ──
	g.set("game_clear", true)
	g.set("game_over", false)
	g.set("killed", 12)
	g.set("leaked", 0)
	await _shot("08_result_clear.png")

	# ── ⑨ 결과: 실패(거점 파괴) ──
	g.set("game_clear", false)
	g.set("game_over", true)
	g.set("stuck", false)
	g.set("killed", 5)
	g.set("leaked", 4)
	await _shot("09_result_fail.png")

	# ── ⑩ 무한 플레이 ──
	g.call("_start_endless")
	await process_frame
	for i in range(10):
		g.call("advance_step")
	g.set("endless_score", 8420)
	g.set("place_count", 26)
	await _shot("10_endless_play.png")

	# ── ⑪ 무한 결과 ──
	g.set("game_over", true)
	g.set("stuck", true)
	await _shot("11_endless_result.png")

	# ── ⑫ 긴 폰(9:19.5)에서 허브·플레이 ──
	g.set("game_over", false)
	g.set("mode", "menu")
	await _resize(800, 1733)
	await _shot("12_menu_tall.png")
	g.call("_start_stage", 0)
	await process_frame
	await _shot("13_play_tall.png")

	# ── ⑭ 짧은 창(태블릿 4:3) ──
	await _resize(800, 1067)
	await _shot("14_play_tablet.png")

	print("DONE")
	quit()
