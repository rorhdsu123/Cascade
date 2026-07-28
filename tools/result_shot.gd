extends SceneTree
# 결과 팝업 캡처 — 광고 부활(C47) 3케이스. 창 모드 필수(헤드리스는 렌더 텍스처 null).
# 실행: godot --path . --script tools/result_shot.gd

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-plumbing/fd5e584d-b2cc-4e3d-b6e6-32854ef08700/scratchpad/res"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# ── 실패 + 부활 가능(거점 파괴·미사용): 광고 이어하기(주) + 재도전(부) + 홈
	main.call("_start_stage", 0)
	await process_frame
	main.set("killed", 6)
	main.set("leaked", 3)
	main.set("stuck", false)
	main.set("enemies", [{"col": 2, "row": 4, "vis_row": 4.0, "hp": 10, "maxhp": 10, "etype": "basic", "id": 1, "step_every": 3}])
	main.set("revive_used", false)
	main.set("game_over", true)
	await _grab("revive")

	# ── 광고 로드 대기(W2 R1): 버튼이 톤 다운 + ▶ 없이 '광고 불러오는 중'. 팝업 전체가 잠긴 상태.
	main.set("_ad_pending", true)
	await _grab("ad_pending")
	main.set("_ad_pending", false)

	# ── 실패 + 부활 불가(이미 사용): 재도전(주) + 홈
	main.set("revive_used", true)
	main.set("game_over", true)
	await _grab("used")

	# ── 클리어
	main.call("_start_stage", 0)
	await process_frame
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"]))
	main.set("leaked", 0)
	main.set("game_over", false)
	main.set("game_clear", true)
	await _grab("clear")

	print("DONE")
	quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
