extends SceneTree
# 터치→마우스 에뮬레이션 end-to-end 검증. [[godot-pixel-verify-needs-window]] 창 필수.
#   godot --path . --script tools/touch_probe.gd
# InputEventScreenTouch/Drag를 Input.parse_input_event로 흘려, emulate_mouse_from_touch가
# 마우스 이벤트를 합성해 기존 _input(집기/드래그/놓기)이 반응하는지 확인. 반응하면 ScreenDrag 재작성 불필요.
#
# ⚠**두 경로를 따로 잰다**(C189). C183 이후 `click_mode`의 기본값이 기기마다 갈린다 —
#   `show_input_toggle = not OS.has_feature("mobile")`이고 `click_mode = show_input_toggle`이라
#   **PC는 클릭 배치, 모바일은 드래그**다. 데스크톱에서 돌리는 프로브가 드래그만 재면 실제 PC 기본
#   경로를 한 번도 안 밟고, 반대로 클릭만 재면 **출시 대상인 모바일 경로**를 안 밟는다. 둘 다 밟는다.
#
# ⚠**인트로 카드가 첫 누름을 삼킨다**(C74). 캠페인 진입은 `intro_t >= 0`으로 시작하고, 그동안 들어온
#   누름은 '스킵'으로 소비된 뒤 `return`한다 — 판 입력이 아니다. 옛 프로브는 이걸 안 넘겨서
#   집기 누름이 스킵에 먹혔고, **게임이 멀쩡한데 프로브만 빨간불**이었다(2026-08-13 진단).
#   원인은 게임 회귀가 아니라 **하네스가 게임 상태를 안 기다린 것**이다 — 그래서 아래 `_await_playable`이
#   측정 전에 판 입력이 실제로 열렸는지부터 확인하고, 그 확인 자체를 하나의 검사 항목으로 찍는다.

const TIMEOUT_FRAMES: int = 600

var _fail: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

# ---- 입력 합성 ----

func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame
	await process_frame

func _drag(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)
	await process_frame
	await process_frame

# ---- 상태 ----

func _filled(g: Node) -> int:
	var b: Array = g.get("board")
	var n: int = 0
	for r in b:
		for c in r:
			if c != "":
				n += 1
	return n

# 인트로 카드와 resolve 연출이 끝나 **판 입력이 실제로 받아지는 상태**까지 기다린다.
# 여기서 안 기다리면 뒤의 모든 측정이 "입력이 삼켜진 것"과 "게임이 반응 안 한 것"을 구분 못 한다.
func _await_playable(g: Node) -> bool:
	var i: int = 0
	while i < TIMEOUT_FRAMES:
		if float(g.get("intro_t")) < 0.0 and not bool(g.get("resolving")):
			return true
		await process_frame
		i += 1
	return false

# 조각을 든 채 후보 칸을 훑어 **놓을 수 있는 자리**를 찾는다. 조각 모양(I5h·R23…)이 배급마다
# 달라서 좌표를 박아두면 프로브가 조각 운에 따라 깜빡인다.
func _drag_to_placeable(g: Node, from: Vector2) -> Vector2:
	var prev: Vector2 = from
	for row in range(ROWS_MAX):
		for col in range(COLS_MAX):
			var p: Vector2 = g.call("_cell_center", col, row)
			await _drag(p, p - prev)
			prev = p
			if bool(g.call("_can_place", g.call("_ghost_cells"))):
				return p
	return Vector2(-1, -1)

# 클릭 경로엔 **이동이 없다** — 보드를 탭하는 순간 그 좌표로 hover를 세우고 바로 판정한다
# (`_input`의 click_mode 분기). 그래서 목표 칸은 포인터를 끌지 말고 상태로 찾아야 한다.
# 끌기로 찾으면 실제 경로에 없는 이동을 요구하게 되고, 그게 C189 이전 프로브의 두 번째 오진이었다.
func _find_placeable(g: Node) -> Vector2:
	for row in range(ROWS_MAX):
		for col in range(COLS_MAX):
			var p: Vector2 = g.call("_cell_center", col, row)
			g.set("drag_pos", p)
			g.call("_sync_hover_from_drag")
			if bool(g.call("_can_place", g.call("_ghost_cells"))):
				return p
	return Vector2(-1, -1)

const COLS_MAX: int = 8
const ROWS_MAX: int = 8

func _ck(cond: bool, label: String) -> void:
	if not cond:
		_fail.append(label)
	print("  %s %s" % ["ok  " if cond else "FAIL", label])

# ---- 케이스 ----

# 모바일 기본 경로: 집어서 → 끌고 → **뗄 때** 놓인다.
func _case_drag(g: Node) -> void:
	print("[drag] 모바일 기본 경로 (click_mode=false)")
	g.set("show_input_toggle", false)   # 모바일엔 토글 버튼이 없다 = 히트 영역도 없다
	g.set("click_mode", false)

	var before: int = _filled(g)
	var start: Vector2 = (g.call("_tray_slot_rect", 0) as Rect2).get_center()
	await _touch(start, true)
	_ck(bool(g.get("dragging")), "터치 누름으로 조각이 집힌다 (dragging=true)")

	var target: Vector2 = await _drag_to_placeable(g, start)
	_ck(target.x >= 0.0, "끌기가 hover에 반영돼 놓을 자리를 찾는다")
	if target.x < 0.0:
		return

	await _touch(target, false)
	_ck(not bool(g.get("dragging")), "뗄 때 손에서 놓인다 (dragging=false)")
	_ck(_filled(g) > before, "보드에 실제로 놓였다 (filled %d → %d)" % [before, _filled(g)])

# PC 기본 경로: 조각을 클릭해 집고 → 보드를 클릭해 놓는다. 떼기는 안 쓴다.
func _case_click(g: Node) -> void:
	print("[click] PC 기본 경로 (click_mode=true)")
	g.set("show_input_toggle", true)
	g.set("click_mode", true)

	var before: int = _filled(g)
	var start: Vector2 = (g.call("_tray_slot_rect", 0) as Rect2).get_center()
	await _touch(start, true)
	await _touch(start, false)   # 클릭 경로는 떼기를 무시한다 — 여기서 안 풀리는 게 정상이다
	_ck(bool(g.get("dragging")), "탭으로 조각이 집힌다 (dragging=true)")

	var target: Vector2 = await _find_placeable(g)
	_ck(target.x >= 0.0, "든 조각을 놓을 자리가 판에 있다")
	if target.x < 0.0:
		return

	await _touch(target, true)    # 놓기는 **누름**에서 확정된다
	_ck(not bool(g.get("dragging")), "보드 탭으로 놓인다 (dragging=false)")
	_ck(_filled(g) > before, "보드에 실제로 놓였다 (filled %d → %d)" % [before, _filled(g)])
	await _touch(target, false)

# ---- 실행 ----

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(800, 1400))
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame

	# ── 기본값부터 찍는다 ──────────────────────────────────────────────
	# 아래 두 케이스는 `click_mode`를 **강제로** 세워놓고 각 경로를 밟는다 — 즉 "두 경로가 동작하나"만
	# 본다. 정작 2026-08-14에 아이폰에서 터진 건 경로가 아니라 **어느 경로가 기본으로 잡히나**였다
	# (웹 export는 `has_feature("mobile")`이 거짓이라 폰에서 PC 분기를 탔다). 그 값은 기기마다
	# 다르므로 여기선 판정하지 않고 **찍기만 한다** — 이 줄이 없으면 다음에 또 안 보인다.
	print("[기본값] is_touch_device=%s show_input_toggle=%s click_mode=%s (%s / touchscreen=%s)" % [
			g.get("is_touch_device"), g.get("show_input_toggle"), g.get("click_mode"),
			OS.get_name(), DisplayServer.is_touchscreen_available()])
	_ck(bool(g.get("click_mode")) == bool(g.get("show_input_toggle")),
			"기본 입력 방식이 기기 판정과 일치한다 (click_mode == show_input_toggle)")
	_ck(not (bool(g.get("is_touch_device")) and bool(g.get("show_input_toggle"))),
			"터치 기기엔 PC 전용 입력 토글을 안 그린다")

	for case_name in ["drag", "click"]:
		g.call("_start_stage", 0)
		await process_frame
		await process_frame
		# 인트로 카드를 **의도적으로** 한 번 눌러 넘긴다 — 이 누름은 판 입력이 아니다.
		if float(g.get("intro_t")) >= 0.0:
			await _touch(Vector2(400, 700), true)
			await _touch(Vector2(400, 700), false)
		var ready: bool = await _await_playable(g)
		_ck(ready, "[%s] 인트로·resolve가 끝나 판 입력이 열렸다" % case_name)
		if not ready:
			continue
		if case_name == "drag":
			await _case_drag(g)
		else:
			await _case_click(g)

	var ok: bool = _fail.is_empty()
	print("")
	if not ok:
		print("실패 %d건: %s" % [_fail.size(), ", ".join(_fail)])
	print("TOUCH_EMULATION_OK=%s" % str(ok))
	quit(0 if ok else 1)
