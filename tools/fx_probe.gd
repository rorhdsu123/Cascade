extends SceneTree
# C90 D 검증: _fire_climax 산개 불꽃 + 앰비언트 스파클. 창 모드 필수.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/27b571fe-f454-4f5c-9c2a-6c5dda5fee6b/scratchpad/fx"
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
	# 보드 맥락
	var board: Array = main.get("board")
	for rc in [[1,2],[1,3],[2,5],[3,1],[4,4],[5,7],[6,2],[6,3]]:
		board[rc[0]][rc[1]] = ["R","B","Y"][(rc[0]+rc[1]) % 3]
	main.set("board", board)
	# 전멸 climax 직접 발화
	main.call("_fire_climax")
	# 히트스톱이 걸리면 impacts가 안 도니 0으로
	main.set("hitstop", 0.0)
	# 0.1s 간격으로 전개 캡처(시차 발화 0~0.6s + 수명 ~0.6s)
	var labels: Array = ["00","01","02","03","04","05","06","07","08","09"]
	for k in range(labels.size()):
		await _grab(labels[k])
		for s in range(3):
			main.call("_process", 0.033)
			main.set("hitstop", 0.0)
	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
