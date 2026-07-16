extends SceneTree

# 블록 착지 팝(배치 강화, C45) 캡처 — 일회성.
# 비완성 자리에 조각을 놓고 팝이 살아있는 1~2프레임에서 찍는다.
# 완성 못 시킨 수도 '탁' 들어앉는 손맛이 남는지 확인(C30 노트 d: 빈손인 수 문제).

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/414a65ff-f1ae-4ffe-a2cc-df007e0db6ae/scratchpad"

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)

	# 빈 보드 + 적 몇 마리(팝이 적과 안 겹치는 걸 보게)
	for r in range(g.ROWS):
		for c in range(g.COLS):
			g.board[r][c] = ""
	g.enemies = []

	# ㄱ자 4칸 조각(가로 3 + 아래 1)을 빈 자리에 놓는다 — 여러 칸 동시 팝
	g.tray[0] = {"key": "T", "offsets": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], "color": "B"}
	g.sel = 0
	g.dragging = true
	g.click_mode = true
	g.hover_col = 2
	g.hover_row = 3
	g.drag_pos = Vector2(g.BOARD_X + 3 * g.CELL + g.CELL * 0.5, g.BOARD_Y + 3 * g.CELL + g.CELL * 0.5)
	await process_frame

	g._place_piece()      # 비완성 배치 → 착지 팝 생성 + _end_turn
	g.dragging = false    # 들고 있던 조각 렌더 제거(팝을 가리지 않게)

	# 팝이 아직 큰 1~2프레임에서 캡처
	g.queue_redraw()
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/place_pop.png" % OUT)
	print("saved place_pop, remaining pops=%d" % g.place_pops.size())
	quit()
