extends SceneTree
# 아트 배선 전/후 비교용 **고정 프레임** 캡처.
#   godot --path . --script tools/art_frames.gd -- <출력디렉터리>
#
# design_shots.gd와 다른 점 = 프레임을 얼린다.
#   저쪽은 anim_t가 실시간으로 흘러 맥동(적 링·비행기 글로우·금테)이 매 실행 달라진다 → 픽셀 비교 불가.
#   여기선 _process를 끄고 anim_t를 상수로 박아, **같은 코드면 바이트 동일 PNG**가 나온다.
#   그래서 리팩터가 렌더를 안 건드렸음을 증명하거나, 스프라이트 배선 전/후 차이만 뽑아낼 수 있다.
#
# ⚠창 모드 필수 — --headless는 렌더 텍스처가 null이라 크래시한다([[godot-pixel-verify-needs-window]]).
# ⚠persist_enabled=false 필수 — 여기서 주입한 상태가 실유저 세이브에 각인되면 안 된다(C100).

const ANIM_T: float = 12.345   # 얼린 시각. 맥동 위상을 고정하는 유일한 목적

var g: Node = null
var out_dir: String = ""

func _initialize() -> void:
	_run.call_deferred()

# 프레임을 얼린 뒤 한 장. _process를 끄고 나서 anim_t를 박는 순서가 중요하다
# (켜둔 채로 박으면 다음 _process가 곧바로 delta를 더해 어긋난다).
func _shot(name: String) -> void:
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.set("anim_t", ANIM_T)
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")
	g.process_mode = Node.PROCESS_MODE_INHERIT
	print("shot ", name)

func _fill_board() -> void:
	var board: Array = g.get("board")
	var pal: Array = ["R", "O", "Y", "G", "B", "P"]
	var fill: Array = [
		[5, 0], [5, 1], [5, 3], [5, 4], [5, 6],
		[6, 0], [6, 1], [6, 2], [6, 4], [6, 5], [6, 7],
		[7, 1], [7, 2], [7, 3], [7, 5], [7, 6], [7, 7],
		[4, 2], [4, 6],
	]
	for i in range(fill.size()):
		var rc: Array = fill[i]
		board[int(rc[0])][int(rc[1])] = pal[i % pal.size()]
	g.set("board", board)

func _enter_play() -> void:
	g.call("seed_game", 424242)   # ⚠필수 — 트레이 조각·적 스폰이 게임 스트림이라 시드 없으면 매 실행 달라진다
	g.call("_start_stage", 3)
	g.set("persist_enabled", false)
	g.set("intro_t", -1.0)
	await process_frame
	_fill_board()

func _run() -> void:
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	if uargs.is_empty():
		printerr("usage: godot --path . --script tools/art_frames.gd -- <출력디렉터리>")
		quit(1)
		return
	out_dir = uargs[0]
	if not out_dir.ends_with("/"):
		out_dir += "/"
	DirAccess.make_dir_recursive_absolute(out_dir)

	g = load("res://Main.tscn").instantiate()
	# ⚠add_child(=_ready) '전에' 꺼야 한다 — _ready가 곧바로 session_begin()을 찍는다.
	#   계측은 헤드리스에서만 자동으로 꺼지는데(analytics.gd:57) 이 하네스는 창 모드가 필수라
	#   가만 두면 프로브 세션이 실측 로그(analytics.jsonl)에 섞인다.
	g.get("_analytics").enabled = false
	root.add_child(g)
	g.set("persist_enabled", false)      # ⚠실유저 진행도 보호
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")
	g.set("dev_unlock_all", false)
	g.set("show_input_toggle", false)

	# ── 0. 아이콘이 사는 화면들. 블록과 달리 아이콘은 인게임 밖에 흩어져 있다
	#    (허브=깃발·무한, 스테이지=체크·자물쇠, 설정=기어, 결과=재생·재시도, HUD=기어·해골).
	g.set("mode", "menu")
	g.set("cleared", {0: true, 1: true, 2: true})
	g.set("endless_best", 12480)
	await _shot("f_hub")

	g.set("mode", "select")
	g.call("_sel_enter")
	await _shot("g_select")

	# ── 1. 정지 보드 — 보드 블록 + 트레이 프리뷰(축소 렌더)
	await _enter_play()
	await _shot("a_board")

	g.set("settings_open", true)
	await _shot("h_settings")
	g.set("settings_open", false)

	# ── 2. 충전(백열 직전) — 스프라이트 전환에서 제일 깨지기 쉬운 자리.
	#    modulate는 곱셈이라 텍스처를 흰색보다 밝게 못 만든다 → 가산 패스가 필요한 지점.
	var cells: Array = []
	for c in range(8):
		cells.append(Vector2i(c, 7))
	var board2: Array = g.get("board")
	for c2 in range(8):
		board2[7][c2] = ["R", "O", "Y", "G", "B", "P"][c2 % 6]
	g.set("board", board2)
	g.set("clear_cells", cells)
	g.set("clear_rows", [7])
	g.set("clear_cols", [])
	g.set("clear_done", false)
	g.set("clear_tint", Color("#ffd23b"))
	g.set("combo", 5)
	g.set("resolving", true)
	g.set("resolve_timer", float(g.get("charge_dur")) * 0.95)   # 거의 다 달아오른 순간
	await _shot("b_charge")
	# 대조군 — 가산 레이어만 끈 같은 프레임. b와 바이트 동일하면 가산 패스가 죽은 것이다
	# (자식 노드가 부모와 같은 프레임에 다시 안 그려지는 경우를 잡는 탐침).
	var glow: Node = g.get("_glow")
	if glow != null:
		glow.visible = false
		await _shot("b2_charge_noglow")
		glow.visible = true
	g.set("resolving", false)
	g.set("clear_done", true)
	g.set("clear_cells", [])
	g.set("clear_rows", [])

	# ── 3. 손에 든 조각 — 커서를 따라다니는 별도 렌더 경로
	g.set("sel", 0)
	g.set("drag_slot", 0)
	g.set("dragging", true)
	g.set("drag_pos", Vector2(400.0, 500.0))
	await _shot("c_held")
	g.set("dragging", false)

	# ── 4. 거점 붕괴 — 열마다 시차를 두고 쏟아지는 블록(보드와 다른 렌더 자리)
	g.set("core_t", 0.55)
	await _shot("d_collapse")
	g.set("core_t", -1.0)

	# ── 5. 튜토리얼 타깃 고스트 — 반투명 블록(알파 경로)
	g.set("tut_lock", true)
	g.set("tut_cells", [Vector2i(3, 3), Vector2i(4, 3)])
	await _shot("e_tut")
	g.set("tut_lock", false)
	g.set("tut_cells", [])

	# ── 6. 결과(실패) — 재생(광고 이어하기)·재시도 아이콘이 사는 유일한 화면
	g.set("killed", 6)
	g.set("leaked", 3)
	g.set("stuck", false)
	g.set("revive_used", false)
	g.set("game_over", true)
	g.set("result_t", 1.0)
	await _shot("i_result")

	print("DONE")
	quit()
