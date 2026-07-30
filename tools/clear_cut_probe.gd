extends SceneTree
# 연출 → 결과 팝업 '이음매'를 실시간으로 본다. 색종이가 실제로 어디 있는지, 컷 순간에 뭐가 바뀌는지
#   확인하려면 일시정지로는 안 된다(파티클이 안 움직임) — 그냥 돌리면서 매 프레임 찍는다.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/309ebea2-5f92-4557-9f51-4e014e6e67d6/scratchpad/cut"
var main: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 3)
	await process_frame
	var st: Dictionary = main.get("st")
	main.set("killed", int(st["total"])); main.set("leaked", 0)
	main.set("game_over", false); main.set("game_clear", true)
	main.call("_plan_clear_fx")           # 실제 클리어와 같은 계획(색종이는 1.0s에 자동 발화)
	main.set("clear_show_t", -main.get("CLEAR_HOLD"))   # 프리롤부터 = 실제 승리와 같은 시작점

	var shots: Array = [-0.90, -0.72, -0.60, -0.50, -0.20, -0.04, 0.06, 0.30, 0.62, 1.05, 2.20, 2.75]
	var idx: int = 0
	for _n in range(600):
		await process_frame
		await RenderingServer.frame_post_draw
		var t: float = float(main.get("clear_show_t"))
		if idx < shots.size() and t >= float(shots[idx]):
			root.get_texture().get_image().save_png("%s_%03d.png" % [OUT, int(round(float(shots[idx]) * 100.0))])
			print("shot ", shots[idx], " (실제 t=", t, ")")
			idx += 1
		if idx >= shots.size():
			break
	# 컷 직후 — 무대가 꺼지고 팝업이 뜬 첫 프레임들
	for k in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_cut1.png")
	print("cut1 stage_on=", main.call("_clear_stage_on"))
	for k2 in range(8):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_cut2.png")
	print("cut2 result_t=", main.get("result_t"))
	for k3 in range(40):
		await process_frame
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_cut3.png")
	print("cut3 result_t=", main.get("result_t"), " (버튼이 떠 있어야 함)")
	print("DONE"); quit()
