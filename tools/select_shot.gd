extends SceneTree
# 스테이지 리스트(select) 화면 폴리싱 확인.
#   godot --path . --script tools/select_shot.gd
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/39d505ff-097b-4e95-a2e1-39e027fe26ac/scratchpad/shots/"
var g: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")
	g.set("dev_unlock_all", false)
	g.set("mode", "select")

	# 실사용 맥락: 전부 깬 진열장(select는 _all_cleared일 때만 뜬다)
	var all_c: Dictionary = {}
	for i in range(8):
		all_c[i] = true
	g.set("cleared", all_c)

	# 진입 기본: 1번 선택
	g.set("sel_stage", 0)
	g.set("hover_stage", -1)
	await _shot("s1_select_default.png")

	# 4번(index 3) 선택 + 6번 호버
	g.set("sel_stage", 3)
	g.set("hover_stage", 5)
	await _shot("s2_select_pick.png")

	print("DONE")
	quit()
