extends SceneTree
# 촬영 전 확인 3건 전용 **임시** 하네스 (G2 · 2026-08-09).
#   MODE=leak|combo|endless godot --path . --script tools/vid_check.gd -- <출력디렉터리>
#   ⚠창 모드 필수([[godot-pixel-verify-needs-window]]). --headless는 렌더 텍스처 null.
#
# 스틸이 아니라 **동영상**을 뽑는다 — 세 질문이 전부 "흐름에서 보이나"라서다.
#   endless_juice_movie.gd와 같은 방식: process_mode DISABLED + `_process`를 고정 delta로 손으로 돌림.
#   엔진이 자기 delta로 또 돌면 프레임 간격이 들쭉날쭉해져 재생 속도가 어긋난다.

const FPS: float = 30.0

var g: Node = null
var out_dir: String = ""
var _n: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _frame() -> void:
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%sf_%04d.png" % [out_dir, _n])
	_n += 1

func _roll(frames: int) -> void:
	for i in range(frames):
		g.call("_process", 1.0 / FPS)
		await _frame()

func _hold(frames: int) -> void:   # 시간을 안 흘리고 같은 그림을 반복(앞머리 여유)
	for i in range(frames):
		await _frame()

func _fill_board(skip_col: int, rows: Array) -> void:
	var cols: Array = ["R", "B", "Y", "G"]
	var board: Array = g.get("board")
	for r in range(8):
		for c in range(8):
			board[r][c] = ""
	for r2 in rows:
		for c2 in range(8):
			if c2 != skip_col:
				board[int(r2)][c2] = cols[(int(r2) * 3 + c2) % cols.size()]
	# 위쪽에 잔여 블록 몇 개 — 빈 보드는 실제 플레이처럼 안 보인다
	for spec in [[0, 1], [0, 2], [1, 6], [1, 7], [7, 0], [7, 1]]:
		if not rows.has(spec[0]):
			board[int(spec[0])][int(spec[1])] = cols[int(spec[1]) % cols.size()]
	g.set("board", board)

func _run() -> void:
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = uargs[0] if uargs.size() > 0 else "/tmp/"
	if not out_dir.ends_with("/"):
		out_dir += "/"
	var mode: String = OS.get_environment("MODE")
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	g.set("persist_enabled", false)   # ⚠실유저 세이브 보호

	match mode:
		"leak": await _leak()
		"combo": await _combo()
		"endless": await _endless()
		_:
			print("MODE=leak|combo|endless 를 줄 것")
	print("DONE frames=", _n)
	quit()

# ── ① 적이 거점에 닿는 순간, 화면에서 사건이 보이나 ──────────────────────────
#   실제 경로를 태운다: advance_step에서 맨 아랫줄 적이 row 8로 나가 누수 → _reveal_leaks.
#   거점은 안 죽인다(core_hp 넉넉) — 죽음 연출이 아니라 **평소의 피격**이 보이는지가 질문이다.
func _leak() -> void:
	g.call("seed_game", 771)
	g.call("_start_stage", 4)
	g.set("dda_enabled", false)
	await process_frame
	g.set("intro_t", -1.0)   # ⚠스테이지 인트로 카드를 지나보낸다 — 안 그러면 화면 중앙이 카드로 가려져 판정이 오염된다
	_fill_board(-1, [5, 6])
	g.set("core_hp", 6)
	var enemies: Array = []
	# 아래 두 마리가 이번 스텝에 거점으로 나간다(2열 동시 누수 = 실제로 흔한 모양)
	enemies.append({"id": 901, "col": 2, "row": 7, "vis_row": 7.0,
			"hp": 30, "maxhp": 30, "etype": "basic", "step_every": 1, "flinch": 0.0})
	enemies.append({"id": 902, "col": 5, "row": 7, "vis_row": 7.0,
			"hp": 30, "maxhp": 30, "etype": "basic", "step_every": 1, "flinch": 0.0})
	# 남아서 계속 내려오는 적들(화면이 비지 않게)
	for spec in [[3, 1], [4, 4], [2, 6]]:
		enemies.append({"id": 910 + int(spec[0]), "col": int(spec[1]), "row": int(spec[0]),
				"vis_row": float(spec[0]), "hp": 30, "maxhp": 30, "etype": "basic",
				"step_every": 9999, "flinch": 0.0})
	g.set("enemies", enemies)
	g.set("place_count", 0)
	g.set("mode", "play")
	await process_frame
	g.process_mode = Node.PROCESS_MODE_DISABLED
	await _hold(6)          # 피격 직전 정지 프레임(비교 기준)
	g.call("_end_turn")
	await _roll(54)         # 1.8초 — 플래시 0.5s · 붉은 화면 · 흔들림 · "-1" 플로터 수명 0.9s

# ── ② 콤보 칭찬 단어가 압축 후에도 읽히나 ────────────────────────────────────
#   세로 5줄을 한 번에 지워 combo 5("PERFECT!")를 실제 경로로 띄운다.
func _combo() -> void:
	g.call("seed_game", 771)
	g.call("_start_stage", 4)
	g.set("dda_enabled", false)
	await process_frame
	g.set("intro_t", -1.0)   # ⚠인트로 카드 지나보내기(위 _leak 주석과 같은 이유)
	_fill_board(3, [2, 3, 4, 5, 6])
	# 지워질 줄 위에 적을 세워 둔다 — 실제 화면은 처치 연출이 같이 터진다
	var enemies: Array = []
	for spec in [[2, 1], [4, 5], [6, 2]]:
		enemies.append({"id": 920 + int(spec[0]), "col": int(spec[1]), "row": int(spec[0]),
				"vis_row": float(spec[0]), "hp": 30, "maxhp": 30, "etype": "basic",
				"step_every": 9999, "flinch": 0.0})
	g.set("enemies", enemies)
	var tray: Array = g.get("tray")
	tray[0] = {"type": "I5v", "color": "R", "offsets": (g.PIECES["I5v"] as Array).duplicate()}
	g.set("tray", tray)
	g.set("sel", 0)
	g.set("hover_col", 3)
	g.set("hover_row", 2)
	# ⚠`combo`는 '동시에 지운 줄 수'가 아니라 **연속으로 줄을 낸 배치 수**다(_place_piece에서 +1).
	#   그래서 한 방에 5줄을 지워도 첫 배치면 combo=1 → 칭찬 단어(>=2)가 아예 안 뜬다.
	#   여기선 이미 스트릭을 타고 있는 상태를 만든다: COMBO=5면 직전까지 4연속.
	var want: int = int(OS.get_environment("COMBO")) if OS.get_environment("COMBO") != "" else 5
	g.set("combo", maxi(1, want) - 1)
	g.set("mode", "play")
	await process_frame
	g.process_mode = Node.PROCESS_MODE_DISABLED
	await _hold(4)
	g.call("_place_piece")
	print("flash_combo=", g.get("flash_combo"), " climax=", g.get("flash_climax"))
	await _roll(60)         # 2초 — 팝인 0.09s + 수명 1.15s + 여유

# ── ③ 무한에서 쓸 만한 3초가 나오나 ──────────────────────────────────────────
#   봇이 실제로 두면서 흐르는 3초를 뽑는다(상태를 박고 얼리면 '흐름'을 못 본다).
func _endless() -> void:
	g.call("seed_game", 771)
	g.call("_start_endless")
	g.set("dda_enabled", false)
	await process_frame
	_bot_play(int(OS.get_environment("DEPTH")) if OS.get_environment("DEPTH") != "" else 16)
	g.set("mode", "play")
	await process_frame
	g.process_mode = Node.PROCESS_MODE_DISABLED
	# 4초를 통째로 흘린다. ⚠앞 판은 **해소가 끝나기 전에 다음 조각을 박아** 줄이 안 터진 채
	#   보드만 채웠다(막힘사) — 다음 수는 `resolving`이 내려간 뒤에만 둔다.
	var since: int = 99
	for i in range(120):
		if not g.get("resolving") and not g.get("game_over") and since >= 9:
			var mv: Dictionary = _best_move()
			if not mv.is_empty():
				g.set("sel", mv["slot"])
				g.set("hover_col", mv["col"])
				g.set("hover_row", mv["row"])
				g.call("_place_piece")
				since = 0
		since += 1
		g.call("_process", 1.0 / FPS)
		await _frame()
		if g.get("game_over"):
			break
	print("score=", g.get("endless_score"), " depth_over=", g.get("game_over"))

# ── 봇(endless_juice_shots.gd에서 그대로) ────────────────────────────────────
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
