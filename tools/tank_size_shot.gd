extends SceneTree
# 탱크 크기 판정 프레임 — "이 칸에 놓을 수 있나"가 적 위에서도 읽히는지 보려는 것(창 모드 필수).
#   유저 지적: 장갑(tank)이 칸을 거의 꽉 채워 **칸이 비었는지 찼는지 안 보인다.**
#   적은 배치를 막지 않는다(`_can_place`는 board만 본다) = 적 밑의 칸 상태가 읽혀야 조준이 성립한다.
#
# 한 프레임에 판정에 필요한 대조를 다 넣는다:
#   ① 빈 칸 위의 탱크 / ② 블록 찬 칸 위의 탱크 — 둘이 달라 보여야 한다(이게 핵심 질문)
#   ③ 같은 줄에 basic·fast·swarm — 크기 위계가 유지되는지(탱크는 여전히 제일 육중해야 한다)
#   ④ 탱크 옆 빈 칸 — 그 칸이 비었다는 게 탱크에 안 먹히는지
#
#   godot --path . --script tools/tank_size_shot.gd        (TAG=after 로 파일명 구분)

const OUT_DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/2ced079a-4415-49c4-8abb-490ca530f41e/scratchpad"
var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set("persist_enabled", false)   # ⚠실유저 진행도 보호(창 모드 probe 공통 규약)
	main.call("_start_stage", 6)         # 7판 = 장갑 도입판
	await process_frame
	main.set("intro_t", -1.0)            # 인트로 카드 걷기
	main.set("callout_text", "")
	main.set("callout_timer", 0.0)

	# 보드: 탱크 밑이 '찬 칸'인 경우와 '빈 칸'인 경우를 나란히 만든다.
	var board: Array = main.get("board")
	for r in range(8):
		for c in range(8):
			board[r][c] = ""
	for c in range(8):
		board[3][c] = "B" if c % 2 == 0 else ""    # 3행 = 격자무늬(찬 칸/빈 칸 교대)
	for c in range(2, 6):
		board[5][c] = "O"                          # 5행 = 통째로 찬 줄
	main.set("board", board)

	# 적 배치 — 3행 격자 위에 탱크 둘(하나는 찬 칸, 하나는 빈 칸), 1행에 크기 비교용 4종.
	var spec: Array = [
		[0, 1, "tank"], [2, 1, "basic"], [4, 1, "fast"], [6, 1, "swarm"],   # 크기 위계 비교
		[0, 3, "tank"],                                                     # 찬 칸 위
		[1, 3, "tank"],                                                     # 빈 칸 위
		[3, 5, "tank"],                                                     # 꽉 찬 줄 위
	]
	var es: Array = []
	var seq: int = 200
	for s in spec:
		es.append({
			"col": s[0], "row": s[1], "vis_row": float(s[1]),
			"hp": 200, "maxhp": 200, "etype": s[2], "id": seq,
			"step_every": 3, "remain": 3, "stepped": false, "gen": 0, "flinch": 0.0,
		})
		seq += 1
	main.set("enemies", es)
	main.set("place_count", 4)

	var tag: String = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "before"
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "%s/tank_%s.png" % [OUT_DIR, tag]
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
