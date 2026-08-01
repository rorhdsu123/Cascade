extends SceneTree
# 도둑 가독성 검증 — 창 모드 필수. 4상태를 한 판에 늘어놓고 원본/확대로 본다.
#   ① 하강 중(안 훔침) ② 훔친 직후(carrying, 바닥) ③ 도망 중(carrying, 중단) ④ 탈출 직전(상단)
#   비교군으로 basic 하나(같은 보라 원)를 옆에 둔다 — 형태가 실제로 갈리는지.
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/e428d88b-4bd5-4bfe-9f14-2a04806df7eb/scratchpad"
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 13)
	main.intro_t = -1.0
	await process_frame
	main.enemies.clear()
	_add(4001, 1, 1, false)   # 하강 중
	_add(4002, 3, 7, true)    # 훔친 직후(바닥)
	_add(4003, 5, 4, true)    # 도망 중(중단)
	_add(4004, 7, 0, true)    # 탈출 직전
	main.enemies.append({     # 비교군 basic
		"col": 0, "row": 4, "vis_row": 4.0, "hp": 100, "maxhp": 100,
		"etype": "basic", "id": 4005, "step_every": 2, "remain": 2,
	})
	main.vault = 2
	main.call("queue_redraw")
	for i in range(10):
		main._process(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/thief_states.png")
	print("saved: thief_states.png (vault=%d, n=%d)" % [main.vault, main.enemies.size()])
	quit()

func _add(id: int, col: int, row: int, carrying: bool) -> void:
	main.enemies.append({
		"col": col, "row": row, "vis_row": float(row), "hp": 150, "maxhp": 150,
		"etype": "thief", "id": id, "step_every": 1, "remain": 1, "carrying": carrying,
	})
