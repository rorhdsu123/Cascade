extends SceneTree
# 무한모드 연출 **프레임 캡처** — 봇으로 실제 판을 만든 뒤(보드·적이 진짜여야 판단이 된다)
#   각 연출 비트의 상태를 박고 얼려서 한 장씩 뽑는다.
#   ⚠창 모드 필수([[godot-pixel-verify-needs-window]]). --headless는 렌더 텍스처 null.
#   godot --path . --script tools/endless_juice_shots.gd -- <출력디렉터리>
#
# ⚠**전 세트를 한 번에 돌리면 가끔 행이 걸린다**(창 모드 봇 플레이는 OS 이벤트를 타서 flaky —
#   endless_ui_probe.gd가 같은 이유로 로직/렌더를 갈라놨다). 실측: 같은 명령이 2분에 끝나기도,
#   10분 넘게 안 끝나기도 했다. 한 컷만 필요하면 `_fresh()` + 상태 주입만 하는 짧은 스크립트를
#   따로 쓰는 편이 빠르다. 봇 수(`_fresh`의 depth)를 줄이는 것도 확률을 낮춘다.
#
# ⚠**결과 팝업(11·12)은 유저의 실제 최고점을 덮어쓴다.** `_draw_result`가 그리기 도중
#   `_leaderboard.submit()`을 부르고 `persist_enabled=false`는 그걸 안 막는다.
#   찍기 전 `endless.save`를 백업하고 끝나면 바로 복원·폐기할 것.

var g: Node = null
var out_dir: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")
	g.process_mode = Node.PROCESS_MODE_INHERIT
	print("shot ", name)

# 봇 n수 — 실제 보드/적 배치를 만든다(빈 보드 위 연출은 판단 불가)
func _bot_play(n: int) -> void:
	for i in range(n):
		var s: int = 0
		while g.get("resolving") and s < 400:
			g.call("_process", 0.05)
			s += 1
		if g.get("game_over"):
			return
		var mv: Dictionary = _best_move()
		if mv.is_empty():
			return
		g.set("sel", mv["slot"])
		g.set("hover_col", mv["col"])
		g.set("hover_row", mv["row"])
		g.call("_place_piece")
	var s2: int = 0
	while g.get("resolving") and s2 < 400:
		g.call("_process", 0.05)
		s2 += 1

func _fresh(depth: int, score: int, best: int) -> void:
	g.call("seed_game", 771)
	g.call("_start_endless")
	g.set("persist_enabled", false)
	g.set("dda_enabled", false)
	await process_frame
	_bot_play(depth)
	g.set("endless_score", score)
	g.set("endless_score_shown", float(score))
	g.set("endless_best", best)
	g.set("endless_prev_best", best)
	g.set("mode", "play")

func _run() -> void:
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = uargs[0] if uargs.size() > 0 else "/tmp/"
	if not out_dir.ends_with("/"):
		out_dir += "/"
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	# ── ① 기본 플레이(존 0 = 밤하늘 아님) ──
	await _fresh(24, 2200, 0)
	await _shot("01_play_zone0")

	# ── ② 존 2 정착(밤하늘 보라) ──
	await _fresh(60, 15000, 0)
	g.set("zone_index", 2)
	g.set("zone_mix", 1.0)
	g.set("zone_col", Color("#382178"))
	await _shot("02_play_zone2")

	# ── ③ 존 전이 비트(링 + 배경 플래시) — 전이 초반 ──
	g.set("zone_trans_t", 1.3 * 0.85)   # p≈0.15(링 확장 초입 + 플래시 살아있음)
	await _shot("03_zone_trans")

	# ── ④ 칭찬 단어: 최하 등급(GOOD, 판당 48%) ──
	await _fresh(40, 8000, 0)
	g.set("praise_t", 1.15 * 0.75)
	g.set("praise_combo", 2)
	g.set("flash_combo", 2)
	await _shot("04_praise_good")

	# ── ⑤ 칭찬 단어: 최고 등급(UNREAL) ──
	g.set("praise_t", 1.15 * 0.75)
	g.set("praise_combo", 9)
	g.set("flash_combo", 9)
	await _shot("05_praise_unreal")

	# ── ⑥ PB 돌파 버스트: 갓레이 피크(p≈0.12) ──
	await _fresh(70, 18400, 12000)
	g.set("endless_beat_best", true)
	g.set("pb_pop_t", 1.6 * (1.0 - 0.12))
	await _shot("06_pb_burst_peak")

	# ── ⑦ PB 리본 홀드(p≈0.5) ──
	g.set("pb_pop_t", 1.6 * (1.0 - 0.5))
	await _shot("07_pb_ribbon")

	# ── ⑧ PB 스티커 상주(버스트 끝난 뒤 판 끝까지) ──
	g.set("pb_pop_t", -1.0)
	await _shot("08_pb_sticker_resident")

	# ── ⑨ PB 돌파 + 존 전이 동시(둘 다 점수로 발화 = 겹칠 수 있다) ──
	g.set("pb_pop_t", 1.6 * (1.0 - 0.12))
	g.set("zone_trans_t", 1.3 * 0.85)
	g.set("zone_index", 3)
	g.set("zone_mix", 1.0)
	g.set("zone_col", Color("#481f7a"))
	await _shot("09_pb_plus_zone")

	# ── ⑩ 전멸(CLIMAX) 순간 ──
	await _fresh(50, 11000, 0)
	g.set("flash_climax", true)
	g.set("flash_combo", 6)
	g.set("flash_timer", 0.18)
	g.set("praise_t", 1.15 * 0.9)
	g.set("praise_combo", 6)
	g.call("_fire_climax")
	g.call("_process", 0.05)
	await _shot("10_climax")

	# ── ⑪ 결과 팝업: 신기록 ──
	await _fresh(40, 21500, 12000)
	g.set("endless_new_best", true)
	g.set("game_over", true)
	g.set("stuck", false)
	g.set("result_t", 1.0)
	await _shot("11_result_newbest")

	# ── ⑫ 결과 팝업: 최고 못 넘음 ──
	g.set("endless_score", 7300)
	g.set("endless_score_shown", 7300.0)
	g.set("endless_new_best", false)
	await _shot("12_result_gap")

	print("DONE")
	quit()

# ── 봇 ──
func _best_move() -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1e9
	var tray: Array = g.get("tray")
	var ROWS: int = g.get("ROWS")
	var COLS: int = g.get("COLS")
	var board: Array = g.get("board")
	for slot in range(3):
		if tray[slot].is_empty():
			continue
		var offsets: Array = tray[slot]["offsets"]
		for r in range(ROWS):
			for c in range(COLS):
				var cells: Array = []
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
					if cc.x < 0 or cc.x >= COLS or cc.y < 0 or cc.y >= ROWS:
						ok = false
						break
					if board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var sc: float = _score(cells, slot, ROWS, COLS, board, tray)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best

func _score(cells: Array, slot: int, ROWS: int, COLS: int, board: Array, tray: Array) -> float:
	var occ: Array = []
	for r in range(ROWS):
		var row: Array = []
		for c in range(COLS):
			row.append(board[r][c] != "")
		occ.append(row)
	for ci in cells:
		var cv: Vector2i = ci as Vector2i
		occ[cv.y][cv.x] = true
	var full_rows: Array = []
	var full_cols: Array = []
	for r in range(ROWS):
		var fr: bool = true
		for c in range(COLS):
			if not occ[r][c]:
				fr = false
				break
		if fr:
			full_rows.append(r)
	for c in range(COLS):
		var fc: bool = true
		for r in range(ROWS):
			if not occ[r][c]:
				fc = false
				break
		if fc:
			full_cols.append(c)
	var score: float = 500.0 * float(full_rows.size() + full_cols.size())
	var after: Array = []
	for r2 in range(ROWS):
		var row2: Array = []
		for c2 in range(COLS):
			var f: bool = occ[r2][c2]
			if full_rows.has(r2) or full_cols.has(c2):
				f = false
			row2.append(f)
		after.append(row2)
	for slot2 in range(3):
		if slot2 == slot or tray[slot2].is_empty():
			continue
		if not _fits_anywhere(after, tray[slot2]["offsets"], ROWS, COLS):
			score -= 900.0
	for e in g.get("enemies"):
		if full_rows.has(int(e["row"])) or full_cols.has(int(e["col"])):
			score += 120.0
	var holes: int = 0
	for r4 in range(ROWS):
		for c4 in range(COLS):
			if not after[r4][c4]:
				holes += 1
	return score + float(holes) * 2.0

func _fits_anywhere(occ: Array, offsets: Array, ROWS: int, COLS: int) -> bool:
	for r in range(ROWS):
		for c in range(COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
				if cc.x < 0 or cc.x >= COLS or cc.y < 0 or cc.y >= ROWS or occ[cc.y][cc.x]:
					ok = false
					break
			if ok:
				return true
	return false
