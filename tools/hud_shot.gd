extends SceneTree
# 플레이 HUD 자잘 감사 — 캠페인·무한, 콤보 켬. 창 모드 필수.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/5e850407-1b82-4a53-a146-054a00f1d333/scratchpad/hud"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# 캠페인 stage 0, 콤보 3, 임박(remain=1) 상황
	main.call("_start_stage", 0)
	await process_frame
	main.set("combo", 3)
	main.set("killed", 6)
	main.set("place_count", 2)   # step_every=3 → remain=1(임박)
	await _grab("campaign")

	# 캠페인 영어 로케일 + remain>1(복수 'turns') 확인
	main.set("_locale", "en")
	main.set("combo", 5)
	main.set("place_count", 0)   # remain = step_every(=3) → 복수
	await _grab("campaign_en")

	# 무한, 콤보 4, 점수 있음
	main.set("_locale", "ko")
	main.call("_start_endless")
	await process_frame
	main.set("combo", 4)
	main.set("endless_score", 1240)
	main.set("endless_best", 3200)
	main.set("place_count", 5)
	await _grab("endless")

	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
