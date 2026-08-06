extends SceneTree

# 결과 팝업(실패) 캡처 + 재도전 버튼 클릭 검증 — 일회성.

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/732bc2cc-e69c-4419-8bb1-fd1c0c02122a/scratchpad"

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)
	g.set_process(false)

	# 실패 상태를 만든다: 총 적 중 일부만 잡고 거점 파괴로 종료
	g.killed = 5
	g.leaked = 2
	g.stuck = false
	g.game_over = true
	var expect: int = int(g.st["total"]) - g.killed - g.leaked
	print("스테이지 total=%d, killed=%d, leaked=%d → 팝업에 떠야 할 남은 적 = %d"
			% [int(g.st["total"]), g.killed, g.leaked, expect])

	await _shot(g, "result_fail")

	# 호버 상태 그림도 한 장
	var hov: InputEventMouseMotion = InputEventMouseMotion.new()
	hov.position = g.RETRY_BTN.get_center()
	g._input(hov)
	print("재도전 버튼 호버=%s" % g._retry_hover)
	await _shot(g, "result_fail_hover")

	# 빈 곳 클릭 → 아무 일도 없어야 함(모달)
	var stray: InputEventMouseButton = InputEventMouseButton.new()
	stray.position = Vector2(60, 950)
	stray.button_index = MOUSE_BUTTON_LEFT
	stray.pressed = true
	g._input(stray)
	# 버튼은 **뗄 때** 발동한다(C144)
	stray.pressed = false
	g._input(stray)
	print("빈 곳 클릭 후 — mode=%s game_over=%s (홈으로 튕기지 않아야 함)" % [g.mode, g.game_over])

	# 재도전 버튼 클릭 → 같은 스테이지 재시작
	var clk: InputEventMouseButton = InputEventMouseButton.new()
	clk.position = g.RETRY_BTN.get_center()
	clk.button_index = MOUSE_BUTTON_LEFT
	clk.pressed = true
	g._input(clk)
	# 버튼은 **뗄 때** 발동한다(C144)
	clk.pressed = false
	g._input(clk)
	print("재도전 클릭 후 — mode=%s game_over=%s killed=%d leaked=%d stage=%d"
			% [g.mode, g.game_over, g.killed, g.leaked, g.stage_idx])

	# 클리어 팝업(같은 패널 재사용 — 버튼이 '다음 스테이지'로 바뀌어야 함)
	g.killed = 20
	g.leaked = 0
	g.game_clear = true
	g._retry_hover = false
	await _shot(g, "result_clear")
	quit()

func _shot(g: Node, name: String) -> void:
	g.queue_redraw()
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("saved %s" % name)
