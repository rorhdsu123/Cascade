extends SceneTree
# 아이템(유도 비행기 탭-투-유즈) 로직 탐침 — 헤드리스 OK(렌더 안 함).
#   검증: ① 2줄+ 클리어 = 적립(상한 PLANE_CAP 클램프) ② 탭 발사 = 거점 근접 적 표적·감소
#         ③ 착지 처치 후 웨이브 불변식(spawned==killed+leaked+onboard) 보존 ④ 표적 없으면 무소모
# 실행: godot --headless --script tools/plane_item_probe.gd

var main: Node
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("✅ ", msg)
	else:
		fails += 1
		print("❌ ", msg)

func _onboard_gen0(g: Node) -> int:
	var n: int = 0
	for e in g.enemies:
		if String(e["etype"]) == "gem":
			continue
		if String(e["etype"]) == "split" and int(e.get("gen", 0)) == 1:
			continue
		n += 1
	return n

func _add_enemy(g: Node, id: int, col: int, row: int, hp: int) -> void:
	g.enemies.append({"id": id, "etype": "basic", "col": col, "row": row, "hp": hp})
	g.spawned += 1   # 불변식 기준선 유지(수동 추가분도 spawned에 셈)

func _drain_resolve() -> void:
	var s: int = 0
	while main.resolving and s < 400:
		main.call("_process", 0.05)
		s += 1

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame

	# ── ① 적립: 두 줄 꽉 채우고 double 클리어 → planes_banked += 2 ──
	main.enemies.clear()
	main.planes_banked = 0
	main.combo = 1
	var r1: int = main.ROWS - 1
	var r2: int = main.ROWS - 2
	for c in range(main.COLS):
		main.board[r1][c] = main.COLORS[0]
		main.board[r2][c] = main.COLORS[0]
	main.last_color = main.COLORS[0]
	main.call("_begin_resolve", [r1, r2], [])
	_drain_resolve()
	_ok(main.planes_banked == 2, "double 클리어 → 적립 2 (실제 " + str(main.planes_banked) + ")")

	# ── ③ 상한 클램프: 이미 2, 4줄 더 벌면 CAP에서 멈춤 ──
	main.combo = 1
	for r in range(main.ROWS - 4, main.ROWS):
		for c in range(main.COLS):
			main.board[r][c] = main.COLORS[0]
	main.last_color = main.COLORS[0]
	main.call("_begin_resolve", [main.ROWS - 1, main.ROWS - 2, main.ROWS - 3, main.ROWS - 4], [])
	_drain_resolve()
	_ok(main.planes_banked == main.PLANE_CAP, "적립 상한 클램프 = " + str(main.PLANE_CAP) + " (실제 " + str(main.planes_banked) + ")")

	# ── ② 발사: 거점 근접(row 큰) 적을 표적·감소 ──
	main.enemies.clear()
	main.spawned = main.killed + main.leaked + 0   # 카운터 기준선 리셋(수동 시나리오)
	_add_enemy(main, 90001, 2, main.ROWS - 6, 1)   # 먼 적
	_add_enemy(main, 90002, 5, main.ROWS - 2, 1)   # 거점 근접(더 큰 row) = 표적이어야 함
	_add_enemy(main, 90003, 1, main.ROWS - 4, 1)
	main.planes_banked = 3
	var sp0: int = main.spawned
	var inv0: bool = (main.spawned == main.killed + main.leaked + _onboard_gen0(main))
	_ok(inv0, "발사 전 불변식 기준선 성립")
	main.call("_fire_banked_plane")
	_ok(main.planes_banked == 2, "발사 → 적립 3→2 (실제 " + str(main.planes_banked) + ")")
	_ok(main.seekers.size() == 1, "비행기 1대 비행 중")
	var tid: int = int(main.seekers[0]["target_id"]) if main.seekers.size() > 0 else -1
	_ok(tid == 90002, "표적 = 거점 근접 적(id 90002), 실제 " + str(tid))

	# 착지까지 진행 → 처치·불변식
	var s: int = 0
	while main.seekers.size() > 0 and s < 100:
		main.call("_process", 0.05)
		s += 1
	var still_alive: bool = false
	for e in main.enemies:
		if int(e["id"]) == 90002:
			still_alive = true
	_ok(not still_alive, "착지 → 표적 처치됨")
	_ok(main.spawned == main.killed + main.leaked + _onboard_gen0(main),
			"처치 후 불변식 보존 (sp " + str(main.spawned) + " = k " + str(main.killed) + "+lk " + str(main.leaked) + "+ob " + str(_onboard_gen0(main)) + ")")
	_ok(main.spawned == sp0, "spawned 불변(처치는 새 스폰 아님)")

	# ── ④ 표적 없음: 적 비우고 발사 → 무소모 ──
	main.enemies.clear()
	var banked_before: int = main.planes_banked
	main.call("_fire_banked_plane")
	_ok(main.planes_banked == banked_before, "표적 없으면 무소모 (적립 " + str(main.planes_banked) + " 유지)")

	print("── 아이템 로직: 실패 ", fails, "건 ──")
	print("DONE")
	quit()
