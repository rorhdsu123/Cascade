extends SceneTree
# 부팅 3칸 확인 — [엔진 스플래시 그림] → [게임 로고 화면] → [홈].
#   godot --path . --script tools/boot_shot.gd -- <출력디렉터리>   (창 모드 — 헤드리스는 렌더텍스처 null)
#
# 이 도구가 답해야 하는 건 하나다: **컷에서 로고 말고 다른 게 움직이나.**
#   그래서 로고 화면과 홈을 같은 창에서 연달아 찍고, 두 프레임의 배경 픽셀을 숫자로 대조한다
#   (눈으로는 몇 십 px 어긋난 걸 못 본다 — 그린 자리와 실제 자리는 반드시 숫자로 본다).
#
# ⚠Main은 `--script` 실행이면 로고 화면을 건너뛴다(프로브 보호). 여기선 일부러 되돌려 놓는다.
var g: Node = null
var out_dir: String = "/tmp/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = String(args[0])
	if not out_dir.ends_with("/"):
		out_dir += "/"
	DirAccess.make_dir_recursive_absolute(out_dir)

	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	g.set("persist_enabled", false)   # 실유저 진행도 보호 — 창 모드 probe 공통 규약
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")

	# 1) 게임 로고 화면(스튜디오 스플래시 바로 다음 칸)
	g.set("mode", "logo")
	g.set("logo_t", 0.0)
	await _shot("b1_logo.png")

	# 2) 홈 — 전환이 끝난 뒤. 같은 락업이 위로 올라가 있어야 한다.
	#   ⚠_logo_done은 이제 컷이 아니라 **미끄러짐을 시작**한다(menu_intro) — 그대로 찍으면 로고가
	#     아직 옛 자리에 있는 프레임이 잡혀 이 도구가 "안 움직였다"고 잘못 말한다. 여기선 끝난 상태를 본다.
	#     미끄러지는 도중은 tools/logo_slide_shot.gd 몫이다.
	g.call("_logo_done")
	g.set("menu_intro", -1.0)
	await _shot("b2_home.png")

	print("mode_after=", g.get("mode"), " logo_t=", g.get("logo_t"))
	print("DONE")
	quit()
