extends SceneTree

# 전멸(full_board) 클라이맥스에서 '전체화면 오버레이'가 남아 있는지 픽셀로 검증 — 일회성.
# 보드/적/파티클이 절대 닿지 않는 구석 픽셀만 본다. 이 픽셀이 배경색에서 벗어나면
# 화면 전체를 덮는 draw_rect가 살아 있다는 뜻.

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/732bc2cc-e69c-4419-8bb1-fd1c0c02122a/scratchpad"
const PROBE := Vector2i(4, 995)   # 좌하단 구석
const BG := Color("#0d0d1a")

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)
	g.set_process(false)   # 시간은 내가 민다

	# row 6을 col 7만 남기고 채운다 → 1칸 조각으로 줄 완성
	for r in range(g.ROWS):
		for c in range(g.COLS):
			g.board[r][c] = ""
	for c in range(g.COLS - 1):
		g.board[6][c] = "B"
	g.tray[0] = {"key": "1", "offsets": [Vector2i(0, 0)], "color": "Y"}
	g.sel = 0
	g.hover_col = 7
	g.hover_row = 6
	g.combo = g.CLIMAX_COMBO - 1   # _place_piece가 +1 → CLIMAX_COMBO 도달 = 전멸

	g._place_piece()
	print("전멸 예약: climax_pending=%.2f (>=0 이면 클라이맥스 발화 예정)" % g.climax_pending)

	var worst: float = 0.0
	var worst_t: float = 0.0
	var worst_col: Color = BG
	var t: float = 0.0
	while t < 2.5:
		for i in range(5):
			g._process(0.01)   # 0.05s 전진
		t += 0.05
		g.queue_redraw()
		await process_frame
		await process_frame
		var img: Image = root.get_texture().get_image()
		var px: Color = img.get_pixelv(PROBE)
		# 배경색과의 거리 = 전체화면 오버레이가 얹힌 정도
		var d: float = absf(px.r - BG.r) + absf(px.g - BG.g) + absf(px.b - BG.b)
		# 골드 판정: 오버레이가 노란기(파랑 대비 빨강·초록 우세)를 띠는가
		var goldish: bool = d > 0.02 and px.r > px.b + 0.06 and px.g > px.b + 0.03
		print("t=%.2f  이탈=%.3f  색=(%.2f,%.2f,%.2f)%s" % [t, d, px.r, px.g, px.b, "  <-- 골드끼" if goldish else ""])
		if d > worst:
			worst = d
			worst_t = t
			worst_col = px
			img.save_png("%s/climax_worst.png" % OUT)

	print("구석 픽셀 최대 이탈: %.4f  @t=%.2fs  색=%s (배경=%s)" % [worst, worst_t, worst_col, BG])
	quit()
