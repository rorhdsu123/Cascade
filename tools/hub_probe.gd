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
	# ⚠실유저 진행도 보호(C100 확장): 이 probe는 Main.tscn을 띄우므로 _ready가 돌아
	#   persist_enabled=true가 된다. 아래서 cleared를 주입하거나 봇이 스테이지를 깨면 그 값이
	#   **실제 campaign.save에 각인**된다(전 스테이지 주입 = 16383 = "진행도가 저절로 전승됨"의 진범).
	#   C100은 campaign_flow.gd만 막았고 나머지 창 모드 probe는 새고 있었다 → 여기서 끈다.
	g.set("persist_enabled", false)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1280))
	await process_frame
	await process_frame

	var ADV: Rect2 = g.get("MENU_ADV_BTN")
	var CLASSIC: Rect2 = g.get("MENU_CLASSIC_BTN")
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

	# ⚠기대값 갱신(C92): Adventure는 판으로 직행하지 않는다. 허브 → 진행 리드아웃(select)이고
	#   실제 진입은 그 화면의 프런티어 버튼 몫 — 판 직행·타일 선택·재플레이는 폐기됐다.
	#   (여기 기대가 stage0/stage3으로 남아 C92 이후 계속 빨간 채였다. 코드가 아니라 프로브가 낡음.)
	print("── 신규: Adventure는 진행 화면(select)으로 ──")
	await _hub({})
	await _click(ADV)
	_check("Adventure 클릭", _state(), "select")
	await _hub({})
	await _key(KEY_SPACE)
	_check("SPACE", _state(), "select")

	print("── 스테이지1 클리어 후: 무한 해금 + Adventure는 여전히 진행 화면 ──")
	await _hub({0: true})
	await _click(CLASSIC)
	_check("무한 버튼(해금)", _state(), "endless")
	await _hub({0: true, 1: true, 2: true})
	await _click(ADV)
	_check("Adventure(3개 깸)", _state(), "select")

	print("── 전부 깸: 반복 재도전 대신 목록 ──")
	var all_c: Dictionary = {}
	for i in range(8):
		all_c[i] = true
	await _hub(all_c)
	await _click(ADV)
	_check("Adventure(전부 깸)", _state(), "select")

	print("── 기존 세이브 가드: 최고점이 있으면 잠기지 않는다 ──")
	await _hub({})
	g.set("endless_best", 8420)   # 잠금 도입 전에 무한을 해본 설치
	await _click(CLASSIC)
	_check("최고점 보유 → 해금", _state(), "endless")

	# 진입 스위치(Main.LEADERBOARD_ENABLED)를 따라 기대를 뒤집는다 — 껐으면 '안 열리는 것'이 정답.
	#   상수를 못 읽어오는 경우는 없다(const도 get으로 읽힌다). 켜면 원래 검사로 자동 복귀.
	var lb_on: bool = bool(g.get("LEADERBOARD_ENABLED"))
	print("── 리더보드 진입(트로피): 스위치=%s ──" % ("ON" if lb_on else "OFF"))
	await _hub({})
	await _click(LB)
	_check("트로피", _state(), "leaderboard" if lb_on else "menu")
	await _hub({})
	await _key(KEY_L)
	_check("키보드 L", _state(), "leaderboard" if lb_on else "menu")

	print("\nRESULT: %s (실패 %d)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit()
