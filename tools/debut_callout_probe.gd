extends SceneTree
# 콜아웃 이음새 탐침 — "도입판 시작 적의 콜아웃이 인트로 카드 뒤로 미뤄졌다가, 카드가 끝나면 뜬다".
#   숫자로 확인한다(스크린샷은 창 모드가 필요하고 눈으로는 1.13s 겹침을 못 가린다).
#   godot --headless --path . --script tools/debut_callout_probe.gd

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.set("persist_enabled", false)   # ⚠_ready가 켠다 — 안 끄면 봇의 클리어가 실유저 진행도에 각인된다(regress와 동형 가드)
	g.cleared[0] = true
	var fails: int = 0
	# ① 도입판(3판 = fast) — 시작 적이 신규 타입이고, 콜아웃은 대기열에 있어야 한다.
	g._start_stage(2)
	var et0: String = String(g.enemies[0]["etype"]) if not g.enemies.is_empty() else "(없음)"
	fails += _chk("도입판 시작 적 = fast", et0 == "fast", et0)
	fails += _chk("콜아웃 대기중", g.callout_pending != "", g.callout_pending)
	fails += _chk("카드 중엔 배너 안 뜸", g.callout_timer == 0.0, str(g.callout_timer))
	# 인트로 카드가 도는 동안(1.13s)에도 배너는 계속 잠겨 있어야 한다.
	var t: float = 0.0
	while t < g.INTRO_TOTAL - 0.05:
		g._process(0.05)
		t += 0.05
	fails += _chk("카드 재생 내내 잠김", g.callout_timer == 0.0 and g.callout_pending != "", str(g.callout_timer))
	# 카드가 끝나면 그제야 만충으로 켜진다.
	g._process(0.2)
	fails += _chk("카드 끝 → 배너 점등", g.callout_timer > 0.0, "%.2fs" % g.callout_timer)
	fails += _chk("배너 수명 만충", g.callout_timer > g.CALLOUT_DUR - 0.3, "%.2f / %.2f" % [g.callout_timer, g.CALLOUT_DUR])
	fails += _chk("대기열 비움", g.callout_pending == "", g.callout_pending)
	fails += _chk("문구 = 속공", g.callout_text.find("속공") >= 0 or g.callout_text.find("FAST") >= 0, g.callout_text)
	# ② 도입판이 아닌 판(4판 = 새 타입 없음) — 시작 적은 종전대로 basic, 대기열도 비어 있어야 한다.
	g._start_stage(3)
	var et1: String = String(g.enemies[0]["etype"]) if not g.enemies.is_empty() else "(없음)"
	fails += _chk("비도입판 시작 적 = basic", et1 == "basic", et1)
	fails += _chk("비도입판 대기열 없음", g.callout_pending == "", g.callout_pending)
	# ③ 튜토리얼 판(1판)은 시작 적 자체가 없다(박자1 무대) — 건드리지 않았는지.
	g.cleared[0] = false
	g._start_stage(0)
	fails += _chk("튜토리얼 판 무영향", g.enemies.is_empty(), "적 %d마리" % g.enemies.size())
	g.cleared[0] = true
	print("결과: %s" % ("전항 통과" if fails == 0 else "%d항 실패" % fails))
	quit()

func _chk(label: String, ok: bool, got: String) -> int:
	print("  %s %-24s : %s" % ["OK  " if ok else "실패", label, got])
	return 0 if ok else 1
