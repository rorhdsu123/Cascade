extends SceneTree
# 결과 연출 영상 — 무대 끝 → 하드 컷 → 클리어 팝업 순차 개봉(카드→헤드라인→버튼)까지.
#   무비라이터로만 돌린다(고정 델타). 매 프레임 save_png는 인코딩 시간이 delta에 섞여 타임라인이 거짓말을 한다.
#   실행: godot --path . --write-movie <out.avi> --fixed-fps 60 --script tools/result_movie.gd
const FPS: int = 60
const SECONDS: float = 4.2      # 무대 잔여 0.8s + 컷 + 팝업 개봉·여운
var main: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 3)
	await process_frame
	# 판이 진행된 상태에서 이긴 것처럼(팝업 뒤로 비치는 화면이 '방금 그 판'이어야 한다)
	for _w in range(60):
		main.call("_process", 0.05)
		await process_frame
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"])); main.set("leaked", 0)
	main.set("game_over", false); main.set("game_clear", true)
	main.call("_plan_clear_fx")
	main.set("clear_show_t", 2.00)   # 무대 막바지부터 — 하드 컷(2.80)이 화면에 담긴다
	main.set("result_t", -1.0)
	for _i in range(int(SECONDS * float(FPS))):
		await process_frame
	print("DONE"); quit()
