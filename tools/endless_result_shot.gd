extends SceneTree
# 무한(점수) 결과 팝업 렌더 — 주 CTA를 전 상태 공통 자리로 옮긴 뒤(RESULT_CTA) 이 상태도
#   내용과 버튼이 안 겹치는지 확인한다. 캠페인과 달리 캡션·최고기록 숫자가 버튼 바로 위에 온다.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/309ebea2-5f92-4557-9f51-4e014e6e67d6/scratchpad/eres"
var main: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# [점수, 최고, 부활사용, 라벨] — 신기록 / 최고까지 N점 두 갈래
	for job in [[12400, 9000, false, "record"], [5200, 9000, true, "gap"]]:
		paused = false
		main.call("_start_endless")
		await process_frame
		main.set("endless_score", int(job[0]))
		main.set("endless_best", int(job[1]))
		main.set("endless_prev_best", int(job[1]))
		main.set("revive_used", bool(job[2]))
		main.set("game_over", true)
		main.set("stuck", false)
		main.set("result_t", 1.0)
		paused = true
		main.call("queue_redraw")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_%s.png" % [OUT, String(job[3])])
		print("shot ", job[3])
	print("DONE"); quit()
