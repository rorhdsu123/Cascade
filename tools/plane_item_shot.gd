extends SceneTree
# 아이템 칸(유도 비행기) UI 캡처 — 창 모드 필수. 적립 0/1/3 상태 + 발사 후 비행 프레임.
# 실행: godot --path . --script tools/plane_item_shot.gd

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/9aa1040a-4815-47c9-bf15-fb86bb7329a3/scratchpad/item"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame
	main.set("intro_t", -1.0)
	main.set_process(false)
	# 적 몇 마리(발사 표적용)
	main.set("enemies", [
		{"col": 3, "row": main.ROWS - 6, "vis_row": float(main.ROWS - 6), "hp": 60, "maxhp": 60, "etype": "basic", "id": 501, "step_every": 3},
		{"col": 6, "row": main.ROWS - 2, "vis_row": float(main.ROWS - 2), "hp": 60, "maxhp": 60, "etype": "basic", "id": 502, "step_every": 3},
	])

	main.set("planes_banked", 0)
	await _grab("bank0")
	main.set("planes_banked", 1)
	await _grab("bank1")
	main.set("planes_banked", 3)
	main.set("plane_bank_pulse", 0.6)   # 방금 적립 반짝
	await _grab("bank3_pulse")
	main.set("plane_bank_pulse", 0.0)
	await _grab("bank3")

	# 발사 → 비행 중 프레임
	main.call("_fire_banked_plane")
	for i in range(10):
		main.call("_process", 0.02)
	await _grab("inflight")

	print("DONE seekers=", (main.get("seekers") as Array).size(), " banked=", main.get("planes_banked"))
	quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
