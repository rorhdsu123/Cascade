extends SceneTree
# 유도 종이비행기 발사 수 진단 — 가로 N줄 클리어 × 콤보별 실제 seeker 수.
# 헤드리스 OK(발사 계획은 순수 로직, 렌더 안 함).
# 실행: godot --headless --script tools/seeker_probe.gd

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 4)
	await process_frame
	main.set_process(false)

	# 적을 각 행에 골고루 배치(생존자 후보 존재 보장)
	var base_enemies: Array = []
	var eid: int = 1
	for r in range(8):
		base_enemies.append({"col": (r * 3) % 8, "row": r, "vis_row": float(r), "hp": 60, "maxhp": 60, "etype": "basic", "id": eid, "step_every": 3})
		eid += 1
	main.set("last_color", "B")

	# 가로 1/2/3/4줄 × 콤보 0..6
	for nrows in [1, 2, 3, 4]:
		for cmb in range(0, 7):
			# 적 리셋
			var es: Array = []
			for e in base_enemies:
				es.append(e.duplicate())
			main.set("enemies", es)
			main.set("combo", cmb)
			var rows: Array = []
			for i in range(nrows):
				rows.append(2 + i)   # 상단부 연속 행
			main.call("_begin_resolve", rows, [])
			var plan: Array = main.get("resolve_seeker_plan")
			# band 밖 생존자 수도 같이(원인 분리)
			print("가로 ", nrows, "줄 · combo ", cmb, " → seekers=", plan.size())
	print("DONE")
	quit()
