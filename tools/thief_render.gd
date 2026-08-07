extends SceneTree
# 도둑 가독성 검증 — 창 모드 필수. 4상태를 한 판에 늘어놓고 원본/확대로 본다.
#   ① 하강 중(안 훔침) ② 훔친 직후(carrying, 바닥) ③ 도망 중(carrying, 중단) ④ 탈출 직전(상단)
#   비교군으로 basic 하나(같은 보라 원)를 옆에 둔다 — 형태가 실제로 갈리는지.
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/c4f0ea00-30c5-4dfc-9c13-65e4483f2cae/scratchpad"
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# ⚠**하드코딩 인덱스 금지.** 예전엔 _start_stage(13)이었는데 배열 재배치(S21·S22) 뒤로는
	#   엉뚱한 판(보석3)을 띄우면서 **금고 카드가 없는 화면**을 도둑 검증용이라고 내놓고 있었다.
	#   도둑 판은 파킹돼 있어 _start_stage 경로가 아예 없다 → thief_probe와 같은 방식으로 직접 세운다.
	var SD: GDScript = load("res://stage_data.gd")
	var d: Dictionary = SD.PARKED_PROTECT.duplicate(true)
	main.endless = false
	main.featured = false
	main.stage_idx = -1
	main.st = d
	main.director = load("res://modes/stage_mode.gd").new(d)
	main.mode = "play"
	main.call("_init_game")
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

	# ── 훔치는 순간(S25): 거점 띠 → 자루로 다이아가 날아가는 프레임을 잡는다. ──
	#   ⚠carrying을 손으로 세팅하면 _grab을 안 탄다 = 연출이 아예 안 생긴다. 실제 경로로 태워야 한다:
	#     도둑을 row=ROWS(거점 아래)에 세우고 advance_step()을 부르면 grab 분기가 돈다.
	main.enemies.clear()
	main.vault = 4
	main.enemies.append({
		"col": 3, "row": main.ROWS, "vis_row": float(main.ROWS), "hp": 150, "maxhp": 150,
		"etype": "thief", "id": 4100, "step_every": 1, "remain": 1, "carrying": false,
	})
	main.call("advance_step")
	print("grab: vault=%d · steal_flights=%d" % [main.vault, main.steal_flights.size()])
	# 비행을 세 프레임(초·중·말)으로 잡는다 — 궤적이 읽히는지는 한 장으로 판정할 수 없다.
	for shot in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(SP + "/thief_steal%d.png" % shot)
		var ft: float = float(main.steal_flights[0]["t"]) if main.steal_flights.size() > 0 else -1.0
		print("saved: thief_steal%d.png (t=%.3f)" % [shot, ft])
		for i in range(2):
			main._process(0.04)
			await process_frame
	quit()

func _add(id: int, col: int, row: int, carrying: bool) -> void:
	main.enemies.append({
		"col": col, "row": row, "vis_row": float(row), "hp": 150, "maxhp": 150,
		"etype": "thief", "id": id, "step_every": 1, "remain": 1, "carrying": carrying,
	})
