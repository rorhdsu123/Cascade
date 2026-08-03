extends SceneTree
# 웹 빌드가 데스크톱 브라우저에서 어떻게 보이는지 실측한다 (NAN 2026 G1).
#   godot --path . --script tools/web_viewport_probe.gd
# ⚠창 모드 필수 — --headless는 렌더 텍스처가 null이라 크래시한다.
# ⚠persist_enabled=false 필수 — 아니면 여기서 주입한 상태가 실유저 세이브에 각인된다(C100).
#
# 왜 창 크기만 바꿔 찍으면 되나: stretch=canvas_items · aspect=expand는 플랫폼과 무관하게
#   창 종횡비로만 결정된다. 웹 캔버스(canvas_resize_policy=2=Adaptive)는 브라우저 창을
#   그대로 채우므로, 같은 크기의 데스크톱 창이 곧 그 브라우저의 화면이다.

const OUT: String = "res://build/webshots/"   # build/는 .gitignore 대상

# 이름, 폭, 높이 — 심사자가 열 법한 창들
const CASES: Array = [
	["a_base_800x1280",   800, 1280],   # 대조군: 기준 세로
	["b_laptop_1440x780", 1440,  780],  # 13~14" 노트북 브라우저 뷰포트(가로)
	["c_desktop_1920x950", 1920, 950],  # 외장 모니터 최대화(가로)
	["d_narrow_700x1100",  700, 1100],  # 브라우저를 세로로 좁힌 경우
]

var g: Node = null
var out_dir: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("shot %s  window=%s  viewport=%s" % [
		name, str(DisplayServer.window_get_size()), str(root.get_visible_rect().size)])

func _run() -> void:
	out_dir = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)

	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	g.set("persist_enabled", false)      # ⚠실유저 진행도 보호
	await process_frame
	g.set("_locale", "en")
	g.set("dev_unlock_all", false)
	g.set("show_input_toggle", false)

	g.call("_start_stage", 3)
	g.set("persist_enabled", false)
	g.set("intro_t", -1.0)
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

	for c in CASES:
		DisplayServer.window_set_size(Vector2i(int(c[1]), int(c[2])))
		await process_frame
		await process_frame
		await process_frame
		await _shot(String(c[0]))

	# 허브도 한 장 — 첫 화면이라 인상이 여기서 갈린다.
	g.set("mode", "menu")
	g.set("cleared", {0: true, 1: true, 2: true})
	DisplayServer.window_set_size(Vector2i(1440, 780))
	await process_frame
	await process_frame
	await _shot("e_hub_1440x780")

	print("done -> ", out_dir)
	quit()
