extends SceneTree
# 위치-트리거 분열 로직 검증 (헤드리스 OK — _draw 안 탐).
#   split gen0 하나를 심고 advance_step을 돌려 row 5(SPLIT_ROW)에서 갈라지는지,
#   그 결과가 '부모 잔존(gen0·split_done·절반HP) + 쌍둥이 1(gen1)'인지, HP가 절반인지 확인.
# 실행: /opt/homebrew/bin/godot --headless --path . --script tools/split_event_probe.gd
func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.dda_enabled = false
	g._start_stage(6)
	g.enemies.clear()
	g.enemies.append({
		"col": 3, "row": 0, "vis_row": 0.0, "hp": 40, "maxhp": 40,
		"etype": "split", "id": 9000, "step_every": 1, "gen": 0,
	})
	print("SPLIT_ROW=", g.SPLIT_ROW)
	for step in range(8):
		g.advance_step()
		var rows: Array = []
		var gens: Array = []
		var hps: Array = []
		var done: Array = []
		for e in g.enemies:
			rows.append(int(e["row"]))
			gens.append(int(e.get("gen", 0)))
			hps.append(int(e["hp"]))
			done.append(1 if e.get("split_done", false) else 0)
		print("step%d: n=%d rows=%s gens=%s hps=%s done=%s  core_hp=%d killed=%d leaked=%d" % [
			step, g.enemies.size(), str(rows), str(gens), str(hps), str(done), g.core_hp, g.killed, g.leaked])
	quit()
