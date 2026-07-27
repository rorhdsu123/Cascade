extends SceneTree
# 6색 캔디 팔레트 검증 — 6색 블록 밴드 + 그 위에 적/보석을 세워 충돌(묻힘)을 눈으로 판정.
# 실행: godot --path . --script tools/candy_probe.gd   (창 모드 필수 — headless는 렌더 텍스처 null)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/54409de7-1e4b-4eea-8bdc-a19cc75327a1/scratchpad/candy"
const BANDS: Array = ["R", "O", "Y", "G", "B", "P", "", ""]  # 행 0~5 = 6색, 6~7 = 빈칸(보석 놓을 자리)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	main.set("intro_t", -1.0)   # 인트로 카드 끄기 — 가운데 밴드가 안 가리게
	await process_frame

	var board: Array = main.get("board")
	for r in range(8):
		for c in range(8):
			board[r][c] = String(BANDS[r]) if r < BANDS.size() else ""
	main.set("board", board)

	# 적: 각 색 밴드 위(col 6)에 충돌 가능성 큰 타입을 얹는다.
	#   coral행=thief(자홍), orange행=basic(바이올렛), sky행=fast(시안), blue행=split(파랑), yellow행=tank.
	var eid: int = 700
	var enemies: Array = []
	# 각 색 위에 최근접·대표 적을 얹어 최악 케이스 스트레스: 초록 위 라임(swarm), 파랑 위 분열(split),
	#   보라 위 basic(바이올렛)+thief(자홍) 둘 다, 빨강 위 fast, 주황 위 tank.
	var place: Array = [
		{"row": 0, "col": 6, "etype": "fast", "hp": 39},
		{"row": 1, "col": 6, "etype": "tank", "hp": 256},
		{"row": 2, "col": 6, "etype": "basic", "hp": 65},
		{"row": 3, "col": 6, "etype": "swarm", "hp": 26},
		{"row": 4, "col": 6, "etype": "split", "hp": 50},
		{"row": 5, "col": 4, "etype": "basic", "hp": 65},
		{"row": 5, "col": 6, "etype": "thief", "hp": 40},
	]
	for p in place:
		eid += 1
		enemies.append({"id": eid, "col": int(p["col"]), "row": int(p["row"]), "vis_row": float(p["row"]),
			"hp": int(p["hp"]), "maxhp": int(p["hp"]), "etype": String(p["etype"]),
			"step_every": 9999, "flinch": 0.0, "gtype": 0})
	# 보석 3종(골드/로즈/인디고)을 빈칸 행(6)에 놓아 블록 앰버·로즈·파랑과 나란히 비교
	for i in range(3):
		eid += 1
		enemies.append({"id": eid, "col": 1 + i * 2, "row": 6, "vis_row": 6.0,
			"hp": 1, "maxhp": 1, "etype": "gem", "gtype": i, "step_every": 9999, "flinch": 0.0})
	main.set("enemies", enemies)

	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "_grid.png")
	print("SAVED ", OUT, "_grid.png  size=", img.get_size())
	quit()
