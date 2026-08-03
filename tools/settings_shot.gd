extends SceneTree
# 설정 모달 창 스모크 + 픽셀검증. [[godot-pixel-verify-needs-window]] 창 필수.
#   godot --path . --script tools/settings_shot.gd -- <출력디렉터리>
# ⚠출력 경로를 상수로 박지 말 것 — 예전엔 어느 세션의 스크래치패드가 박혀 있어 다른 데서
#   돌리면 조용히 저장만 실패했다. 인자로 받고, 없으면 저장소 안 build/로 떨어뜨린다.

var out_dir: String = ""

func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = a[0] if a.size() > 0 else "res://build/settings_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not out_dir.ends_with("/"):
		out_dir += "/"
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _shot(name: String) -> void:
	if _headless():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name)

# 기어로 모달 열기. 인트로 카드를 먼저 끄는 게 핵심 — 재시작하면 인트로가 다시 켜지므로
#   '한 번만' 꺼서는 뒤쪽 검증이 조용히 헛돈다(실제로 AFTER HOME이 늘 통과처럼 보였다).
func _open_settings(g: Node, gear: Rect2) -> void:
	g.set("intro_t", -1.0)
	_click(g, gear.position + gear.size * 0.5)

func _click(g: Node, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.call("_input", ev)

func _run() -> void:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame

	# 스테이지 진입(중간 스테이지 = 콤보 표시가 뜰 여지도 확인)
	g.call("_start_stage", 2)
	await process_frame
	# ⚠인트로 카드를 먼저 꺼야 한다 — 켜져 있으면 _input의 첫 분기가 클릭을 '인트로 건너뛰기'로
	#   먹어치워서 기어를 눌러도 모달이 안 열린다. 이것 때문에 이 도구가 조용히 무력했다.
	g.set("intro_t", -1.0)
	# 실유저 설정을 떠 둔다 — 끝에서 되돌린다(아래 RESTORED 참조).
	var sound0: bool = bool(g.get("sound_on"))
	var haptic0: bool = bool(g.get("haptic_on"))
	print("PLAY: mode=%s settings_open=%s sound=%s haptic=%s" % [
		g.get("mode"), str(g.get("settings_open")), str(g.get("sound_on")), str(g.get("haptic_on"))])
	g.call("queue_redraw")
	await _shot("set_1_play_gear.png")   # 우상단 기어가 보이는가

	# 기어 클릭 → 모달 열림
	var gear: Rect2 = g.get("gear_rect")
	_open_settings(g, gear)
	await process_frame
	print("AFTER GEAR: settings_open=%s" % str(g.get("settings_open")))
	g.call("queue_redraw")
	await _shot("set_2_modal.png")       # 모달(소리 ON·진동 ON) — 토글은 둘뿐이어야 한다

	# 레이아웃 좌표 획득
	var lay: Dictionary = g.call("_settings_layout")

	# 소리 토글 클릭 → true→false
	_click(g, (lay["sound_tog"] as Rect2).get_center())
	await process_frame
	# 진동 토글 클릭 → true→false
	_click(g, (lay["haptic_tog"] as Rect2).get_center())
	await process_frame
	print("AFTER TOGGLES: sound=%s haptic=%s" % [str(g.get("sound_on")), str(g.get("haptic_on"))])
	g.call("queue_redraw")
	await _shot("set_3_toggled.png")     # 둘 다 OFF 로 뒤집힘

	# 닫기(X) → 모달 닫힘
	_click(g, (lay["close"] as Rect2).get_center())
	await process_frame
	print("AFTER CLOSE: settings_open=%s" % str(g.get("settings_open")))

	# 다시 열어 '재시작' 버튼 → 같은 스테이지 재시작(mode 유지 play, killed 리셋)
	_open_settings(g, gear)
	await process_frame
	g.set("killed", 7)   # 재시작이 판을 초기화하는지 표시
	_click(g, (lay["replay_btn"] as Rect2).get_center())
	await process_frame
	print("AFTER REPLAY: mode=%s settings_open=%s killed=%s" % [
		g.get("mode"), str(g.get("settings_open")), str(g.get("killed"))])

	# 다시 열어 '메뉴로' → 허브로 빠진다
	_open_settings(g, gear)
	await process_frame
	print("REOPENED FOR HOME: settings_open=%s" % str(g.get("settings_open")))
	_click(g, (lay["home_btn"] as Rect2).get_center())
	await process_frame
	print("AFTER HOME: mode=%s settings_open=%s" % [g.get("mode"), str(g.get("settings_open"))])

	# ⚠원상복구 — 이 도구는 토글을 진짜로 누르므로 `user://settings.save`가 실제로 덮인다.
	#   persist_enabled 가드는 여기선 안 걸린다(Main.tscn을 instantiate + await 하므로 _ready가
	#   돌아 true가 된다). 그래서 손으로 되돌린다. 안 하면 유저 소리·진동이 프로브 때문에 꺼진다.
	g.set("sound_on", sound0)
	g.set("haptic_on", haptic0)
	g.call("_save_settings")
	print("RESTORED: sound=%s haptic=%s" % [str(g.get("sound_on")), str(g.get("haptic_on"))])

	quit()
