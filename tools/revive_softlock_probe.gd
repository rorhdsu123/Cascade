extends SceneTree
# 부활 배치-소프트락 수정 확인 (일회성) — C89(웨이브 회계)와 별개인 '부활 후 놓을 자리 없음' 경로.
#   전제: 부활 직후 못 놓으면 턴 전환이 없어 막힘 재판정(_end_turn)이 안 돌아 게임오버도 안 뜬다.
#   각 시나리오마다 ① 구(舊) 로직(하단 3줄만 비우고 트레이 유지)이 소프트락(못 놓음)인지
#   ② 신(新) _revive()(트레이 리필 + 안전망) 후 _has_valid_placement()==true 인지를 대조한다.

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	print("── 부활 배치-소프트락 프로브 ──")

	var det: bool = false

	# 시나리오 A: 막힘사 + 트레이에 세로 5칸(I5v). 보드 만원.
	_scn(g, "A 막힘사·I5v·만원", true, func():
		for r in range(g.ROWS):
			for c in range(g.COLS):
				g.board[r][c] = "B"
		g.tray[0] = _piece(g, "I5v", "B")
		g.tray[1] = {}
		g.tray[2] = {}
		g.sel = 0
	)

	# 시나리오 B: 거점사 + 트레이에 I5v. 보드 만원(거점사는 board를 안 비우므로 안전망만이 살림).
	det = g.director.deterministic_track()
	_scn(g, "B 거점사·I5v·만원", false, func():
		for r in range(g.ROWS):
			for c in range(g.COLS):
				g.board[r][c] = "B"
		g.tray[0] = _piece(g, "I5v", "B")
		g.tray[1] = {}
		g.tray[2] = {}
		g.sel = 0
	)

	# 시나리오 C: 막힘사 + 상단 5줄 채우고 하단 3줄만 빈 = 구 로직이 딱 못 끼우는 세로 5칸.
	_scn(g, "C 막힘사·상단5줄·I5v", true, func():
		for r in range(g.ROWS):
			for c in range(g.COLS):
				g.board[r][c] = "B" if r < g.ROWS - g.REVIVE_CLEAR_ROWS else ""
		g.tray[0] = _piece(g, "I5v", "B")
		g.tray[1] = {}
		g.tray[2] = {}
		g.sel = 0
	)

	print("(참고) 이 스테이지 결정적 트랙 = %s" % det)
	quit()

func _piece(g: Node, ty: String, col: String) -> Dictionary:
	return {"type": ty, "color": col, "offsets": (g.PIECES[ty] as Array).duplicate()}

# was_stuck=true → 막힘사 경로, false → 거점사 경로로 _revive() 태움
func _scn(g: Node, name: String, was_stuck: bool, setup: Callable) -> void:
	g._start_stage(3)

	# ── 구 로직 재현: 하단 REVIVE_CLEAR_ROWS만 비우고(막힘사) 트레이는 그대로 유지 → 놓을 자리?
	setup.call()
	if was_stuck:
		for r in range(g.ROWS - g.REVIVE_CLEAR_ROWS, g.ROWS):
			for c in range(g.COLS):
				g.board[r][c] = ""
	var old_ok: bool = g._has_valid_placement()

	# ── 신 로직: 실제 _revive() 태우고 놓을 자리 보장되는지
	setup.call()
	g.game_over = true
	g.stuck = was_stuck
	g.revive_used = false
	g._revive()
	var new_ok: bool = g._has_valid_placement()

	var verdict: String = "✅" if new_ok else "❌"
	print("%s [%s] 구로직 놓을자리=%s → 신_revive 놓을자리=%s (트레이 %d개)" % [
		verdict, name, "있음" if old_ok else "없음(소프트락)",
		"있음" if new_ok else "없음(소프트락)", _tray_n(g)])

func _tray_n(g: Node) -> int:
	var n: int = 0
	for i in range(3):
		if not g.tray[i].is_empty():
			n += 1
	return n
