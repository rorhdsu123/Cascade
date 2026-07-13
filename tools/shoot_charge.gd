extends SceneTree

# 충전(줄 폭발) 연출을 프레임 단위로 캡처 — 일회성.
# 게임의 _process를 끄고 수동으로 시간을 밀어, resolve_timer가 원하는 값일 때 화면을 저장한다.

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/a94bf984-26de-42e7-954a-d29968395e39/scratchpad"

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)
	g.set_process(false)   # 시간은 내가 민다

	# row 6을 col 7만 비우고 파랑/빨강으로 채운다(알록달록한 보드 = 색 통일 효과를 보려고)
	for r in range(g.ROWS):
		for c in range(g.COLS):
			g.board[r][c] = ""
	var mix: Array = ["B", "R", "B", "Y", "R", "B", "R"]
	for c in range(g.COLS - 1):
		g.board[6][c] = mix[c]
	# 주변에도 블록을 좀 깔아 대비를 만든다
	g.board[5][1] = "R"
	g.board[5][2] = "Y"
	g.board[7][3] = "B"
	g.board[4][5] = "R"
	# 노란 1칸 조각으로 줄 완성 → 줄 전체가 노랑으로 물들어야 한다
	g.tray[0] = {"key": "1", "offsets": [Vector2i(0, 0)], "color": "Y"}
	g.sel = 0
	g.hover_col = 7
	g.hover_row = 6
	g.combo = 3   # → _place_piece가 +1 = 콤보 4 (충전 홀드 0.56s = 가장 긴 구간)

	await _shot(g, "0_before")   # 배치 직전
	g._place_piece()

	for target in [0.30, 0.55, 0.575, 0.60, 0.66, 0.80]:
		var guard: int = 0
		while g.resolve_timer < target and g.resolving and guard < 500:
			g._process(0.01)
			guard += 1
		await _shot(g, "t%04d" % int(target * 1000.0))
	quit()

func _shot(g: Node, name: String) -> void:
	g.queue_redraw()
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/charge_%s.png" % [OUT, name])
	print("saved %s  (resolve_timer=%.2f  clear_done=%s  남은셀=%d)"
			% [name, g.resolve_timer, g.clear_done, g.clear_cells.size()])
