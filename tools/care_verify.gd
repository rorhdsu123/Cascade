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
	# 두 칸 계단(2026-08-04 st12 실플레이로 교정). 조각=2패(3번째 판) / 비행기=3패 / 천장 3패.
	#   [n패, 줄-완성 케어, 비행기 케어]
	for row in [[0, false, false], [1, false, false], [2, true, false], [3, true, true], [7, true, true]]:
		var n: int = int(row[0])
		g.dda_enabled = true
		g.fail_streak[2] = n
		g._start_stage(2)
		var clear_on: bool = g._care_level() >= g.CARE_CLEAR_FAILS
		var plane_on: bool = g.plane_cd_left == g.CARE_PLANE_FIRST_CD
		_ok(clear_on == bool(row[1]), "%d패 → 줄-완성 케어 %s" % [n, "ON" if bool(row[1]) else "off"],
			"실제=%s" % ("ON" if clear_on else "off"))
		_ok(plane_on == bool(row[2]), "%d패 → 비행기 케어 %s" % [n, "ON" if bool(row[2]) else "off"],
			"실제=%s" % ("ON" if plane_on else "off"))
	# 2패에서 줄-완성만 걸리고 비행기는 아직 안 걸린다 = 계단이 실제로 두 칸이다(한 칸이면 천장이 무의미).
	g.fail_streak[2] = 2
	g._start_stage(2)
	_ok(g._plane_cd() == int(g.st.get("plane_cd", 10)), "2패 단계는 비행기 재등장 간격도 원본")
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
	_ok(g._care_level() == 0, "dda_enabled=false면 케어 단계 0")
	_ok(g.plane_cd_left == int(g.st.get("plane_cd", 10)), "dda_enabled=false면 비행기 배급 원본",
		"plane_cd_left=%d" % g.plane_cd_left)
	g.dda_enabled = true
	g.fail_streak[-1] = 5
	g._start_endless()
	_ok(g._care_level() == 0, "무한모드는 케어 없음(랭크 공정성)")
	_ok((g.pool_override as Dictionary).is_empty(), "풀 오버라이드는 게임 코드가 절대 안 세운다(프로브 전용)")

	print("\n── ③ 배급: 트레이 3장이 어떤 순서로든 다 놓인다 ──")
	# S4 ①. 옛 가드는 '하나라도 놓이면 통과'라 한 장을 놓는 순간 나머지가 갇히는 딜이 그대로 나갔다.
	#   플레이어에겐 '내가 잘못 놨다'로 보이지만 실은 처음부터 출구가 없는 배급이다.
	g.dda_enabled = true
	g.fail_streak[2] = 0
	var bad: int = 0
	for t in range(300):
		g._start_stage(2)
		if not g._tray_all_placeable():
			bad += 1
	_ok(bad == 0, "빈 보드 300판의 첫 트레이가 전부 완전 소화 가능", "실패 %d판" % bad)
	# 가드가 '통과'와 '불가'를 실제로 가르는지 — 늘 true를 돌려주는 죽은 검사가 아님을 보인다.
	g._start_stage(2)
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if not (r == 0 and c == 0):
				g.board[r][c] = "R"      # 한 칸만 비운 보드
	g.tray[0] = {"type": "I5h", "color": "R", "offsets": g.PIECES["I5h"].duplicate()}
	g.tray[1] = {}
	g.tray[2] = {}
	_ok(not g._tray_all_placeable(), "한 칸만 남은 보드에 5바는 불가로 판정된다")
	g.board[0][0] = ""
	g.board[0][1] = ""
	g.tray[0] = {"type": "D2h", "color": "R", "offsets": g.PIECES["D2h"].duplicate()}
	_ok(g._tray_all_placeable(), "두 칸 남은 보드에 2칸 조각은 가능으로 판정된다")

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
	_ok(not g._plane_allowed(), "수집 판은 비행기 없음 = 줄-완성 케어가 그 판의 유일한 레버")
	_ok(g._care_level() >= g.CARE_CLEAR_FAILS, "그 판도 줄-완성 케어는 받는다")

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
	_ok(g._care_level() == 0, "클리어 뒤 재진입은 케어 없음(즉시 복귀)")
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
	_ok(b._care_level() >= b.CARE_CLEAR_FAILS, "돌아온 유저가 첫 판부터 케어를 받는다")

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
