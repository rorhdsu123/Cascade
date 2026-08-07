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
	# ⚠실유저 진행도 보호(C100 확장): 이 probe는 Main.tscn을 띄우므로 _ready가 돌아
	#   persist_enabled=true가 된다. 아래서 cleared를 주입하거나 봇이 스테이지를 깨면 그 값이
	#   **실제 campaign.save에 각인**된다(전 스테이지 주입 = 16383 = "진행도가 저절로 전승됨"의 진범).
	#   C100은 campaign_flow.gd만 막았고 나머지 창 모드 probe는 새고 있었다 → 여기서 끈다.
	g.set("persist_enabled", false)
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

	# 4) 지금 판에서 진 적 있음 — 제목 아래 한 줄이 격려로 바뀐다(_sel_message, C157).
	#    ⚠케어(3패 완화)를 발설하면 안 되므로 진 횟수와 무관하게 같은 문구여야 한다.
	g.set("cleared", _cleared(4))
	g.set("fail_streak", {4: 2})
	g.call("_sel_enter")
	await _shot("s4_retry.png")

	print("DONE total=", total)
	quit()
