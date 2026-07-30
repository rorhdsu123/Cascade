extends RefCounted

# 광고 이음새 (Phase V W2 — 설계 정본은 AD_PLAN.md).
# 게임 코드(Main.gd)는 광고 SDK를 직접 만지지 않고 이 서비스로만 광고를 요청한다.
# leaderboard.gd·analytics.gd와 같은 발상: AdMob 플러그인은 _platform_* 뒤에만 있고
# 게임 코드는 R1 때와 한 줄도 안 달라졌다(gamemode-director-seam과 동형).
#
# 백엔드는 둘이다(_platform_on 하나로 갈린다):
#   · 페이크(R1) — 난수 없는 결정적 상태 기계. 계정·실광고 0으로 상태 기계 전부를 검증한다.
#   · 실 SDK(R2) — poingstudios/godot-admob-plugin v5.0.0. 안드로이드/iOS 실기기에서,
#     그리고 데스크톱에선 `--ad-mock`을 줬을 때만(에디터 목 광고) 켜진다.
#     ⚠기본이 페이크인 이유: 기존 하네스(regress·sim·shot 프로브)가 광고를 안 만나야 한다.
#
# 불변식 6개(깨면 회귀·팝업·수익 판독이 무너진다):
#   ① 게임 RNG를 절대 안 쓴다 — 페이크는 난수 자체를 안 쓰는 결정적 상태 기계다(회귀 byte-identical).
#   ② 헤드리스(regress·sim)에선 스스로 꺼진다. 꺼진 상태의 요청은 즉시 '폴백 가능' 실패로 떨어져
#      게임이 공짜 부활 경로로 흐른다 = 하네스가 광고에 막히지 않는다. (프로브는 enabled를 손으로 켠다.)
#   ③ 광고 지표(ad_*)는 이 서비스가 직접 남긴다 — 게임 코드는 광고 계측을 몰라도 된다.
#   ④ 결과는 성공이든 실패든 **콜백으로 정확히 1회** 돌려준다. 콜백을 안 부르는 경로가 하나라도 있으면
#      결과 팝업이 영영 잠긴다(대기 중엔 다른 버튼을 막으므로 = 소프트락).
#   ⑤ '유저가 광고를 중간에 껐다'만 폴백 아님(fallback=false). 나머지 실패(재고 없음·오류·비활성)는
#      전부 폴백 가능 = 공짜로 이어준다. 광고가 안 나온 건 유저 잘못이 아니다(AD_PLAN §1-2).
#   ⑥ **실 SDK 경로엔 반드시 타임아웃이 있다.** 네트워크·SDK는 콜백을 영영 안 줄 수 있는데
#      ④가 깨지는 유일한 현실 경로가 그것이다. 타임아웃 = no_fill 취급 = 공짜 부활(⑤와 같은 논리).
#   ⑦ **동의(UMP)는 게임을 막지 않는다.** 동의를 못 받았거나 절차가 실패하면 광고만 안 나가고
#      게임은 그대로 돈다(부활은 공짜 폴백). 동의 절차가 게임 진행의 전제가 되는 경로는 없다.

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
const R_NO_CONSENT: String = "no_consent"    # 동의 미확보/진행 중 → 폴백. no_fill과 갈라야 판독이 산다
#                                              ('재고가 없다'와 '동의를 못 받았다'는 대응이 완전히 다르다)

# --- 인터스티셜 빈도 캡 (SPEC §8.1 B / C55) ---
const INTERSTITIAL_FREE_RUNS: int = 2        # 세션 첫 2판은 면제(첫인상 보호)
const INTERSTITIAL_EVERY_RUNS: int = 3       # 이후 3판마다
const INTERSTITIAL_MIN_GAP_MS: int = 180000  # …또는 3분마다 — 둘 중 '늦은 쪽'이므로 AND로 판정

# --- 실 SDK 타임아웃 (불변식 ⑥) ---
# 로드: 재고 조회는 보통 1초 안쪽. 10초면 '안 오는 것'으로 봐도 된다 — 죽은 화면에서 더 기다리게
#   하느니 공짜로 이어주는 게 낫다(AD_PLAN §1-2).
const LOAD_TIMEOUT_MS: int = 10000
# 표시: '광고가 화면에 떴다'(on_ad_showed)까지만 재는 시계다. 뜬 뒤로는 유저 시간이라 안 재촉한다
#   — 30초짜리를 다 보고 있는데 8초에 끊으면 보상을 훔치는 셈이 된다.
const SHOW_START_TIMEOUT_MS: int = 8000
# 동의: 유저가 폼을 읽고 고르는 시간이 포함되니 넉넉해야 한다. 넘기면 **광고만** 포기하고(게임은
#   불변식 ⑦으로 이미 안전) 그 사실을 계측에 남긴다 — '광고가 안 나오는데 이유가 없는' 상태를 막는 게
#   이 타이머의 전부다. 폼이 떠 있는 동안은 시계를 멈춘다(유저 시간).
const CONSENT_TIMEOUT_MS: int = 60000

# --- 광고 유닛 ID ---
# 유닛 셋이 둘이다: **테스트**(구글 공개 유닛, 계정 0) / **실**(AdMob 계정 필요, R3).
#
# ⚠클로즈드 테스트(테스터 12명)는 **테스트 유닛으로 내는 게 맞다.** 실 유닛을 켜면 본인·테스터가
#   자기 광고를 누르게 되고, 그건 AdMob 계정 정지의 대표 사유다("무효 트래픽"). 수익 신호는 어차피
#   12명으로는 안 나오고 W4 유료 UA 코호트에서 재는 것이라, 실 유닛은 그때 켠다.
#
# ⚠실 유닛으로 넘어갈 때 같이 바꿔야 하는 것: project.godot의 `admob/general/*/app_id`
#   (지금은 값이 기본값=구글 테스트 App ID와 같아서 파일에 아예 안 적혀 있다) + 개발기기에서
#   테스트하려면 RequestConfiguration.test_device_ids. 절차는 RELEASE.md §9.
const UNIT_REWARDED_ANDROID: String = "ca-app-pub-3940256099942544/5224354917"
const UNIT_REWARDED_IOS: String = "ca-app-pub-3940256099942544/1712485313"
const UNIT_INTERSTITIAL_ANDROID: String = "ca-app-pub-3940256099942544/1033173712"
const UNIT_INTERSTITIAL_IOS: String = "ca-app-pub-3940256099942544/4411468910"

# 실 유닛 — AdMob 계정 개설 후 채운다. **비어 있는 동안은 LIVE_UNITS를 켜도 테스트 유닛으로 돈다**
#   (빈 문자열을 유닛 ID로 넘기면 로드가 조용히 실패해 광고가 통째로 죽는다 = 수익 0인데 원인이 안 보임).
const LIVE_UNIT_REWARDED_ANDROID: String = ""
const LIVE_UNIT_REWARDED_IOS: String = ""
const LIVE_UNIT_INTERSTITIAL_ANDROID: String = ""
const LIVE_UNIT_INTERSTITIAL_IOS: String = ""

# R3에서 이 한 줄을 true로. 그 전엔 실 유닛 상수가 비어 있으니 켜도 아무 일도 안 일어난다.
const LIVE_UNITS: bool = false

# AdMob 로드 실패 코드 3 = no-fill(재고 없음). 나머지는 오류로 가른다 — 둘 다 공짜 부활로 흐르지만
#   지표에선 갈라야 한다('재고가 없다'와 '우리 배선이 틀렸다'는 다른 문제다).
const ADMOB_ERROR_NO_FILL: int = 3

var enabled: bool = true                     # 헤드리스에선 _init이 false로 내린다(불변식 ②)
# ⚠인터스티셜은 배관만 깔고 노출은 끈다(AD_PLAN §3). 캡 수치가 사람 플테 0회 상태서 정한 값이라
#   지금 켜면 근거 없이 코지 톤만 깎는다. W4 UA 코호트에서 on/off 리텐션 비교 후 켠다.
var interstitial_enabled: bool = false

# 데스크톱에서 실 SDK 경로(에디터 목 광고)를 켜는 스위치. 프로브가 실 콜백 배선을 기기 없이
#   밟기 위한 것이라 CLI 인자로만 열린다 — 평소 데스크톱 실행·기존 프로브는 페이크 그대로다.
var allow_editor_mock: bool = OS.get_cmdline_args().has("--ad-mock") \
		or OS.get_cmdline_user_args().has("--ad-mock")

# --- 페이크 백엔드 노브 (R1 검증용 — 실기기에선 _platform_on=true라 이 값들은 안 쓰인다) ---
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

# --- 실 SDK 상태 ---
var _platform_on: bool = false        # 실 AdMob 백엔드를 쓰는가(아니면 페이크)
var _platform_inited: bool = false    # MobileAds.initialize 완료 콜백을 받았나(진단용)

# --- 동의(UMP) 상태 (불변식 ⑦) ---
# 광고를 요청해도 되는가. 페이크·플랫폼 off 경로는 애초에 동의 대상이 아니라 true로 시작하고,
#   실 SDK를 켜는 순간에만 false로 내려 동의 절차가 끝날 때까지 요청을 막는다.
var _consent_ready: bool = true
var _consent_status: int = -1              # ConsentInformation.ConsentStatus (진단·계측용, -1=미조회)
var _consent_form_shown: bool = false      # 이번 실행에서 동의 폼을 실제로 띄웠나
var _privacy_options_required: bool = false  # 설정에 '개인정보 옵션' 항목을 노출해야 하나
var _consent_pending_ms: float = -1.0      # 동의 절차 남은 시계(-1 = 진행 중 아님)
var _consent_form_open: bool = false       # 폼이 화면에 떠 있나(그동안 시계 정지 = 유저 시간)

# 동의 지역을 강제하는 디버그 스위치 — EEA 밖(한국)에서 동의 폼을 실제로 띄워보는 유일한 방법.
#   ⚠구글 규칙상 test_device_hashed_ids가 함께 있어야 debug_geography가 먹는다. 해시 ID는
#     동의 절차를 한 번 돌리면 logcat에 찍힌다("Use new ConsentDebugSettings.Builder()...").
#   예: adb shell am start ... 대신 빌드에 넣기 어려우니 개발 중엔 CLI로 준다(데스크톱 목 광고 경로).
var consent_debug_eea: bool = OS.get_cmdline_args().has("--ad-consent-eea") \
		or OS.get_cmdline_user_args().has("--ad-consent-eea")
var consent_debug_device_id: String = ""   # 위 스위치와 한 쌍(빈 값이면 debug_geography가 무시된다)
var _loader = null                    # RewardedAdLoader — 로드 중 살려둬야 콜백이 온다
var _rewarded = null                  # RewardedAd (손에 든 광고 1편)
var _int_loader = null                # InterstitialAdLoader
var _interstitial = null              # InterstitialAd

func _init(analytics = null) -> void:
	_analytics = analytics
	if DisplayServer.get_name() == "headless":
		enabled = false
	if not enabled:
		return
	var on_device: bool = OS.get_name() == "Android" or OS.get_name() == "iOS"
	if not on_device and not allow_editor_mock:
		return                            # 데스크톱 개발·기존 하네스 = 페이크 그대로
	if _platform_available():
		_platform_on = true
		# 동의(UMP)는 **실기기에서만** 받는다. 데스크톱 목 광고는 실 광고망을 안 타므로 동의 대상이
		#   아니고, 거기서 동의를 요구하면 UMP 싱글턴이 없어 절차가 영영 안 끝나 광고가 통째로 죽는다.
		if not on_device:
			_platform_initialize()
		elif _platform_consent_available():
			# ⚠순서가 정책이다: **동의부터**, 그 다음 SDK 초기화·광고 요청. 뒤집으면 동의 없이 광고를
			#   요청하는 창이 열린다(EEA/UK 위반). 절차가 끝나면 _consent_settle이 초기화를 잇는다.
			_consent_ready = false
			_consent_pending_ms = float(CONSENT_TIMEOUT_MS)
			_platform_consent_begin()
		else:
			# 실기기인데 UMP 싱글턴이 없다 = GMA는 붙었는데 동의 모듈만 빠진 배선 사고.
			#   동의 없이 광고를 내보내면 정책 위반이고, 페이크로 때우면 사고가 안 드러난다
			#   → GMA 플러그인 부재와 같은 처방: 광고를 끄고 공짜 부활로 흘린다(불변식 ⑤·⑦).
			enabled = false
			push_error("AdService: UMP(동의) 싱글턴 없음 — 광고 끄고 공짜 부활로 흐른다")
	elif on_device:
		# ⚠실기기인데 네이티브 플러그인이 없다 = 배선 사고(플러그인 비활성·gradle 빌드 off·aar 누락).
		#   여기서 페이크로 때우면 최악이다 — 광고가 "도는 것처럼" 보여서 사고가 안 드러나고,
		#   수익만 0인 채 소프트런치 데이터가 통째로 거짓이 된다.
		#   그래서 서비스를 통째로 끈다: 유저는 공짜 부활로 안 다치고(불변식 ⑤), ad_* 지표가
		#   통째로 비어 있어 판독기에서 즉시 눈에 띈다.
		enabled = false
		push_error("AdService: AdMob 네이티브 플러그인 없음 — 광고 끄고 공짜 부활로 흐른다")

# 어느 백엔드가 붙었는지 — 프로브·로그 판독용.
func backend() -> String:
	if not enabled:
		return "disabled"
	return "admob" if _platform_on else "fake"

# --- 리워드(부활) ---

# 판 시작 때 미리 채워둔다. 결과 팝업이 뜨는 순간 is_rewarded_ready()가 실값이어야
#   revive_offered.is_ad_ready가 진짜 신호가 된다(ANALYTICS_TAXONOMY §3-7).
func preload_rewarded(placement: String = PLACEMENT_REVIVE) -> void:
	if not enabled or _rewarded_ready or _job.size() > 0:
		return
	if not _consent_ready:
		return                      # 동의 전엔 요청 자체를 안 만든다(불변식 ⑦)
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
	if not _consent_ready:
		# 동의가 아직/영영 없다 → 광고는 못 틀지만 유저를 벌주지 않는다: 공짜로 이어준다(불변식 ⑦+⑤).
		_log("ad_no_fill", {"format": FORMAT_REWARDED, "placement": placement, "latency_ms": 0,
				"no_consent": true})
		_deliver(cb, _result(false, R_NO_CONSENT, true))
		return
	if _job.size() > 0:
		# 진행 중인 게 **프리로드**(유저 없는 요청)면 거기에 유저의 요청을 붙인다.
		#   실 SDK는 로드에 1~3초가 걸려서, 그 창에 누른 손을 조용히 버리면 버튼이 죽은 것처럼 보인다.
		#   (유저 요청이 이미 떠 있는 경우는 Main이 _ad_pending으로 막으므로 여기 안 온다.)
		if String(_job["kind"]) == "load" and not (_job["cb"] as Callable).is_valid():
			_job["cb"] = cb
		return
	if _rewarded_ready:
		_start_show(placement, cb)
	else:
		# 준비가 안 됐으면 그 자리에서 1회 재시도한다. 실패하면 폴백(= 공짜 부활)으로 떨어진다.
		_start_load(placement, cb)

# 진행 중인가 — 결과 팝업이 대기 상태를 그리고 다른 버튼 입력을 막는 데 쓴다.
func is_busy() -> bool:
	return _job.size() > 0

# 비동기 진행. Main._process가 매 프레임 부른다(delta 초). 유휴면 즉시 반환 = 비용 0.
#   페이크에선 이 시계가 '완료 예정 시각'이고, 실 SDK에선 '타임아웃'이다(불변식 ⑥).
func poll(delta: float) -> void:
	_poll_consent(delta)
	if _job.is_empty():
		return
	var kind: String = String(_job["kind"])
	if bool(_job.get("platform", false)):
		# 광고가 이미 화면에 떠 있으면 시계를 멈춘다 — 여기서부턴 유저가 쓰는 시간이다.
		if kind == "show" and bool(_job.get("shown", false)):
			return
		_job["t"] = float(_job["t"]) - delta * 1000.0
		if float(_job["t"]) > 0.0:
			return
		if kind == "load":
			_finish_load(false, R_NO_FILL)          # 안 오는 응답 = 재고 없음 취급 → 공짜 부활
		else:
			_finish_show(false, R_ERROR, true, 0)   # 표시가 시작조차 안 됨 → 공짜 부활
		return
	_job["t"] = float(_job["t"]) - delta * 1000.0
	if float(_job["t"]) > 0.0:
		return
	if kind == "load":
		_finish_load(fake_fill and not fake_error, R_ERROR if fake_error else R_NO_FILL)
	else:
		_finish_fake_show()

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
	if not _consent_ready:
		return false
	if _runs_this_session <= INTERSTITIAL_FREE_RUNS:
		return false
	if _runs_since_ad < INTERSTITIAL_EVERY_RUNS:
		return false
	if _now_ms() - _last_interstitial_ms < INTERSTITIAL_MIN_GAP_MS:
		return false
	return true

# 인터스티셜 노출. 리워드와 달리 결과가 게임 상태를 안 바꾸므로 콜백은 선택.
#   ⚠캡 카운터는 '띄우기로 결정한 순간' 리셋한다 — 로드가 실패해도 다음 판에 곧바로 또 시도하면
#     캡이 무의미해진다(실패가 빈도를 올리는 역설).
func show_interstitial(placement: String = PLACEMENT_RUN_TRANSITION, cb: Callable = Callable()) -> void:
	if not should_show_interstitial():
		_deliver(cb, _result(false, R_DISABLED, false))
		return
	_runs_since_ad = 0
	_last_interstitial_ms = _now_ms()
	_log("ad_requested", {"format": FORMAT_INTERSTITIAL, "placement": placement, "mediation": "none"})
	if _platform_on:
		_platform_load_interstitial(placement, cb)
		return
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
	if _platform_on:
		_job = {"kind": "load", "t": float(LOAD_TIMEOUT_MS), "placement": placement, "cb": cb,
				"latency": 0, "platform": true, "t0": _now_ms()}
		_platform_load_rewarded(placement)
		return
	_job = {"kind": "load", "t": float(fake_load_ms), "placement": placement, "cb": cb,
			"latency": fake_load_ms}
	if fake_load_ms <= 0:
		_finish_load(fake_fill and not fake_error, R_ERROR if fake_error else R_NO_FILL)

# 로드 종결 — 성공이면 채워두고(대기 중인 요청이 있으면 이어서 시청), 실패면 폴백으로 돌려준다.
func _finish_load(ok: bool, fail_reason: String) -> void:
	var placement: String = String(_job["placement"])
	var cb: Callable = _job["cb"]
	var latency: int = int(_job["latency"])
	if bool(_job.get("platform", false)):
		latency = _now_ms() - int(_job["t0"])
	_job = {}
	if not ok:
		_rewarded_ready = false
		_log("ad_no_fill", {"format": FORMAT_REWARDED, "placement": placement, "latency_ms": latency})
		# 프리로드(콜백 없음)면 조용히 실패로 남긴다 — 유저는 아직 아무것도 안 눌렀다.
		if cb.is_valid():
			_deliver(cb, _result(false, fail_reason, true, latency))
		return
	_rewarded_ready = true
	_log("ad_filled", {"format": FORMAT_REWARDED, "placement": placement, "latency_ms": latency})
	if cb.is_valid():
		_start_show(placement, cb)   # 유저가 기다리고 있던 요청 = 로드 성공 즉시 이어서 시청

func _start_show(placement: String, cb: Callable) -> void:
	# ⚠ad_shown은 '띄우라고 시킨 순간'에 남긴다(실제 표시 콜백이 아니라). 페이크·실 SDK의 지표
	#   모양을 같게 유지하려는 것이고, 표시 실패는 ad_closed의 watched_pct=0으로 구분된다.
	_log("ad_shown", {"format": FORMAT_REWARDED, "placement": placement})
	if _platform_on:
		_job = {"kind": "show", "t": float(SHOW_START_TIMEOUT_MS), "placement": placement,
				"cb": cb, "platform": true, "shown": false, "earned": false}
		_platform_show_rewarded(placement)
		return
	_job = {"kind": "show", "t": float(fake_watch_ms), "placement": placement, "cb": cb}
	if fake_watch_ms <= 0:
		_finish_fake_show()

func _finish_fake_show() -> void:
	if fake_user_cancel:
		# 중도 이탈: 보상 없음(AdMob 규칙). 단 부활 기회는 소진 안 됨 = 다시 누를 수 있다(AD_PLAN §1-3).
		_finish_show(false, R_USER_CANCEL, false, fake_watched_pct)
	else:
		_finish_show(true, R_REWARDED, false, 100)

# 시청 종결 — 모든 경로(보상·이탈·오류·타임아웃)가 여기 하나로 모인다(불변식 ④).
func _finish_show(granted: bool, reason: String, fallback: bool, watched_pct: int) -> void:
	var placement: String = String(_job["placement"])
	var cb: Callable = _job["cb"]
	_job = {}
	_rewarded_ready = false   # 한 편은 한 번만 — 다음엔 다시 로드해야 한다
	if granted:
		_log("ad_rewarded", {"placement": placement, "reward_granted": true})
		_log("ad_closed", {"format": FORMAT_REWARDED, "watched_pct": watched_pct})
		_deliver(cb, _result(true, R_REWARDED, false, 0, watched_pct))
		return
	_log("ad_closed", {"format": FORMAT_REWARDED, "watched_pct": watched_pct})
	_deliver(cb, _result(false, reason, fallback, 0, watched_pct))

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

# --- 플랫폼 백엔드 (R2 — poingstudios/godot-admob-plugin v5.0.0) ---
# 여기 밖으로 새는 AdMob 타입은 하나도 없다. 위 상태 기계는 플러그인이 있든 없든 똑같이 돈다.
# ⚠전제조건 = export_presets.cfg의 use_gradle_build=true(안드로이드 네이티브 플러그인 요구, de6d2c3)
#   + addons/admob 활성화 + addons/admob/android/bin 바이너리(저장소에 커밋해 둠).

func _platform_available() -> bool:
	# 플러그인 미설치/비활성이면 전역 클래스 자체가 없다 → 스크립트 파싱은 통과하되 여기서 false.
	#   is_required=false라 없을 때 에러 대신 경고만 남는다(데스크톱 개발이 시끄러워지지 않게).
	return MobileSingletonPlugin._get_plugin("PoingGodotAdMobRewardedAd", false) != null

func _platform_initialize() -> void:
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status) -> void:
		_platform_inited = true
	MobileAds.initialize(listener)

# --- 동의(UMP) — Google User Messaging Platform ---
# 흐름(구글 권장 순서): 동의 정보 갱신 → (필요하면) 동의 폼 표시 → 상태 확인 → 그때 SDK 초기화·광고 요청.
#   어느 단계가 실패해도 게임은 안 막힌다 — _consent_settle이 광고만 끄고 끝낸다(불변식 ⑦).
#
# ⚠"동의가 필요 없다"(NOT_REQUIRED, 예: 한국)와 "동의를 받았다"(OBTAINED) 둘만 광고 요청 가능이다.
#   REQUIRED·UNKNOWN에서 요청하면 정책 위반이라 여기서 막는다.

# 동의 절차가 응답 없이 멈춘 경우를 닫는다. 게임은 이미 안 막혀 있으니(불변식 ⑦) 여기서 하는 일은
#   '광고를 포기했다'는 사실을 계측에 남기는 것뿐 — 그게 없으면 fill률 0의 원인을 영원히 못 찾는다.
func _poll_consent(delta: float) -> void:
	if _consent_pending_ms < 0.0 or _consent_form_open:
		return
	_consent_pending_ms -= delta * 1000.0
	if _consent_pending_ms > 0.0:
		return
	_consent_pending_ms = -1.0
	push_warning("AdService: 동의 절차 응답 없음(%dms) — 이번 실행은 광고 없이 돈다" % CONSENT_TIMEOUT_MS)
	_log("ad_consent_updated", {
		"status": "timeout", "form_shown": _consent_form_shown,
		"privacy_options_required": false, "can_request_ads": false, "unit_mode": unit_mode(),
	})

func _platform_consent_available() -> bool:
	return MobileSingletonPlugin._get_plugin("PoingGodotAdMobUserMessagingPlatform", false) != null

func _platform_consent_begin() -> void:
	var params := ConsentRequestParameters.new()
	# 아동 대상 앱이 아니다(퍼즐/디펜스, 연령 게이트 없음). true면 광고가 전부 비개인화로 강제된다.
	params.tag_for_under_age_of_consent = false
	if consent_debug_eea and consent_debug_device_id != "":
		var dbg := ConsentDebugSettings.new()
		dbg.debug_geography = DebugGeography.Values.EEA
		var ids: Array[String] = [consent_debug_device_id]
		dbg.test_device_hashed_ids = ids
		params.consent_debug_settings = dbg
	UserMessagingPlatform.consent_information.update(
			params,
			func() -> void: _on_consent_info_ok(),
			func(err) -> void: _on_consent_info_failed(err))

func _on_consent_info_ok() -> void:
	var ci = UserMessagingPlatform.consent_information
	# 폼이 없으면(동의 불필요 지역 등) 더 할 게 없다 — 상태만 읽고 정산한다.
	if not ci.get_is_consent_form_available():
		_consent_settle()
		return
	UserMessagingPlatform.load_consent_form(
			func(form) -> void: _on_consent_form_loaded(form),
			func(err) -> void: _on_consent_form_failed(err))

func _on_consent_info_failed(err) -> void:
	# 네트워크 없음 등. 광고는 이번 실행에서 포기하고 게임은 그대로 간다. 다음 실행에서 다시 시도된다.
	push_warning("AdService: 동의 정보 갱신 실패(%s) — 이번 실행은 광고 없이 돈다" % _form_err(err))
	_consent_settle()

func _on_consent_form_loaded(form) -> void:
	var ci = UserMessagingPlatform.consent_information
	if ci.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		_consent_form_shown = true
		_consent_form_open = true       # 유저가 읽고 고르는 시간 — 타임아웃 시계를 멈춘다
		form.show(func(_err) -> void:
			_consent_form_open = false
			_consent_settle())          # 닫힌 뒤 상태를 다시 읽는다
		return
	_consent_settle()

func _on_consent_form_failed(err) -> void:
	push_warning("AdService: 동의 폼 로드 실패(%s) — 이번 실행은 광고 없이 돈다" % _form_err(err))
	_consent_settle()

# 동의 절차의 유일한 종착점. 여기서만 _consent_ready가 정해지고, 여기서만 SDK 초기화가 이어진다.
func _consent_settle() -> void:
	_consent_pending_ms = -1.0        # 절차 종료 — 타임아웃 시계를 내린다
	var ci = UserMessagingPlatform.consent_information
	_consent_status = ci.get_consent_status()
	_privacy_options_required = (ci.get_privacy_options_requirement_status()
			== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED)
	_consent_ready = (_consent_status == ConsentInformation.ConsentStatus.NOT_REQUIRED
			or _consent_status == ConsentInformation.ConsentStatus.OBTAINED)
	_log("ad_consent_updated", {
		"status": _consent_status_name(),
		"form_shown": _consent_form_shown,
		"privacy_options_required": _privacy_options_required,
		"can_request_ads": _consent_ready,
		"unit_mode": unit_mode(),
	})
	if not _consent_ready:
		return
	if not _platform_inited:
		_platform_initialize()

func _consent_status_name() -> String:
	match _consent_status:
		ConsentInformation.ConsentStatus.NOT_REQUIRED: return "not_required"
		ConsentInformation.ConsentStatus.REQUIRED: return "required"
		ConsentInformation.ConsentStatus.OBTAINED: return "obtained"
		ConsentInformation.ConsentStatus.UNKNOWN: return "unknown"
	return "unqueried"

func _form_err(err) -> String:
	if err == null:
		return "?"
	return "%d %s" % [err.error_code, err.message]

# --- 개인정보 옵션(동의 재설정) — 설정 화면에서 부른다 ---
# 구글 요구: EEA/UK에서 동의를 받은 유저는 **언제든 동의를 바꿀 수 있는 입구**가 있어야 한다.
#   그 입구가 필요한 지역인지는 SDK가 알려준다 → 필요할 때만 설정에 항목을 노출한다
#   (안 그러면 한국 유저에게 아무 의미 없는 항목이 상시로 붙는다).
func privacy_options_required() -> bool:
	return enabled and _platform_on and _privacy_options_required

func show_privacy_options() -> void:
	if not privacy_options_required():
		return
	UserMessagingPlatform.show_privacy_options_form(func(_err) -> void: _consent_settle())

# 실 유닛을 쓰는가 — LIVE_UNITS 스위치 AND 해당 플랫폼 상수가 실제로 채워져 있을 때만.
#   '켰다고 생각했는데 빈 문자열이라 광고가 통째로 죽는' 사고를 구조적으로 막는다.
func live_units() -> bool:
	if not LIVE_UNITS:
		return false
	var is_ios: bool = OS.get_name() == "iOS"
	var r: String = LIVE_UNIT_REWARDED_IOS if is_ios else LIVE_UNIT_REWARDED_ANDROID
	if r == "":
		push_warning("AdService: LIVE_UNITS=true인데 실 유닛 ID가 비어 있다 — 테스트 유닛으로 돈다")
		return false
	return true

# 어느 유닛 셋으로 도는지 — logcat·프로브에서 '테스트 유닛으로 출고됐나'를 눈으로 확인하는 창.
func unit_mode() -> String:
	return "live" if live_units() else "test"

func _unit_id(format: String) -> String:
	var is_ios: bool = OS.get_name() == "iOS"
	if live_units():
		if format == FORMAT_INTERSTITIAL:
			return LIVE_UNIT_INTERSTITIAL_IOS if is_ios else LIVE_UNIT_INTERSTITIAL_ANDROID
		return LIVE_UNIT_REWARDED_IOS if is_ios else LIVE_UNIT_REWARDED_ANDROID
	if format == FORMAT_INTERSTITIAL:
		return UNIT_INTERSTITIAL_IOS if is_ios else UNIT_INTERSTITIAL_ANDROID
	return UNIT_REWARDED_IOS if is_ios else UNIT_REWARDED_ANDROID

func _platform_load_rewarded(_placement: String) -> void:
	var load_cb := RewardedAdLoadCallback.new()
	load_cb.on_ad_loaded = func(ad) -> void:
		_on_platform_rewarded_loaded(ad)
	load_cb.on_ad_failed_to_load = func(err) -> void:
		_on_platform_rewarded_load_failed(err)
	_loader = RewardedAdLoader.new()
	_loader.load(_unit_id(FORMAT_REWARDED), AdRequest.new(), load_cb)

func _platform_show_rewarded(_placement: String) -> void:
	if _rewarded == null:
		# 손에 든 광고가 없는데 표시 요청이 왔다 = 배선 사고. 소프트락 대신 즉시 폴백으로 닫는다.
		_finish_show(false, R_ERROR, true, 0)
		return
	var fsc := FullScreenContentCallback.new()
	fsc.on_ad_showed_full_screen_content = func() -> void:
		if _job.size() > 0 and String(_job["kind"]) == "show":
			_job["shown"] = true          # 여기서부터 타임아웃 시계를 멈춘다(유저 시간)
	fsc.on_ad_dismissed_full_screen_content = func() -> void:
		_on_platform_rewarded_dismissed()
	fsc.on_ad_failed_to_show_full_screen_content = func(_err) -> void:
		_destroy_rewarded()
		if _job.size() > 0 and String(_job["kind"]) == "show":
			_finish_show(false, R_ERROR, true, 0)
	_rewarded.full_screen_content_callback = fsc
	var reward_listener := OnUserEarnedRewardListener.new()
	reward_listener.on_user_earned_reward = func(_item) -> void:
		# 보상은 여기서 '확정'만 하고 결과는 닫힘(dismissed)에서 돌려준다 — 광고가 아직 화면에
		#   떠 있는데 뒤에서 판이 되살아나면 유저는 무슨 일이 일어났는지 못 본다.
		if _job.size() > 0 and String(_job["kind"]) == "show":
			_job["earned"] = true
	_rewarded.show(reward_listener)

func _on_platform_rewarded_loaded(ad) -> void:
	_rewarded = ad
	if _job.size() > 0 and String(_job["kind"]) == "load" and bool(_job.get("platform", false)):
		_finish_load(true, "")
		return
	# 타임아웃 뒤에 늦게 도착한 광고 — 버리지 말고 다음 요청용으로 손에 쥔다.
	_rewarded_ready = true

func _on_platform_rewarded_load_failed(err) -> void:
	_rewarded = null
	if _job.is_empty() or String(_job["kind"]) != "load":
		return
	var code: int = int(err.code) if err != null else -1
	_finish_load(false, R_NO_FILL if code == ADMOB_ERROR_NO_FILL else R_ERROR)

func _on_platform_rewarded_dismissed() -> void:
	var earned: bool = _job.size() > 0 and bool(_job.get("earned", false))
	_destroy_rewarded()
	if _job.is_empty() or String(_job["kind"]) != "show":
		return
	if earned:
		_finish_show(true, R_REWARDED, false, 100)
	else:
		# 중도 이탈 = 보상 없음. 단 기회는 안 태운다(AD_PLAN §1-3). watched_pct는 SDK가 안 준다.
		_finish_show(false, R_USER_CANCEL, false, 0)

func _destroy_rewarded() -> void:
	# 네이티브 메모리는 우리가 놓아줘야 한다(플러그인 문서의 'Crucial' 항목).
	if _rewarded != null:
		_rewarded.destroy()
		_rewarded = null
	_rewarded_ready = false

# 인터스티셜은 노출 off라 게임에선 안 불린다. 배선만 리워드와 같은 모양으로 갖춰 둔다
#   — 켜는 날(W4 UA 코호트) 코드를 새로 쓰지 않기 위해서다. 상태 기계는 안 쓴다(결과가 게임을 안 바꿈).
func _platform_load_interstitial(placement: String, cb: Callable) -> void:
	var load_cb := InterstitialAdLoadCallback.new()
	load_cb.on_ad_loaded = func(ad) -> void:
		_interstitial = ad
		_log("ad_filled", {"format": FORMAT_INTERSTITIAL, "placement": placement, "latency_ms": 0})
		var fsc := FullScreenContentCallback.new()
		fsc.on_ad_dismissed_full_screen_content = func() -> void:
			_log("ad_closed", {"format": FORMAT_INTERSTITIAL, "watched_pct": 100})
			_destroy_interstitial()
			_deliver(cb, _result(true, R_REWARDED, false))
		fsc.on_ad_failed_to_show_full_screen_content = func(_err) -> void:
			_log("ad_closed", {"format": FORMAT_INTERSTITIAL, "watched_pct": 0})
			_destroy_interstitial()
			_deliver(cb, _result(false, R_ERROR, false))
		_interstitial.full_screen_content_callback = fsc
		_log("ad_shown", {"format": FORMAT_INTERSTITIAL, "placement": placement})
		_interstitial.show()
	load_cb.on_ad_failed_to_load = func(_err) -> void:
		_log("ad_no_fill", {"format": FORMAT_INTERSTITIAL, "placement": placement, "latency_ms": 0})
		_deliver(cb, _result(false, R_NO_FILL, false))
	_int_loader = InterstitialAdLoader.new()
	_int_loader.load(_unit_id(FORMAT_INTERSTITIAL), AdRequest.new(), load_cb)

func _destroy_interstitial() -> void:
	if _interstitial != null:
		_interstitial.destroy()
		_interstitial = null
