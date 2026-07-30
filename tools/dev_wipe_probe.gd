extends SceneTree
# ⚠플테 전용 초기화 버튼 검증 — 렌더(기본/무장) + 두 번 눌러야 실행 + 저장 마스크가 0이 되는지.
#   실제 세이브 파일을 건드리므로, 시작값을 백업했다가 끝에서 되돌린다.
const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade-worktrees-stage/da1f7fc4-8514-4560-89c7-00eb54dcada2/scratchpad/wipe"
var main: Node
func _initialize() -> void: _run.call_deferred()

func _mask() -> int:
	var p: String = "user://campaign.save"
	if not FileAccess.file_exists(p):
		return -1
	var f := FileAccess.open(p, FileAccess.READ)
	var m: int = f.get_32() if f.get_length() >= 4 else -1
	f.close()
	return m

func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var backup: int = _mask()

	# 진행도가 있는 상태를 만든다(1~5 클리어)
	var cl: Dictionary = main.get("cleared")
	cl.clear()
	for i in range(5):
		cl[i] = true
	main.call("_save_campaign")
	main.set("mode", "select")
	main.call("_sel_enter")
	print("초기 마스크=", _mask(), " 클리어수=", main.call("_cleared_count"))

	paused = true
	main.call("queue_redraw"); await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_idle.png")

	main.set("_dev_reset_arm", 2.5)     # 무장 상태 렌더
	main.call("queue_redraw"); await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_armed.png")
	paused = false

	# 첫 탭만으로는 안 지워져야 한다
	main.set("_dev_reset_arm", -1.0)
	print("첫 탭(무장만) 뒤 마스크=", _mask(), " → 아직 그대로여야 함")

	main.call("_dev_wipe_progress")
	await process_frame
	print("실행 후: 마스크=", _mask(), " 클리어수=", main.call("_cleared_count"),
			" 무한해금=", main.call("_endless_unlocked"), " dev_unlock_all=", main.get("dev_unlock_all"))

	main.call("queue_redraw"); await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "_after.png")

	# 원상 복구
	if backup < 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://campaign.save"))
		print("복구: 원래 파일이 없었으므로 삭제 (시작값=", backup, ")")
	else:
		var cl2: Dictionary = main.get("cleared")
		cl2.clear()
		for i in range(32):
			if backup & (1 << i) != 0:
				cl2[i] = true
		main.call("_save_campaign")
		print("복구 마스크=", _mask(), " (시작값=", backup, ")")
	print("DONE"); quit()
