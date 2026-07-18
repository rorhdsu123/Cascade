extends SceneTree
# 분열 form 시각 검증 (창 모드 필수 — 헤드리스는 렌더 텍스처 null 크래시).
#   gen0(쌍둥이 blob+세로 금 = 곧 갈라짐) vs gen1(단일 blob+흉터 = 안 갈라짐)이
#   한눈에 구분되고, 파랑이 로스터(바이올렛/시안/딥바이올렛/라임)와 안 묻는지.
# 실행: /opt/homebrew/bin/godot --path . --script tools/split_render.gd
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/6d2de27d-1c54-47b1-960f-6eec9357f0a4/scratchpad"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	main.call("_start_stage", 5)   # 총력전(모든 색 상수 로드된 상태)
	await process_frame

	# 적을 직접 주입 — 각 타입 한 마리씩 나란히(팔레트 대조) + split gen0/gen1 + 피격 상태
	var seq: int = 1000
	var demo: Array = [
		{"col": 0, "row": 2, "etype": "basic"},
		{"col": 1, "row": 2, "etype": "fast"},
		{"col": 2, "row": 2, "etype": "tank"},
		{"col": 3, "row": 2, "etype": "swarm"},
		{"col": 4, "row": 2, "etype": "split", "gen": 0},           # 분열 직전(쌍둥이)
		{"col": 5, "row": 2, "etype": "split", "gen": 1},           # 자식(흉터)
		{"col": 4, "row": 4, "etype": "split", "gen": 0, "hurt": true},  # 피격 생존(HP바 노출)
		{"col": 5, "row": 4, "etype": "split", "gen": 1, "hurt": true},
	]
	main.enemies.clear()
	for d in demo:
		var hp: int = 100
		var mhp: int = 100
		if d.get("hurt", false):
			hp = 45   # bar 노출용
		main.enemies.append({
			"col": d["col"], "row": d["row"], "vis_row": float(d["row"]),
			"hp": hp, "maxhp": mhp, "etype": d["etype"], "id": seq,
			"step_every": 3, "gen": int(d.get("gen", 0)),
		})
		seq += 1

	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/split_form.png")
	print("saved: split_form.png (%d enemies)" % main.enemies.size())
	quit()
