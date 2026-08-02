extends SceneTree
# 디자이너용 현재-상태 캡처 (UI_ART_PLAN.md의 스크린샷 생성기).
#   godot --path . --script tools/design_shots.gd
# ⚠창 모드 필수 — --headless는 렌더 텍스처가 null이라 크래시한다.
# ⚠persist_enabled=false 필수 — 아니면 여기서 주입한 cleared가 실유저 세이브에 각인된다(C100).

# 문서 옆에 바로 떨어뜨린다 — docs/UI_ART_PLAN.md가 상대경로 design/current/…로 참조한다.
const OUT_RES: String = "res://docs/design/current/"

var g: Node = null
var out_dir: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)

func _run() -> void:
	out_dir = ProjectSettings.globalize_path(OUT_RES)
	DirAccess.make_dir_recursive_absolute(out_dir)
	g = load("res://Main.tscn").instantiate()
	# ⚠add_child(=_ready) '전에' 꺼야 한다 — _ready가 곧바로 session_begin()을 찍는다.
	#   계측은 헤드리스에서만 자동으로 꺼지는데(analytics.gd:57) 이 프로브는 창 모드가 필수라
	#   가만 두면 캡처 세션이 실측 로그(analytics.jsonl)에 섞인다.
	g.get("_analytics").enabled = false
	root.add_child(g)
	g.set("persist_enabled", false)      # ⚠실유저 진행도 보호
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")
	g.set("dev_unlock_all", false)
	g.set("show_input_toggle", false)   # PC 전용 DRAG MODE 토글 — 모바일 출고본엔 없다

	# ── 1. 허브(진행 중)
	g.set("mode", "menu")
	g.set("cleared", {0: true, 1: true, 2: true})
	g.set("endless_best", 12480)
	await _shot("01_hub")

	# ── 3. 스테이지 진행 리드아웃
	g.set("mode", "select")
	g.call("_sel_enter")
	await _shot("03_select")

	# ── 4. 인게임(보드에 블록을 깔아 '블록 완성도'가 보이게)
	g.call("_start_stage", 3)
	g.set("persist_enabled", false)
	g.set("intro_t", -1.0)               # 진입 인트로 배너 스킵(보드를 가린다)
	await process_frame
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
	# 종이비행기 — 두 쓰임을 한 화면에: ① 보드 위 픽업 ② 좌하단 보유 슬롯.
	#   기본 상태로는 둘 다 안 뜨는데, 디자이너가 다시 그려야 할 물건이라 보여야 한다.
	var es: Array = g.get("enemies")
	es.append({"col": 3, "row": 2, "vis_row": 2.0, "hp": 1, "maxhp": 1,
			"etype": "plane", "id": 9001, "step_every": 3})
	g.set("enemies", es)
	g.set("plane_held", true)
	await _shot("04_play")

	# ── 2. 설정 모달 — ⚠플레이 중에만 그려진다(Main.gd:4061이 menu 분기 뒤에 있다). 허브엔 기어가 없다.
	g.set("settings_open", true)
	await _shot("02_settings")
	g.set("settings_open", false)

	# ── 5. 결과 — 실패(부활 제안)
	g.set("killed", 6)
	g.set("leaked", 3)
	g.set("stuck", false)
	g.set("revive_used", false)
	g.set("game_over", true)
	g.set("result_t", 1.0)
	await _shot("05_result_fail")

	# ── 6. 결과 — 클리어
	g.call("_start_stage", 3)
	g.set("persist_enabled", false)
	g.set("intro_t", -1.0)               # 진입 인트로 배너 스킵(보드를 가린다)
	await process_frame
	var st: Dictionary = g.get("st")
	g.set("killed", int(st.get("total", 10)))
	g.set("leaked", 0)
	g.set("game_over", false)
	g.set("game_clear", true)
	g.set("result_t", 1.0)
	await _shot("06_result_clear")

	# ── 7. 블록 확대 크롭(3배·최근접) — 평면 사각형이라는 게 등배에선 안 보인다.
	var play_img: Image = Image.load_from_file(out_dir + "04_play.png")
	var crop: Image = play_img.get_region(Rect2i(40, 630, 360, 270))
	crop.resize(360 * 3, 270 * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(out_dir + "07_block_zoom.png")
	print("shot 07_block_zoom")

	# ── 8. 비행기 슬롯 확대 — 90×90이라 등배로는 형태가 안 읽힌다.
	#   트레이 첫 슬롯까지 함께 잘라 '손에 든 것들 줄'로 나란히 앉은 게 보이게.
	var slot_crop: Image = play_img.get_region(Rect2i(30, 970, 590, 145))
	slot_crop.resize(590 * 2, 145 * 2, Image.INTERPOLATE_NEAREST)
	slot_crop.save_png(out_dir + "08_plane_slot.png")
	print("shot 08_plane_slot")

	print("DONE")
	quit()
