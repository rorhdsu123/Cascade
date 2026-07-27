extends RefCounted

# 애널리틱스 이음새 (Phase V W1 ④ — 설계 정본은 ANALYTICS_TAXONOMY.md).
# 게임 코드(Main.gd)는 SDK나 user:// 파일을 직접 만지지 않고 이 서비스로만 이벤트를 흘린다.
# leaderboard.gd와 같은 발상: 나중에 Firebase Analytics를 붙일 때 _platform_* stub만 채우면
# 게임 코드는 안 건드린다(gamemode-director-seam과 동형).
#
# ⚠지금 백엔드는 로컬 JSONL(`user://analytics.jsonl`)뿐이다 — 이게 W1 사람 플테의 실제 수집 경로다.
#   실기기서 판이 끝나면 파일을 뽑아 `tools/analytics_report.gd`로 읽는다. Firebase(W2)가 붙으면
#   _platform_log_event가 같은 이벤트를 그대로 중계하고 JSONL은 로컬 백업으로 남는다.
#
# 불변식 3개(깨면 회귀·결정성이 무너진다):
#   ① 게임 RNG를 절대 안 쓴다 — id는 전용 RandomNumberGenerator(_rng)로만 뽑는다. randi()/game_rng 금지.
#   ② 헤드리스(regress·sim·probe)에선 스스로 꺼진다 — 하네스가 파일을 더럽히거나 느려지지 않게.
#   ③ 발화는 상태를 안 바꾼다 — 어떤 이벤트도 게임 값을 되돌려주지 않는다(read-only 관찰자).

const LOG_PATH: String = "user://analytics.jsonl"     # 이벤트 1줄 = JSON 1개(append-only)
const META_PATH: String = "user://analytics.meta"     # {install_id, session_count} — is_first_session 판정용
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

func _init() -> void:
	_rng.randomize()
	# 헤드리스 = 회귀/시뮬/프로브 하네스. 여기선 계측이 노이즈이자 느림이라 스스로 꺼진다(불변식 ②).
	if DisplayServer.get_name() == "headless":
		enabled = false
	_load_meta()

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

# --- 플랫폼 백엔드 (stub — W2 광고·Firebase 배선 단계에서 채움) ---
# TODO(W2): Firebase Analytics 중계. 안드로이드 플러그인 붙이면 여기서 log_event 호출만 하면 된다.
#   파라미터 상한(이벤트당 25개)·custom dimension 등록(mode/cause/stage_id/band)은 §6 참조.
func _platform_available() -> bool:
	return false

func _platform_log_event(_name: String, _params: Dictionary) -> void:
	pass
