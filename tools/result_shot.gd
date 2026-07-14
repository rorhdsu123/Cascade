extends SceneTree
# 결과 팝업 현황 캡처 — 실패/클리어 두 장. 폴리싱 전 기준선.
# 실행: godot --path . --script tools/result_shot.gd   (창 모드 필수)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/98a1100f-49fc-42c1-9cb4-a221c1201840/scratchpad/res"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# ── 실패: 일부만 잡고 거점 파괴로 종료
	main.call("_start_stage", 0)
	await process_frame
	main.set("killed", 5)
	main.set("leaked", 2)
	main.set("stuck", false)
	main.set("game_over", true)
	var st: Dictionary = main.get("st")
	print("실패 — total=%d killed=5 leaked=2 → 남은 적 %d"
			% [int(st["total"]), int(st["total"]) - 7])
	await _grab("fail")

	# ── 클리어: 전부 처치
	main.call("_start_stage", 0)
	await process_frame
	st = main.get("st")
	main.set("killed", int(st["total"]))
	main.set("leaked", 0)
	main.set("game_over", false)
	main.set("game_clear", true)
	print("클리어 — killed=%d leaked=0" % int(st["total"]))
	await _grab("clear")

	print("DONE")
	quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
