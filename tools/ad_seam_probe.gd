extends SceneTree
# 광고 이음매 검증 (AD_PLAN §3) — 인터스티셜의 자리는 '결과 화면을 닫고 다음 판을 열기 직전' 한 곳뿐이고,
#   다음 판 시작은 광고 콜백(또는 안전밸브)까지 미뤄진다. 여기서 못 박는 것:
#     A. 노출 OFF(기본) = 예전과 동일하게 즉시 다음 판 — 회귀 없음
#     B. 노출 ON + 재고 있음 = 광고를 거쳐서 다음 판(ad_shown 기록 + 판이 실제로 열림)
#     C. no-fill = 콜백이 실패로 와도 다음 판이 열린다(광고 실패가 진행을 막지 않음)
#     D. 콜백 침묵 = AD_SEAM_TIMEOUT 뒤 안전밸브가 판을 연다(진행이 광고에 인질로 안 잡힘)
#     E. 판 시작 지점(_init_game)에서는 인터스티셜을 띄우지 않는다(진입 연출을 먹는 자리)
# 실행: godot --headless --path . --script tools/ad_seam_probe.gd

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var fails: int = 0

	# ── A. 기본(노출 OFF): 즉시 다음 판
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g._start_stage(3)
	g.set_process(false)
	g.game_clear = true
	g._result_advance()
	var a_ok: bool = g.stage_idx == 4 and g._ad_seam_t < 0.0
	print("[A] 노출OFF → stage_idx=%d seam=%.1f  (4 / -1 이어야)  %s" % [g.stage_idx, g._ad_seam_t, "OK" if a_ok else "FAIL"])
	if not a_ok: fails += 1

	# ── B. 노출 ON + 재고 있음: 광고를 거쳐 다음 판
	var g2: Node = S.new()
	root.add_child(g2)
	await process_frame
	g2._start_stage(3)
	g2.set_process(false)
	_arm_interstitial(g2, true)
	g2.game_clear = true
	g2._result_advance()
	var shown: bool = g2._ads.debug_interstitial_attempts == 1 and (g2._ads.debug_events as Array).has("ad_shown")
	var b_ok: bool = shown and g2.stage_idx == 4 and g2._ad_seam_t < 0.0 and not g2._ad_pending
	print("[B] 노출ON+재고 → ad_shown=%s stage_idx=%d pending=%s  (true/4/false 이어야)  %s"
			% [shown, g2.stage_idx, g2._ad_pending, "OK" if b_ok else "FAIL"])
	if not b_ok: fails += 1

	# ── C. no-fill: 실패 콜백이 와도 다음 판이 열린다
	var g3: Node = S.new()
	root.add_child(g3)
	await process_frame
	g3._start_stage(3)
	g3.set_process(false)
	_arm_interstitial(g3, false)
	g3.game_clear = true
	g3._result_advance()
	var no_fill: bool = g3._ads.debug_interstitial_attempts == 1 and not (g3._ads.debug_events as Array).has("ad_shown")
	var c_ok: bool = no_fill and g3.stage_idx == 4
	print("[C] no-fill → 인터스티셜시도=%d 노출없음 stage_idx=%d  (1/4 이어야)  %s"
			% [g3._ads.debug_interstitial_attempts, g3.stage_idx, "OK" if c_ok else "FAIL"])
	if not c_ok: fails += 1

	# ── D. 안전밸브: 콜백이 안 오는 상황을 손으로 만들고 타임아웃까지 굴린다
	var g4: Node = S.new()
	root.add_child(g4)
	await process_frame
	g4._start_stage(3)
	g4.set_process(false)
	g4.game_clear = true
	g4._ad_seam_t = 0.0        # 광고를 띄웠고 콜백이 침묵하는 상태
	g4._ad_pending = true
	var before: int = g4.stage_idx
	g4._process(g4.AD_SEAM_TIMEOUT * 0.5)
	var mid_held: bool = g4.stage_idx == before      # 절반 시점엔 아직 안 열려야 한다
	g4._process(g4.AD_SEAM_TIMEOUT * 0.6)
	var d_ok: bool = mid_held and g4.stage_idx == before + 1 and g4._ad_seam_t < 0.0 and not g4._ad_pending
	print("[D] 콜백침묵 → 절반유지=%s 타임아웃후 stage_idx=%d pending=%s  (true/4/false 이어야)  %s"
			% [mid_held, g4.stage_idx, g4._ad_pending, "OK" if d_ok else "FAIL"])
	if not d_ok: fails += 1

	# ── E. 판 시작 지점에서는 안 띄운다: 캡을 다 채워 놓고 _start_stage만 해본다
	var g5: Node = S.new()
	root.add_child(g5)
	await process_frame
	g5.set_process(false)
	_arm_interstitial(g5, true)
	(g5._ads.debug_events as Array).clear()
	g5._start_stage(5)          # 판 시작 — 여기서 인터스티셜이 뜨면 진입 연출을 먹는다
	var e_ok: bool = g5._ads.debug_interstitial_attempts == 0
	print("[E] 판 시작 지점 → 인터스티셜시도=%d  (0 이어야 = 진입 연출을 안 먹음)  %s"
			% [g5._ads.debug_interstitial_attempts, "OK" if e_ok else "FAIL"])
	if not e_ok: fails += 1

	# ── F. 실패 직후 재도전엔 안 붙는다(벌 위에 대기를 얹지 않는다)
	var g6: Node = S.new()
	root.add_child(g6)
	await process_frame
	g6._start_stage(3)
	g6.set_process(false)
	_arm_interstitial(g6, true)
	(g6._ads.debug_events as Array).clear()
	g6.game_over = true            # 실패 → 재도전 경로
	g6._result_advance()
	var f_ok: bool = g6._ads.debug_interstitial_attempts == 0 and g6.stage_idx == 3
	print("[F] 실패 재도전 → 인터스티셜시도=%d stage_idx=%d  (0/3 이어야)  %s"
			% [g6._ads.debug_interstitial_attempts, g6.stage_idx, "OK" if f_ok else "FAIL"])
	if not f_ok: fails += 1

	# ── G. 온보딩 면제: 누적 클리어가 AD_ONBOARD_CLEARS 미만이면 캡을 통과해도 안 뜬다
	var g7: Node = S.new()
	root.add_child(g7)
	await process_frame
	g7._start_stage(3)
	g7.set_process(false)
	_arm_interstitial(g7, true)
	g7.cleared = {0: true, 1: true}          # 누적 2판 = 아직 배우는 중
	(g7._ads.debug_events as Array).clear()
	g7.game_clear = true
	g7._result_advance()
	var g_blocked: bool = g7._ads.debug_interstitial_attempts == 0 and g7.stage_idx == 4
	# 같은 조건에서 진행도만 채우면 뜬다(면제가 '진행도' 때문이라는 대조군)
	var g8: Node = S.new()
	root.add_child(g8)
	await process_frame
	g8._start_stage(3)
	g8.set_process(false)
	_arm_interstitial(g8, true)
	g8.cleared = {0: true, 1: true, 2: true, 3: true, 4: true}   # 누적 5판
	(g8._ads.debug_events as Array).clear()
	g8.game_clear = true
	g8._result_advance()
	var g_open: bool = g8._ads.debug_interstitial_attempts == 1
	var gg_ok: bool = g_blocked and g_open
	print("[G] 온보딩(누적2) 차단=%s · 누적5 허용=%s  (true/true 이어야)  %s"
			% [g_blocked, g_open, "OK" if gg_ok else "FAIL"])
	if not gg_ok: fails += 1

	print("── %s (실패 %d) ──" % ["PASS" if fails == 0 else "FAIL", fails])
	quit()

# 캡·동의를 다 통과한 상태로 만든다(빈도 캡 자체는 ad_probe가 검증).
func _arm_interstitial(g: Node, fill: bool) -> void:
	# 온보딩 면제(AD_ONBOARD_CLEARS)도 통과시켜 둔다 — 그 게이트 자체는 케이스 G가 따로 검증한다.
	g.cleared = {0: true, 1: true, 2: true, 3: true, 4: true}
	var ads = g._ads
	ads.enabled = true               # 헤드리스라 _init이 꺼둔 것을 다시 켠다(프로브 한정 — ad_probe와 같은 관례)
	ads.interstitial_enabled = true  # ⚠게임에선 꺼져 있다. 이음매 자체를 재려고 여기서만 켠다
	ads.fake_fill = fill
	ads.fake_error = false
	ads._consent_ready = true
	ads._runs_this_session = ads.INTERSTITIAL_FREE_RUNS + 1
	ads._runs_since_ad = ads.INTERSTITIAL_EVERY_RUNS
	ads._last_interstitial_ms = -ads.INTERSTITIAL_MIN_GAP_MS * 2
