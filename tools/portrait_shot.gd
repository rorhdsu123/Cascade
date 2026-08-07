extends SceneTree
# 반응형 세로 프레임 창 검증. [[godot-pixel-verify-needs-window]] 창 필수(헤드리스 X).
#   godot --path . --script tools/portrait_shot.gd
# 폭 800 고정 · 창 높이를 폰 비율로 바꿔 viewport가 expand 되는지, 레이아웃이 파생되는지 확인.
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/f16231b9-9641-40ea-80b9-aca7ddb43813/scratchpad/"

func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _resize(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	await process_frame
	await process_frame

func _shot(g: Node, name: String) -> void:
	if _headless():
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _click(g: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)
	# 버튼은 **뗄 때** 발동한다(C144) — 누름만 보내면 걸리기만 하고 아무 일도 안 일어난다.
	ev.pressed = false
	g.call("_input", ev)
	await process_frame

func _dump(g: Node, tag: String) -> void:
	print("[%s] vh=%s board_y=%s bot_y=%s mode_btn.y=%s vp=%s" % [
		tag, g.get("vh"), g.get("board_y"), g.get("bot_y"),
		(g.get("mode_btn") as Rect2).position.y,
		str(g.get_viewport().get_visible_rect().size)])

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame

	# --- 데스크톱 기준(800x1000): 원본과 픽셀-동일해야 ---
	await _resize(800, 1000)
	_dump(g, "desktop 800x1000")
	await _shot(g, "p_menu_1000.png")

	# --- 9:19.5 폰(800x1733): viewport 세로 확장 ---
	await _resize(800, 1733)
	_dump(g, "phone 9:19.5")
	await _shot(g, "p_menu_phone.png")

	# 메뉴 → Adventure → 스테이지0 → PLAY 로 실제 플레이 진입.
	# 메뉴·선택은 _ui_dy만큼 내려 그리므로, 실제 탭 좌표 = 논리 중심 + dy.
	var udy: Vector2 = Vector2(0.0, g.call("_ui_dy"))
	_click(g, (g.get("MENU_ADV_BTN") as Rect2).get_center() + udy)
	await process_frame
	print("after ADV: mode=%s" % g.get("mode"))
	await _shot(g, "p_select_phone.png")
	_click(g, g.call("_stage_rect", 0).get_center() + udy)
	await process_frame
	_click(g, (g.get("PLAY_BTN") as Rect2).get_center() + udy)
	await process_frame
	await process_frame
	print("after PLAY: mode=%s" % g.get("mode"))
	_dump(g, "play phone")
	await _shot(g, "p_play_phone.png")

	# 같은 플레이 화면을 데스크톱 크기로 — 원본 대비 확인
	await _resize(800, 1000)
	_dump(g, "play desktop")
	await _shot(g, "p_play_1000.png")

	# 4:3 태블릿(800x1067)
	await _resize(800, 1067)
	_dump(g, "tablet 4:3")
	await _shot(g, "p_play_tablet.png")

	quit()
