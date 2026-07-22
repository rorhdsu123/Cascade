extends SceneTree
# 허브 개편(C80) 검증 — 무한 잠금이 새는 뒷문이 없는지 + Adventure 이어하기 목적지.
#   godot --path . --script tools/hub_probe.gd
var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, got: String, want: String) -> void:
	var ok: bool = got == want
	if not ok:
		fails += 1
	print("%s %-34s %s (기대 %s)" % ["OK  " if ok else "FAIL", tag, got, want])

func _dy() -> Vector2:
	return Vector2(0.0, g.call("_ui_dy"))

func _click(r: Rect2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = r.get_center() + _dy()
	g.call("_input", ev)
	await process_frame

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	g.call("_input", ev)
	await process_frame

# 현재 상태를 한 문자열로: 모드(+무한이면 endless, 스테이지면 인덱스)
func _state() -> String:
	if bool(g.get("settings_open")):
		return "settings"
	var m: String = String(g.get("mode"))
	if m != "play":
		return m
	return "endless" if bool(g.get("endless")) else "stage%d" % int(g.get("stage_idx"))

func _hub(cleared_map: Dictionary) -> void:
	g.set("cleared", cleared_map)
	g.set("endless_best", 0)   # 로컬 세이브 값이 잠금 판정에 새지 않게 격리(기존세이브 가드는 따로 검사)
	g.set("dev_unlock_all", false)
	g.set("settings_open", false)
	g.set("mode", "menu")
	await process_frame

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame

	var ADV: Rect2 = g.get("MENU_ADV_BTN")
	var CHIP: Rect2 = g.get("MENU_STAGES_BTN")
	var CLASSIC: Rect2 = g.get("MENU_CLASSIC_BTN")
	var GEAR: Rect2 = g.get("MENU_GEAR_BTN")
	var LB: Rect2 = g.get("MENU_LB_BTN")
	var LBPLAY: Rect2 = g.get("LB_PLAY_BTN")

	print("── 신규(스테이지1 미클리어): 무한은 모든 문이 잠겨야 ──")
	await _hub({})
	await _click(CLASSIC)
	_check("허브 무한 버튼", _state(), "menu")
	await _hub({})
	await _key(KEY_E)
	_check("키보드 E", _state(), "menu")
	await _hub({})
	await _key(KEY_0)
	_check("키보드 0", _state(), "menu")
	await _hub({})
	g.set("mode", "leaderboard")
	await _click(LBPLAY)
	_check("리더보드 CTA", _state(), "leaderboard")
	await _hub({})
	g.set("mode", "leaderboard")
	await _key(KEY_SPACE)
	_check("리더보드 SPACE", _state(), "leaderboard")

	print("── 신규: Adventure는 스테이지1(튜토리얼)로 바로 ──")
	await _hub({})
	await _click(ADV)
	_check("Adventure 클릭", _state(), "stage0")
	await _hub({})
	await _key(KEY_SPACE)
	_check("SPACE", _state(), "stage0")

	print("── 스테이지1 클리어 후: 무한 해금 + 이어하기 목적지 ──")
	await _hub({0: true})
	await _click(CLASSIC)
	_check("무한 버튼(해금)", _state(), "endless")
	await _hub({0: true, 1: true, 2: true})
	await _click(ADV)
	_check("이어하기(3개 깸 → 4번째)", _state(), "stage3")

	print("── 전부 깸: 반복 재도전 대신 목록 ──")
	var all_c: Dictionary = {}
	for i in range(8):
		all_c[i] = true
	await _hub(all_c)
	await _click(ADV)
	_check("Adventure(전부 깸)", _state(), "select")

	print("── 목록 칩 · 기어 · 설정 모달이 허브 입력을 막는가 ──")
	await _hub({0: true})
	await _click(CHIP)
	_check("스테이지 목록 칩", _state(), "select")
	# 신규(깬 판 0)엔 칩이 안 그려진다 → 그 자리를 눌러도 아무 일 없어야(유령 버튼 방지)
	await _hub({})
	await _click(CHIP)
	_check("신규: 칩 자리 무반응", _state(), "menu")
	await _hub({0: true})
	await _click(GEAR)
	_check("기어", _state(), "settings")
	await _click(CLASSIC)   # 모달이 떠 있는 동안 뒤 버튼이 눌리면 안 된다
	_check("모달 중 뒤 버튼 차단", _state(), "settings")
	var lay: Dictionary = g.call("_settings_layout")
	_check("허브 설정 = compact", str(bool(lay["compact"])), "true")
	_check("compact엔 홈 버튼 없음", str((lay["home_btn"] as Rect2).has_point(Vector2(400, 600))), "false")
	await _key(KEY_ESCAPE)
	_check("ESC로 모달 닫힘", _state(), "menu")

	print("── 기존 세이브 가드: 최고점이 있으면 잠기지 않는다 ──")
	await _hub({})
	g.set("endless_best", 8420)   # 잠금 도입 전에 무한을 해본 설치
	await _click(CLASSIC)
	_check("최고점 보유 → 해금", _state(), "endless")

	print("── 리더보드 진입(트로피)은 여전히 열려 있어야 ──")
	await _hub({})
	await _click(LB)
	_check("트로피", _state(), "leaderboard")

	print("\nRESULT: %s (실패 %d)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit()
