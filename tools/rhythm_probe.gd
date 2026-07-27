extends SceneTree
# C90 A 검증: 실제 줄-클리어 시퀀스를 태워 '파괴 → (한 박) → 칭찬 단어' 스태거를 프레임으로 확인.
# combo=4 → 충전 ~0.47s → _burst_lines(셀 소멸 + praise_delay=0.09) → 0.09s 뒤 "GREAT!" 팝인.
# 창 모드 필수. 30fps(0.033) 수동 스텝으로 버스트 전후를 조밀 캡처.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/27b571fe-f454-4f5c-9c2a-6c5dda5fee6b/scratchpad/rhythm"
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

	# 보드 맨 아래 행을 꽉 채워 파괴가 눈에 보이게(색은 임의 원색 키).
	var board: Array = main.get("board")
	var cols: int = main.get("COLS")
	var rows: int = main.get("ROWS")
	var row: int = rows - 2   # 바닥 방어선 위 한 칸(거점 겹침 회피)
	for c in range(cols):
		board[row][c] = "amber"
	main.set("board", board)
	main.set("last_color", "amber")
	main.set("combo", 4)              # → 칭찬 "GREAT!" (2=GOOD 3=NICE 4=GREAT)

	# 줄 완성 처리 시작(로직 결과는 시퀀스가 재생하며 반영).
	main.call("_begin_resolve", [row], [])

	# 0.025s(40fps) 스텝을 32회 = ~0.8s. 매 스텝 캡처(충전→파괴→갭→단어 오버슛).
	var t: float = 0.0
	for i in range(32):
		main.call("_process", 0.025)
		t += 0.025
		await _grab("%02d_%03d" % [i, int(t * 1000.0)])
	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
