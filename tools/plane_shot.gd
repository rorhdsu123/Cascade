extends SceneTree
# 비행기 아이템 시각 검증 — 보드 픽업 / 슬롯 보유 / 표적 조준링을 캡처. 창 모드 필수(헤드리스는 렌더 텍스처 null).
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/299f7101-5737-4dec-9e7a-ff0181c34c5a/scratchpad/plane"
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 3)
	await process_frame
	main.set("intro_t", -1.0)   # ⚠인트로 카드가 판을 덮어 전부 어둡게 나온다 — 넘기고 캡처
	paused = true   # 타이머가 캡처 사이에 흘러가지 않게

	# 적 몇 마리 + 보드 위 픽업 하나를 손으로 앉힌다(스폰 쿨다운을 기다리지 않고 상태만 만든다)
	var es: Array = [
		{"col": 1, "row": 6, "vis_row": 6.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 101, "step_every": 3},
		{"col": 4, "row": 7, "vis_row": 7.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 102, "step_every": 3},
		{"col": 6, "row": 3, "vis_row": 3.0, "hp": 39, "maxhp": 39, "etype": "fast", "id": 103, "step_every": 2},
		{"col": 2, "row": 2, "vis_row": 2.0, "hp": 1, "maxhp": 1, "etype": "plane", "id": 104, "step_every": 3},
	]
	main.set("enemies", es)
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_pickup.png")
	print("shot: 보드 픽업(빈 슬롯)")

	# 획득 상태 — 슬롯 보유 + 표적 조준링(제일 아래 = col4/row7이 잡혀야 한다)
	var es2: Array = []
	for e in es:
		if String(e["etype"]) != "plane":
			es2.append(e)
	main.set("enemies", es2)
	main.set("plane_held", true)
	main.set("plane_armed", false)
	main.set("plane_pop", 0.0)
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_held.png")
	print("shot: 보유(미조준) — 조준링이 없어야 정상")

	# 1탭 = 조준: 표적 링 + 슬롯→표적 점선 + 슬롯 밝아짐
	main.set("plane_armed", true)
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_armed.png")
	var tgt: Dictionary = main.call("_plane_target")
	print("shot: 조준  표적 = col %d / row %d (기대 col4/row7)" % [int(tgt["col"]), int(tgt["row"])])

	# 발사 직후 — 비행 중
	paused = false
	main.call("_fire_plane")
	for _i in range(3):
		await process_frame
	paused = true
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_fire.png")
	print("shot: 발사 비행 중  (seekers=%d, 예약피격=%d)" % [
		(main.get("seekers") as Array).size(), (main.get("plane_shots") as Array).size()])
	print("DONE")
	quit()
