extends SceneTree
# 겹침 금지 규칙의 시각 검증 — 창 모드 필수([[godot-pixel-verify-needs-window]]).
#   실제 advance_step을 태워 end-to-end로 본다(vis_col을 손으로 세팅하지 않는다):
#   ① before: 붉은 착지칸이 '돌아갈 칸'에 대각으로 뜬다 = slip이 미리 예고된다
#   ② mid: vis_col 이징으로 대각으로 스르륵 (순간이동 아님)
#   ③ after: 한 칸에 하나 — 선두 옆으로 비껴 내려앉았다
# 배치: 선두 basic(3,7)은 step 4라 이번 박자에 안 움직이고, 뒤의 fast(3,6)는 step 2라 움직인다.
#   오른쪽 레인((4,7))에 한 마리를 둬서 '덜 붐비는 쪽'인 왼쪽(2,7)으로 돌아가는지도 본다.
#   ⚠붉은 착지칸은 깊이 램프(row4=0 → row7=1)라 바닥 근처여야 보인다 → 일부러 아래에 깐다.
# 실행: godot --path . --script tools/slip_render.gd
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/e428d88b-4bd5-4bfe-9f14-2a04806df7eb/scratchpad"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 5)
	main.intro_t = -1.0
	main.place_count = 5   # 다음 박자 pc=6: step4는 대기(6%4≠0) · step2는 이동(6%2==0)
	await process_frame

	main.enemies.clear()
	_add(3001, 3, 7, "basic", 4)   # 선두(대기)
	_add(3002, 3, 6, "fast", 2)    # 뒤(이동) → 아래가 막혔으니 옆으로 돌아간다
	_add(3003, 4, 7, "basic", 4)   # 오른쪽 레인 혼잡도 +1 → 왼쪽으로 돌아야 한다
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/slip_before.png")
	print("before: fast at (%d,%d)" % [main.enemies[1]["col"], main.enemies[1]["row"]])

	main.call("advance_step")
	print("after : fast at (%d,%d)  slip=%d block=%d" % [
		main.enemies[1]["col"], main.enemies[1]["row"], main.dbg_slip, main.dbg_block])
	main.call("queue_redraw")
	for i in range(2):   # 이징 중간 프레임(대각 이동)
		main._process(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/slip_mid.png")

	for i in range(30):
		main._process(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/slip_done.png")
	print("saved: slip_before / slip_mid / slip_done")
	quit()

func _add(id: int, col: int, row: int, etype: String, step: int) -> void:
	main.enemies.append({
		"col": col, "row": row, "vis_row": float(row), "vis_col": float(col),
		"hp": 100, "maxhp": 100, "etype": etype, "id": id, "step_every": step,
		"remain": 1,
	})
