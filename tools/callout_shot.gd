extends SceneTree
# 도입판 콜아웃 배너 캡처 — 인트로 카드가 끝난 직후(배너가 떠 있어야 하는 순간)를 프레임으로 뜬다.
#   창 필수([[godot-pixel-verify-needs-window]]). godot --path . --script tools/callout_shot.gd
# 눈으로 1.6초를 잡는 대신 상태를 직접 굴려 결정적으로 잡는다: _start_stage → 카드 시간만큼 _process →
#   그 프레임 캡처. 배너가 안 보이면 '못 본 것'인지 '안 그려진 것'인지 여기서 갈린다.

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/dc33be79-19cc-4ca2-893d-f1dd426c456d/scratchpad/callout_"

var g: Node

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)
	print("shot ", name)

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	g.set("persist_enabled", false)
	g.set("dev_unlock_all", true)
	DisplayServer.window_set_size(Vector2i(800, 1000))
	await process_frame

	# 3판(속공 도입). 카드가 도는 동안 = 배너 잠김 / 카드 직후 = 배너 점등.
	g.call("_start_stage", 2)
	await process_frame
	print("시작 적 = %s · 대기 문구 = '%s'" % [
		String(g.get("enemies")[0]["etype"]) if not g.get("enemies").is_empty() else "(없음)",
		g.get("callout_pending")])
	await _shot("st3_card.png")            # 카드 재생 중(배너 없어야 정상)
	# 카드 총 길이(INTRO_TOTAL)만큼 굴린다 — 그 다음 프레임부터 배너.
	var steps: int = int(g.get("INTRO_TOTAL") / 0.05) + 2
	for i in range(steps):
		g.call("_process", 0.05)
	print("카드 후: intro_t=%.2f · 배너 남은 시간=%.2fs · 문구='%s'" % [
		g.get("intro_t"), g.get("callout_timer"), g.get("callout_text")])
	await _shot("st3_banner.png")           # 배너 만충 순간
	for i in range(8):                       # 0.4s 뒤(사람이 실제로 볼 구간)
		g.call("_process", 0.05)
	print("0.4s 뒤: 배너 남은 시간=%.2fs" % g.get("callout_timer"))
	await _shot("st3_banner_04.png")

	# ── 배치 경우의 수 — 말풍선이 판을 벗어나거나 대상을 놓치지 않는지 ──
	#   앵커를 직접 옮겨 잡는다(스폰 RNG를 기다리면 열이 매번 달라져 재현이 안 된다).
	await _case(0, 4, "deep_left.png")       # 깊은 행 + 왼쪽 끝 열 → 위로 뒤집히고 가로 클램프
	await _case(7, 5, "deep_right.png")      # 깊은 행 + 오른쪽 끝 열
	await _case(0, 0, "top_left.png")        # 맨 윗줄 왼쪽 끝 → 아래로 뒤집힘
	# ── 긴 문구 — 비행기·도둑은 한 줄로 판보다 넓다. 접혀서 판 안에 들어와야 한다. ──
	await _long(0, 3, "callout_plane", "long_plane_left.png")
	await _long(7, 0, "callout_thief", "long_thief_topright.png")
	# 대상이 죽은 경우 — 마지막 자리에 남아 페이드해야 한다(화면을 가로질러 튀면 안 된다).
	g.get("enemies").clear()
	await _shot("anchor_dead.png")
	print("앵커 소멸 후: 남은 시간=%.2fs (마지막 자리 유지)" % g.get("callout_timer"))
	print("DONE")
	quit()

func _long(col: int, row: int, key: String, name: String) -> void:
	var es: Array = g.get("enemies")
	if es.is_empty():
		return
	var e: Dictionary = es[0]
	e["col"] = col
	e["row"] = row
	e["vis_row"] = float(row)
	g.call("_set_callout", g.call("_t", key), int(e["id"]))
	await _shot(name)

func _case(col: int, row: int, name: String) -> void:
	var es: Array = g.get("enemies")
	if es.is_empty():
		return
	var e: Dictionary = es[0]
	e["col"] = col
	e["row"] = row
	e["vis_row"] = float(row)
	g.call("_set_callout", "FAST — quick!", int(e["id"]))
	await _shot(name)
