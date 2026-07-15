extends SceneTree
# HP 바 게이팅 검증 — '피격당하고 살아남은 적'(hp < maxhp)에게만 바가 뜨는지 렌더로 확인.
# 풀피 적은 바가 없어야(외형만), 데미지 입은 적은 바 + 하트, 숫자는 없어야 한다.
# 실행: godot --path . --script tools/hpbar_probe.gd   (창 모드 필수 — headless는 렌더 텍스처 null)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/17e2ebd0-22f7-4f12-a5f0-ad52b6eaa18b/scratchpad/hpbar.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 3)   # 장갑 스테이지(탱크 포함)
	await process_frame

	# 두 행: 위 = 풀피(바 없어야), 아래 = 반피(바 떠야). 4타입.
	var types: Array = ["basic", "tank", "fast", "swarm"]
	var maxhp_of: Dictionary = {"basic": 44, "tank": 200, "fast": 26, "swarm": 18}
	var enemies: Array = []
	var eid: int = 800
	for t in range(types.size()):
		var ty: String = String(types[t])
		var mh: int = int(maxhp_of[ty])
		eid += 1
		# 행 1: 풀피 → 바 없음
		enemies.append({"id": eid, "col": 1 + t * 2, "row": 1, "vis_row": 1.0,
				"hp": mh, "maxhp": mh, "etype": ty, "step_every": 9999, "flinch": 0.0})
		eid += 1
		# 행 4: 반피 → 바 뜸
		enemies.append({"id": eid, "col": 1 + t * 2, "row": 4, "vis_row": 4.0,
				"hp": maxi(1, int(mh * 0.45)), "maxhp": mh, "etype": ty, "step_every": 9999, "flinch": 0.0})
	main.set("enemies", enemies)

	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = root.get_texture().get_image()
	img.save_png(OUT)

	# 실측: 행1(풀피) 바 자리에 초록이 없어야, 행4(반피) 바 자리엔 초록이 있어야.
	# 바는 셀 상단(y = 150 + row*64 + 2 부터 ~16px). 셀 중앙 x에서 표본.
	print("타입 | 풀피(row1) 바자리 초록? | 반피(row4) 바자리 초록?")
	for t in range(types.size()):
		var col: int = 1 + t * 2
		var px: int = 144 + col * 64 + 24   # 하트/채움 자리(초록). 빈칸 쪽(오른쪽)은 어두워 오판
		var full_p: Color = img.get_pixel(px, 150 + 1 * 64 + 8)
		var half_p: Color = img.get_pixel(px, 150 + 4 * 64 + 8)
		var full_green: bool = full_p.g > 0.4 and full_p.g > full_p.r + 0.15
		var half_green: bool = half_p.g > 0.4 and half_p.g > half_p.r + 0.15
		print("  %-5s | %s | %s" % [String(types[t]), str(full_green), str(half_green)])
	print("DONE")
	quit()
