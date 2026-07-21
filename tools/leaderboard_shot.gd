extends SceneTree
# 리더보드 화면 창 스모크 + 픽셀검증. [[godot-pixel-verify-needs-window]] 창 필수.
#   /Applications/Godot.app/Contents/MacOS/Godot --path . --script tools/leaderboard_shot.gd
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-endless/944e7ae5-23be-4d33-94fd-37e210ec3cec/scratchpad/"

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

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame

	# 서비스 내부값 직접 세팅(파일 안 건드림) — 채워진 화면 검증
	var lb = g.get("_leaderboard")
	lb.set("_best", 128400)
	lb.set("_clean_best", 42100)
	print("board=%s" % str(lb.call("board")))
	print("rank=%s pct=%d" % [str(lb.call("friend_rank")), lb.call("percentile")])

	# 메뉴(트로피 버튼 보이게)
	g.set("mode", "menu")
	g.call("queue_redraw")
	await _shot("lb_menu.png")

	# 트로피 클릭 → 리더보드 진입
	var lbb: Rect2 = g.get("MENU_LB_BTN")
	_click(g, lbb.get_center())
	await process_frame
	print("AFTER TROPHY CLICK: mode=%s" % g.get("mode"))
	g.call("queue_redraw")
	await _shot("lb_full.png")

	# 빈 상태(기록 0)
	lb.set("_best", 0)
	lb.set("_clean_best", 0)
	g.call("queue_redraw")
	await _shot("lb_empty.png")

	# CTA(무한 도전) → 무한 시작?
	lb.set("_best", 128400)
	var cta: Rect2 = g.get("LB_PLAY_BTN")
	_click(g, cta.get_center())
	await process_frame
	print("AFTER CTA CLICK: mode=%s endless=%s" % [g.get("mode"), str(g.get("endless"))])
	quit()

func _click(g: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)
