extends SceneTree
# C90 검증: 점수 롤업 + PB 판전체 폭발 발화. 창 모드 필수(헤드리스는 렌더텍스처 null).
# endless_score를 높이 두고 shown=0에서 _process를 굴려 '또르르 차오르다 크라운(best) 넘는 순간' 캡처.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/27b571fe-f454-4f5c-9c2a-6c5dda5fee6b/scratchpad/rollup"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	main.call("_start_endless")
	await process_frame
	# 자동 _process 차단 — 씬트리가 돌리면 캡처 전에 롤업이 끝나버림. 수동으로 스텝 구동.
	main.set_process(false)
	main.set_physics_process(false)
	main.set("combo", 4)
	main.set("place_count", 5)
	main.set("endless_best", 3200)          # 크라운(추격 기준선)
	main.set("endless_score", 5000)         # 실제 점수는 5000까지 목표
	main.set("endless_score_shown", 0.0)    # 표시는 0에서 시작 → 롤업
	main.set("endless_beat_best", false)

	# 수동 30fps 스텝으로 롤업 진행. 각 구간 캡처(0 → 접근 → 돌파순간 → 도착).
	await _grab("t0_start")
	await _step(1); await _grab("t1_climbing")   # ~1485 (크라운 아래)
	await _step(2); await _grab("t2_crossing")   # ~3263 (3200 돌파 → pb_pop_t 발화)
	await _step(2); await _grab("t3_after")      # ~4200 (돌파 직후 방사광)
	await _step(12); await _grab("t4_settled")   # 5000 도착 + 크라운 락

	print("beat=", main.get("endless_beat_best"), " shown=", main.get("endless_score_shown"), " pb_pop_t=", main.get("pb_pop_t"))
	print("DONE"); quit()

func _step(n: int) -> void:
	# 수동 30fps 스텝(자동 process 꺼둠). 무한 플레이 상태라 hitstop/menu 조기반환 없음.
	for i in range(n):
		main.call("_process", 0.033)
	main.call("queue_redraw")

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag, " shown=", main.get("endless_score_shown"), " beat=", main.get("endless_beat_best"))
