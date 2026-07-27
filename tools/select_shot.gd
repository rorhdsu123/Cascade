extends SceneTree
# 진행(select) 화면 폴리싱 확인.
#   godot --path . --script tools/select_shot.gd   (창 모드 — 헤드리스는 렌더텍스처 null)
const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/2e271b2e-cf92-4d5f-ba11-2347ef54100e/scratchpad/shots/"
var g: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)

func _cleared(n: int) -> Dictionary:
	var d: Dictionary = {}
	for i in range(n):
		d[i] = true
	return d

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")
	g.set("dev_unlock_all", false)

	var total: int = (g.get("STAGES") as Array).size()

	# 1) 프레시 시작 — 0 클리어, 프런티어=1(맨 위 금빛). 스크롤 상단.
	g.set("cleared", _cleared(0))
	g.set("mode", "select")
	g.call("_sel_enter")
	await _shot("s1_fresh.png")

	# 2) 중반 진행 — 9 클리어, 프런티어=10. 스크롤이 프런티어를 뷰포트 중앙으로 자동 정렬.
	g.set("cleared", _cleared(9))
	g.call("_sel_enter")
	await _shot("s2_frontier_scroll.png")

	# 3) 모두 클리어 — 프런티어 없음, '따라잡음' 안내 푸터(전용 화면은 별도 기획).
	g.set("cleared", _cleared(total))
	g.call("_sel_enter")
	await _shot("s3_allclear.png")

	print("DONE total=", total)
	quit()
