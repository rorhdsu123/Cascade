extends SceneTree
# 클리어 연출 영상 캡처. Godot 무비라이터(--write-movie --fixed-fps)로 돌려야 한다 —
#   매 프레임 save_png를 하면 인코딩 시간만큼 delta가 부풀어 타임라인이 실제와 달라진다(고정 델타가 답).
#   실행: godot --path . --write-movie <out.avi> --fixed-fps 60 --script tools/clear_movie.gd
const FPS: int = 60
const SECONDS: float = 5.8      # 프리롤 0.84s + 무대 2.8s + 팝업 개봉·여운
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 3)
	await process_frame
	# 판이 진행된 상태에서 이긴 것처럼 — 프리롤 동안 '무엇이 살아 있는지'가 보여야 한다
	for _w in range(60):
		main.call("_process", 0.05)
		await process_frame
	# 실제 클리어와 같은 상태로 못 박는다(판정 경로는 안 건드리고 연출만 재생)
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"])); main.set("leaked", 0)
	main.set("game_over", false); main.set("game_clear", true)
	main.call("_plan_clear_fx")
	# 피니시 스윕이 쓸 블록을 심는다 — 워밍업만으론 판이 비어 스윕이 아무것도 안 그린다
	var keys: Array = ["R", "O", "Y", "G", "B", "P"]
	var bd: Array = main.get("board")
	for r in range(bd.size()):
		var row: Array = bd[r]
		for c in range(row.size()):
			if row[c] == "" and (r * 3 + c * 5) % 7 < 4:
				row[c] = String(keys[(r + c) % keys.size()])
	main.set("board", bd)
	main.set("clear_show_t", -main.get("CLEAR_HOLD"))   # 프리롤 처음부터 녹화
	main.set("result_t", -1.0)
	for _i in range(int(SECONDS * float(FPS))):
		await process_frame
	print("DONE"); quit()
