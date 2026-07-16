extends SceneTree

# 조준 프리뷰(배치 전 '이 적이 죽는다' 외곽 강조) 캡처 + 로직 검증 — 일회성 (C43 인지).
# 같은 보드·같은 적에서 콤보만 바꿔 밴드가 어떻게 번지는지 본다:
#   ① combo0  → 밴드=완성 줄(row6)만. 적은 5/7행에 있어 아무도 안 걸림 = 무표적(표식 0).
#   ② combo2  → 밴드=row 5/6/7. 인접행 적 3마리 조준, 멀리 있는 1마리는 제외.
#   ③ climax  → combo4(+1=5=CLIMAX) → 전멸. 모든 적 조준.
# 각 케이스에서 _blast_band(실제 처치와 공유)로 '죽어야 할 id'를 계산해 출력 = 지상 진실.

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/414a65ff-f1ae-4ffe-a2cc-df007e0db6ae/scratchpad"

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(0)

	# 보드: row 6을 col 7만 남기고 채움 → (7,6)에 1칸 놓으면 가로줄 완성
	for r in range(g.ROWS):
		for c in range(g.COLS):
			g.board[r][c] = ""
	var mix: Array = ["B", "R", "B", "Y", "R", "B", "R"]
	for c in range(g.COLS - 1):
		g.board[6][c] = mix[c]

	# 적 5마리: 인접행(5,7)에 3 + 멀리(2행)에 1 + 드롭 칸(7,6)에 1(들고 있는 조각이 덮는다).
	# 5/7행은 블록이 없어 겹침 없이 깨끗하게 보이고, (7,6)은 커서 아래 가림 케이스.
	g.enemies = [
		_enemy(101, 2, 5),
		_enemy(102, 5, 7),
		_enemy(103, 6, 5),
		_enemy(104, 1, 2),
		_enemy(105, 7, 6),
	]

	# 노란 1칸 조각을 (7,6) 위에 들고 있는 상태. drag_pos를 드롭 칸 중심에 둬 조각이 그 칸에 그려진다
	# (click_mode=lift 0). 안 그러면 _draw_held가 조각을 엉뚱한 곳(drag_pos 기본 0,0)에 그린다.
	g.tray[0] = {"key": "1", "offsets": [Vector2i(0, 0)], "color": "Y"}
	g.sel = 0
	g.dragging = true
	g.click_mode = true
	g.hover_col = 7
	g.hover_row = 6
	g.drag_pos = Vector2(g.BOARD_X + 7 * g.CELL + g.CELL * 0.5, g.BOARD_Y + 6 * g.CELL + g.CELL * 0.5)

	g.combo = 0
	_report(g, "aim_combo0")
	await _shot(g, "aim_combo0")

	g.combo = 2
	_report(g, "aim_combo2")
	await _shot(g, "aim_combo2")

	g.combo = 4
	_report(g, "aim_climax")
	await _shot(g, "aim_climax")
	quit()

func _enemy(id: int, col: int, row: int) -> Dictionary:
	return {"col": col, "row": row, "vis_row": float(row), "hp": 30, "maxhp": 30,
			"etype": "basic", "id": id, "flinch": 0.0, "step_every": 2}

# 지상 진실: 실제 처치가 쓰는 _blast_band를 combo+1로 돌려 '죽어야 할 적 id'를 뽑는다.
func _report(g: Node, name: String) -> void:
	var wl: Dictionary = g._would_clear_lines(g._ghost_cells())
	var band: Dictionary = g._blast_band(wl["rows"], wl["cols"], g.combo + 1)
	var pv_cols: Dictionary = band["cols"]
	var pv_rows: Dictionary = band["rows"]
	var doomed: Array = []
	for e in g.enemies:
		if pv_cols.has(e["col"]) or pv_rows.has(e["row"]):
			doomed.append(e["id"])
	print("[%s] combo=%d rows=%s cols=%s full=%s band_rows=%s band_cols=%s → doomed=%s"
			% [name, g.combo, str(wl["rows"]), str(wl["cols"]), str(band["full_board"]),
			str(pv_rows.keys()), str(pv_cols.keys()), str(doomed)])

func _shot(g: Node, name: String) -> void:
	for i in range(6):   # 맥동 밝은 위상 잡기
		await process_frame
	g.queue_redraw()
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("saved %s" % name)
