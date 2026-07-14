extends SceneTree
# '거점 파괴' 죽음 연출 검증 — 실제 트리거(_end_turn → 누수 → core_hp 0)를 태워 프레임 캡처.
# 실행: godot --path . --script tools/core_probe.gd   (창 모드 필수)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/7403dd74-472a-4952-afac-6f6948b37825/scratchpad/core"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame

	# 보드에 블록을 흩뿌린다 (무너지는 게 보이게)
	var cols: Array = ["R", "B", "Y"]
	var board: Array = main.get("board")
	for r in range(8):
		for c in range(8):
			board[r][c] = cols[(r * 5 + c * 3) % 3] if (r + c) % 4 != 0 else ""
	main.set("board", board)

	# 거점 HP를 1로 낮추고, 맨 아랫줄 적이 다음 스텝에 거점에 닿게 세운다.
	main.set("core_hp", 1)
	var enemies: Array = main.get("enemies")
	enemies.clear()
	# row 7 + step_every 1 → advance_step에서 row 8 = 누수 → core_hp 0
	enemies.append({"id": 901, "col": 3, "row": 7, "vis_row": 7.0,
			"hp": 30, "maxhp": 30, "etype": "basic", "step_every": 1, "flinch": 0.0})
	# 살아남아 서 있을 적들 (내 방어선만 무너지고 적은 남는다)
	for spec in [[2, 1], [4, 6]]:
		enemies.append({"id": 910 + int(spec[0]), "col": int(spec[1]), "row": int(spec[0]),
				"vis_row": float(spec[0]), "hp": 30, "maxhp": 30, "etype": "basic",
				"step_every": 9999, "flinch": 0.0})
	main.set("enemies", enemies)
	main.set("place_count", 0)   # advance_step에서 place_count 1 → 1 % 1 == 0 → 전진

	await _grab("00_before")

	main.call("_end_turn")
	print(">>> game_over=", main.get("game_over"), " stuck=", main.get("stuck"),
			" core_hp=", main.get("core_hp"), " core_t=", main.get("core_t"),
			" hitstop=", main.get("hitstop"))

	for i in range(12):
		await _grab("%02d_t%03dms" % [i + 1, int(float(main.get("core_t")) * 1000.0)])
		await _settle(5)

	await _settle(40)
	await _grab("30_settled")
	await _settle(60)
	await _grab("31_popup")
	print(">>> death_playing=", main.call("_death_playing"), " core_t=", main.get("core_t"))
	print("DONE")
	quit()

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame

func _grab(tag: String) -> void:
	main.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag, "  core_t=%.3f" % float(main.get("core_t")),
			" hitstop=%.3f" % float(main.get("hitstop")))
