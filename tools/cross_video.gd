extends SceneTree
# 크로스(십자 관통) 연출 영상용 프레임 시퀀스 덤프. 창 모드 필수.
# 실행: godot --path . --script tools/cross_video.gd
# 뒤이어 ffmpeg로 mp4 인코딩(아래 셸에서).

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/efe67560-638a-4d54-b126-9957c48f7dbb/scratchpad/frames"
const DT: float = 0.02
const N: int = 95

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	# 이전 프레임 청소
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 4)   # S5 = 장갑(tank) 맥락
	await process_frame
	main.set("intro_t", -1.0)
	main.set_process(false)
	# 교차점(col4,row3)에 장갑 + 행/열 팔에 기본적 + 라인 밖 생존자
	main.set("enemies", [
		{"col": 4, "row": 3, "vis_row": 3.0, "hp": 400, "maxhp": 400, "etype": "tank", "id": 1, "step_every": 3},
		{"col": 4, "row": 1, "vis_row": 1.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 2, "step_every": 3},
		{"col": 4, "row": 6, "vis_row": 6.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 3, "step_every": 3},
		{"col": 1, "row": 3, "vis_row": 3.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 4, "step_every": 3},
		{"col": 7, "row": 3, "vis_row": 3.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 5, "step_every": 3},
	])
	main.set("combo", 1)
	main.set("last_color", "B")
	# 시작 전 정적 프레임 몇 장(맥락)
	for i in range(6):
		await _grab(i)
	main.call("_begin_resolve", [3], [4])
	for i in range(N):
		main.call("_process", DT)
		await _grab(6 + i)
	print("DONE frames=", 6 + N)
	quit()

func _grab(idx: int) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/f_%04d.png" % [DIR, idx])
