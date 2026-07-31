extends SceneTree
# 클리어 결과 팝업 입력 검증 — 성적을 걷어내며 클리어 전용 패널(짧은 카드)로 갈렸다.
#   버튼 좌표는 _result_layout() 단일 출처지만, '클리어 분기'는 이 경로로만 지나가므로 따로 못 박는다.
# 실행: godot --headless --path . --script tools/clear_result_input.gd

func _init() -> void:
	var S: GDScript = load("res://Main.gd")

	# ── A. 클리어 → [다음 스테이지] 클릭 → 다음 판으로 진입
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(3)
	g.set_process(false)
	g.killed = int(g.st["total"])
	g.leaked = 0
	g.game_clear = true
	g.clear_show_t = 1000.0        # 무대 끝난 뒤(팝업 활성)
	g.result_t = 1.0              # 버튼까지 개봉 완료
	var lay: Dictionary = g._result_layout()
	print("[A] revivable=%s (클리어니 false여야)  패널h=%d" % [lay["revivable"], int((lay["panel"] as Rect2).size.y)])
	var cc: InputEventMouseButton = InputEventMouseButton.new()
	cc.position = (lay["retry"] as Rect2).get_center()
	cc.button_index = MOUSE_BUTTON_LEFT
	cc.pressed = true
	g._input(cc)
	print("    다음스테이지 클릭 → stage_idx=%d game_clear=%s (4/false 여야)" % [g.stage_idx, g.game_clear])

	# ── B. 클리어 → [홈] 클릭 → 허브
	var g2: Node = S.new()
	root.add_child(g2)
	await process_frame
	g2._start_stage(3)
	g2.set_process(false)
	g2.killed = int(g2.st["total"])
	g2.game_clear = true
	g2.clear_show_t = 1000.0
	g2.result_t = 1.0
	var lay2: Dictionary = g2._result_layout()
	var hc: InputEventMouseButton = InputEventMouseButton.new()
	hc.position = (lay2["home"] as Rect2).get_center()
	hc.button_index = MOUSE_BUTTON_LEFT
	hc.pressed = true
	g2._input(hc)
	print("[B] 홈클릭 → mode=%s (menu여야)" % g2.mode)

	# ── C. 무대 재생 중엔 같은 좌표를 눌러도 아무 일이 없어야 한다(스킵 제거 + 입력 삼킴)
	var g3: Node = S.new()
	root.add_child(g3)
	await process_frame
	g3._start_stage(3)
	g3.set_process(false)
	g3.killed = int(g3.st["total"])
	g3.game_clear = true
	g3.clear_show_t = -g3.CLEAR_HOLD   # 프리롤 = 무대 재생 중
	g3.result_t = -1.0
	var lay3: Dictionary = g3._result_layout()
	var sc: InputEventMouseButton = InputEventMouseButton.new()
	sc.position = (lay3["retry"] as Rect2).get_center()
	sc.button_index = MOUSE_BUTTON_LEFT
	sc.pressed = true
	g3._input(sc)
	print("[C] 무대중 버튼자리 클릭 → stage_idx=%d clear_show_t=%.2f (3/음수 유지여야 = 안 잘리고 안 넘어감)"
			% [g3.stage_idx, g3.clear_show_t])
	print("DONE")
	quit()
