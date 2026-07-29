extends SceneTree
# 착지 이펙트 검증: 조각을 실제로 놓고 0.04s 간격 전개 캡처. 창 모드 필수(--headless는 렌더 텍스처 null).
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/0b577b30-ab15-4d00-b7df-3a57379683c8/scratchpad/place"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	seed(7)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_endless")
	main.call("seed_game", 12345)
	main.call("_refill_tray")       # 고정 시드로 트레이 재추첨 = 매 실행 같은 조각
	await process_frame
	main.set_process(false)
	main.set_physics_process(false)
	# 보드 맥락 조금
	var board: Array = main.get("board")
	for rc in [[7,1],[7,2],[6,6],[5,3]]:
		board[rc[0]][rc[1]] = ["R","B","Y"][(rc[0] + rc[1]) % 3]
	main.set("board", board)
	# 첫 트레이 조각을 보드 중앙에 놓는다
	main.set("sel", 0)
	main.set("hover_col", 5)
	main.set("hover_row", 3)
	var want: Array = main.call("_ghost_cells")
	main.call("_place_piece")
	print("target=", want, " pops=", main.get("place_pops").size(), " dust=", main.get("debris").size())
	for k in range(8):
		await _grab("%02d" % k)
		main.call("_process", 0.04)
		main.set("hitstop", 0.0)
	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
