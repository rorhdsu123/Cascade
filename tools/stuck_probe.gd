extends SceneTree
# '놓을 곳 없음' 죽음 연출 검증 — 실제 트리거(_end_turn)를 태워서 채움 물결을 프레임 캡처한다.
# 실행: godot --path . --script tools/stuck_probe.gd   (창 모드 필수)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/7403dd74-472a-4952-afac-6f6948b37825/scratchpad/stuck"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame

	# 보드를 '고립된 빈 칸'만 남기고 채운다: (r+c)%3==0 인 칸만 빈다.
	# 이 패턴은 상하좌우 이웃이 절대 같이 비지 않으므로, 2칸 이상 조각은 어디에도 못 들어간다.
	var cols: Array = ["R", "B", "Y"]
	var board: Array = main.get("board")
	for r in range(8):
		for c in range(8):
			board[r][c] = "" if (r + c) % 3 == 0 else cols[(r * 3 + c) % 3]
	main.set("board", board)

	# 트레이 3칸 모두 2×2 → 고립된 한 칸짜리 구멍에 절대 못 들어간다
	var o4: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	main.set("tray", [
		{"type": "O4", "color": "R", "offsets": o4},
		{"type": "O4", "color": "B", "offsets": o4},
		{"type": "O4", "color": "Y", "offsets": o4},
	])

	# 적을 몇 마리 세워둔다(묻히는지 확인용). step_every를 크게 줘서 전진/누수하지 않게.
	var enemies: Array = main.get("enemies")
	enemies.clear()
	for spec in [[2, 1], [5, 4], [6, 6]]:
		enemies.append({
			"id": 900 + int(spec[0]), "col": int(spec[1]), "row": int(spec[0]),
			"vis_row": float(spec[0]), "hp": 30, "maxhp": 30, "etype": "basic",
			"step_every": 9999, "flinch": 0.0,
		})
	main.set("enemies", enemies)
	main.set("core_hp", 99)   # 누수로 인한 '거점 파괴' 게임오버를 막는다 (지금 보는 건 stuck 경로)

	await _grab("00_before")

	# 실제 트리거를 탄다
	main.call("_end_turn")
	print(">>> game_over=", main.get("game_over"), " stuck=", main.get("stuck"),
			" stuck_t=", main.get("stuck_t"), " fill_cells=", (main.get("stuck_fill") as Dictionary).size())

	# 채움 물결 (행당 50ms, 8행 = 0.4초). 60fps 기준 3프레임마다 한 행.
	for i in range(9):
		await _grab("%02d_fill_%03dms" % [i + 1, int(main.get("stuck_t") * 1000.0)])
		await _settle(3)

	await _settle(30)
	await _grab("20_full")           # 다 찬 보드 (응시 구간)

	# 응시가 끝나면 팝업이 떠야 한다
	await _settle(90)
	await _grab("21_popup")
	print(">>> death_playing=", main.call("_death_playing"), " stuck_t=", main.get("stuck_t"))
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
	print("shot ", tag, "  stuck_t=%.3f" % float(main.get("stuck_t")))
