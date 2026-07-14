extends SceneTree
# 실패 헤드라인 3단계 렌더 — 남은 적 비율에 따라 말이 갈리는 게 실제로 읽히는지.
# 실행: godot --path . --script tools/fail_headline.gd  (창 모드 필수)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/98a1100f-49fc-42c1-9cb4-a221c1201840/scratchpad/hl"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# total=20 기준. 남은 적 2(10%) / 7(35%) / 15(75%)
	for spec in [[18, 0, "close"], [13, 0, "near"], [5, 0, "far"]]:
		main.call("_start_stage", 0)
		await process_frame
		main.set("killed", int(spec[0]))
		main.set("leaked", int(spec[1]))
		main.set("stuck", false)
		main.set("game_over", true)
		var st: Dictionary = main.get("st")
		var total: int = int(st["total"])
		var rem: int = total - int(spec[0]) - int(spec[1])
		print("남은 적 %2d/%d (%3.0f%%) → \"%s\""
				% [rem, total, 100.0 * float(rem) / float(total), main.call("_fail_headline")])
		await _grab(String(spec[2]))

	print("DONE")
	quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
