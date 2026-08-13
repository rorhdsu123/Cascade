extends SceneTree
# 메인 메뉴(허브) 창 스모크 + 픽셀검증. [[godot-pixel-verify-needs-window]] 창 필수.
#   godot --path . --script tools/menu_shot.gd
const ShotDir = preload("res://tools/shot_dir.gd")
# 출력 경로 = SHOT_DIR 환경변수, 없으면 build/shots/ (tools/shot_dir.gd 참조).
var DIR: String = ShotDir.resolve("")
func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _shot(name: String) -> void:
	if _headless():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	print("BOOT: mode=%s" % g.get("mode"))
	# 최고점 후크가 보이게 살짝 심어둠(그리기 경로만 확인)
	g.set("endless_best", 12345)
	g.call("queue_redraw")
	await _shot("menu.png")

	# Adventure 클릭 → select 로 가는가
	var adv: Rect2 = g.get("MENU_ADV_BTN")
	_click(g, adv.position + adv.size * 0.5)
	await process_frame
	print("AFTER ADV CLICK: mode=%s" % g.get("mode"))
	g.call("queue_redraw")
	await _shot("menu_select.png")

	# select 의 back 버튼 → menu 복귀
	var bk: Rect2 = g.get("BACK_BTN")
	_click(g, bk.position + bk.size * 0.5)
	await process_frame
	print("AFTER BACK CLICK: mode=%s" % g.get("mode"))

	# Classic 클릭 → 무한 시작
	_click(g, (g.get("MENU_CLASSIC_BTN") as Rect2).get_center())
	await process_frame
	print("AFTER CLASSIC CLICK: mode=%s endless=%s director=%s" % [
		g.get("mode"), str(g.get("endless")),
		g.get("director").get_script().resource_path.get_file() if g.get("director") != null else "nil"])
	quit()

func _click(g: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)
	# 버튼은 **뗄 때** 발동한다(C144) — 누름만 보내면 걸리기만 하고 아무 일도 안 일어난다.
	ev.pressed = false
	g.call("_input", ev)
