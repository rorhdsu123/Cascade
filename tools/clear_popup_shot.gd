extends SceneTree
# 클리어 결과 팝업 렌더 — 성적을 걷어내고 패널을 조인 뒤(460×330) 두 변형을 확인한다:
#   ① 일반 클리어(헤드라인 + 버튼만)  ② 프런티어(마지막 판: 헤드라인 + 안내 한 줄 + 버튼)
#   개봉 단계도 함께 본다(카드만 / 카드+헤드라인 / 전부). 창 모드 필수.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/309ebea2-5f92-4557-9f51-4e014e6e67d6/scratchpad/cpop"
var main: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var total: int = int(main.get("STAGES").size())
	for job in [[3, "mid"], [total - 1, "frontier"]]:
		var idx: int = int(job[0])
		var tag: String = String(job[1])
		paused = false
		main.call("_start_stage", idx)
		await process_frame
		var st: Dictionary = main.get("st")
		main.set("killed", int(st["total"])); main.set("leaked", 0)
		main.set("game_over", false); main.set("game_clear", true)
		main.set("clear_show_t", 1000.0)   # 무대는 끝난 상태(팝업만 본다)
		main.set("confetti", [])
		main.set("intro_t", -1.0)
		paused = true
		for t in [0.10, 0.20, 0.40, 1.00]:
			main.set("result_t", t)
			main.call("queue_redraw")
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s_%s_%03d.png" % [OUT, tag, int(t * 100.0)])
		print("shots done: ", tag)
	print("DONE"); quit()
