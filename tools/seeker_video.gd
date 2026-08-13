extends SceneTree
# 유도 로켓(동시 N줄 → N발) 영상용 프레임 덤프. 창 모드 필수.
# 더블(가로 2줄) 클리어 + 줄 밖 흩어진 적 → 로켓 2발이 거점 가까운 순으로 날아가 처치.

const ShotDir = preload("res://tools/shot_dir.gd")
# 출력 경로 = SHOT_DIR 환경변수, 없으면 build/shots/ (tools/shot_dir.gd 참조).
var DIR: String = ShotDir.resolve("frames")
const DT: float = 0.02
const N: int = 110

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 4)
	await process_frame
	main.set("intro_t", -1.0)
	main.set_process(false)
	# 밴드(행 6,7 = 하단) 위 = 죽음 / 상단 흩어진 2마리 = 생존자 → 종이비행기가 코어(하단)서 위로 길게 난다
	main.set("enemies", [
		{"col": 2, "row": 6, "vis_row": 6.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 1, "step_every": 3},
		{"col": 5, "row": 7, "vis_row": 7.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 2, "step_every": 3},
		{"col": 6, "row": 6, "vis_row": 6.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 8, "step_every": 3},
		{"col": 2, "row": 1, "vis_row": 1.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 3, "step_every": 3},  # 상단 생존자 → 표적
		{"col": 5, "row": 0, "vis_row": 0.0, "hp": 60, "maxhp": 60, "etype": "basic", "id": 4, "step_every": 3},  # 상단 생존자 → 표적
	])
	main.set("combo", 1)
	main.set("last_color", "B")
	for i in range(6):
		await _grab(i)
	main.call("_begin_resolve", [6, 7], [])   # 더블 = 하단 가로 2줄
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
