extends SceneTree
# 세션 경계 검증 (C200). 헤드리스 OK — 픽셀을 안 읽는다.
#   godot --headless --path . --script tools/session_grace_probe.gd
#
# 무엇을 지키나 — **폰에서 한 방문이 여러 세션으로 조각나지 않는 것.**
# 2026-08-13 첫 코호트에서 세션 33건 중 12건이 4초 미만이었고 한 사람이 하루에 11개를 만들었다.
# `visibilitychange→hidden`이 화면 잠금·알림·앱 전환에서도 뜨는데 그때마다 세션을 끊었기 때문이다.
# 그 파편이 분모에 들어가 "한 판도 안 한 세션 69.7%"라는 허깨비를 만들었다(방문으로 접으면 18%).
# C198이 유예를 넣어 고쳤고, 이 프로브가 그 유예를 지킨다.
#
# ⚠**브라우저로는 이 분기를 못 잰다.** `_on_web_visibility`는 데스크톱에서 `_js()`가 null이라
#   즉시 되돌아가고, 창 모드로 띄워도 자동화 탭은 포커스가 없어 `visibilityState`가 계속 hidden이다
#   (2026-08-14 실측). 그래서 판단을 `needs_new_session()`으로 떼어내 여기서 직접 잰다.

const AnalyticsService = preload("res://analytics.gd")

var _fail: Array[String] = []

func _initialize() -> void:
	_run()

func _ck(cond: bool, label: String) -> void:
	if not cond:
		_fail.append(label)
	print("  %s %s" % ["ok  " if cond else "FAIL", label])

func _new_service() -> Object:
	var a: Object = AnalyticsService.new()
	# 하네스라 `_init`이 계측을 껐다(설계대로). 이벤트 모양을 보려면 켜야 한다.
	# ⚠원격은 건드리지 않는다 — `_remote_on`은 `--script`에서 구조적으로 false다.
	a.set("enabled", true)
	return a

func _run() -> void:
	var grace: int = int(AnalyticsService.SESSION_GRACE_MS)
	print("── 세션 유예 %d ms (%.0f분) ──" % [grace, float(grace) / 60000.0])

	# ① 유예 판단 — 경계 양쪽
	var a: Object = _new_service()
	a.set("_hidden_at_ms", -1)
	_ck(not a.call("needs_new_session", 999999), "가려진 적이 없으면 새 세션을 안 연다")
	a.set("_hidden_at_ms", 10000)
	_ck(not a.call("needs_new_session", 10000 + grace - 1), "유예 직전(−1ms)엔 같은 세션을 잇는다")
	_ck(a.call("needs_new_session", 10000 + grace), "유예에 닿으면 새 세션을 연다")
	_ck(a.call("needs_new_session", 10000 + grace * 10), "한참 뒤 복귀도 새 세션")

	# ② 짧게 가렸다 돌아오는 것이 세션을 늘리지 않는다 — 이게 이 수정의 본체다
	var b: Object = _new_service()
	b.call("session_begin")
	var sid1: String = String(b.get("_session_id"))
	for i in range(8):                      # 알림 8번 = 옛 코드였다면 세션 9개
		b.set("_hidden_at_ms", 1000 * i)
		if b.call("needs_new_session", 1000 * i + 500):
			b.call("session_end", b.get("_hidden_at_ms"))
			b.call("session_begin")
		b.set("_hidden_at_ms", -1)
	_ck(String(b.get("_session_id")) == sid1, "짧은 가려짐 8회를 겪어도 세션이 하나로 유지된다")

	# ③ 세션 길이는 **가려진 시각**으로 잰다(돌아온 시각이 아니라)
	var c: Object = _new_service()
	c.call("session_begin")
	c.set("_session_started_ms", 0)         # 기준을 0으로 고정해 계산을 눈으로 확인 가능하게
	c.call("session_end", 45000)            # 45초에 가려졌다 = 체류 45초
	var ev: Dictionary = c.get("last_event")
	_ck(String(ev.get("event", "")) == "session_ended", "session_ended가 발화한다")
	_ck(int(ev.get("duration_ms", -1)) == 45000,
			"체류가 가려진 시각으로 잡힌다 (기대 45000, 실제 %s)" % str(ev.get("duration_ms")))

	# ③-b 가려질 때 **잠정 스냅샷**이 남는다 — 탭을 안 닫고 떠난 사람의 체류를 이걸로만 안다
	var g: Object = _new_service()
	g.call("session_begin")
	g.set("_session_started_ms", 0)
	g.set("_runs_played", 2)
	g.call("session_snapshot")
	var sv: Dictionary = g.get("last_event")
	_ck(String(sv.get("event", "")) == "session_paused", "가려질 때 session_paused가 남는다")
	_ck(int(sv.get("runs_played", -1)) == 2, "스냅샷이 그때까지의 판 수를 담는다")
	_ck(String(g.get("_session_id")) != "", "스냅샷은 세션을 닫지 않는다")

	# ④ is_first_session은 한 로드의 **첫 세션에만** 참 — 여기가 8/13에 두 배로 새던 자리다
	var d: Object = _new_service()
	d.set("_is_first_session", true)
	d.call("session_begin")
	var e1: Dictionary = d.get("last_event")
	d.call("session_end")
	d.call("session_begin")
	var e2: Dictionary = d.get("last_event")
	_ck(bool(e1.get("is_first_session", false)) == true, "첫 세션은 is_first_session=true")
	_ck(bool(e2.get("is_first_session", true)) == false, "두 번째 세션은 false (옛 코드는 true였다)")
	_ck(bool(e1.get("resumed", true)) == false and bool(e2.get("resumed", false)) == true,
			"resumed로 파편과 첫 진입을 가른다")

	# ⑤ 기기 종류가 이벤트에 실린다 — 폰만 겪는 문제를 데이터로 가르는 유일한 칸
	_ck(e1.has("touch"), "모든 이벤트에 touch가 붙는다")
	_ck(AnalyticsService.detect_touch_device() == bool(e1.get("touch")),
			"touch 값이 기기 판정과 일치한다")

	print("")
	if not _fail.is_empty():
		print("실패 %d건: %s" % [_fail.size(), ", ".join(_fail)])
	print("SESSION_GRACE_OK=%s" % str(_fail.is_empty()))
	quit(0 if _fail.is_empty() else 1)
