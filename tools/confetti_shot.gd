extends SceneTree
# 클리어 축하 색종이 캡처 — 여러 프레임(스폰 직후 / 떨어지는 중)으로 움직임 확인. 창 모드 필수.
# 실행: godot --path . --script tools/confetti_shot.gd

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/6beeb68b-ad06-4de4-8f3b-94cbf9731a2e/scratchpad/confetti"

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
	# 클리어 상태 + 색종이 스폰
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"]))
	main.set("game_clear", true)
	main.call("_spawn_confetti")

	# t≈0.3s: 위에서 막 쏟아지는 중
	for _i in range(6):
		main.call("_process", 0.05)
	await _grab("early")

	# t≈1.2s: 화면 중앙까지 내려와 팝업 위로 흩날림
	for _i in range(18):
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
