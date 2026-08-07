extends SceneTree
# 도둑 2단 콜아웃 실측(C160) — 등장 시 '막아라', 훔치는 순간 '도망치기 전에 잡아라'.
#   godot --path . --script tools/thief_callout_probe.gd
#
# 눈으로 잡지 않는다: 도둑을 바닥 직전에 심고 advance_step을 한 번 굴려 grab을 강제한 뒤,
#   그 프레임의 callout_text가 바뀌었는지 본다. 안 바뀌면 '못 본 것'이 아니라 '안 뜬 것'이다.
# 판당 1회 규율도 같이 본다 — 두 번째 도둑이 훔쳐도 다시 뜨면 안 된다.

var g: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	g.set("persist_enabled", false)
	g.set("dev_unlock_all", true)
	# ⚠protect 판(st14)은 STAGES에 없다 — stage_data.PARKED_PROTECT로 캠페인 밖에 파킹돼 있다.
	#   grab 분기는 protect 게이트가 없으므로(적 etype만 본다) 아무 판에서나 재현된다. 폭탄 없는
	#   1판을 쓴다 — 폭탄 판에서 돌리면 같은 advance_step 후반의 스폰 콜아웃이 결과를 덮어쓴다
	#   (첫 시도에서 실제로 BOMB 문구가 잡혔다. 프로브가 아니라 판 선택 문제였다).
	g.call("_start_stage", 0)
	await process_frame

	var rows: int = g.get("ROWS")

	# ① 등장 콜아웃 — 스폰 경로가 내는 것. seen_types를 비우고 도둑 하나를 직접 낸다.
	g.get("enemies").clear()
	g.set("seen_types", {})
	_plant_thief(3, rows - 1)
	print("① 등장    : '%s'" % g.get("callout_text"))

	# ② 훔치는 순간 — advance_step 한 번이면 row가 ROWS에 닿아 grab이 돈다.
	g.call("advance_step")
	var es: Array = g.get("enemies")
	var carrying: bool = (not es.is_empty()) and bool(es[0].get("carrying", false))
	print("② 훔친 뒤 : '%s'  (carrying=%s · 플래그=%s)" % [
			g.get("callout_text"), str(carrying),
			str(g.get("seen_types").get("thief_stolen", false))])

	# ③ 판당 1회 — 두 번째 도둑이 또 훔쳐도 콜아웃은 안 바뀌어야 한다.
	g.call("_set_callout", "(지움)", -1)
	g.get("enemies").clear()
	_plant_thief(5, rows - 1)
	g.call("advance_step")
	print("③ 두 번째 : '%s'  ← '(지움)'이면 재발화 없음(정상)" % g.get("callout_text"))
	print("DONE")
	quit()

func _plant_thief(col: int, row: int) -> void:
	var seq: int = int(g.get("enemy_seq"))
	g.get("enemies").append({
		"col": col, "row": row, "vis_row": float(row), "hp": 999, "maxhp": 999,
		"etype": "thief", "id": seq, "step_every": 1, "carrying": false,
	})
	g.set("enemy_seq", seq + 1)
	# 등장 콜아웃은 스폰 경로가 내므로, 직접 심을 땐 같은 규율(타입당 1회)로 흉내낸다.
	var st: Dictionary = g.get("seen_types")
	if not st.get("thief", false):
		st["thief"] = true
		g.call("_set_callout", g.call("_t", "callout_thief"), seq)
