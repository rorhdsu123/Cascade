extends SceneTree
# 세이브 감사 검증 — 캠페인 진행도 영속 라운드트립 + 손상(부분쓰기) 내성.
#   godot --path . --script tools/save_probe.gd
# [[godot-pixel-verify-needs-window]] Main._ready가 렌더 셋업을 타므로 창 필수(--headless 금지).

const CAMPAIGN_SAVE := "user://campaign.save"
const SETTINGS_SAVE := "user://settings.save"

var _fail := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fail += 1

func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fresh_main() -> Node:
	var g: Node = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	return g

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(800, 1000))

	# ── 1. 클리어 → 저장 → 새 부팅에서 복원 ──────────────────────────
	_rm(CAMPAIGN_SAVE)
	var g1: Node = await _fresh_main()
	# 부팅 직후 진행도 0(파일 없음): 스테이지 1만 열림
	_check("boot: stage0 unlocked", g1.call("_is_unlocked", 0))
	_check("boot: stage1 locked", not g1.call("_is_unlocked", 1))
	_check("boot: stage2 locked", not g1.call("_is_unlocked", 2))
	# 스테이지 0·1 클리어를 흉내내고 저장(실게임 _check_win 경로와 동일한 상태변화)
	var cl: Dictionary = g1.get("cleared")
	cl[0] = true
	cl[1] = true
	g1.call("_save_campaign")
	g1.free()

	var g2: Node = await _fresh_main()
	var cl2: Dictionary = g2.get("cleared")
	_check("reload: stage0 cleared", bool(cl2.get(0, false)))
	_check("reload: stage1 cleared", bool(cl2.get(1, false)))
	_check("reload: stage2 not cleared", not bool(cl2.get(2, false)))
	# 해금 규칙까지 관통: 직전 깬 스테이지 2가 열리고, 3은 잠김
	_check("reload: stage2 unlocked", g2.call("_is_unlocked", 2))
	_check("reload: stage3 locked", not g2.call("_is_unlocked", 3))
	g2.free()

	# ── 2. 손상(부분쓰기 1바이트) → 기본값으로 안전 강등 ─────────────
	var bad := FileAccess.open(CAMPAIGN_SAVE, FileAccess.WRITE)
	bad.store_8(0x7f)   # 4바이트 미만
	bad.close()
	var g3: Node = await _fresh_main()
	var cl3: Dictionary = g3.get("cleared")
	_check("corrupt: no phantom unlocks", cl3.size() == 0)
	_check("corrupt: stage1 locked", not g3.call("_is_unlocked", 1))
	g3.free()

	# ── 3. 설정 손상(0바이트) → sound_on 기본 true 유지 ─────────────
	_rm(SETTINGS_SAVE)
	var badf := FileAccess.open(SETTINGS_SAVE, FileAccess.WRITE)
	badf.close()   # 0바이트
	var g4: Node = await _fresh_main()
	_check("corrupt settings: sound_on stays true", bool(g4.get("sound_on")))
	g4.free()

	_rm(CAMPAIGN_SAVE)
	_rm(SETTINGS_SAVE)
	print("RESULT " + ("ALL PASS" if _fail == 0 else str(_fail) + " FAIL"))
	quit(_fail)
