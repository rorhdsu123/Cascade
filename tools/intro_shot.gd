extends SceneTree
# 스테이지 인트로 카드 위상별 캡처 — 중앙 등장 → 상단 목표 카드 도킹. 창 필수([[godot-pixel-verify-needs-window]]).
#   godot --path . --script tools/intro_shot.gd
# intro_t를 직접 세팅해 위상(appear/hold/dock)을 결정적으로 잡는다(±1틱 미세 드리프트 무시 가능).

const DIR: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/044773c2-357e-40d6-bf33-6bd037c3a086/scratchpad/intro_"

var g: Node

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)
	print("shot ", name)

# 특정 스테이지 인트로를 특정 위상(t)에서 잡는다. 매번 intro_t를 재설정.
func _phase(stage: int, t: float, name: String) -> void:
	g.call("_start_stage", stage)
	await process_frame
	g.set("intro_t", t)
	await _shot(name)

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 1000))
	await process_frame

	# S5 장갑 — 등장 → 홀드 → 칩 비행(밴드 페이드) → 칩 상단 근접
	await _phase(4, 0.14, "s5_appear.png")
	await _phase(4, 0.60, "s5_hold.png")
	await _phase(4, 0.92, "s5_fly1.png")
	await _phase(4, 1.06, "s5_fly2.png")

	# 판별 콘텐츠 차이 — S2 무리 · S7 분열 홀드컷
	await _phase(1, 0.60, "s2_hold.png")
	await _phase(6, 0.60, "s7_hold.png")

	print("DONE")
	quit()
