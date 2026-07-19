extends SceneTree
# 분열선 접근에 따라 세로 금이 벌어지는 tell 검증 (창 모드 필수).
#   같은 gen0 분열체를 row 0→5(=SPLIT_ROW)에 세워, 위→아래로 금이 얇음→활짝 벌어지는지.
#   맨 오른쪽 열엔 split_done(분열 후 흉터) 하나 — '더는 안 쪼개짐' 대조.
# 실행: /opt/homebrew/bin/godot --path . --script tools/split_crack_probe.gd
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/8cf0c757-9720-457d-90a4-0cf315279360/scratchpad"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 6)   # 분열 도입 스테이지
	await process_frame

	var seq: int = 2000
	main.enemies.clear()
	# 같은 분열체를 여러 행에: 아래로 갈수록 금이 벌어져야 한다(ct = row/SPLIT_ROW).
	for r in [0, 1, 2, 3, 4, 5]:
		main.enemies.append({
			"col": 1, "row": r, "vis_row": float(r), "hp": 100, "maxhp": 100,
			"etype": "split", "id": seq, "step_every": 3, "gen": 0,
		})
		seq += 1
	# 분열 후 흉터(split_done) — 대조군
	main.enemies.append({
		"col": 5, "row": 2, "vis_row": 2.0, "hp": 100, "maxhp": 100,
		"etype": "split", "id": seq, "step_every": 3, "gen": 0, "split_done": true,
	})
	seq += 1
	# 실제 쌍둥이(gen1) 대조
	main.enemies.append({
		"col": 6, "row": 2, "vis_row": 2.0, "hp": 100, "maxhp": 100,
		"etype": "split", "id": seq, "step_every": 3, "gen": 1, "split_done": true,
	})

	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/split_crack.png")
	print("saved: split_crack.png (%d enemies)" % main.enemies.size())
	quit()
