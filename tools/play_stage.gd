extends SceneTree
# 특정 스테이지로 바로 들어가 '직접 플레이'하는 개발용 런처(창 모드 필수).
#   선택 화면의 선형 잠금을 우회해 _start_stage를 직접 부른다 — 밸런스 변경을 손으로 확인할 때.
#   실행: STAGE=14 godot --path . --script tools/play_stage.gd     (STAGE = 화면에 보이는 번호, 1부터)
#   ⚠프로브가 아니다: quit하지 않고 그대로 사람이 조작한다. 창을 닫으면 끝.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var env: String = OS.get_environment("STAGE")
	var shown: int = int(env) if env != "" else 1
	var idx: int = clampi(shown - 1, 0, int(main.STAGES.size()) - 1)
	main.dev_unlock_all = true      # 돌아가기·재도전 시에도 잠금에 안 걸리게
	main.call("_start_stage", idx)
	print("▶ 스테이지 %d 시작 (배열 idx %d, %s)" % [idx + 1, idx, str(main.STAGES[idx].get("name", "?"))])
