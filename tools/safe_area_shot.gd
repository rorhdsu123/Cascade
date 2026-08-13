extends SceneTree
# 세이프에어리어(노치·홈 인디케이터) 레이아웃 검증. 창 필수([[godot-pixel-verify-needs-window]]).
#   godot --path . --script tools/safe_area_shot.gd
# 실기기 없이 보기 위해 Main.safe_debug로 인셋을 주입한다.
#   iPhone 15 Pro(1179×2556, 상단 59pt·하단 34pt) 환산: 배율 1179/800=1.474
#   → 논리 인셋 ≈ 상 120 / 하 69, 논리 뷰포트 높이 ≈ 1734.
const ShotDir = preload("res://tools/shot_dir.gd")
# 출력 경로 = SHOT_DIR 환경변수, 없으면 build/shots/ (tools/shot_dir.gd 참조).
var DIR: String = ShotDir.resolve("shots/")
const INSET := Vector2(120.0, 69.0)
const VH: int = 1734

var g: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	# 세이프에어리어 경계선을 붉게 그어 '이 위/아래로 UI가 넘어가면 안 된다'를 눈으로 보이게.
	var sc: float = float(DisplayServer.window_get_size().x) / 800.0
	for line_y in [int(INSET.x * sc), img.get_height() - int(INSET.y * sc)]:
		for x in range(img.get_width()):
			img.set_pixel(x, clampi(line_y, 0, img.get_height() - 1), Color(1, 0.2, 0.2))
	img.save_png(DIR + name)

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, VH))
	await process_frame
	await process_frame
	g.set("_locale", "en")
	g.set("safe_debug", INSET)
	g.call("_relayout")
	await process_frame
	print("safe_top=%s safe_bottom=%s board_y=%s bot_y=%s gear=%s ui_dy=%.1f" % [
		g.get("safe_top"), g.get("safe_bottom"), g.get("board_y"), g.get("bot_y"),
		str(g.get("gear_rect")), g.call("_ui_dy")])

	g.set("mode", "menu")
	g.set("endless_best", 12480)
	await _shot("s1_menu_safe.png")

	g.set("mode", "leaderboard")
	await _shot("s2_leaderboard_safe.png")

	g.call("_start_endless")
	await process_frame
	for i in range(10):
		g.call("advance_step")
	g.set("endless_score", 8420)
	g.set("place_count", 26)
	g.set("endless_beat_best", false)
	await _shot("s3_endless_safe.png")

	print("DONE")
	quit()
