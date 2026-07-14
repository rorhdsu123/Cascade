extends SceneTree
# 드래그앤드롭 검증용 프로브 — Main을 띄우고 합성 입력으로 드래그를 재현해 프레임을 캡처한다.
# 실행: godot --path . --script tools/drag_probe.gd  (창 모드 필수: 헤드리스는 렌더 텍스처가 null)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/7403dd74-472a-4952-afac-6f6948b37825/scratchpad/shot"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame

	# 보드에 블록을 심어 '못 놓는 자리'를 만든다
	var board: Array = main.get("board")
	for c in range(0, 5):
		board[7][c] = "R"      # 빨간 줄 — 예전 빨간 고스트와 헷갈리던 바로 그 색
		board[6][c] = "B"
	main.set("board", board)

	# 트레이 0번을 2×2 정사각으로 고정 (결과 예측 가능하게)
	var tray: Array = main.get("tray")
	tray[0] = {"type": "O4", "color": "Y",
			"offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]}
	main.set("tray", tray)
	await _grab("00_idle")   # 안 들었을 때: 보드에 프리뷰가 없어야 한다

	var slot: Rect2 = main.call("_tray_slot_rect", 0)
	_press(slot.get_center())
	await _grab("01_pickup")

	# ① 빈 칸 위 → 스냅 + 착지 프리뷰
	_move(Vector2(144 + 64 * 3 + 32, 150 + 64 * 2 + 80))
	await _grab("02_valid_snap")

	# ② 기존 블록(빨강/파랑) 위 → 스냅 없음, 보드 표시 없음, 조각만 떠 있어야
	_move(Vector2(144 + 64 * 2 + 32, 150 + 64 * 7 + 80))
	await _grab("03_invalid_float")

	# ③ 보드 밖(좌측) → 역시 스냅 없음
	_move(Vector2(40, 150 + 64 * 6 + 80))
	await _grab("04_invalid_offboard")

	# ④ 못 놓는 자리에서 떼기 → 트레이로 스냅백
	_release(Vector2(144 + 64 * 2 + 32, 150 + 64 * 7 + 80))
	await _grab("05_snapback")

	# ⑤ 유효한 자리에 드롭 → 실제 배치
	_press((main.call("_tray_slot_rect", 0) as Rect2).get_center())
	_move(Vector2(144 + 64 * 6 + 32, 150 + 64 * 2 + 80))
	await _grab("06_before_drop")
	_release(Vector2(144 + 64 * 6 + 32, 150 + 64 * 2 + 80))
	await _grab("07_placed")

	# ===== 클릭 모드 =====
	var tray2: Array = main.get("tray")
	tray2[0] = {"type": "O4", "color": "Y",
			"offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]}
	main.set("tray", tray2)

	_press(Vector2(688, 923))    # MODE_BTN 중심 (596+184/2, 900+46/2)
	_release(Vector2(688, 923))
	await _grab("08_click_mode_on")

	# 조각 클릭해 집기 (떼도 계속 들려 있어야 한다)
	_press((main.call("_tray_slot_rect", 0) as Rect2).get_center())
	_release((main.call("_tray_slot_rect", 0) as Rect2).get_center())
	_move(Vector2(144 + 64 * 2 + 32, 150 + 64 * 7 + 32))   # 기존 블록 위
	await _grab("09_click_held_invalid")                    # 스냅 없음, 빨강 없음

	_move(Vector2(144 + 64 * 1 + 32, 150 + 64 * 3 + 32))   # 빈 칸
	await _grab("10_click_held_valid")                      # 스냅 + 프리뷰

	_press(Vector2(144 + 64 * 1 + 32, 150 + 64 * 3 + 32))  # 보드 클릭 → 배치
	_release(Vector2(144 + 64 * 1 + 32, 150 + 64 * 3 + 32))
	await _grab("11_click_placed")

	print("DONE  click_mode=", main.get("click_mode"))
	quit()

func _press(p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	main.call("_input", e)

func _release(p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	main.call("_input", e)

func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	main.call("_input", e)

func _grab(tag: String) -> void:
	main.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag,
			"  dragging=", main.get("dragging"),
			" hover=", main.get("hover_col"), ",", main.get("hover_row"),
			" snapback=", not (main.get("snapback") as Dictionary).is_empty())
