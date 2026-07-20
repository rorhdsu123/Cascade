extends SceneTree
# 설정 모달 창 스모크 + 픽셀검증. [[godot-pixel-verify-needs-window]] 창 필수.
#   godot --path . --script tools/settings_shot.gd
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/9ee687d1-95f7-48f3-9f2a-471d8d181a0b/scratchpad/"

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

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame

	# 스테이지 진입(중간 스테이지 = 콤보 표시가 뜰 여지도 확인)
	g.call("_start_stage", 2)
	await process_frame
	print("PLAY: mode=%s settings_open=%s sound=%s bgm=%s" % [
		g.get("mode"), str(g.get("settings_open")), str(g.get("sound_on")), str(g.get("bgm_on"))])
	g.call("queue_redraw")
	await _shot("set_1_play_gear.png")   # 우상단 기어가 보이는가

	# 기어 클릭 → 모달 열림
	var gear: Rect2 = g.get("SETTINGS_GEAR")
	_click(g, gear.position + gear.size * 0.5)
	await process_frame
	print("AFTER GEAR: settings_open=%s" % str(g.get("settings_open")))
	g.call("queue_redraw")
	await _shot("set_2_modal.png")       # 모달(소리 ON·배경음 OFF)

	# 레이아웃 좌표 획득
	var lay: Dictionary = g.call("_settings_layout")

	# 소리 토글 클릭 → true→false
	_click(g, (lay["sound_tog"] as Rect2).get_center())
	await process_frame
	# 배경음 토글 클릭 → false→true
	_click(g, (lay["bgm_tog"] as Rect2).get_center())
	await process_frame
	print("AFTER TOGGLES: sound=%s bgm=%s" % [str(g.get("sound_on")), str(g.get("bgm_on"))])
	g.call("queue_redraw")
	await _shot("set_3_toggled.png")     # 소리 OFF·배경음 ON 으로 뒤집힘

	# 닫기(X) → 모달 닫힘
	_click(g, (lay["close"] as Rect2).get_center())
	await process_frame
	print("AFTER CLOSE: settings_open=%s" % str(g.get("settings_open")))

	# 다시 열어 '재시작' 버튼 → 같은 스테이지 재시작(mode 유지 play, killed 리셋)
	_click(g, gear.position + gear.size * 0.5)
	await process_frame
	g.set("killed", 7)   # 재시작이 판을 초기화하는지 표시
	_click(g, (lay["replay_btn"] as Rect2).get_center())
	await process_frame
	print("AFTER REPLAY: mode=%s settings_open=%s killed=%s" % [
		g.get("mode"), str(g.get("settings_open")), str(g.get("killed"))])

	# 다시 열어 '메뉴로' → mode=select(스테이지 홈)
	_click(g, gear.position + gear.size * 0.5)
	await process_frame
	_click(g, (lay["home_btn"] as Rect2).get_center())
	await process_frame
	print("AFTER HOME: mode=%s settings_open=%s" % [g.get("mode"), str(g.get("settings_open"))])

	quit()
