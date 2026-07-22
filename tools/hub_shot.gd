extends SceneTree
# 허브 개편(C80) 렌더 확인 — 신규/진행중/전부깸 + 허브 설정 모달.
#   godot --path . --script tools/hub_shot.gd
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/f6002e9b-75fa-490d-83f5-3867bf2d9dec/scratchpad/shots/"
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

	g.set("mode", "menu"); g.set("cleared", {}); g.set("endless_best", 0)
	await _shot("h1_hub_new.png")

	g.set("cleared", {0: true, 1: true, 2: true}); g.set("endless_best", 12480)
	await _shot("h2_hub_progress.png")

	var all_c: Dictionary = {}
	for i in range(8):
		all_c[i] = true
	g.set("cleared", all_c)
	await _shot("h3_hub_allclear.png")

	g.set("cleared", {}); g.set("endless_best", 0)
	g.set("settings_open", true)
	await _shot("h4_hub_settings.png")
	g.set("settings_open", false)

	g.set("mode", "leaderboard")
	await _shot("h5_lb_locked.png")
	print("DONE")
	quit()
