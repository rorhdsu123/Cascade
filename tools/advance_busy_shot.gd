extends SceneTree
# 적 전진 예고(warn_next/step_beat/lean)가 겹친 '최대 혼잡' 보드 프레임 — 창 모드 필수.
# 지금 방식이 얼마나 시끄러운지 원본 프레임으로 판단하려는 것.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/c4fd0016-bd14-43b0-82b6-47a831bcbe9f/scratchpad/adv"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 5)   # 중후반: swarm desync + 혼합 타입
	await process_frame

	# 손으로 적을 여러 행에 깔고, 예고 상태를 켠다(현재 신호 최대치 재현).
	var es: Array = []
	# col, row, etype, step_every, remain, stepped, gen  (remain 1=다음 배치 전진·2=곧·3=대기)
	# before 프레임(warn_next=true였던 5마리)을 remain=1로 그대로 옮겨 apples-to-apples 비교.
	var spec: Array = [
		[0, 2, "basic", 3, 1, false, 0],   # 상단: before는 붉은칸 → after는 lean만
		[1, 4, "swarm", 2, 1, false, 0],
		[2, 3, "fast",  2, 2, false, 0],   # remain=2 와인드업(살짝 lean)
		[3, 6, "split", 3, 1, false, 0],   # 바닥 근처: after도 붉은칸(중간 세기)
		[4, 1, "basic", 3, 3, false, 0],   # 대기
		[5, 5, "swarm", 2, 1, false, 0],   # depth 중간: 흐린 붉은칸
		[6, 7, "tank",  3, 1, true,  0],   # 하단, 누수 임박(off-board라 칸 없음·lean만)
		[7, 3, "basic", 3, 1, false, 0],   # 상단
	]
	var seq: int = 100
	for s in spec:
		es.append({
			"col": s[0], "row": s[1], "vis_row": float(s[1]),
			"hp": 40, "maxhp": 40, "etype": s[2], "id": seq,
			"step_every": s[3], "remain": s[4], "stepped": s[5], "gen": s[6],
			"flinch": 0.0,
		})
		seq += 1
	main.set("enemies", es)
	main.set("step_beat", 0.18)   # 방금 스텝 → stepped 적에 링
	main.set("place_count", 2)
	main.set("combo", 4)
	main.set("killed", 5)
	await _grab("busy")
	print("DONE"); quit()

func _grab(tag: String) -> void:
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%s.png" % [OUT, tag])
	print("shot ", tag)
