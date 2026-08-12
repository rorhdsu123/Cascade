extends RefCounted

# 애널리틱스 이음새 (Phase V W1 ④ — 설계 정본은 ANALYTICS_TAXONOMY.md).
# 게임 코드(Main.gd)는 SDK나 user:// 파일을 직접 만지지 않고 이 서비스로만 이벤트를 흘린다.
# leaderboard.gd와 같은 발상: 나중에 Firebase Analytics를 붙일 때 _platform_* stub만 채우면
# 게임 코드는 안 건드린다(gamemode-director-seam과 동형).
#
# 백엔드는 둘이다. **로컬 JSONL**(`user://analytics.jsonl`)이 늘 남고(내 기기에서 뽑아 읽는 용),
#   `REMOTE_URL`을 채우면 **원격 싱크**가 같은 이벤트를 우리 엔드포인트로 중계한다.
#   원격이 필요한 이유: 남의 기기(웹 플레이테스터·클로즈드 테스터)에 쌓인 JSONL은 뽑아올 방법이 없다.
#   Firebase가 아니라 순수 HTTP인 이유: 네이티브 플러그인이 필요 없어서 웹·안드로이드가 같은 코드로 돈다
#   (AdMob 플러그인에서 밟은 compileSdk·플러그인 부재 위장 같은 지뢰를 통째로 피한다).
#
# 불변식 3개(깨면 회귀·결정성이 무너진다):
#   ① 게임 RNG를 절대 안 쓴다 — id는 전용 RandomNumberGenerator(_rng)로만 뽑는다. randi()/game_rng 금지.
#   ② 헤드리스(regress·sim·probe)에선 스스로 꺼진다 — 하네스가 파일을 더럽히거나 느려지지 않게.
#   ③ 발화는 상태를 안 바꾼다 — 어떤 이벤트도 게임 값을 되돌려주지 않는다(read-only 관찰자).

const LOG_PATH: String = "user://analytics.jsonl"     # 이벤트 1줄 = JSON 1개(append-only)
const META_PATH: String = "user://analytics.meta"     # {install_id, session_count} — is_first_session 판정용

# --- 원격 싱크 설정 ---
# ⚠비어 있으면 원격은 통째로 꺼진다(로컬 JSONL만). 이게 기본값이고, 안전한 기본값이다 —
#   URL을 안 채운 채로 조용히 "보내는 줄 알았는데 아무 데도 안 가는" 상태가 안 생긴다.
#   엔드포인트 요구사항: POST를 받고 CORS를 허용할 것(웹 빌드는 브라우저가 막는다).
const REMOTE_URL: String = ""
const REMOTE_BATCH: int = 12          # 이만큼 쌓이면 보낸다(요청 수를 줄인다)
const REMOTE_BATCH_WEB: int = 4       # 웹은 탭이 언제든 닫히므로 더 자주 보낸다
const REMOTE_MAX_BUFFER: int = 200    # 전송 실패가 쌓여도 여기까지. 넘으면 오래된 것부터 버린다
const REMOTE_TIMEOUT_S: float = 20.0
# 배치가 안 차도 즉시 보내는 이벤트 — 세션이 여기서 끝나버릴 수 있는 자리들.
#   이걸 안 하면 "한 판 하고 나간 사람"의 데이터가 영영 안 온다 = 이탈 분석이 통째로 빈다.
const REMOTE_FLUSH_ON: Array = ["session_ended", "run_failed", "stage_cleared", "endless_run_ended"]
const LOG_MAX_BYTES: int = 512 * 1024                 # 상한. 넘으면 새로 시작(플테 1인 세션엔 차고 넘침)
const SCHEMA_VERSION: int = 1                         # 택소노미 v1

# P0 이벤트 화이트리스트(ANALYTICS_TAXONOMY §7). 오타 이벤트가 조용히 쌓이는 걸 막는다 —
#   목록에 없는 이름은 기록하되 `unknown_event` 플래그를 달아 리포트가 잡아낸다.
const P0_EVENTS: Array = [
	"app_opened", "session_ended",
	"run_started", "run_failed", "stage_cleared", "stage_failed",
	"revive_offered", "revive_taken", "revive_declined",
	"tutorial_beat_completed", "first_line_cleared",
	"endless_run_ended", "combo_peak",
	# P2 — W2 광고 배선(§3-7). 발화 주체는 AdService 자신이다(게임 코드는 광고 계측을 모른다).
	"ad_requested", "ad_filled", "ad_no_fill", "ad_shown", "ad_rewarded", "ad_closed",
	# 동의(UMP) 상태 — fill률을 읽을 때 반드시 같이 봐야 한다. 동의 미확보는 '재고 없음'이 아니라
	#   '요청 자체를 안 한 것'이라, 이 이벤트가 없으면 낮은 fill률의 원인을 가를 수 없다(R3).
	"ad_consent_updated",
]

var enabled: bool = true          # 하네스·헤드리스에선 _init이 false로 내린다
var event_count: int = 0          # 이번 세션 발화 수(probe 검증용)
var last_event: Dictionary = {}   # 마지막 발화(probe 검증용)

var _rng := RandomNumberGenerator.new()   # 전용 RNG — 게임 스트림과 분리(불변식 ①)
var _session_id: String = ""
var _install_id: String = ""
var _is_first_session: bool = false
var _session_started_ms: int = 0
var _runs_played: int = 0
# 현재 판 좌표(§2 공통 파라미터). 판 밖에선 비어 있다.
var _mode: String = ""
var _run_id: String = ""
var _seed: int = 0
var _run_started_ms: int = 0
var _session_first_line: bool = false   # first_line_cleared는 세션 1회만(TTF쾌감)
# 원격 싱크 상태. _remote_on이 false면 아래 셋은 영영 안 쓰인다.
var _remote_on: bool = false
var _remote_buf: Array = []             # 아직 안 보낸 이벤트
var _remote_sent: Array = []            # 지금 날아가는 중인 배치 — 실패하면 되돌린다
var _remote_http: HTTPRequest = null    # 웹이 아닐 때만 만든다(웹은 sendBeacon)

func _init() -> void:
	_rng.randomize()
	# 헤드리스 = 회귀/시뮬/프로브 하네스. 여기선 계측이 노이즈이자 느림이라 스스로 꺼진다(불변식 ②).
	if DisplayServer.get_name() == "headless":
		enabled = false
	# ⚠창 모드 하네스도 꺼야 한다. 픽셀 검증 프로브(design_shots·art_frames)는 렌더 텍스처 때문에
	#   헤드리스로 못 돌려서 위 조건에 안 걸린다 → 캡처를 뽑을 때마다 가짜 세션이 실측에 섞였다.
	#   `--script`로 뜬 프로세스는 tools/ 하네스뿐이다(출고 빌드엔 이 인자가 없다).
	#   ⚠_init에서 걸러야 한다 — 아래 _load_meta()가 session_count를 올리므로, 노드를 받은 쪽에서
	#     enabled=false를 나중에 꽂아봐야 카운터는 이미 올라가 있다(실제로 그랬다).
	#   ⚠단 하나의 예외 = 계측 프로브 자신. 얘는 계측을 **켜서** 검증하는 게 존재 이유고,
	#     로그·메타·캠페인 세이브를 스스로 치우고 되돌린다(tools/analytics_probe.gd `_run()`).
	#     C118이 이 예외를 빠뜨려서 프로브가 0개 이벤트로 조용히 죽어 있었다 — 게이트를 넣은 커밋이
	#     그 게이트의 검증 장치를 같이 껐고, 통과/실패를 안 보면 안 드러나는 종류의 사고다.
	var args: PackedStringArray = OS.get_cmdline_args()
	if args.has("--script") and not _is_analytics_probe(args):
		enabled = false
	# 원격은 `enabled`보다 한 겹 더 조인다 — **어떤 하네스에서도 절대 안 나간다.**
	#   프로브는 계측이 켜진 채 도니까, 이 조건이 없으면 봇 판이 실제 수집기로 흘러들어
	#   사람 데이터에 섞인다(로컬 JSONL은 프로브가 스스로 지우므로 문제없다).
	_remote_on = enabled and REMOTE_URL != "" and not args.has("--script")
	_load_meta()

func _is_analytics_probe(args: PackedStringArray) -> bool:
	for a in args:
		if a.ends_with("analytics_probe.gd"):
			return true
	return false

# --- 세션 ---

# 앱 진입 1회. Main._ready에서 부른다.
func session_begin() -> void:
	if not enabled:
		return
	_session_id = _new_id()
	_session_started_ms = Time.get_ticks_msec()
	_runs_played = 0
	_session_first_line = false
	log_event("app_opened", {"is_first_session": _is_first_session, "cold_start": true})

# 앱 종료(창 닫기·백그라운드 이탈). 세션 길이·판 수는 여기서만 확정된다.
func session_end() -> void:
	if not enabled or _session_id == "":
		return
	log_event("session_ended", {
		"duration_ms": Time.get_ticks_msec() - _session_started_ms,
		"runs_played": _runs_played,
	})
	_session_id = ""

# --- 판(run) ---

# 한 판 시작. mode = campaign/endless/featured(§2 — 듀얼코어 어느 기둥인지가 가장 중요한 축).
func run_begin(mode: String, seed_val: int, params: Dictionary = {}) -> void:
	if not enabled:
		return
	_mode = mode
	_run_id = _new_id()
	_seed = seed_val
	_run_started_ms = Time.get_ticks_msec()
	_runs_played += 1
	log_event("run_started", params)

# 판 종료 공통 꼬리 — 이 판의 최대 콤보를 남긴다(§3-3 combo_peak).
#   run_failed/stage_cleared/endless_run_ended를 먼저 쏘고 마지막에 부른다.
# ⚠좌표(run_id·mode)는 여기서 안 비운다 — 광고 부활은 '같은 판의 연속'이라, 죽는 순간 좌표를 닫으면
#   부활 뒤에 난 revive_taken·stage_cleared가 판에서 떨어져 나가 퍼널이 끊긴다(계측 프로브가 잡은 결함).
#   다음 판의 run_begin이 좌표를 갈아끼우는 것으로 충분하다. 죽은 뒤 팝업에서 난 이벤트(거절 등)도
#   그 판의 사건이므로 같은 run_id를 다는 게 옳다.
func run_end(max_combo: int) -> void:
	if not enabled or _run_id == "":
		return
	log_event("combo_peak", {"max_combo": max_combo})

# 이번 판 경과(ms) — 종료 이벤트가 duration_ms로 실어 보낸다.
func run_duration_ms() -> int:
	if _run_started_ms == 0:
		return 0
	return Time.get_ticks_msec() - _run_started_ms

# 첫 줄 클리어까지 걸린 시간(세션 1회) — "첫 도파민까지 시간"(§5). 두 번째부터는 조용히 무시.
func first_line_cleared() -> void:
	if not enabled or _session_first_line:
		return
	_session_first_line = true
	log_event("first_line_cleared", {"time_since_open_ms": Time.get_ticks_msec() - _session_started_ms})

# --- 발화 ---

# 이벤트 1건. params에 §2 공통 파라미터를 얹어 싱크로 보낸다.
#   ⚠호출부는 반환값에 의존하지 않는다(불변식 ③ — 관찰자는 게임에 아무것도 안 돌려준다).
func log_event(name: String, params: Dictionary = {}) -> void:
	if not enabled:
		return
	var ev: Dictionary = {
		"event": name,
		"t_ms": Time.get_ticks_msec(),
		"schema": SCHEMA_VERSION,
		"build_version": _build_version(),
		"platform": _platform(),
		"session_id": _session_id,
		"install_id": _install_id,
	}
	if _mode != "":
		ev["mode"] = _mode
		ev["run_id"] = _run_id
		ev["seed"] = _seed
	for k in params:
		ev[String(k)] = params[k]
	if not P0_EVENTS.has(name):
		ev["unknown_event"] = true   # 택소노미 밖 이름 — 리포트가 잡아낸다(오타 방지)
	event_count += 1
	last_event = ev
	_platform_log_event(name, ev)   # 지금 no-op, W2에서 Firebase 중계
	_write_line(ev)

# --- 로컬 백엔드 (지금 유일한 실수집 경로) ---

func _write_line(ev: Dictionary) -> void:
	# 상한 넘으면 새로 시작 — 플테 1세션 분량엔 충분하고, 무한히 커져 기기를 먹지 않게.
	if FileAccess.file_exists(LOG_PATH):
		var probe := FileAccess.open(LOG_PATH, FileAccess.READ)
		if probe != null:
			var too_big: bool = probe.get_length() > LOG_MAX_BYTES
			probe.close()
			if too_big:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(LOG_PATH) \
			else FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(ev))
	f.close()

# 설치 단위 식별자 + 세션 카운트. 손상 내성: 못 읽으면 새로 만든다(C70 세이브 감사 원칙).
func _load_meta() -> void:
	var sessions: int = 0
	if FileAccess.file_exists(META_PATH):
		var f := FileAccess.open(META_PATH, FileAccess.READ)
		if f != null:
			var raw: String = f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				_install_id = String((parsed as Dictionary).get("install_id", ""))
				sessions = int((parsed as Dictionary).get("session_count", 0))
	if _install_id == "":
		_install_id = _new_id()
	_is_first_session = (sessions == 0)
	if enabled:
		_save_meta(sessions + 1)

func _save_meta(sessions: int) -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"install_id": _install_id, "session_count": sessions}))
		f.close()

func _new_id() -> String:
	# 전용 RNG(불변식 ①). 64비트를 16자리 hex로 — 충돌 걱정 없는 단순 id.
	return "%08x%08x" % [_rng.randi(), _rng.randi()]

func _build_version() -> String:
	var v: Variant = ProjectSettings.get_setting("application/config/version", "")
	return String(v) if String(v) != "" else "0.0.0-dev"

func _platform() -> String:
	var n: String = OS.get_name().to_lower()
	if n == "android" or n == "ios":
		return n
	if n == "web":
		return "web"
	return "desktop_" + n

# --- 원격 백엔드 (우리 엔드포인트로 HTTP POST) ---
#
# 전송 경로가 플랫폼마다 다르다:
#   웹    → navigator.sendBeacon. **탭을 닫는 중에도 브라우저가 대신 보내준다**는 게 핵심이다.
#           HTTPRequest로 보내면 언로드 시점에 요청이 끊겨서, 하필 제일 중요한 `session_ended`가
#           가장 자주 유실된다(이탈한 사람의 마지막 이벤트 = 이탈 분석의 본체).
#   그 외  → HTTPRequest. 노드라서 트리에 붙여야 하는데, 트리 루트에 직접 매달아
#           Main.gd를 안 건드린다(게임 코드는 수집 경로를 모른다 — leaderboard·ad_service와 동형).
#
# ⚠앱이 죽는 순간의 마지막 배치는 어느 경로로도 100% 보장되지 않는다. 그래서 배치를 작게 잡고
#   위 REMOTE_FLUSH_ON 자리에서 즉시 비운다. 완전 무손실이 아니라 '이탈 직전까지'가 목표다.

func _platform_available() -> bool:
	return _remote_on

func _platform_log_event(name: String, params: Dictionary) -> void:
	if not _remote_on:
		return
	_remote_buf.append(params)
	# 상한 초과분은 **오래된 것부터** 버린다 — 최근 이벤트가 이탈 지점에 더 가깝다.
	if _remote_buf.size() > REMOTE_MAX_BUFFER:
		_remote_buf = _remote_buf.slice(_remote_buf.size() - REMOTE_MAX_BUFFER)
	var batch: int = REMOTE_BATCH_WEB if OS.has_feature("web") else REMOTE_BATCH
	if _remote_buf.size() >= batch or REMOTE_FLUSH_ON.has(name):
		_remote_flush()

# 버퍼를 한 배치 비운다. 이미 날아가는 게 있으면 그게 끝난 뒤에 다시 불린다(중복 전송 방지).
func _remote_flush() -> void:
	if not _remote_on or _remote_buf.is_empty() or not _remote_sent.is_empty():
		return
	var payload: String = JSON.stringify({
		"schema": SCHEMA_VERSION,
		"install_id": _install_id,
		"events": _remote_buf,
	})
	if OS.has_feature("web"):
		# sendBeacon은 fire-and-forget이라 성패를 알 수 없다 → 되돌릴 게 없으니 버퍼를 바로 비운다.
		#   text/plain으로 보내면 CORS preflight(OPTIONS)가 안 붙는다 — 엔드포인트가 단순해진다.
		_remote_buf = []
		_remote_beacon(payload)
		return
	var http: HTTPRequest = _remote_node()
	if http == null:
		return          # 트리가 아직 없다. 버퍼에 남으니 다음 이벤트에서 다시 시도한다.
	_remote_sent = _remote_buf
	_remote_buf = []
	var err: int = http.request(REMOTE_URL, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, payload)
	if err != OK:
		_remote_requeue()

func _remote_beacon(payload: String) -> void:
	# 실제 플랫폼 게이트는 호출부의 OS.has_feature("web")이고, 여기 있는 건 널 안전장치다.
	#   (JavaScriptBridge 싱글턴 자체는 데스크톱에도 등록돼 있어서 has_singleton으로는 못 가른다 — 실측 확인.)
	var js: Object = Engine.get_singleton("JavaScriptBridge") if Engine.has_singleton("JavaScriptBridge") else null
	if js == null:
		return
	# JSON.stringify로 감싸 자바스크립트 문자열 리터럴을 만든다(따옴표·개행 이스케이프를 직접 안 짠다).
	js.call("eval", "navigator.sendBeacon(%s, new Blob([%s], {type:'text/plain'}))" % [
		JSON.stringify(REMOTE_URL), JSON.stringify(payload)], true)

func _remote_node() -> HTTPRequest:
	if _remote_http != null and is_instance_valid(_remote_http):
		return _remote_http
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	_remote_http = HTTPRequest.new()
	_remote_http.name = "AnalyticsSink"
	_remote_http.timeout = REMOTE_TIMEOUT_S
	_remote_http.request_completed.connect(_on_remote_done)
	root.add_child(_remote_http)
	return _remote_http

func _on_remote_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_remote_sent = []
	else:
		_remote_requeue()      # 네트워크가 끊겼거나 서버가 5xx — 다음 기회에 다시 보낸다
	_remote_flush()            # 그 사이 쌓인 게 있으면 이어서

# 실패한 배치를 버퍼 **앞**에 되돌린다(시간 순서 유지). 상한은 여기서도 지킨다.
func _remote_requeue() -> void:
	if _remote_sent.is_empty():
		return
	_remote_buf = _remote_sent + _remote_buf
	_remote_sent = []
	if _remote_buf.size() > REMOTE_MAX_BUFFER:
		_remote_buf = _remote_buf.slice(_remote_buf.size() - REMOTE_MAX_BUFFER)
