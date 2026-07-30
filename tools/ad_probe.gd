extends SceneTree
# 광고 배관 검증 (Phase V W2 R1 — 설계 정본 AD_PLAN.md §6).
#   실행: godot --headless --path . --script tools/ad_probe.gd
#   (헤드리스 OK — 렌더를 안 보고 상태 기계만 본다. AdService는 헤드리스서 스스로 꺼지므로
#    프로브가 enabled를 손으로 켠다 = '꺼짐이 기본'이라는 불변식 ②를 깨지 않으면서 검증.)
#
# 무엇을 보나 — AD_PLAN §6의 6시나리오:
#   1) fill → 끝까지 시청 → 부활(ad_reward)
#   2) fill → 중도 취소 → 부활 안 됨 + 기회 소진 안 됨(다시 누르면 됨)
#   3) no-fill → 공짜 부활(free_fallback)
#   4) 부활 1회 쓴 뒤 재실패 → 이어하기 버튼 안 뜸(판당 1회)
#   5) 인터스티셜 캡 카운터(첫 2판 면제 + 3판 AND 3분)
#   6) 두 부활 경로 모두 놓을 자리 보장(소프트락 안전망 d6689ad 유지)

const AdService = preload("res://ad_service.gd")

var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("%s %s%s" % ["OK  " if ok else "FAIL", tag, ("  — " + detail) if detail != "" else ""])

# --- 게임 헬퍼 (analytics_probe와 동형) ---

func _settle() -> void:
	var s: int = 0
	while g.resolving and s < 400:
		g._process(0.05)
		s += 1

# 거점사 강제 — 실제 판정 경로(_end_turn의 pending_core_dead 분기)를 그대로 탄다.
func _force_core_death() -> void:
	g.core_hp = 0
	g.pending_core_dead = true
	g._end_turn()
	_settle()

# 트레이에 실제로 놓을 수 있는 조각이 하나라도 있나 — 부활의 최소 계약(부활은 놓을 수 있어야 부활).
func _any_placeable() -> bool:
	for slot in range(3):
		if g.tray[slot].is_empty():
			continue
		var offsets: Array = g.tray[slot]["offsets"]
		for r in range(g.ROWS):
			for c in range(g.COLS):
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS or g.board[cc.y][cc.x] != "":
						ok = false
						break
				if ok:
					return true
	return false

func _has(ev: String) -> bool:
	return (g._ads.debug_events as Array).has(ev)

func _clear_events() -> void:
	(g._ads.debug_events as Array).clear()

# --- 5) 인터스티셜 캡: 서비스 단독 검증(게임 없이, 시간 주입) ---

func _probe_interstitial_cap() -> void:
	var s = AdService.new(null)
	s.enabled = true
	s.interstitial_enabled = true    # ⚠게임에선 꺼져 있다. 정책 자체를 재려고 여기서만 켠다.
	s.set_test_time_ms(0)
	# 첫 2판은 무조건 면제
	s.note_run_started()
	_check("cap: 1판째 면제", not s.should_show_interstitial())
	s.note_run_started()
	_check("cap: 2판째 면제", not s.should_show_interstitial())
	# 3판째 = 면제는 끝났지만 아직 3분이 안 지났다 → '늦은 쪽'이라 안 뜸
	s.note_run_started()
	_check("cap: 3판째도 3분 전이면 안 뜸", not s.should_show_interstitial())
	# 3분 경과 + 3판 누적 → 뜬다
	s.set_test_time_ms(190000)
	_check("cap: 3판+3분 충족이면 뜸", s.should_show_interstitial())
	s.show_interstitial()
	_check("cap: 노출 직후 카운터 리셋", not s.should_show_interstitial())
	# 시간만 더 흘러도 판 수가 안 찼으면 안 뜬다(AND 판정 확인)
	s.set_test_time_ms(600000)
	s.note_run_started()
	s.note_run_started()
	_check("cap: 시간만 지나고 판 수 미달이면 안 뜸", not s.should_show_interstitial())
	s.note_run_started()
	_check("cap: 판 수까지 차면 뜸", s.should_show_interstitial())
	# 게임 기본값은 꺼짐 — 배관만 깔고 노출은 off(AD_PLAN §3)
	var off = AdService.new(null)
	off.enabled = true
	for i in range(9):
		off.note_run_started()
	off.set_test_time_ms(999999)
	_check("cap: 게임 기본값은 노출 off", not off.should_show_interstitial())

# --- 게임 통합 ---

# ⚠노브는 반드시 _start_stage 전에 세운다 — 프리로드가 판 시작(_init_game)에서 일어나므로,
#   나중에 세우면 이미 채워진 광고를 쥔 채라 no-fill 경로가 안 열린다(첫 실행서 이 순서에 걸렸다).
func _fresh_run(fill: bool = true) -> void:
	g._ads.enabled = true          # 헤드리스라 꺼진 걸 다시 켠다(프로브 한정)
	g._ads.fake_fill = fill
	g._ads.fake_user_cancel = false
	g._ads.fake_error = false
	g._ads.fake_load_ms = 0
	g._ads.fake_watch_ms = 0
	g._ads._rewarded_ready = false  # 이전 시나리오가 손에 쥔 광고를 비운다(시나리오 독립성)
	g._start_stage(0)
	_clear_events()                 # 프리로드 발화는 버리고, 이후 '누름' 경로만 본다

func _run() -> void:
	_probe_interstitial_cap()

	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	# ── 1) fill → 끝까지 시청 → 광고 부활 ─────────────────────────────
	_fresh_run()
	await process_frame
	_force_core_death()
	_check("1: 실패로 부활 제안이 열림", g.game_over and not g.revive_used)
	_check("1: 제안 시점에 광고가 준비돼 있음", g._ads.is_rewarded_ready(), "프리로드 실값")
	g._request_revive_ad()
	_check("1: 부활 성사", g.revive_used and not g.game_over)
	_check("1: 보상 이벤트 발화", _has("ad_rewarded") and _has("ad_shown"))
	_check("6: 광고 부활 후 놓을 자리 있음", _any_placeable(), "소프트락 안전망")

	# ── 4) 판당 1회 — 부활 쓴 뒤 재실패하면 버튼이 안 뜬다 ──────────────
	_force_core_death()
	_check("4: 재실패 시 이어하기 버튼 없음", not bool(g._result_layout()["revivable"]))
	g._request_revive_ad()
	_check("4: 소진 후 요청은 무시됨", g.game_over, "판은 그대로 종료 상태")

	# ── 2) fill → 중도 취소 → 부활 안 됨 + 기회 소진 안 됨 ──────────────
	_fresh_run()
	await process_frame
	g._ads.fake_user_cancel = true
	_force_core_death()
	g._request_revive_ad()
	_check("2: 중도 취소면 부활 안 됨", g.game_over and not g.revive_used)
	_check("2: 기회 소진 안 됨(버튼 유지)", bool(g._result_layout()["revivable"]))
	_check("2: 이탈 이벤트 발화", _has("ad_closed") and not _has("ad_rewarded"))
	# 다시 누르면 이번엔 끝까지 본다 → 부활
	g._ads.fake_user_cancel = false
	g._request_revive_ad()
	_check("2: 재시도하면 부활됨", g.revive_used and not g.game_over)

	# ── 3) no-fill → 공짜 부활 ────────────────────────────────────────
	_fresh_run(false)          # 판 시작부터 재고 없음 = 프리로드 실패 상태로 죽는다
	await process_frame
	_force_core_death()
	_check("3: no-fill이면 준비 안 됨", not g._ads.is_rewarded_ready())
	_check("3: 그래도 버튼은 뜬다", bool(g._result_layout()["revivable"]), "재고 없음은 유저 잘못이 아니다")
	g._request_revive_ad()
	_check("3: 공짜로 이어짐", g.revive_used and not g.game_over)
	_check("3: no-fill 이벤트 발화", _has("ad_no_fill") and not _has("ad_rewarded"))
	_check("6: 공짜 부활 후 놓을 자리 있음", _any_placeable(), "소프트락 안전망")

	# ── 로드 지연 = 대기 상태(팝업 잠금)가 실제로 서고 풀리는가 ───────────
	_fresh_run()
	await process_frame
	g._ads.fake_load_ms = 500
	g._ads.fake_watch_ms = 500
	# 손에 쥔 광고를 비운다 — 그래야 누름이 '로드 → 시청' 2단계를 다 통과한다(프리로드가 이미
	#   채워져 있으면 로드 단계가 통째로 건너뛰어 대기 상태를 절반만 재게 된다).
	g._ads._rewarded_ready = false
	_force_core_death()
	g._request_revive_ad()
	_check("대기: 요청 직후 팝업 잠김", g._ad_pending and g._ads.is_busy())
	_check("대기: 아직 부활 전", not g.revive_used)
	g._ads.poll(0.6)     # 로드 완료 → 시청 시작
	_check("대기: 시청 중에도 잠김 유지", g._ad_pending)
	g._ads.poll(0.6)     # 시청 완료 → 보상
	_check("대기: 콜백 도착 후 잠금 해제", not g._ad_pending)
	_check("대기: 부활 성사", g.revive_used and not g.game_over)

	print("\n=== ad_probe: %s ===" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	quit(1 if fails > 0 else 0)
