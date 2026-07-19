extends SceneTree
# C61 seam 스모크(헤드리스 OK — 로직만, 렌더 X): 점수·retry가 감독 능력으로 도는가.
#   godot --headless --path . --script tools/seam_smoke.gd
func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)

	# ── 스테이지: scores()=false, 점수 미누적, retry_kind=stage ──
	g.call("_start_stage", 0)
	var d1 = g.get("director")
	var stage_scores: bool = d1.scores()
	var stage_clearsc: int = d1.clear_score(2)
	var stage_killsc: int = d1.kill_score(3)
	var stage_retry: String = d1.retry_kind()
	var stage_dda: bool = d1.allows_dda()
	print("STAGE: scores=%s clear_score(2)=%d kill_score(3)=%d retry=%s dda=%s" % [
		str(stage_scores), stage_clearsc, stage_killsc, stage_retry, str(stage_dda)])

	# ── 무한: scores()=true, 점수식, retry_kind=new_run ──
	g.call("_start_endless")
	var d2 = g.get("director")
	print("ENDLESS: scores=%s clear_score(2)=%d kill_score(3)=%d retry=%s dda=%s" % [
		str(d2.scores()), d2.clear_score(2), d2.kill_score(3), d2.retry_kind(), str(d2.allows_dda())])
	# 점수 누적 경로(감독 호출) 실동작
	g.set("endless_score", 0)
	g.set("combo", 4)
	g.call("_add_endless_score", d2.kill_score(g.get("combo")))
	var acc: int = g.get("endless_score")   # HOME 섹션의 _start_*가 리셋하기 전에 캡처
	print("ENDLESS accumulate: combo=4 kill_score→score=%d (기대 400)" % acc)

	# ── _home_mode: 무한=menu, 스테이지=select ──
	g.call("_start_endless"); var hm_e: String = g.call("_home_mode")
	g.call("_start_stage", 0); var hm_s: String = g.call("_home_mode")
	print("HOME: endless=%s stage=%s (기대 menu/select)" % [hm_e, hm_s])

	var ok: bool = (not stage_scores) and stage_clearsc == 0 and stage_killsc == 0 \
		and stage_retry == "stage" and stage_dda \
		and d2.scores() and d2.clear_score(2) == 100 and d2.kill_score(3) == 300 \
		and d2.retry_kind() == "new_run" and not d2.allows_dda() \
		and acc == 400 and hm_e == "menu" and hm_s == "select"
	print("SEAM_OK=%s" % str(ok))
	quit()
