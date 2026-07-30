extends SceneTree
# 실 AdMob 배선 검증 (Phase V W2 R2 — 설계 정본 AD_PLAN.md §5 R2).
#   실행: godot --path . --script tools/ad_mock_probe.gd -- --ad-mock      ⚠창 모드 + --ad-mock
#
# ad_probe.gd와 무엇이 다른가:
#   ad_probe = **페이크 백엔드**(우리가 쓴 상태 기계)를 잰다. 실 SDK가 붙어도 그건 안 변한다.
#   여기 = **플러그인 콜백 → 우리 상태 기계** 사이의 번역이 맞는지를 잰다. R2에서 새로 생긴
#   유일한 위험 구간이고, 실기기 없이 밟을 수 있는 유일한 방법이 에디터 목 광고다.
#   (`--ad-mock`이 없으면 AdService는 데스크톱서 페이크로 남는다 = 기존 하네스 무영향.)
#
# 무엇을 보나:
#   A) 백엔드가 실제로 admob으로 붙었나(안 붙으면 아래 전부가 페이크를 재는 헛검사가 된다)
#   B) 로드→시청→보상→닫힘 = 부활(ad_reward)
#   C) 로드 실패(code 3=no-fill) = 공짜 부활(free_fallback)
#   D) 보상 없이 닫힘(중도 이탈) = 부활 안 됨 + 기회 소진 안 됨
#   E) 표시 실패 = 공짜 부활
#   F) 로드 타임아웃(불변식 ⑥) = 공짜 부활 + 늦게 온 광고는 버리지 않음
#   G) 표시 시작 타임아웃(불변식 ⑥) = 공짜 부활
#   H) 게임 통합 — 결과 팝업의 '이어하기'가 실 콜백 경로를 지나 부활까지 간다

const AdService = preload("res://ad_service.gd")

# 실 SDK가 주는 오류 dict의 최소 형태(LoadAdError.create/AdError.create가 요구하는 키).
const ERR_NO_FILL: Dictionary = {
	"code": 3, "domain": "com.google.android.gms.ads", "message": "No fill",
	"cause": {}, "response_info": {},
}
const ERR_SHOW: Dictionary = {
	"code": 0, "domain": "com.google.android.gms.ads", "message": "Failed to show", "cause": {},
}

var g: Node = null
var fails: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("%s %s%s" % ["OK  " if ok else "FAIL", tag, ("  — " + detail) if detail != "" else ""])

func _plugin() -> Object:
	return MobileSingletonPlugin._get_plugin("PoingGodotAdMobRewardedAd", false)

# 목의 로드 타이머(0.5초)보다 넉넉히 기다린다.
func _wait_load() -> void:
	await create_timer(0.8).timeout

func _new_service() -> Object:
	# 창 모드라 enabled는 이미 true고, --ad-mock이 있으면 _init이 실 백엔드를 고른다.
	return AdService.new(null)

# --- 서비스 단독 (콜백 번역 검증) ---

func _probe_service() -> void:
	# A) 백엔드 확인 — 이게 fake면 아래 검사는 전부 의미가 없다.
	var s0 = _new_service()
	_check("A: 백엔드가 admob", s0.backend() == "admob", s0.backend())
	if s0.backend() != "admob":
		print("   ⚠ --ad-mock 없이 돌렸거나 addons/admob이 비활성이다. 이후 검사는 건너뛴다.")
		return

	# B) 로드 → 시청 → 보상 → 닫힘 = 부활
	var s = _new_service()
	var got: Array = []
	s.show_rewarded(AdService.PLACEMENT_REVIVE, func(r): got.append(r))
	await _wait_load()
	_check("B: 로드 성공 후 시청 단계", s.is_busy() and String(s._job["kind"]) == "show")
	await process_frame
	_check("B: 표시 확인되면 타임아웃 시계 정지", bool(s._job.get("shown", false)))
	var uid: int = int(s._rewarded._uid)
	_plugin().on_rewarded_ad_user_earned_reward.emit(uid, {"type": "revive", "amount": 1})
	await process_frame
	_check("B: 보상은 닫힐 때까지 확정만 해둔다", bool(s._job.get("earned", false)) and got.is_empty())
	_plugin().on_rewarded_ad_dismissed_full_screen_content.emit(uid)
	await process_frame
	_check("B: 닫힘에서 1회 결과", got.size() == 1)
	_check("B: 보상 성사", got.size() == 1 and bool(got[0]["granted"]))
	_check("B: 지표 발화", (s.debug_events as Array).has("ad_rewarded"))
	_check("B: 잡 정리됨", not s.is_busy())

	# C) 로드 실패(no-fill) = 공짜 부활
	var s2 = _new_service()
	var got2: Array = []
	s2.show_rewarded(AdService.PLACEMENT_REVIVE, func(r): got2.append(r))
	_plugin().on_rewarded_ad_failed_to_load.emit(int(s2._loader._uid), ERR_NO_FILL)
	await process_frame
	_check("C: no-fill이면 폴백 1회", got2.size() == 1 and bool(got2[0]["fallback"]))
	_check("C: 사유가 no_fill", got2.size() == 1 and String(got2[0]["reason"]) == AdService.R_NO_FILL)
	_check("C: 보상은 아님", got2.size() == 1 and not bool(got2[0]["granted"]))

	# D) 보상 없이 닫힘 = 부활 안 됨 + 기회 소진 안 됨(폴백도 아님)
	var s3 = _new_service()
	var got3: Array = []
	s3.show_rewarded(AdService.PLACEMENT_REVIVE, func(r): got3.append(r))
	await _wait_load()
	await process_frame
	_plugin().on_rewarded_ad_dismissed_full_screen_content.emit(int(s3._rewarded._uid))
	await process_frame
	_check("D: 중도 이탈은 보상 없음", got3.size() == 1 and not bool(got3[0]["granted"]))
	_check("D: 폴백도 아님(다시 누를 수 있어야 한다)", got3.size() == 1 and not bool(got3[0]["fallback"]))
	_check("D: 사유가 user_cancel", got3.size() == 1 and String(got3[0]["reason"]) == AdService.R_USER_CANCEL)

	# E) 표시 실패 = 공짜 부활
	var s4 = _new_service()
	var got4: Array = []
	s4.show_rewarded(AdService.PLACEMENT_REVIVE, func(r): got4.append(r))
	await _wait_load()
	await process_frame
	_plugin().on_rewarded_ad_failed_to_show_full_screen_content.emit(int(s4._rewarded._uid), ERR_SHOW)
	await process_frame
	_check("E: 표시 실패는 폴백", got4.size() == 1 and bool(got4[0]["fallback"]))
	_check("E: 사유가 error", got4.size() == 1 and String(got4[0]["reason"]) == AdService.R_ERROR)

	# F) 로드 타임아웃(불변식 ⑥) — 목의 0.5초 타이머보다 먼저 시계를 태운다.
	var s5 = _new_service()
	var got5: Array = []
	s5.show_rewarded(AdService.PLACEMENT_REVIVE, func(r): got5.append(r))
	s5.poll(float(AdService.LOAD_TIMEOUT_MS) / 1000.0 + 1.0)
	_check("F: 응답이 없으면 폴백으로 닫힌다", got5.size() == 1 and bool(got5[0]["fallback"]))
	_check("F: 팝업 잠금 해제", not s5.is_busy())
	await _wait_load()
	_check("F: 늦게 온 광고는 다음 요청용으로 남긴다", s5.is_rewarded_ready())

	# G) 표시 시작 타임아웃(불변식 ⑥) — showed 콜백은 다음 프레임에 오므로, 그 전에 시계를 태운다.
	var s6 = _new_service()
	var got6: Array = []
	s6.preload_rewarded()
	await _wait_load()
	_check("G: 프리로드로 준비됨", s6.is_rewarded_ready())
	s6.show_rewarded(AdService.PLACEMENT_REVIVE, func(r): got6.append(r))
	s6.poll(float(AdService.SHOW_START_TIMEOUT_MS) / 1000.0 + 1.0)
	_check("G: 표시가 시작 안 되면 폴백", got6.size() == 1 and bool(got6[0]["fallback"]))
	await process_frame   # 뒤늦게 도착하는 showed 콜백이 빈 잡을 건드리지 않는지
	_check("G: 늦은 콜백이 결과를 두 번 안 만든다", got6.size() == 1)

# --- 게임 통합 ---

func _settle() -> void:
	var s: int = 0
	while g.resolving and s < 400:
		g._process(0.05)
		s += 1

func _force_core_death() -> void:
	g.core_hp = 0
	g.pending_core_dead = true
	g._end_turn()
	_settle()

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

func _probe_game() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	_check("H: 게임도 admob 백엔드", g._ads.backend() == "admob", g._ads.backend())
	g._start_stage(0)
	await _wait_load()      # 판 시작 프리로드가 실제로 채워질 때까지
	_check("H: 프리로드 실값(is_ad_ready)", g._ads.is_rewarded_ready())
	_force_core_death()
	_check("H: 부활 제안이 열림", g.game_over and not g.revive_used)
	g._request_revive_ad()
	await process_frame
	_check("H: 요청 중엔 팝업 잠김", g._ad_pending and g._ads.is_busy())
	_check("H: 아직 부활 전", not g.revive_used)
	var uid: int = int(g._ads._rewarded._uid)
	_plugin().on_rewarded_ad_user_earned_reward.emit(uid, {"type": "revive", "amount": 1})
	await process_frame
	_plugin().on_rewarded_ad_dismissed_full_screen_content.emit(uid)
	await process_frame
	_check("H: 광고 부활 성사", g.revive_used and not g.game_over)
	_check("H: 잠금 해제", not g._ad_pending)
	_check("H: 부활 후 놓을 자리 있음", _any_placeable(), "소프트락 안전망")

func _run() -> void:
	await _probe_service()
	await _probe_game()
	print("\n=== ad_mock_probe: %s ===" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	quit(1 if fails > 0 else 0)
