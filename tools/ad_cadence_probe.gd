extends SceneTree
# 인터스티셜 실효 케이던스 — 캡 함수가 아니라 '플레이 세션'을 흉내내서 **몇 번째 클리어에서 광고가 뜨는지**
#   실제로 센다. 캡은 (첫 N판 면제) AND (M판마다) AND (T분마다)인데, 슬롯을 '이긴 판 뒤'로 옮긴 뒤에는
#   실패가 카운터만 올리고 광고는 안 띄우므로 체감 간격이 캡 상수와 다르다 → 숫자로 봐야 한다.
# 실행: godot --headless --path . --script tools/ad_cadence_probe.gd
#   ⚠시간 게이트는 실시간(_now_ms)이라, 판 소요시간은 _last_interstitial_ms를 뒤로 밀어 흉내낸다.

const RUNS: int = 16

func _init() -> void:
	print("캡 = 첫 %d판 면제 · %d판마다 · %d초마다(AND) + 온보딩 면제(누적 클리어 %d판 전까지 없음)"
			% [_c("INTERSTITIAL_FREE_RUNS"), _c("INTERSTITIAL_EVERY_RUNS"), _c("INTERSTITIAL_MIN_GAP_MS") / 1000,
			int(load("res://Main.gd").get("AD_ONBOARD_CLEARS"))])
	for secs in [60, 120, 240]:
		await _run_session(secs, false)
	print("")
	print("── 실패를 섞으면(클리어 2판 뒤 1판 실패 반복) ──")
	await _run_session(120, true)
	print("")
	print("DONE")
	quit()

func _c(name: String) -> int:
	return int(load("res://ad_service.gd").get(name))

# secs_per_run = 한 판에 걸리는 시간(초). with_fail = 3판마다 1판은 실패로 처리.
func _run_session(secs_per_run: int, with_fail: bool) -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	await process_frame
	g.set_process(false)
	var ads = g._ads
	ads.enabled = true               # 헤드리스 게이트 해제(프로브 한정)
	ads.interstitial_enabled = true  # ⚠게임에선 꺼져 있다
	ads.fake_fill = true
	ads.fake_error = false
	ads._consent_ready = true
	# 신규 설치를 흉내낸다 = 진행도 0에서 출발(온보딩 면제 AD_ONBOARD_CLEARS가 실제로 걸리는지 함께 본다)
	g.cleared = {}

	# ⚠판 진행은 `_result_advance()`가 다음 판을 여는 것으로만 센다. 루프에서 `_start_stage`를 또 부르면
	#   한 판이 두 번 세어져(note_run_started 2회) 캡이 실제보다 빨리 열린다 — 처음에 그렇게 잘못 재었다.
	g._start_stage(0)                        # 세션 첫 판(= 카운터 1)
	var shown_at: Array = []
	var line: String = ""
	for i in range(RUNS):
		var fail: bool = with_fail and (i % 3 == 2)
		(ads.debug_events as Array).clear()
		# 판을 치르는 데 걸린 시간을 흉내낸다(시간 게이트가 흐르게)
		ads._last_interstitial_ms -= secs_per_run * 1000
		g.game_clear = not fail
		g.game_over = fail
		if not fail:
			g.cleared[g.stage_idx] = true      # _check_win이 하는 일 = 진행도 적립(온보딩 게이트 입력)
		g._result_advance()                  # 판정 → (광고) → 다음 판 시작(카운터 +1)
		var got: bool = (ads.debug_events as Array).has("ad_shown")
		if got:
			shown_at.append(i + 1)
		line += ("F" if fail else ("A" if got else "·"))
	print("판 %ds → 광고 %d회 @ %s   [%s]  (A=광고, ·=없음, F=실패)"
			% [secs_per_run, shown_at.size(), str(shown_at), line])
	g.queue_free()
