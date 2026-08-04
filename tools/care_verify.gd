extends SceneTree
# care_verify.gd — 실패 케어(S1) 배선 검증. 승률이 아니라 '규칙대로 켜지고 꺼지나'를 본다.
#   밸런스 수치는 tools/care_probe.gd 몫. 여기는 계단·게이팅·회계·영속만 본다.
#
# ⚠[영속] 항목은 실제 user://campaign.save를 쓴다. 반드시 백업·복원 래퍼로 돌릴 것:
#   tools/care_verify.sh (백업 → 실행 → 복원 → mtime 확인)
#   래퍼 없이 직접 돌리면 실유저 진행도가 날아간다([[campaign-save-reset-gotchas]]).
#   SKIP_PERSIST=1을 주면 영속 항목을 통째로 건너뛴다(디스크 무접촉).

var fails: int = 0

func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  ✅ %s" % label)
	else:
		fails += 1
		print("  ❌ %s   %s" % [label, detail])

func _init() -> void:
	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	g.set("persist_enabled", false)
	g.cleared[0] = true

	print("\n── ① 계단: 연속 실패 횟수 → 케어 단계 ──")
	# 3패 천장(유저 결정 2026-08-04). 그 위로는 더 세지지 않는다.
	for pair in [[0, false], [1, false], [2, false], [3, true], [7, true]]:
		var n: int = int(pair[0])
		var want_care: bool = bool(pair[1])
		g.dda_enabled = true
		g.fail_streak[2] = n
		g._start_stage(2)
		var on: bool = not (g.care_pool as Dictionary).is_empty()
		_ok(on == want_care, "%d패 → 조각 케어 %s" % [n, "ON" if want_care else "off"],
			"실제=%s" % ("ON" if on else "off"))
	g.fail_streak[2] = 7
	g._start_stage(2)
	var cd_cap: int = g.plane_cd_left
	g.fail_streak[2] = 3
	g._start_stage(2)
	_ok(cd_cap == g.plane_cd_left, "7패가 3패보다 세지지 않는다(천장)", "7패=%d 3패=%d" % [cd_cap, g.plane_cd_left])

	print("\n── ② 게이팅: 구제를 끄면 케어도 꺼진다 ──")
	# 하네스·시뮬(regress·sim·campaign_probe)이 전부 이 스위치를 쓴다 → 별도 조치 없이 순수 난이도가 측정된다.
	g.dda_enabled = false
	g.fail_streak[2] = 5
	g._start_stage(2)
	_ok((g.care_pool as Dictionary).is_empty(), "dda_enabled=false면 조각 케어 off")
	_ok(g.plane_cd_left == int(g.st.get("plane_cd", 10)), "dda_enabled=false면 비행기 배급 원본",
		"plane_cd_left=%d" % g.plane_cd_left)
	g.dda_enabled = true
	g.fail_streak[-1] = 5
	g._start_endless()
	_ok((g.care_pool as Dictionary).is_empty(), "무한모드는 케어 없음(랭크 공정성)")

	print("\n── ③ 조각 풀: 5바만 오르고 나머지 비율은 그대로 ──")
	g.dda_enabled = true
	g.fail_streak[2] = 3
	g._start_stage(2)
	var base: Dictionary = g.st["pool"]
	var care: Dictionary = g.care_pool
	_ok(not care.is_empty(), "st3는 케어 풀이 생긴다(기본 27.8% < 목표)")
	if not care.is_empty():
		_ok(_share(care) > _share(base), "5바 비중이 올랐다 %.1f%% → %.1f%%" % [100.0 * _share(base), 100.0 * _share(care)])
		_ok(_share(care) <= 0.40, "탐지선 아래다(≤40%%) — C109서 47%%는 유저가 눈으로 잡아냈다",
			"실제 %.1f%%" % [100.0 * _share(care)])
		var same: bool = true
		var detail: String = ""
		for k in base:
			if k == "I5h" or k == "I5v":
				continue
			if int(care.get(k, -1)) != int(base[k]):
				same = false
				detail = "%s %d→%d" % [k, int(base[k]), int(care.get(k, -1))]
		_ok(same, "5바 외 조각은 가중치 불변(작은 조각 늘리기는 실측상 역효과)", detail)
		_ok(int(care["I5h"]) > int(base["I5h"]) and int(care["I5v"]) > int(base["I5v"]),
			"가로·세로 5바가 함께 오른다(판별 성격 유지)")
	# 이미 목표 이상인 판(st2=POOL_RICH 41.2%)은 조각 케어가 안 걸린다 — 비행기 쪽으로만 케어된다.
	g.fail_streak[1] = 3
	g._start_stage(1)
	_ok((g.care_pool as Dictionary).is_empty(), "이미 5바가 많은 판(RICH)은 조각 케어 없음")

	print("\n── ④ 비행기: 배급만 늘고 '세상에 한 대'는 그대로 ──")
	g.fail_streak[2] = 0
	g._start_stage(2)
	var cd_normal: int = g.plane_cd_left
	g.fail_streak[2] = 3
	g._start_stage(2)
	_ok(g.plane_cd_left < cd_normal, "케어 판은 첫 픽업이 빠르다 %d → %d" % [cd_normal, g.plane_cd_left])
	_ok(g.plane_cd_left == g.CARE_PLANE_FIRST_CD, "첫 픽업 간격 = CARE_PLANE_FIRST_CD")
	_ok(g._plane_cd() < int(g.st.get("plane_cd", 10)), "재등장 간격도 짧아진다 %d → %d" % [
		int(g.st.get("plane_cd", 10)), g._plane_cd()])
	# 수집·튜토리얼 판엔 비행기가 아예 없다 → 케어는 조각 풀로만 걸린다(레버 하나로 전 판을 못 덮는다).
	g.fail_streak[4] = 3
	g._start_stage(4)
	_ok(not g._plane_allowed(), "수집 판은 비행기 없음 = 조각 풀이 그 판의 유일한 케어")
	_ok(not (g.care_pool as Dictionary).is_empty(), "그 판도 조각 케어는 받는다")

	print("\n── ⑤ 회계: 부활·클리어가 카운터를 바르게 되돌린다 ──")
	g.fail_streak[2] = 1
	g._start_stage(2)
	g._bump_fail_streak()
	_ok(int(g.fail_streak[2]) == 2, "패배 → +1")
	g._undo_fail_streak()
	_ok(int(g.fail_streak[2]) == 2 - 1, "부활 → 되돌림(한 시도가 2패로 세지지 않는다)")
	g.fail_streak[2] = 3
	g._start_stage(2)
	g.fail_streak[2] = 0      # _check_win이 하는 일(클리어 = 즉시 원 난이도 복귀)
	# 계측은 fail_streak이 아니라 run_care_level을 읽어야 한다 — 위 한 줄 때문에 '케어받고 깬 판'이
	#   통계에서 통째로 사라진다. 조용한 기능이라 이 필드가 유일한 관측 수단이다.
	_ok(int(g.run_care_level) == 3, "클리어로 카운터가 밀려도 판 시작 시 케어 단계는 남는다",
		"run_care_level=%d" % int(g.run_care_level))
	g._start_stage(2)
	_ok((g.care_pool as Dictionary).is_empty(), "클리어 뒤 재진입은 케어 없음(즉시 복귀)")
	_ok(int(g.run_care_level) == 0, "그 다음 판의 계측값도 0으로 돌아온다")
	# 무한(stage_idx=-1)은 같은 딕셔너리를 스크래치로 쓴다 — 캠페인 칸을 밀어내면 안 된다.
	g._start_endless()
	g._bump_fail_streak()
	_ok(int(g.fail_streak.get(-1, 0)) > 0, "무한도 메모리엔 센다(기존 동작 보존)")

	if OS.get_environment("SKIP_PERSIST") == "":
		_persist(S)
	else:
		print("\n── ⑥ 영속: SKIP_PERSIST=1 — 건너뜀 ──")

	print("\nRESULT: %s (실패 %d)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)

# ⚠여기서만 디스크를 만진다. 래퍼(tools/care_verify.sh)가 백업·복원을 책임진다.
func _persist(S: GDScript) -> void:
	print("\n── ⑥ 영속: 앱을 껐다 켜도 케어가 유지된다 ──")
	var a: Node = S.new()
	root.add_child(a)
	a.set("persist_enabled", true)
	a.cleared.clear()
	a.cleared[0] = true
	a.fail_streak.clear()
	a.stage_idx = 2
	a.fail_streak[2] = 2
	a._bump_fail_streak()          # 3패 = 케어 단계. 여기서 디스크에 쓰인다.

	var b: Node = S.new()           # 새 인스턴스 = 앱 재시작
	root.add_child(b)
	b.set("persist_enabled", false)
	b.cleared.clear()
	b.fail_streak.clear()
	b._load_campaign()
	_ok(int(b.fail_streak.get(2, 0)) == 3, "재시작 뒤에도 3패가 남아 있다",
		"실제=%d" % int(b.fail_streak.get(2, 0)))
	_ok(bool(b.cleared.get(0, false)), "진행도(cleared)는 그대로 읽힌다")
	b.dda_enabled = true
	b._start_stage(2)
	_ok(not (b.care_pool as Dictionary).is_empty(), "돌아온 유저가 첫 판부터 케어를 받는다")

	# 옛 세이브(4바이트) 호환 — 케어 도입 전 파일을 읽어도 죽지 않고 연속 실패 0에서 시작한다.
	var f := FileAccess.open("user://campaign.save", FileAccess.WRITE)
	f.store_32(1)
	f.close()
	var c: Node = S.new()
	root.add_child(c)
	c.set("persist_enabled", false)
	c.cleared.clear()
	c.fail_streak.clear()
	c._load_campaign()
	_ok(bool(c.cleared.get(0, false)) and int(c.fail_streak.get(2, 0)) == 0,
		"옛 4바이트 세이브도 읽힌다(진행도 유지·연속실패 0)")

func _share(w: Dictionary) -> float:
	var total: int = 0
	var i5: int = 0
	for k in w:
		total += int(w[k])
		if k == "I5h" or k == "I5v":
			i5 += int(w[k])
	return 0.0 if total <= 0 else float(i5) / float(total)
