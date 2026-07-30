extends SceneTree
# 클리어 프리롤 검증 — 목표 배지가 HUD 카드를 떠나 중앙으로 올라가 터지는 구간(clear_show_t < 0).
# 동사별로 배지가 달라지는지 함께 본다(hold / collect / protect). 창 모드 필수(헤드리스는 렌더 텍스처 null).
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/309ebea2-5f92-4557-9f51-4e014e6e67d6/scratchpad/token"
var main: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# [캠페인 인덱스, 라벨] — 0-based. ⚠캠페인 순서 ≠ st 이름 순서: 4=st9(수집1종) 10=st10(수집2종) 5=st11(해체) 13=st14(보호)
	for job in [[3, "hold"], [4, "collect1"], [10, "collect2"], [5, "defuse"], [13, "protect"]]:
		var idx: int = int(job[0])
		var tag: String = String(job[1])
		paused = false
		main.call("_start_stage", idx)
		await process_frame
		var st: Dictionary = main.get("st")
		# 승리 상태를 손으로 못 박는다(판정 경로는 건드리지 않음 — 연출만 검증)
		main.set("killed", int(st["total"])); main.set("leaked", 0)
		main.set("game_over", false); main.set("game_clear", true)
		main.set("confetti", [])
		main.set("intro_t", -1.0)          # 인트로 카드가 겹쳐 뜨면 배지가 두 개로 보인다
		if bool(st.get("collect", false)):
			var tg: Array = st.get("collect_targets", [1])
			var got: Array = []
			for v in tg:
				got.append(int(v))
			main.set("collected_by_type", got)   # 쿼터 달성 상태
		if bool(st.get("protect", false)):
			main.set("vault", int(st.get("vault_start", 4)))
		# 피니시 스윕은 '남은 블록'을 쓸어야 보이므로 판을 손으로 채운다(빈 판이면 스윕이 아무것도 안 그린다)
		var keys: Array = ["R", "O", "Y", "G", "B", "P"]
		var bd: Array = main.get("board")
		for r in range(bd.size()):
			var row: Array = bd[r]
			for c in range(row.size()):
				if (r * 3 + c * 5) % 7 < 4:
					row[c] = String(keys[(r + c) % keys.size()])
		main.set("board", bd)
		paused = true
		for t in [-1.92, -1.84, -1.76, -1.10, -0.94, -0.88, -0.82, -0.76, -0.70, -0.58, -0.46, -0.30]:
			main.set("clear_show_t", t)
			main.call("queue_redraw")
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s_%s_%+04d.png" % [OUT, tag, int(t * 100.0)])
		print("shots done: ", tag)
	print("DONE"); quit()
