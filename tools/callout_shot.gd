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
	print("DONE")
	quit()
