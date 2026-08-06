extends SceneTree
# 버튼 눌림 규칙 검증(C144). 세 가지를 한꺼번에 본다:
#   ① 마우스를 올리기만 하면 아무 일도 없다(옛 호버 반응 제거 — PC도 폰과 같은 규칙)
#   ② 누르면 눌린 그림이 켜지고 **동작은 아직 안 한다**(그래서 눌린 프레임이 실제로 그려진다)
#   ③ 뗄 때 발동. 누른 채 밖으로 끌고 떼면 취소.
#   godot --path . --script tools/press_probe.gd
var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, got, want) -> void:
	if got != want:
		fails += 1
	print("%s %-42s %s (기대 %s)" % ["OK  " if got == want else "FAIL", tag, got, want])

func _dy() -> Vector2:
	return Vector2(0.0, g.call("_ui_dy"))

func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	g.call("_input", ev)

func _btn(p: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = p
	g.call("_input", ev)

func _run() -> void:
	var scn: PackedScene = load("res://Main.tscn")
	g = scn.instantiate()
	root.add_child(g)
	await process_frame

	# ── 허브: Adventure 버튼 ── 누름=그림만, 뗌=발동
	g.set("mode", "menu")
	var adv: Rect2 = g.get("MENU_ADV_BTN")
	var c: Vector2 = adv.get_center() + _dy()

	_move(c)
	_check("허브: 올리기만 → 눌림 아님", bool(g.get("_adv_hover")), false)
	_btn(c, true)
	_check("허브: 누름 → 눌림", bool(g.get("_adv_hover")), true)
	_check("허브: 누름만으론 화면 안 바뀜", String(g.get("mode")), "menu")
	_btn(c, false)
	_check("허브: 뗌 → 발동", String(g.get("mode")), "select")
	await process_frame   # 지연 해제(_clear_btn_hot)가 도는 프레임
	_check("허브: 뗀 뒤 → 원복", bool(g.get("_adv_hover")), false)

	# ── 취소: 누른 채 버튼 밖으로 끌고 뗌 ──
	g.set("mode", "menu")
	_btn(c, true)
	_check("취소: 누름 → 눌림", bool(g.get("_adv_hover")), true)
	_move(c + Vector2(0.0, 500.0))
	_check("취소: 밖으로 끌면 → 그림 풀림", bool(g.get("_adv_hover")), false)
	_btn(c + Vector2(0.0, 500.0), false)
	_check("취소: 밖에서 뗌 → 발동 안 함", String(g.get("mode")), "menu")
	await process_frame

	# ── 진행 화면: 목록을 끌다 버튼 위를 지나가도 안 눌린다 ──
	g.set("mode", "select")
	# ⚠실유저 진행도를 타면 안 된다 — 전 스테이지 클리어 상태면 시작 버튼이 정상적으로 죽어 있어서
	#   (`_all_cleared()` 게이트) 눌림 검사가 통째로 거짓 FAIL이 난다. 세션 메모리만 비운다(저장 안 함).
	g.set("cleared", {})
	var play: Rect2 = g.get("PLAY_BTN")
	var pc: Vector2 = play.get_center() + _dy()
	_btn(Vector2(pc.x, pc.y - 400.0), true)   # 그리드에서 누르기 시작(드래그 스크롤)
	_move(pc)
	_check("select: 딴 데서 눌러 지나감 → 안 눌림", bool(g.get("_play_hover")), false)
	_btn(pc, false)
	_check("select: 그 상태로 뗌 → 발동 안 함", String(g.get("mode")), "select")
	await process_frame
	_btn(pc, true)
	_check("select: 시작 누름 → 눌림", bool(g.get("_play_hover")), true)
	_check("select: 누름만으론 판 시작 안 함", String(g.get("mode")), "select")
	_btn(pc, false)
	_check("select: 뗌 → 판 시작", String(g.get("mode")), "play")
	await process_frame

	# ── 설정 모달: 소리 토글(눌러도 모달이 안 닫히는 행) ──
	g.set("settings_open", true)
	var was_sound: bool = bool(g.get("sound_on"))
	var st: Rect2 = (g.call("_settings_layout") as Dictionary)["sound_tog"]
	_move(st.get_center())
	_check("설정: 올리기만 → 눌림 아님", bool(g.get("_set_sound_hover")), false)
	_btn(st.get_center(), true)
	_check("설정: 누름 → 눌림", bool(g.get("_set_sound_hover")), true)
	_check("설정: 누름만으론 안 바뀜", bool(g.get("sound_on")), was_sound)
	_btn(st.get_center(), false)
	_check("설정: 뗌 → 토글됨", bool(g.get("sound_on")), not was_sound)
	await process_frame
	_btn(st.get_center(), true)   # 원복(세이브 오염 방지)
	_btn(st.get_center(), false)
	await process_frame
	g.set("settings_open", false)

	# ── 플레이 중 기어: 누름은 삼키고(조각 집기로 안 샘) 뗄 때 열린다 ──
	g.set("mode", "play")
	g.set("intro_t", -1.0)   # 인트로 재생 중이면 _input이 먼저 다 삼킨다(스킵 경로)
	var gr: Rect2 = g.get("gear_rect")
	_move(gr.get_center())
	_check("기어: 올리기만 → 눌림 아님", bool(g.get("_gear_hover")), false)
	_btn(gr.get_center(), true)
	_check("기어: 누름 → 눌림", bool(g.get("_gear_hover")), true)
	_check("기어: 누름만으론 안 열림", bool(g.get("settings_open")), false)
	_check("기어: 누름이 조각 집기로 안 샘", bool(g.get("dragging")), false)
	_btn(gr.get_center(), false)
	_check("기어: 뗌 → 설정 열림", bool(g.get("settings_open")), true)

	print("\n%s  (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
