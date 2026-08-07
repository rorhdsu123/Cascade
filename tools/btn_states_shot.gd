extends SceneTree
# 큰 버튼 3상태(기본·눌림·비활성)를 **한 프레임씩** 같은 자리에서 캡처한다.
#   godot --path . --script tools/btn_states_shot.gd -- <출력디렉터리>
#
# 왜 따로 필요한가 — art_frames.gd는 화면별 프레임이라 버튼이 늘 '기본' 상태로만 찍힌다.
#   상태 3종은 파일이 갈리는 축(btn_lg / btn_lg_press / btn_lg_off)이라 셋을 나란히 못 보면
#   납품본이 위계를 세우는지 판단이 안 된다(1차 납품에서 비활성이 눌림보다 밝게 온 걸 이걸로 잡았다).
#
# ⚠창 모드 필수 — --headless는 렌더 텍스처가 null이라 크래시한다.
# ⚠persist_enabled=false 필수 — 주입한 상태가 실유저 세이브에 각인되면 안 된다.

const ANIM_T: float = 12.345

var g: Node = null
var out_dir: String = ""

func _shot(name: String) -> void:
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.set("anim_t", ANIM_T)
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")
	g.process_mode = Node.PROCESS_MODE_INHERIT
	print("shot ", name)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	if uargs.is_empty():
		printerr("usage: godot --path . --script tools/btn_states_shot.gd -- <출력디렉터리>")
		quit(1)
		return
	out_dir = uargs[0]
	if not out_dir.ends_with("/"):
		out_dir += "/"
	DirAccess.make_dir_recursive_absolute(out_dir)

	g = load("res://Main.tscn").instantiate()
	g.get("_analytics").enabled = false   # ⚠_ready 전에 — 안 그러면 프로브가 실측 로그에 섞인다
	root.add_child(g)
	g.set("persist_enabled", false)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame
	g.set("_locale", "en")

	# ── 허브 주 버튼(모험) — 기본 / 눌림
	g.set("mode", "menu")
	g.set("cleared", {0: true, 1: true, 2: true})
	g.set("endless_best", 12480)
	g.set("_adv_hover", false)
	g.set("_classic_hover", false)
	await _shot("hub_normal")
	g.set("_adv_hover", true)
	await _shot("hub_press")
	g.set("_adv_hover", false)

	# ── 결과 팝업 광고 CTA — 기본 / 눌림 / 비활성(광고 로드 대기)
	#    이 버튼 하나가 세 상태를 다 지나는 유일한 자리다(_ad_pending이 비활성 축).
	g.set("mode", "play")
	g.call("seed_game", 424242)
	g.call("_start_stage", 3)
	g.set("persist_enabled", false)
	g.set("intro_t", -1.0)
	await process_frame
	g.set("game_over", true)
	g.set("revive_used", false)
	g.set("result_t", 99.0)
	g.set("_cont_hover", false)
	g.set("_ad_pending", false)
	await _shot("cta_normal")
	g.set("_cont_hover", true)
	await _shot("cta_press")
	g.set("_cont_hover", false)
	g.set("_ad_pending", true)
	await _shot("cta_off")

	print("DONE")
	quit()
