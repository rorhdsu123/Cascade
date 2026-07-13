extends SceneTree

# 드래그 프리뷰(고스트 + 줄 완성 예고) 캡처 — 일회성.
# 세 경우: ① 놓으면 줄이 터지는 자리 ② 그냥 놓기만 하는 자리 ③ 못 놓는 자리

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/a94bf984-26de-42e7-954a-d29968395e39/scratchpad"

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)

	# 알록달록한 보드: row 6은 col 7만 비었고, col 2도 거의 찬 상태(세로줄 프리뷰도 보게)
	for r in range(g.ROWS):
		for c in range(g.COLS):
			g.board[r][c] = ""
	var mix: Array = ["B", "R", "B", "Y", "R", "B", "R"]
	for c in range(g.COLS - 1):
		g.board[6][c] = mix[c]
	g.board[5][1] = "R"
	g.board[5][2] = "Y"
	g.board[7][3] = "B"
	g.board[4][5] = "R"
	# 노란 1칸 조각
	g.tray[0] = {"key": "1", "offsets": [Vector2i(0, 0)], "color": "Y"}
	g.sel = 0

	# ① 줄이 완성되는 자리 (row 6, col 7)
	g.hover_col = 7
	g.hover_row = 6
	await _shot(g, "preview_clear")

	# ② 그냥 놓기만 하는 자리 (빈 곳)
	g.hover_col = 2
	g.hover_row = 2
	await _shot(g, "preview_plain")

	# ③ 못 놓는 자리 (이미 블록이 있는 칸)
	g.hover_col = 3
	g.hover_row = 7
	await _shot(g, "preview_blocked")
	quit()

func _shot(g: Node, name: String) -> void:
	# 맥동(pulse)이 밝은 위상일 때 찍히도록 몇 프레임 흘린다
	for i in range(6):
		await process_frame
	g.queue_redraw()
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("saved %s" % name)
