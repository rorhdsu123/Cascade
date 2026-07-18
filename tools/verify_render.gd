extends SceneTree
# 창 모드 렌더 스모크 — 리팩터 후 감독 접근자(core_hp_max/enemy_total/hud_step_every)가
#   렌더 경로에서 크래시 없이 올바른 값을 그리는지. 시드 프로브(로직)가 못 잡는 렌더를 검증.
# 실행: /opt/homebrew/bin/godot --path . --script tools/verify_render.gd   (창 모드 필수)
const SP := "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/c99d40d4-265c-4b53-a6eb-1db7bfadcea4/scratchpad"

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# ① 감독 값이 STAGES와 일치하는지 (렌더가 읽는 3개 접근자)
	print("── 감독 접근자 vs STAGES ──")
	for si in range(main.STAGES.size()):
		main.call("_start_stage", si)
		var d = main.get("director")
		var stg = main.STAGES[si]
		var ok = d.core_hp_max() == int(stg["core_hp"]) and d.enemy_total() == int(stg["total"]) and d.hud_step_every() == int(stg["step_every"])
		print("stage %d: core_hp_max=%d total=%d hud_step=%d  %s" % [
			si, d.core_hp_max(), d.enemy_total(), d.hud_step_every(), "OK" if ok else "❌MISMATCH"])

	# ② 플레이 HUD 스샷 (hp바=core_hp_max, 목표카드=enemy_total, 전진시계=hud_step_every 렌더)
	main.call("_start_stage", 3)
	await process_frame
	for i in range(5):
		main.call("advance_step")
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/verify_play.png")

	# ③ 클리어 결과 + 색종이 (enemy_total 읽는 _draw_result)
	main.set("game_clear", true)
	main.call("_spawn_confetti")
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/verify_clear.png")

	# ④ 실패 결과 (_fail_headline·_draw_result의 enemy_total 읽기)
	main.call("_start_stage", 3)
	await process_frame
	main.set("killed", 10)
	main.set("leaked", 2)
	main.set("game_over", true)
	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SP + "/verify_fail.png")

	print("saved: verify_play/clear/fail.png")
	quit()
