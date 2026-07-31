extends SceneTree
# 클리어 축하 무대 검증 — 암전 진행 + 워드마크 등장을 시점별로 캡처. 창 모드 필수.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/da1f7fc4-8514-4560-89c7-00eb54dcada2/scratchpad/stage"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	main.call("_start_stage", 3)
	await process_frame
	# 클리어 상태로 못 박고, 무대 타이머만 수동으로 돌린다(연출만 검증 — 판정 경로는 건드리지 않음)
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"])); main.set("leaked", 0)
	main.set("game_over", false); main.set("game_clear", true)
	main.set("confetti", [])          # 색종이는 이 단계 검증 대상이 아니라 로고를 가리기만 한다
	# ⚠트리를 멈추지 않으면 캡처 사이의 await마다 _process가 돌아 타이머가 흘러버린다
	#   (0.0을 세팅해도 그릴 땐 0.25였다). 그리기는 pause와 무관하게 동작한다.
	paused = true

	for t in [0.02, 0.10, 0.18, 0.26, 0.34, 0.46, 0.58, 0.68, 0.78, 0.88, 1.05, 1.40]:
		main.set("clear_show_t", t)
		main.call("queue_redraw")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_%03d.png" % [OUT, int(t * 100.0)])
		print("shot t=", t)

	# 스킵 후 결과 팝업이 정상적으로 뜨는지(무대가 팝업을 영구히 막지 않는지) 확인
	paused = false
	main.set("clear_show_t", 2.0)
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_after.png" % OUT)
	print("shot after")
	print("DONE"); quit()
