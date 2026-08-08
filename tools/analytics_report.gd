extends SceneTree
# 플테 로그 판독기 — `analytics.jsonl`을 ANALYTICS_TAXONOMY §5의 파생지표로 접는다(Phase V W1).
#   실행: godot --headless --path . --script tools/analytics_report.gd
#   다른 파일:  ANALYTICS_LOG=/경로/analytics.jsonl godot --headless --path . --script tools/analytics_report.gd
#
# 실기기 플테에서 로그 꺼내기(안드로이드): user:// = /sdcard/Android/data/<패키지>/files/
#   adb pull /sdcard/Android/data/<패키지>/files/analytics.jsonl ./playtest/피험자1.jsonl
#   여러 명이면 파일을 이어붙여도 된다(install_id·session_id로 갈라 읽는다).
#
# ⚠이건 '기계 몫'만 본다. 왜 그만뒀나(표정·말)는 PLAYTEST_PROTOCOL.md의 사람 몫.

func _initialize() -> void:
	var path: String = OS.get_environment("ANALYTICS_LOG")
	if path == "":
		path = OS.get_user_data_dir() + "/analytics.jsonl"
	var evs: Array = _read(path)
	if evs.is_empty():
		print("이벤트 없음: %s" % path)
		quit(1)
		return
	print("── 로그: %s (%d 이벤트) ──" % [path, evs.size()])
	_summary(evs)
	_funnel(evs)
	_deaths(evs)
	_pillars(evs)
	_human_gap(evs)
	quit()

func _read(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line == "":
			continue
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary:
			out.append(v)
	f.close()
	return out

func _of(evs: Array, name: String) -> Array:
	var out: Array = []
	for e in evs:
		if String((e as Dictionary).get("event", "")) == name:
			out.append(e)
	return out

func _pct(a: int, b: int) -> String:
	if b <= 0:
		return "—"
	return "%.0f%% (%d/%d)" % [float(a) * 100.0 / float(b), a, b]

func _avg(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s: float = 0.0
	for v in vals:
		s += float(v)
	return s / float(vals.size())

# ── 표본 개요: 사람 수(install_id) · 세션 · 판 수 · 세션 길이
func _summary(evs: Array) -> void:
	var installs: Dictionary = {}
	var sessions: Dictionary = {}
	for e in evs:
		var d: Dictionary = e as Dictionary
		installs[String(d.get("install_id", "?"))] = true
		sessions[String(d.get("session_id", "?"))] = true
	var durs: Array = []
	for e in _of(evs, "session_ended"):
		durs.append(int((e as Dictionary).get("duration_ms", 0)))
	print("\n[표본] 기기 %d · 세션 %d · 판 %d · 평균 세션 %.1f분" % [
		installs.size(), sessions.size(), _of(evs, "run_started").size(), _avg(durs) / 60000.0])

# ── FTUE 퍼널 + 첫 도파민까지 시간
func _funnel(evs: Array) -> void:
	print("\n[FTUE] 튜토리얼 박자별 완료")
	var beats: Dictionary = {1: 0, 2: 0, 3: 0}
	for e in _of(evs, "tutorial_beat_completed"):
		var b: int = int((e as Dictionary).get("beat", 0))
		beats[b] = int(beats.get(b, 0)) + 1
	print("   박자1 %d → 박자2 %d → 박자3 %d   (완주율 %s)" % [
		beats[1], beats[2], beats[3], _pct(int(beats[3]), int(beats[1]))])
	var ttf: Array = []
	for e in _of(evs, "first_line_cleared"):
		ttf.append(int((e as Dictionary).get("time_since_open_ms", 0)))
	if not ttf.is_empty():
		print("   첫 줄 클리어까지 평균 %.1f초 (n=%d)" % [_avg(ttf) / 1000.0, ttf.size()])
	else:
		print("   ⚠첫 줄 클리어 기록 없음 — 아무도 한 줄을 못 지웠거나 배선 문제")

# ── 죽음의 질 + 부활 전환율 + '억울한 죽음' 신호
func _deaths(evs: Array) -> void:
	print("\n[죽음의 질] run_failed cause 분포")
	var causes: Dictionary = {}
	for e in _of(evs, "run_failed"):
		var c: String = String((e as Dictionary).get("cause", "?"))
		causes[c] = int(causes.get(c, 0)) + 1
	var total: int = _of(evs, "run_failed").size()
	for c in causes:
		print("   %-16s %s" % [c, _pct(int(causes[c]), total)])
	var offered: int = _of(evs, "revive_offered").size()
	var taken: int = _of(evs, "revive_taken").size()
	print("\n[부활] 전환율 %s" % _pct(taken, offered))
	# 거절 유형 — 뒤로가기/홈이 많으면 '팝업을 벗어나고 싶다'는 신호(재도전과 다르다)
	var dis: Dictionary = {}
	for e in _of(evs, "revive_declined"):
		var k: String = String((e as Dictionary).get("dismiss_type", "?"))
		dis[k] = int(dis.get(k, 0)) + 1
	if not dis.is_empty():
		print("   거절 유형: %s" % str(dis))
	# 억울한 죽음 신호 — 거절 뒤 30초 안에 세션이 끝났나(§5). cause별로 센다.
	var quit_after: Dictionary = {}
	for i in range(evs.size()):
		var d: Dictionary = evs[i] as Dictionary
		if String(d.get("event", "")) != "revive_declined":
			continue
		var cause: String = _prev_cause(evs, i)
		for j in range(i + 1, evs.size()):
			var e2: Dictionary = evs[j] as Dictionary
			if String(e2.get("event", "")) == "run_started":
				break     # 다음 판을 시작했다 = 이탈 아님
			if String(e2.get("event", "")) == "session_ended":
				if int(e2.get("t_ms", 0)) - int(d.get("t_ms", 0)) <= 30000:
					quit_after[cause] = int(quit_after.get(cause, 0)) + 1
				break
	if quit_after.is_empty():
		print("   억울한 죽음 신호(거절→30초 내 종료): 없음")
	else:
		print("   ⚠억울한 죽음 신호(거절→30초 내 종료): %s  ← 이 원인부터 손본다" % str(quit_after))

# 이 거절 직전의 실패 원인(같은 run_id의 run_failed)
func _prev_cause(evs: Array, idx: int) -> String:
	var rid: String = String((evs[idx] as Dictionary).get("run_id", ""))
	for k in range(idx - 1, -1, -1):
		var d: Dictionary = evs[k] as Dictionary
		if String(d.get("event", "")) == "run_failed" and String(d.get("run_id", "")) == rid:
			return String(d.get("cause", "?"))
	return "?"

# ── 어느 기둥을 사랑하나(듀얼코어 핵심 판정) + 스테이지 벽
func _pillars(evs: Array) -> void:
	print("\n[기둥] 모드별 판 수·체류")
	var runs: Dictionary = {}
	var time_in: Dictionary = {}
	for e in _of(evs, "run_started"):
		var m: String = String((e as Dictionary).get("mode", "?"))
		runs[m] = int(runs.get(m, 0)) + 1
	for name in ["run_failed", "stage_cleared"]:
		for e in _of(evs, name):
			var d: Dictionary = e as Dictionary
			var m2: String = String(d.get("mode", "?"))
			time_in[m2] = int(time_in.get(m2, 0)) + int(d.get("duration_ms", 0))
	for m in runs:
		print("   %-10s 판 %d · 누적 %.1f분" % [m, int(runs[m]), float(int(time_in.get(m, 0))) / 60000.0])
	# 스테이지 벽 — 어느 스테이지에서 반복 실패가 몰리나
	var wall: Dictionary = {}
	for e in _of(evs, "stage_failed"):
		var sid: int = int((e as Dictionary).get("stage_id", 0))
		wall[sid] = int(wall.get(sid, 0)) + 1
	if not wall.is_empty():
		print("\n[스테이지 벽] 스테이지별 실패 수")
		var keys: Array = wall.keys()
		keys.sort()
		for k in keys:
			var cl: int = 0
			for e in _of(evs, "stage_cleared"):
				if int((e as Dictionary).get("stage_id", 0)) == int(k):
					cl += 1
			print("   S%-3d 실패 %d · 클리어 %d" % [int(k), int(wall[k]), cl])
	# 무한 성과
	var er: Array = _of(evs, "endless_run_ended")
	if not er.is_empty():
		var scores: Array = []
		var depths: Array = []
		for e in er:
			scores.append(int((e as Dictionary).get("score", 0)))
			depths.append(int((e as Dictionary).get("max_depth", 0)))
		print("\n[무한] 런 %d · 평균 점수 %.0f · 평균 깊이 %.1f" % [er.size(), _avg(scores), _avg(depths)])
	# 최대 콤보 분포 — 봇 ~7 대비 사람은?
	var peaks: Array = []
	for e in _of(evs, "combo_peak"):
		peaks.append(int((e as Dictionary).get("max_combo", 0)))
	if not peaks.is_empty():
		peaks.sort()
		print("\n[콤보] 판당 최대 콤보 평균 %.1f · 중앙값 %d · 최고 %d" % [
			_avg(peaks), int(peaks[peaks.size() / 2]), int(peaks[peaks.size() - 1])])


# ── 봇↔사람 승률 갭 ── campaign_probe의 승률과 **직접 맞대는** 절(S30).
# 왜 필요한가: 캠페인 난이도 곡선을 전부 봇으로 짜왔는데, 봇은 사람이 아니다. 봇 승률만 보고
#   목표를 정하면 사람에겐 전혀 다른 게임이 나간다. 여기서 내는 값이 그 보정의 기준선이다.
# **첫 목숨 승률**을 1차 지표로 낸다 = 그 런의 **첫 종료 이벤트**가 클리어였나.
#   부활은 광고를 봐야 얻는 것이므로 부활 포함 승률은 '광고를 켠 세계'의 값이다 —
#   광고를 안 보는 유저(또는 no-fill)가 겪는 난이도는 첫 목숨 쪽이다.
# ⚠**작은 n을 판별로 읽지 말 것.** 판당 5회면 95% 구간이 ±40pt를 넘는다 — 그 숫자로 판을
#   튜닝하면 노이즈를 쫓게 된다. 그래서 판별 줄에 구간 폭을 같이 찍는다.
# ⚠**부활 전환율이 너무 높으면 그 표본은 실플레이가 아니다.** 개발자가 광고 경로를 시험하면
#   제안마다 수락해 첫 목숨 승률이 실제보다 낮게 찍힌다(2026-08 표본이 69%였다).
#   위 [부활] 절의 전환율을 먼저 보고, 이상하면 이 절의 값은 상한으로만 읽을 것.
func _human_gap(evs: Array) -> void:
	print("\n[봇↔사람 갭] 첫 목숨 승률 — campaign_probe 승률과 같은 자로 비교")
	var runs: Dictionary = {}          # run_id -> 첫 종료 이벤트
	for e in evs:
		var d: Dictionary = e as Dictionary
		var ev: String = String(d.get("event", ""))
		if ev != "run_failed" and ev != "stage_cleared":
			continue
		var rid: String = String(d.get("run_id", ""))
		if not runs.has(rid) or int(d.get("t_ms", 0)) < int((runs[rid] as Dictionary).get("t_ms", 1 << 60)):
			runs[rid] = d
	var per: Dictionary = {}           # stage_id -> [시도, 첫목숨승]
	var n_all: int = 0
	var w_all: int = 0
	for rid in runs:
		var d: Dictionary = runs[rid]
		# ⚠봇 프로브 런 제외: 같은 파일에 프로브 기록이 섞인다(수십 ms로 끝난다).
		if int(d.get("duration_ms", 0)) <= 5000:
			continue
		var sid: int = int(d.get("stage_id", 0))
		if sid <= 0:
			continue
		if not per.has(sid):
			per[sid] = [0, 0]
		var row: Array = per[sid]
		row[0] += 1
		n_all += 1
		if String(d.get("event", "")) == "stage_cleared":
			row[1] += 1
			w_all += 1
	if n_all == 0:
		print("   사람 플레이 표본 없음(5초 넘는 런이 없다)")
		return
	print("   판 | 시도 | 첫목숨 승률 | 95% 구간")
	var keys: Array = per.keys()
	keys.sort()
	for sid in keys:
		var row: Array = per[sid]
		var pr: float = float(row[1]) / float(row[0])
		# 구간이 0으로 접히면(전승·전패) 표본이 작다는 사실이 가려진다 → 분산에 하한을 둔다.
		var half: float = 1.96 * sqrt(maxf(pr * (1.0 - pr), 0.05) / float(row[0])) * 100.0
		print("   %2d | %4d | %10.1f%% | ±%.0fpt" % [sid, row[0], 100.0 * pr, half])
	var p_all: float = float(w_all) / float(n_all)
	var half_all: float = 1.96 * sqrt(maxf(p_all * (1.0 - p_all), 0.02) / float(n_all)) * 100.0
	print("   ── 전체 첫 목숨 승률 %.1f%% (%d/%d, ±%.0fpt) ──" % [100.0 * p_all, w_all, n_all, half_all])
	print("   ⇒ 같은 빌드에서 `campaign_probe`를 돌려 이 값과 맞댈 것.")
	print("     판별 비교는 시도수로 가중할 것 — 사람 시도는 판마다 고르지 않다(어려운 판에 몰린다).")
