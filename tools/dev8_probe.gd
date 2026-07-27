extends SceneTree
# C90: '8' DEV 키(콤보5 전멸 전체 시퀀스) 검증. 창 모드. 키 핸들러와 동일 셋업을 직접 재현.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/27b571fe-f454-4f5c-9c2a-6c5dda5fee6b/scratchpad/dev8"
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
	# '8' 키와 동일: 바닥 위 한 줄 채우고 combo=5로 실제 resolve
	var board: Array = main.get("board")
	var cols: int = main.get("COLS")
	var rows: int = main.get("ROWS")
	var colors: Array = main.get("COLORS")
	var drow: int = rows - 2
	for c in range(cols):
		board[drow][c] = colors[c % colors.size()]
	main.set("board", board)
	main.set("last_color", colors[0])
	main.set("combo", 5)
	main.call("_begin_resolve", [drow], [])
	print("resolving=", main.get("resolving"), " total=", main.get("resolve_total"))
	# 전체 시퀀스(충전 0.47 + 파괴 + 로켓 + 불꽃 ~1.5s) 캡처
	for k in range(12):
		await _grab("%02d" % k)
		for s in range(4):
			main.call("_process", 0.033)
			main.set("hitstop", 0.0)   # 히트스톱 스킵(연출 진행)
	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
