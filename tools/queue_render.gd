extends SceneTree
# 겹침 금지(줄서기) 시각 검증 — 창 모드 필수([[godot-pixel-verify-needs-window]]).
#   실제 advance_step을 태워 end-to-end로 본다:
#   ① hold : 앞이 막힌 적은 제자리 — 꿈틀(lean)도 붉은 착지칸도 없다(안 움직이니 예고할 게 없다)
#   ② still: 한 박자 더 지나도 그대로 = 가로로 새지 않는다(C102서 대각 slip 폐기)
#   ③ free : 선두가 빠지는 순간 따라 내려간다(줄이 풀린다)
# 배치: 선두 basic(3,7)은 step 4, 뒤의 fast(3,6)은 step 2. pc=6에 뒤엣놈만 주기가 돌아오지만 막혀 대기.
#   pc=8에 선두가 거점으로 빠지면(누수) 그 칸이 비어 뒤엣놈이 내려간다.
# 실행: godot --path . --script tools/queue_render.gd
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
	main.place_count = 5   # 다음 박자 pc=6: step4는 대기(6%4≠0) · step2는 이동 시도(6%2==0)
	await process_frame

	main.enemies.clear()
	_add(3001, 3, 7, "basic", 4)   # 선두
	_add(3002, 3, 6, "fast", 2)    # 뒤 — 앞이 막혀 대기해야 한다
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/queue_before.png")
	print("before: fast at (%d,%d)" % [main.enemies[1]["col"], main.enemies[1]["row"]])

	await _beat("queue_hold")    # pc=6 — 대기
	await _beat("queue_still")   # pc=7 — 그대로(주기도 안 맞음)
	await _beat("queue_free")    # pc=8 — 선두 누수 → 뒤엣놈 전진
	print("saved: queue_before / hold / still / free")
	quit()

func _beat(name: String) -> void:
	main.call("advance_step")
	main.call("queue_redraw")
	for i in range(30):
		main._process(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/%s.png" % name)
	var fast: Dictionary = {}
	for e in main.enemies:
		if int(e["id"]) == 3002:
			fast = e
	print("%s: pc=%d  fast=(%s,%s) blocked=%s  dbg_block=%d  (스폰 포함 n=%d)" % [
		name, main.place_count,
		str(fast.get("col", -1)), str(fast.get("row", -1)),
		str(fast.get("blocked", false)), main.dbg_block, main.enemies.size()])

func _add(id: int, col: int, row: int, etype: String, step: int) -> void:
	main.enemies.append({
		"col": col, "row": row, "vis_row": float(row),
		"hp": 100, "maxhp": 100, "etype": etype, "id": id, "step_every": step,
		"remain": 1,
	})
