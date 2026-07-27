extends SceneTree
# 크로스(행+열 동시 클리어) 관통 십자 빔 미리보기 캡처. 창 모드 필수.
# 실행: godot --path . --script tools/cross_shot.gd

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/efe67560-638a-4d54-b126-9957c48f7dbb/scratchpad/cross"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 4)   # S5 = 장갑(tank) 도입 스테이지 맥락
	await process_frame
	main.set("intro_t", -1.0)      # 인트로 카드가 보드를 가리지 않게 끔
	main.set_process(false)
	# 교차점(col4,row3)에 장갑 + 행/열 팔에 기본적 + 라인 밖 생존자
	main.set("enemies", [
		{"col": 4, "row": 3, "vis_row": 3.0, "hp": 400, "maxhp": 400, "etype": "tank", "id": 1, "step_every": 3},
		{"col": 4, "row": 1, "vis_row": 1.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 2, "step_every": 3},
		{"col": 4, "row": 6, "vis_row": 6.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 3, "step_every": 3},
		{"col": 1, "row": 3, "vis_row": 3.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 4, "step_every": 3},
		{"col": 7, "row": 3, "vis_row": 3.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 5, "step_every": 3},
		{"col": 1, "row": 6, "vis_row": 6.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 6, "step_every": 3},
	])
	main.set("combo", 1)          # lanes_n=1 → 딱 행1+열1 = 깨끗한 십자
	main.set("last_color", "B")
	main.call("_begin_resolve", [3], [4])
	# 크로스 빔이 뜨는 순간부터 페이드까지 촘촘히 캡처
	var shots := {"a": 0.30, "b": 0.40, "c": 0.50, "d": 0.62, "e": 0.80}
	var elapsed := 0.0
	var order := ["a", "b", "c", "d", "e"]
	var idx := 0
	for _i in range(120):
		main.call("_process", 0.02)
		elapsed += 0.02
		if idx < order.size() and elapsed >= shots[order[idx]]:
			await _grab(order[idx])
			idx += 1
	print("DONE beams_left=", (main.get("cross_beams") as Array).size())
	quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
