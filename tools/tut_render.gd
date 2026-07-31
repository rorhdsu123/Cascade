extends SceneTree
# 튜토리얼 안내 문구 가독성 검증 — 창 모드 필수.
#   ① 박자2 지시(tut_msg, 노랑) ② 박자3 사건 캡션(tut_flash, 붉은색)
#   목표 카드(goal_r)·보드와의 겹침을 눈으로 본다.
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/a093b9bf-43de-4d56-83e5-68f30d54bbee/scratchpad"
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var wh: String = OS.get_environment("WIN_H")
	if wh != "":
		DisplayServer.window_set_size(Vector2i(800, int(wh)))
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.dev_unlock_all = true
	main.call("_start_stage", 0)
	main.intro_t = -1.0
	await process_frame
	# 박자2 상태로 몰아넣기: 지시 문구 + 적 몇 마리 + 유도 트레이
	main.tut_phase = 2
	main.tut_lock = false
	main.tut_cells = []
	main.tut_msg = main.call("_t", "tut_kill")
	main.enemies.append({
		"col": 2, "row": 2, "vis_row": 2.0, "hp": 100, "maxhp": 100,
		"etype": "basic", "id": 9001, "step_every": 2, "remain": 2,
	})
	main.call("queue_redraw")
	for i in range(6):
		main._process(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/tut_msg.png")
	# 사건 캡션
	main.tut_flash_msg = main.call("_t", "tut_leak")
	main.tut_flash_t = 2.0
	main.call("queue_redraw")
	for i in range(3):
		main._process(0.01)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/tut_flash.png")
	print("saved: tut_msg.png, tut_flash.png  board_y=%d" % main.board_y)
	quit()
