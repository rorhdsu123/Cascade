extends SceneTree
# 리팩터 회귀 하네스 — 시드 고정 byte-identical A/B.
#   봇(_best_move/_score)은 randi를 안 쓰고 게임만 쓴다 → seed() 고정 시 전 과정 결정적.
#   randi 호출 순서·횟수가 보존되면 아래 per-game 서명이 리팩터 전/후 완전 동일.
#   실행: PROBE_SEED=20260718 REGRESS_N=20 godot --headless --path . --script tools/regress.gd
#   비교: 리팩터 전 출력을 골든으로 저장 → 매 단계 후 diff. 첫 diff = randi 순서 깨짐 or 동작 변화.
#   골든: tools/regress.golden.txt (seed=20260718 N=20). 재베이스 이력:
#     · S22 비행기 2판 추가(15→17판) + 후반 plane_cd 재척도 — 602→682줄. 앞 **61줄 바이트 동일**
#       (s0~s2 = 삽입 지점 앞 3판)이고 첫 불일치가 s3 = 새로 끼운 비행기 R1 자리다.
#       ⚠골든은 판 추가를 못 걸러낸다 — 비행기가 캠페인 전반에서 안 나오게 된 회귀(사용/판 0.12~0.68)를
#         잡은 건 골든이 아니라 plane_verify AB=1이다. 길이를 건드리면 그 프로브를 같이 돌릴 것.
#     · S21 신규 2판(보석3·분열×폭탄) 추가 + 슬롯 표대로 재배열 — **판 수가 13→15로 바뀐 첫 재베이스**라
#       줄 수도 522→602로 늘었다(판당 ~40줄). 앞 **181줄 바이트 동일**(s0~s8 = 재배열 지점 앞 9판)이고
#       첫 불일치가 s9 = 그 자리의 판이 클라이맥스에서 보석2로 바뀐 지점이다. 예상대로다.
#       ⚠판 수가 바뀌면 골든은 정렬 비교용으로만 쓸 것 — 뒷부분은 통째로 다른 판이다.
#     · S19 13판 길이 일괄 하향(total·collect_targets·spawn_every·floor) — **앞 41줄 바이트 동일**
#       (s0 20줄 + s1 20줄 = 안 건드린 1·2판)이고 첫 불일치가 s2 #00 = 손댄 첫 판(3판)이다.
#       변경이 그 줄에 그대로 보인다: sp32 → sp21 = total 32→21. 그 뒤는 단일 스트림이라 전체 시프트
#       (522줄, 판 수 불변). 판정은 골든이 아니라 campaign_probe **승배치**(시드베이스 2개 × N=60):
#       승배치 총합 569→364(−36%) · 전 판이 21.6~31.0배치(71~102초) 밴드 · 최장 189s→102s.
#       ⚠기전 판은 길이만 보면 안 된다 — 이 하향이 폭탄 사다리를 깼고(R2가 R1보다 폭탄이 적어짐,
#         두 번째 폭탄 미등장 8.3%) debut_tune_probe SWEEP=ladder로 잡아 밀도 순서를 복원했다
#         (R1 0.192 < R2 0.204 < R3 0.226).
#     · S17 12판 폭탄 18→24% — **앞 221줄 바이트 동일**이고 첫 불일치가 s11 #00 = 손댄 그 판이다.
#       그 뒤는 단일 스트림이라 전체 시프트. 판정은 debut_tune_probe SWEEP=ladder(2 시드베이스 × N=100).
#     · S14 도입판 값 되사기(st3 total 34→32 · st7 core_hp 4→5 · st11 폭탄 15→22%+core_hp 6→7) —
#       **앞 41줄 바이트 동일**(s0 20줄 + s1 20줄 = 안 건드린 판 둘)이고 첫 불일치가 s2 #00 =
#       손댄 첫 판(st3)이다. 그 뒤는 단일 스트림이라 전체 시프트(521줄, 판 수 불변).
#       ⚠판정을 골든으로 하지 말 것 — campaign_probe는 시드 하나로 전 판을 이어 돌리므로 앞 판의
#         **추첨 횟수가 바뀌면 뒤 판의 표본이 통째로 갈린다**(안 건드린 st4가 +6.5pt, st10이 −8pt로
#         움직인 게 그 값이다 = 재표집 노이즈). 판정은 판마다 시드를 되감는 짝지은 A/B로:
#         tools/debut_tune_probe.gd(2 시드베이스 × N=100) — st3 +7.5 · st7 +7.5 · st11 −3.5pt.
#     · S10 도입판 시작 적 = 신규 타입(SD.debut_type) — 앞 **48줄이 바이트 동일**하고 거기서부터
#       전체 시프트(521줄, 판 수 불변). 판정법이 이 48줄에 다 들어 있다:
#       s0(1판) 20줄 = 신규 타입이 없는 판이라 불변, s1(2판) 20줄 = 무리 도입인데 **무리와 basic이
#       둘 다 한방컷이라 봇 진행이 완전히 같다**(HP 13 vs 32), s2 #00~#06 = 속공이 시작 적이어도
#       결과가 안 갈린 판들. 첫 불일치 s2 u0 #07이 인과 그 자체다:
#         W1 sp34 k31 lk3 (승·누수3) → W0 sp29 k20 lk4 dc1 (거점사·누수4)
#       = 시작 적이 2배치마다 내려와 한 번 더 샜고 core_hp 4를 소진했다.
#       ⚠s0·s1 20줄씩이 안 살아남으면 게이트가 샌 것이다(도입판이 아닌 판을 건드렸거나,
#         debut_type이 이미 나온 타입을 신규로 오판했거나).
#       판정은 골든이 아니라 campaign_probe 독립 시드베이스 2개 × N=100(도입판 5개):
#         무리 0.0 / 속공 63.0→55.0 / 폭탄 76.0→72.0(두 시드 −4로 일치) / 탱크 53.5→52.0(부호 갈림
#         = 노이즈) / 분열 57.0→48.5. 시작 적 한 마리가 basic에서 주역 적으로 바뀐 값이다.
#     · C115 st2 core_hp 3→4 — 첫 불일치가 **옛 빌드가 누수 3회로 죽던 첫 판**(s1 u0 #09, lk3 dc1)이라
#       인과가 그대로 보인다. 그 앞(s0 20줄 + s1 9줄)은 바이트 동일 = 다른 판 동작 불변,
#       뒤는 단일 스트림이라 전체 시프트(정상). 판정은 plane_verify AB=1 시드베이스 3개 × N=100.
#     · 거점사>클리어 우선 수정 반영
#     · C101 겹침 금지(한 칸에 유닛 하나, 충돌=대각 slip) — 전 줄 시프트.
#     · C102 slip → 줄서기(대기) 교체 — 또 전 줄 시프트. 기전 변경이라 골든 대조로는 판정 불가여서
#       campaign_probe 시드고정 A/B로 대신 검증한다(기준선=C101 이전, 밸런스 상수 무수정):
#         전 14스테이지 N=100: 60.8% → 62.1%
#         깔때기·난관 8스테이지(STAGE_IDX=0,1,2,3,6,7,8,9) N=300: 52.8% → 53.1%(Δ +0.38pp),
#           스테이지별 Δ 전부 95%CI(±5~8pp) 안 = 유의한 이동 0건 → 난이도 곡선 보존.
#         st11·st14 N=300도 각각 +3.0pp·+4.0pp로 CI 안(±6.5~7.0pp).
#     · C105 Protect(도둑) 판을 캠페인에서 제외 — 골든이 14판×20×2 → **13판×20×2(521줄)**로 짧아진다.
#       ⚠판정법: pass0의 s0~s12는 **바이트 동일**해야 한다(= 다른 판 동작 불변). pass1 전체는 스트림
#       위치가 한 판만큼 밀려 달라지는 게 정상. 실제로 그렇게 나왔다(pass0 261/261 일치).
#     · C110 st1 풀 재교정(5바 47%→32% + R33 투입) — 또 하류 전체 시프트.
#       판정은 tools/piecestat.gd 배급 실측 + campaign_probe 동시2·동시3.
#     · C109 st1 조각 풀 POOL_RICH→POOL_ONBOARD(터지는 맛) — 배급이 바뀌니 또 하류 전체 시프트.
#       판정은 campaign_probe의 동시2·동시3 컬럼: 0.57→1.38 · 0.04→0.15(시드베이스 2개 × N=300),
#       승률·막힘은 오히려 소폭 개선(94.2→94.7% · 5.7→5.3%).
#     · C108 st1 total 20→14(온보딩 길이 단축) — 시드를 한 번만 뜨는 단일 스트림이라 s0가 짧아진
#       만큼 **하류 전체가 밀린다**(519줄, 정상). 판정은 골든 대조가 아니라 campaign_probe 실측:
#       st1 배치 32.4→24.5 · 막힘 13.3%→5.7% · 승률 86.3→94.2%(시드베이스 2개 × N=300).
#       total이 먹혔는지는 골든의 s0에서 눈으로 본다 — **이긴 판의 sp가 전부 14**여야 한다.
#       (막힘사 ds1은 전부 스폰되기 전에 끝나므로 sp<14가 정상. 승패를 안 가리고 세면 오판한다.)
#     · C106 비행기 픽업 도입 — 520줄 중 **519줄 시프트**(픽업 스폰이 randi를 먹는다).
#       ⚠판정법: 안 밀리는 줄이 정확히 **s0 u0 #00 하나**여야 한다 = 그 판만 튜토리얼(cleared[0] 미설정)
#       이라 비행기 게이트가 닫혀 있다. 다른 줄이 살아남거나 이 줄이 밀리면 게이트가 샌 것이다.
#       ⚠이 하네스의 봇은 비행기를 **줍기만 하고 안 쏜다**(_fire_plane 미호출) → 발사 경로는 골든의
#       사각지대다. 그쪽은 tools/plane_verify.gd(불변식·A/B)가 맡는다.
#     · C104 Protect 상실축 복원(st14 thief_hp_mult 0.35→5.0) — st14가 배열 끝이라 pass1 전체가 밀려
#       188줄 시프트(정상). 판정은 thief_probe 시드고정 N=200: C101 이전 기준선(승률 73.0%·금고전소 17·
#       평균금고 3.10·탈출 0.63) 대비 71.0%·22·3.05·0.53 = 복원. 캠페인 봇 st14 N=300은 67.7%.
#       ⚠남는 한계: 스테이지 하나짜리 ~5pp 미만 효과는 이 표본으로 분해 못 한다(사람 플테 몫).
#   재생성/대조:
#     ⚠구 골든(C58)은 마지막 적 누수가 total을 채우며 동시에 core_hp를 0으로 만든 게임 19건을
#       'W1+dc1'(승리이면서 거점사)로 잘못 기록. _end_turn서 거점사를 _check_win보다 먼저 판정해
#       W0(거점사 패배)로 교정 → 그 19줄만 W1→W0, 나머지 randi 스트림 전부 불변.
#     PROBE_SEED=20260718 REGRESS_N=20 godot --headless --path . --script tools/regress.gd 2>/dev/null \
#       | grep -E "^(──|s[0-9])" | diff tools/regress.golden.txt -
#   ⚠의도적 동작 변경(기전 개편) 후엔 골든을 다시 떠서 커밋한다 — 안 그러면 의도된 차이가 노이즈로 섞임.

func _init() -> void:
	var sd: String = OS.get_environment("PROBE_SEED")
	seed(int(sd) if sd != "" else 20260718)
	var N: int = int(OS.get_environment("REGRESS_N")) if OS.get_environment("REGRESS_N") != "" else 20

	var S: GDScript = load("res://Main.gd")
	var g: Node = S.new()
	root.add_child(g)
	# ⚠_ready가 persist_enabled를 켠다. 안 끄면 이 하네스의 전승이 **실유저 진행도에 각인된다** —
	#   실제로 겪은 사고다(14판 전승 → campaign.save에 16383). S1부터는 실패도 저장하므로 위험이 더 크다.
	g.set("persist_enabled", false)
	g.dda_enabled = false   # 실패 케어(S1)도 이 스위치에 물려 있다 → 회귀는 케어 없는 순수 난이도를 잰다
	g.seed_game(int(sd) if sd != "" else 20260718)   # 게임 스트림 시드(코스메틱 전역 RNG와 분리)
	print("── REGRESS (seed=%s N=%d) ──" % [sd if sd != "" else "20260718", N])
	for pass_i in range(2):
		g.surge_enabled = (pass_i == 1)
		for si in range(g.STAGES.size()):
			for t in range(N):
				var r: Dictionary = _play(g, si)
				print("s%d u%d #%02d: W%d sp%d k%d lk%d pl%d cl%d dc%d ds%d" % [
					si, 1 if g.surge_enabled else 0, t,
					1 if r["win"] else 0, r["spawned"], r["killed"], r["leaked"],
					r["places"], r["clears"],
					1 if r["dead_core"] else 0, 1 if r["dead_stuck"] else 0,
				])
	quit()

func _play(g: Node, si: int) -> Dictionary:
	g._start_stage(si)
	var places: int = 0
	var clears: int = 0
	var guard: int = 0
	while not g.game_over and not g.game_clear and guard < 3000:
		guard += 1
		var s: int = 0
		while g.resolving and s < 400:
			g._process(0.05)
			s += 1
		if g.game_over or g.game_clear:
			break
		var mv: Dictionary = _best_move(g)
		if mv.is_empty():
			break
		g.sel = mv["slot"]
		g.hover_col = mv["col"]
		g.hover_row = mv["row"]
		var before: int = g.combo
		g._place_piece()
		places += 1
		if g.resolving or g.combo > before:
			clears += 1
	var s2: int = 0
	while g.resolving and s2 < 400:
		g._process(0.05)
		s2 += 1
	return {
		"win": g.game_clear, "leaked": g.leaked, "spawned": g.spawned, "killed": g.killed,
		"places": places, "clears": clears,
		"dead_core": g.game_over and not g.stuck,
		"dead_stuck": g.game_over and g.stuck,
	}

# ───────── 그리디 봇 (surge_probe.gd에서 복제, g의 public 표면만 읽음) ─────────
func _best_move(g: Node) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1e9
	for slot in range(3):
		if g.tray[slot].is_empty():
			continue
		var offsets: Array = g.tray[slot]["offsets"]
		for r in range(g.ROWS):
			for c in range(g.COLS):
				var cells: Array = []
				var ok: bool = true
				for o in offsets:
					var ov: Vector2i = o as Vector2i
					var cc: Vector2i = Vector2i(c + ov.x, r + ov.y)
					if cc.x < 0 or cc.x >= g.COLS or cc.y < 0 or cc.y >= g.ROWS:
						ok = false
						break
					if g.board[cc.y][cc.x] != "":
						ok = false
						break
					cells.append(cc)
				if not ok:
					continue
				var sc: float = _score(g, cells, slot)
				if sc > best_score:
					best_score = sc
					best = {"slot": slot, "col": c, "row": r}
	return best

func _score(g: Node, cells: Array, slot: int) -> float:
	var occ: Array = []
	for r in range(g.ROWS):
		var row: Array = []
		for c in range(g.COLS):
			row.append(g.board[r][c] != "")
		occ.append(row)
	for ci in cells:
		var cv: Vector2i = ci as Vector2i
		occ[cv.y][cv.x] = true

	var full_rows: Array = []
	var full_cols: Array = []
	for r in range(g.ROWS):
		var fr: bool = true
		for c in range(g.COLS):
			if not occ[r][c]:
				fr = false
				break
		if fr:
			full_rows.append(r)
	for c in range(g.COLS):
		var fcx: bool = true
		for r in range(g.ROWS):
			if not occ[r][c]:
				fcx = false
				break
		if fcx:
			full_cols.append(c)

	var lines: int = full_rows.size() + full_cols.size()
	var score: float = 0.0
	score += 500.0 * float(lines)

	var after: Array = []
	for r2 in range(g.ROWS):
		var row2: Array = []
		for c2 in range(g.COLS):
			var f: bool = occ[r2][c2]
			if full_rows.has(r2) or full_cols.has(c2):
				f = false
			row2.append(f)
		after.append(row2)
	var others: int = 0
	for slot2 in range(3):
		if slot2 == slot or g.tray[slot2].is_empty():
			continue
		others += 1
		if not _fits_anywhere(g, after, g.tray[slot2]["offsets"]):
			score -= 900.0
	if others == 0:
		var free: int = 0
		for r3 in range(g.ROWS):
			for c3 in range(g.COLS):
				if not after[r3][c3]:
					free += 1
		if free < 12:
			score -= 300.0

	if lines > 0:
		var lanes: int = maxi(1, g.combo + 1)
		var hit: int = 0
		for e in g.enemies:
			var in_band: bool = false
			for fc2 in full_cols:
				if absi(int(e["col"]) - int(fc2)) < lanes:
					in_band = true
			for fr2 in full_rows:
				if absi(int(e["row"]) - int(fr2)) < lanes:
					in_band = true
			if in_band:
				hit += 1
		score += 120.0 * float(hit)
		for e in g.enemies:
			for fc3 in full_cols:
				if int(e["col"]) == int(fc3):
					score += 8.0 * float(e["row"])

	var filled: int = 0
	var holes: int = 0
	for r in range(g.ROWS):
		for c in range(g.COLS):
			if occ[r][c]:
				filled += 1
			else:
				var nb: int = 0
				if r == 0 or occ[r - 1][c]:
					nb += 1
				if r == g.ROWS - 1 or occ[r + 1][c]:
					nb += 1
				if c == 0 or occ[r][c - 1]:
					nb += 1
				if c == g.COLS - 1 or occ[r][c + 1]:
					nb += 1
				if nb == 4:
					holes += 1
	var fill_frac: float = float(filled) / float(g.ROWS * g.COLS)
	score -= 60.0 * fill_frac * fill_frac * float(g.ROWS * g.COLS) / 10.0
	score -= 70.0 * float(holes)

	var touch: int = 0
	for ci2 in cells:
		var cv2: Vector2i = ci2 as Vector2i
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cv2.x + d.x
			var ny: int = cv2.y + d.y
			if nx < 0 or nx >= g.COLS or ny < 0 or ny >= g.ROWS:
				touch += 1
			elif g.board[ny][nx] != "":
				touch += 1
	score += 4.0 * float(touch)
	return score

func _fits_anywhere(g: Node, occ: Array, offsets: Array) -> bool:
	for r in range(g.ROWS):
		for c in range(g.COLS):
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var x: int = c + ov.x
				var y: int = r + ov.y
				if x < 0 or x >= g.COLS or y < 0 or y >= g.ROWS or occ[y][x]:
					ok = false
					break
			if ok:
				return true
	return false
