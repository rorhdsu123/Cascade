extends SceneTree
# C90 C 검증: PB 판전체 폭발. 표시점수가 크라운 넘는 순간 발화 → pb_pop_t 창을 조밀 캡처.
# 창 모드 필수. 보드에 블록 깔아 맥락 확보.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/27b571fe-f454-4f5c-9c2a-6c5dda5fee6b/scratchpad/pb"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_endless")
	await process_frame
	main.set_process(false)
	main.set_physics_process(false)
	# 보드 맥락 — 흩뿌린 블록
	var board: Array = main.get("board")
	var cols: int = main.get("COLS")
	var rows: int = main.get("ROWS")
	for rc in [[1,2],[1,3],[2,2],[2,5],[3,1],[3,6],[4,3],[4,4],[5,0],[5,7],[6,2],[6,3],[6,4]]:
		board[rc[0]][rc[1]] = ["R","B","Y"][(rc[0]+rc[1]) % 3]
	main.set("board", board)
	main.set("combo", 4)
	main.set("place_count", 12)
	main.set("endless_best", 3200)
	main.set("endless_score", 5000)
	main.set("endless_score_shown", 3120.0)   # 크라운 바로 아래서 시작 → 곧 돌파
	main.set("endless_beat_best", false)

	# 돌파까지 굴림
	for i in range(6):
		main.call("_process", 0.033)
		if main.get("endless_beat_best"):
			break
	print("beat=", main.get("endless_beat_best"), " pb_pop_t=", main.get("pb_pop_t"))
	# 폭발 창(1.6s)을 조밀 캡처 — 발화 직후부터
	await _grab("00")
	var labels: Array = ["01","02","03","04","05","06","07","08","09"]
	for k in range(labels.size()):
		for s in range(3):   # 0.033*3 ≈ 0.1s 간격
			main.call("_process", 0.033)
		await _grab(labels[k])
	# 폭발 끝난 뒤(pb_pop_t 만료) — 지속 골드 테두리만 남는지 확인
	for _f in range(70):
		main.call("_process", 0.033)
	await _grab("10_settled")
	print("pb_pop_t after=", main.get("pb_pop_t"), " beat=", main.get("endless_beat_best"))
	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
