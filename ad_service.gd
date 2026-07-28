extends RefCounted

# 광고 이음새 (Phase V W2 R1 — 설계 정본은 AD_PLAN.md).
# 게임 코드(Main.gd)는 광고 SDK를 직접 만지지 않고 이 서비스로만 광고를 요청한다.
# leaderboard.gd·analytics.gd와 같은 발상: R2에서 AdMob 플러그인을 붙일 때 _platform_* 만 채우면
# 게임 코드는 안 건드린다(gamemode-director-seam과 동형).
#
# ⚠지금 백엔드는 페이크(fake_*)뿐이다 — 실광고 0·계정 0인 채로 부활 상태 기계 전부를
#   데스크톱에서 검증하는 게 R1의 목적이다(AD_PLAN §5). 실 SDK는 R2.
#
# 불변식 5개(깨면 회귀·팝업·수익 판독이 무너진다):
#   ① 게임 RNG를 절대 안 쓴다 — 페이크는 난수 자체를 안 쓰는 결정적 상태 기계다(회귀 byte-identical).
#   ② 헤드리스(regress·sim)에선 스스로 꺼진다. 꺼진 상태의 요청은 즉시 '폴백 가능' 실패로 떨어져
#      게임이 공짜 부활 경로로 흐른다 = 하네스가 광고에 막히지 않는다. (프로브는 enabled를 손으로 켠다.)
#   ③ 광고 지표(ad_*)는 이 서비스가 직접 남긴다 — 게임 코드는 광고 계측을 몰라도 된다.
#   ④ 결과는 성공이든 실패든 **콜백으로 정확히 1회** 돌려준다. 콜백을 안 부르는 경로가 하나라도 있으면
#      결과 팝업이 영영 잠긴다(대기 중엔 다른 버튼을 막으므로 = 소프트락).
#   ⑤ '유저가 광고를 중간에 껐다'만 폴백 아님(fallback=false). 나머지 실패(재고 없음·오류·비활성)는
#      전부 폴백 가능 = 공짜로 이어준다. 광고가 안 나온 건 유저 잘못이 아니다(AD_PLAN §1-2).

# --- 포맷·슬롯 ---
const FORMAT_REWARDED: String = "rewarded"
const FORMAT_INTERSTITIAL: String = "interstitial"
const PLACEMENT_REVIVE: String = "revive"              # 리워드 = 부활 (주력 수익)
const PLACEMENT_RUN_TRANSITION: String = "run_transition"  # 인터스티셜 = 새 런 경계

# --- 실패 사유(result.reason) ---
const R_REWARDED: String = "rewarded"        # 끝까지 봄 → 보상 지급
const R_USER_CANCEL: String = "user_cancel"  # 중간에 끔 → 보상 없음, 폴백도 없음(다시 누를 수 있음)
const R_NO_FILL: String = "no_fill"          # 재고 없음 → 폴백
const R_ERROR: String = "error"              # 로드/표시 오류 → 폴백
const R_DISABLED: String = "disabled"        # 서비스 꺼짐(헤드리스 등) → 폴백

# --- 인터스티셜 빈도 캡 (SPEC §8.1 B / C55) ---
const INTERSTITIAL_FREE_RUNS: int = 2        # 세션 첫 2판은 면제(첫인상 보호)
const INTERSTITIAL_EVERY_RUNS: int = 3       # 이후 3판마다
const INTERSTITIAL_MIN_GAP_MS: int = 180000  # …또는 3분마다 — 둘 중 '늦은 쪽'이므로 AND로 판정

var enabled: bool = true                     # 헤드리스에선 _init이 false로 내린다(불변식 ②)
# ⚠인터스티셜은 배관만 깔고 노출은 끈다(AD_PLAN §3). 캡 수치가 사람 플테 0회 상태서 정한 값이라
#   지금 켜면 근거 없이 코지 톤만 깎는다. W4 UA 코호트에서 on/off 리텐션 비교 후 켠다.
var interstitial_enabled: bool = false

# --- 페이크 백엔드 노브 (R1 검증용 — R2에서 실 SDK가 이 자리를 대체) ---
var fake_fill: bool = true            # 광고 재고 있음
var fake_user_cancel: bool = false    # 유저가 시청 중간에 끔
var fake_error: bool = false          # SDK 로드/표시 오류
var fake_load_ms: int = 0             # 로드 지연(0이면 즉시 해소 — 대기 UI 검증할 때만 올린다)
var fake_watch_ms: int = 0            # 시청 소요
var fake_watched_pct: int = 35        # 중도 이탈 시 시청률(ad_closed 지표)

var _analytics = null                 # AnalyticsService (없어도 동작 — 계측만 조용해진다)
var _rewarded_ready: bool = false     # 프리로드로 채워둔 리워드가 손에 있나
var _job: Dictionary = {}             # 진행 중인 비동기 작업 1건. 비어 있으면 유휴
var _test_now_ms: int = -1            # 프로브용 시간 주입(-1 = 실시간)

# 인터스티셜 캡 상태(세션 단위)
var _runs_this_session: int = 0
var _runs_since_ad: int = 0
var _last_interstitial_ms: int = 0

var debug_events: Array = []          # 프로브 검증용 발화 이름 로그(상한 64) — 게임엔 영향 없음

func _init(analytics = null) -> void:
	_analytics = analytics
	if DisplayServer.get_name() == "headless":
		enabled = false

# --- 리워드(부활) ---

# 판 시작 때 미리 채워둔다. 결과 팝업이 뜨는 순간 is_rewarded_ready()가 실값이어야
#   revive_offered.is_ad_ready가 진짜 신호가 된다(ANALYTICS_TAXONOMY §3-7).
func preload_rewarded(placement: String = PLACEMENT_REVIVE) -> void:
	if not enabled or _rewarded_ready or _job.size() > 0:
		return
	_start_load(placement, Callable())

func is_rewarded_ready() -> bool:
	return enabled and _rewarded_ready

# 광고 요청·시청·결과. 결과는 cb(result: Dictionary)로 1회 돌아온다(불변식 ④).
#   result = {granted: bool, reason: String, fallback: bool, latency_ms: int, watched_pct: int}
#   호출부 규칙: granted면 광고 부활 / fallback이면 공짜 부활 / 둘 다 아니면 아무 일도 안 함(팝업 유지).
func show_rewarded(placement: String, cb: Callable) -> void:
	if not enabled:
		_deliver(cb, _result(false, R_DISABLED, true))
		return
	if _job.size() > 0:
		return   # 이미 진행 중 — 중복 누름은 조용히 무시(콜백 미발화 = 기존 콜백이 아직 살아 있음)
	if _rewarded_ready:
		_start_show(placement, cb)
	else:
		# 준비가 안 됐으면 그 자리에서 1회 재시도한다. 실패하면 폴백(= 공짜 부활)으로 떨어진다.
		_start_load(placement, cb)

# 진행 중인가 — 결과 팝업이 대기 상태를 그리고 다른 버튼 입력을 막는 데 쓴다.
func is_busy() -> bool:
	return _job.size() > 0

# 비동기 진행. Main._process가 매 프레임 부른다(delta 초). 유휴면 즉시 반환 = 비용 0.
func poll(delta: float) -> void:
	if _job.is_empty():
		return
	_job["t"] = float(_job["t"]) - delta * 1000.0
	if float(_job["t"]) > 0.0:
		return
	var kind: String = String(_job["kind"])
	if kind == "load":
		_finish_load()
	else:
		_finish_show()

# --- 인터스티셜 (배관만 — interstitial_enabled=false라 실제로는 안 뜬다) ---

# 판 시작마다 부른다. 캡 카운터는 '시작한 판 수'로 센다(끝난 판이 아니라).
func note_run_started() -> void:
	_runs_this_session += 1
	_runs_since_ad += 1

# 새 런 경계에서 인터스티셜을 띄울 자리인가. 캡 = 첫 2판 면제 + (3판마다 AND 3분마다).
#   ⚠'or 늦은 쪽'은 둘 다 충족해야 한다는 뜻이므로 AND가 맞다(하나만 봐도 되면 더 자주 뜬다).
func should_show_interstitial() -> bool:
	if not enabled or not interstitial_enabled:
		return false
	if _runs_this_session <= INTERSTITIAL_FREE_RUNS:
		return false
	if _runs_since_ad < INTERSTITIAL_EVERY_RUNS:
		return false
	if _now_ms() - _last_interstitial_ms < INTERSTITIAL_MIN_GAP_MS:
		return false
	return true

# 인터스티셜 노출. 리워드와 달리 결과가 게임 상태를 안 바꾸므로 콜백은 선택.
func show_interstitial(placement: String = PLACEMENT_RUN_TRANSITION, cb: Callable = Callable()) -> void:
	if not should_show_interstitial():
		_deliver(cb, _result(false, R_DISABLED, false))
		return
	_runs_since_ad = 0
	_last_interstitial_ms = _now_ms()
	_log("ad_requested", {"format": FORMAT_INTERSTITIAL, "placement": placement, "mediation": "none"})
	var fill: bool = fake_fill and not fake_error
	if not fill:
		_log("ad_no_fill", {"format": FORMAT_INTERSTITIAL, "placement": placement, "latency_ms": 0})
		_deliver(cb, _result(false, R_NO_FILL, false))
		return
	_log("ad_filled", {"format": FORMAT_INTERSTITIAL, "placement": placement, "latency_ms": 0})
	_log("ad_shown", {"format": FORMAT_INTERSTITIAL, "placement": placement})
	_log("ad_closed", {"format": FORMAT_INTERSTITIAL, "watched_pct": 100})
	_deliver(cb, _result(true, R_REWARDED, false))

# --- 내부: 비동기 작업 ---

func _start_load(placement: String, cb: Callable) -> void:
	_log("ad_requested", {"format": FORMAT_REWARDED, "placement": placement, "mediation": "none"})
	_platform_load_rewarded(placement)
	_job = {"kind": "load", "t": float(fake_load_ms), "placement": placement, "cb": cb,
			"latency": fake_load_ms}
	if fake_load_ms <= 0:
		_finish_load()

func _finish_load() -> void:
	var placement: String = String(_job["placement"])
	var cb: Callable = _job["cb"]
	var latency: int = int(_job["latency"])
	var fill: bool = fake_fill and not fake_error
	_job = {}
	if not fill:
		_rewarded_ready = false
		var reason: String = R_ERROR if fake_error else R_NO_FILL
		_log("ad_no_fill", {"format": FORMAT_REWARDED, "placement": placement, "latency_ms": latency})
		# 프리로드(콜백 없음)면 조용히 실패로 남긴다 — 유저는 아직 아무것도 안 눌렀다.
		if cb.is_valid():
			_deliver(cb, _result(false, reason, true, latency))
		return
	_rewarded_ready = true
	_log("ad_filled", {"format": FORMAT_REWARDED, "placement": placement, "latency_ms": latency})
	if cb.is_valid():
		_start_show(placement, cb)   # 유저가 기다리고 있던 요청 = 로드 성공 즉시 이어서 시청

func _start_show(placement: String, cb: Callable) -> void:
	_log("ad_shown", {"format": FORMAT_REWARDED, "placement": placement})
	_platform_show_rewarded(placement)
	_job = {"kind": "show", "t": float(fake_watch_ms), "placement": placement, "cb": cb}
	if fake_watch_ms <= 0:
		_finish_show()

func _finish_show() -> void:
	var placement: String = String(_job["placement"])
	var cb: Callable = _job["cb"]
	_job = {}
	_rewarded_ready = false   # 한 편은 한 번만 — 다음엔 다시 로드해야 한다
	if fake_user_cancel:
		# 중도 이탈: 보상 없음(AdMob 규칙). 단 부활 기회는 소진 안 됨 = 다시 누를 수 있다(AD_PLAN §1-3).
		_log("ad_closed", {"format": FORMAT_REWARDED, "watched_pct": fake_watched_pct})
		_deliver(cb, _result(false, R_USER_CANCEL, false, 0, fake_watched_pct))
		return
	_log("ad_rewarded", {"placement": placement, "reward_granted": true})
	_log("ad_closed", {"format": FORMAT_REWARDED, "watched_pct": 100})
	_deliver(cb, _result(true, R_REWARDED, false, 0, 100))

func _result(granted: bool, reason: String, fallback: bool, latency_ms: int = 0,
		watched_pct: int = 0) -> Dictionary:
	return {"granted": granted, "reason": reason, "fallback": fallback,
			"latency_ms": latency_ms, "watched_pct": watched_pct}

func _deliver(cb: Callable, res: Dictionary) -> void:
	if cb.is_valid():
		cb.call(res)

func _log(name: String, params: Dictionary) -> void:
	debug_events.append(name)
	if debug_events.size() > 64:
		debug_events.pop_front()
	if _analytics != null:
		_analytics.log_event(name, params)

func _now_ms() -> int:
	return _test_now_ms if _test_now_ms >= 0 else Time.get_ticks_msec()

# 프로브용 시간 주입 — 3분 갭 규칙을 실시간 대기 없이 검증한다.
func set_test_time_ms(ms: int) -> void:
	_test_now_ms = ms

# --- 플랫폼 백엔드 (stub — R2 AdMob 플러그인 단계에서 채움) ---
# TODO(R2): poingstudios/godot-admob-plugin. 여기서 할 일은 셋뿐 —
#   ① load/show 호출을 실 SDK로 넘기고 ② 플러그인 시그널(loaded/failed/rewarded/closed)을
#   위 _finish_load/_finish_show와 같은 결과 dict로 번역하고 ③ 테스트 유닛 ID를 빌드 플래그로 가른다.
#   ⚠export_presets.cfg의 use_gradle_build=false → true 전환이 선행(안드로이드 플러그인 요구, AD_PLAN §5).
func _platform_available() -> bool:
	return false

func _platform_load_rewarded(_placement: String) -> void:
	pass

func _platform_show_rewarded(_placement: String) -> void:
	pass
