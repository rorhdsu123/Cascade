extends SceneTree
# 영어 로케일 UI 창 검증(i18n + 번들 폰트). [[godot-pixel-verify-needs-window]] 창 필수.
#   godot --path . --script tools/i18n_shot.gd
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/536fcd8a-d763-40a9-b405-1ce3c94b544e/scratchpad/"

func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _shot(name: String) -> void:
	if _headless():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _click(g: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)
	await process_frame

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	# 로케일 강제 en(테스트 기기 무관) + 폰트 확인
	g.set("_locale", "en")
	var f = g.get("_font")
	print("LOCALE=%s  FONT_CLASS=%s  FONT_PATH=%s" % [
		g.get("_locale"), f.get_class(),
		f.resource_path if f != null else "nil"])
	g.set("endless_best", 12345)
	g.call("queue_redraw")
	await _shot("i18n_menu.png")

	# Adventure → select (스테이지 이름/태그 영어 확인)
	g.set("dev_unlock_all", true)   # 전 스테이지 열어 이름·태그 다 보이게
	var adv: Rect2 = g.get("MENU_ADV_BTN")
	await _click(g, adv.position + adv.size * 0.5)
	g.call("queue_redraw")
	await _shot("i18n_select.png")
	print("mode after adv=%s" % g.get("mode"))

	# PLAY → 게임 진입, HUD 렌더
	var play: Rect2 = g.get("PLAY_BTN")
	await _click(g, play.position + play.size * 0.5)
	await process_frame
	await process_frame
	print("mode after play=%s" % g.get("mode"))
	g.call("queue_redraw")
	await _shot("i18n_hud.png")

	# 결과(클리어) 팝업 강제 — 영어 헤드라인/버튼 확인
	g.set("game_clear", true)
	g.set("mode", "result")
	g.set("killed", 20)
	g.set("leaked", 0)
	g.call("queue_redraw")
	await _shot("i18n_result_clear.png")

	# 설정 모달
	g.set("mode", "game")
	g.set("game_clear", false)
	g.set("settings_open", true)
	g.call("queue_redraw")
	await _shot("i18n_settings.png")

	# 한국어 폴백 검증(SystemFont로 한글 렌더되는지) — 메뉴만
	g.set("settings_open", false)
	g.set("mode", "menu")
	g.set("_locale", "ko")
	g.call("queue_redraw")
	await _shot("i18n_menu_ko.png")

	quit()
