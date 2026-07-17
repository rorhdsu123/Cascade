extends SceneTree
# 골드 충격파(_fire_climax = 전멸 연출) 미리보기 캡처. 창 모드 필수.
# 실행: godot --path . --script tools/climax_shot.gd

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/6beeb68b-ad06-4de4-8f3b-94cbf9731a2e/scratchpad/climax"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame
	main.set_process(false)
	# 배경에 적 몇 마리 + 보드에 블록 조금(맥락)
	main.set("enemies", [
		{"col": 1, "row": 2, "vis_row": 2.0, "hp": 10, "maxhp": 10, "etype": "basic", "id": 1, "step_every": 3},
		{"col": 6, "row": 3, "vis_row": 3.0, "hp": 10, "maxhp": 10, "etype": "basic", "id": 2, "step_every": 3},
	])
	main.call("_fire_climax")
	# 충격파가 확장한 시점(≈0.2s 경과)을 잡는다
	for _i in range(4):
		main.call("_process", 0.05)
	await _grab("mid")

	print("DONE")
	quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
