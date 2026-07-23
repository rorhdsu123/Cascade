extends SceneTree
# 진행 pip 검증 — 클리어 팝업 3케이스(첫판·중간·프런티어). 창 모드 필수.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/5e850407-1b82-4a53-a146-054a00f1d333/scratchpad/pip"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# 첫판 클리어 = 1/8
	main.call("_start_stage", 0)
	await process_frame
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"])); main.set("leaked", 0)
	main.set("game_over", false); main.set("game_clear", true)
	main.set("cleared", {0: true})
	await _grab("first")

	# 중간 클리어 = 4/8 (stage_idx=3)
	main.call("_start_stage", 3)
	await process_frame
	main.set("cleared", {0: true, 1: true, 2: true, 3: true})
	main.set("killed", 25); main.set("leaked", 2)
	main.set("game_over", false); main.set("game_clear", true)
	await _grab("mid")

	# 프런티어 = 8/8 (마지막 스테이지)
	main.call("_start_stage", 7)
	await process_frame
	for i in range(8): main.get("cleared")[i] = true
	main.set("killed", 40); main.set("leaked", 0)
	main.set("game_over", false); main.set("game_clear", true)
	await _grab("frontier")

	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
