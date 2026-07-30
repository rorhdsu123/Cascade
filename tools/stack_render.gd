extends SceneTree
# 한 칸 겹침(2~3마리) 렌더 검증 — 창 모드 필수([[godot-pixel-verify-needs-window]]).
#   before/after 비교용: 같은 칸에 2마리(같은 타입/다른 타입) + 3마리 + 겹침 아닌 단독 대조군.
# 실행: godot --path . --script tools/stack_render.gd
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/e428d88b-4bd5-4bfe-9f14-2a04806df7eb/scratchpad"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 5)
	main.intro_t = -1.0   # 인트로 카드 끄기(보드를 가린다)
	await process_frame

	var seq: int = 2000
	var demo: Array = [
		{"col": 1, "row": 0, "etype": "basic"},                    # 대조군: 단독
		{"col": 3, "row": 0, "etype": "basic", "remain": 1},        # 겹침 2 (같은 타입 — 스크린샷 재현)
		{"col": 3, "row": 0, "etype": "basic", "remain": 3},
		{"col": 5, "row": 0, "etype": "fast"},                      # 겹침 2 (다른 타입)
		{"col": 5, "row": 0, "etype": "basic"},
		{"col": 1, "row": 3, "etype": "basic"},                     # 겹침 3
		{"col": 1, "row": 3, "etype": "swarm"},
		{"col": 1, "row": 3, "etype": "fast"},
		{"col": 4, "row": 3, "etype": "tank", "hurt": true},        # 겹침 2 + HP바 노출
		{"col": 4, "row": 3, "etype": "basic", "hurt": true},
		{"col": 6, "row": 5, "etype": "bomb"},                      # 겹침 2 (폭탄 숫자 가독)
		{"col": 6, "row": 5, "etype": "basic"},
	]
	main.enemies.clear()
	for d in demo:
		var mhp: int = 100
		var hp: int = 45 if d.get("hurt", false) else 100
		var ed: Dictionary = {
			"col": d["col"], "row": d["row"], "vis_row": float(d["row"]),
			"hp": hp, "maxhp": mhp, "etype": d["etype"], "id": seq,
			"step_every": 3, "remain": int(d.get("remain", 3)),
		}
		if d["etype"] == "bomb":
			ed["fuse"] = 3
		main.enemies.append(ed)
		seq += 1

	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/stack_render.png")
	print("saved: stack_render.png (%d enemies)" % main.enemies.size())
	quit()
