extends RefCounted

# 무한 리더보드 이음새 (기획: 메모리 endless-leaderboard-design).
# 게임 코드(Main.gd)는 user:// 파일이나 플랫폼 API를 직접 만지지 않고 이 서비스로만
# 점수를 넣고(submit) 뺀다(best/board/percentile). 감독 이음새(gamemode-director-seam)·game_rng
# 분리와 같은 발상: 나중에 Play Games / Game Center를 붙일 때 _platform_* stub만 채우면
# 게임 코드·리더보드 화면(_draw_leaderboard)은 안 건드린다.
#
# ⚠지금은 로컬 백엔드만 살아 있다. 최고점·무부활 최고점은 진짜(로컬 영속)지만,
#   친구 보드·퍼센타일은 플랫폼 연결 전까지 '미리보기 데이터'다(has_platform()==false).
#   화면은 이 서비스가 주는 값만 그리므로, 모바일 배관 때 _platform_* 를 실값으로 바꾸면
#   미리보기가 그대로 실데이터로 승격된다(godot-pixel-verify-needs-window = 실배선은 모바일 때).

const SAVE_PATH: String = "user://endless.save"          # 최고점(raw int32) — 기존 포맷 유지, 마이그레이션·회귀 영향 0
const CLEAN_PATH: String = "user://endless_clean.save"   # 무부활 최고점(raw int32) — 별도 파일이라 기존 세이브 무영향

# 미리보기 친구 보드(플랫폼 연결 전). 코지 톤의 이름·현실적 점수 분포 — 내 최고점이 사이 어딘가에 꽂힌다.
#   실플랫폼 붙으면 _platform_board()가 이 자리를 대체.
const MOCK_FRIENDS: Array = [
	{"name": "하린", "score": 214600},
	{"name": "도윤", "score": 152300},
	{"name": "서준", "score": 96800},
	{"name": "예은", "score": 61400},
	{"name": "민서", "score": 33900},
]

var _best: int = 0
var _clean_best: int = 0   # 부활(광고 이어하기) 없이 끝낸 판의 최고 — '딱 한 판 실력'(콜드리드) 개인기록

func _init() -> void:
	_load()

# 로컬 베스트 조회. 게임 HUD/메뉴/결과 팝업은 이 값을 캐시로 미러링해 읽는다.
func best() -> int:
	return _best

# 무부활 최고점 — 개인기록/배지로만(기획: 별도 보드 X). 부활 점수는 메인 보드엔 인정하되,
#   이 값은 '광고로 안 산 점수'라 순수 실력을 살짝 신호.
func clean_best() -> int:
	return _clean_best

# 점수 제출 — 자동·무마찰(기획: 판 종료 시 자동). 부활 점수도 메인 보드에 인정(별도 표식/제외 없음).
#   revived=false(부활 안 씀)면 무부활 최고점도 함께 갱신. 신기록이면 true.
func submit(score: int, revived: bool = false) -> bool:
	_platform_submit(score)      # 지금 no-op, 모바일 때 Play Games/Game Center
	if not revived and score > _clean_best:
		_clean_best = score
		_save_clean()
	if score > _best:
		_best = score
		_save()
		return true
	return false

# --- 화면이 읽는 두꺼운 데이터 (지금은 로컬 미리보기, 모바일 때 플랫폼 실값) ---

# 실플랫폼(친구 보드·퍼센타일)이 붙었나. 화면은 false면 '미리보기' 주석을 단다(정직).
func has_platform() -> bool:
	return _platform_available()

# 친구 우선 보드 — 내 점수를 친구들 사이에 꽂아 내림차순 정렬. 각 행: {name, score, you}.
#   기획: 글로벌 절대순위는 안 보여줌(도달불가·압박) → 친구 보드만, 글로벌은 percentile()로.
func board() -> Array:
	if _platform_available():
		return _platform_board()
	var rows: Array = []
	for f in MOCK_FRIENDS:
		rows.append({"name": String(f["name"]), "score": int(f["score"]), "you": false})
	rows.append({"name": "나", "score": _best, "you": true})
	rows.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	return rows

# 친구 보드에서 내 순위/총원 — "6명 중 3위"용.
func friend_rank() -> Dictionary:
	var rows: Array = board()
	for i in range(rows.size()):
		if bool(rows[i]["you"]):
			return {"rank": i + 1, "total": rows.size()}
	return {"rank": rows.size(), "total": rows.size()}

# 글로벌 퍼센타일(상위 X%) — 절대순위 대신. 랜덤 시드 운 편차를 뭉개는 대표 지표(기획).
#   기록 없으면 0(화면이 빈 상태 문구로 분기). 지금은 최고점의 단조 함수인 미리보기 값.
func percentile() -> int:
	if _best <= 0:
		return 0
	if _platform_available():
		return _platform_percentile()
	return clampi(52 - int(_best / 5000.0), 2, 99)   # 미리보기: 점수 오를수록 상위로

# --- 로컬 백엔드 (지금, 데스크톱 검증 가능) ---
func _load() -> void:
	_best = _read_i32(SAVE_PATH)
	_clean_best = _read_i32(CLEAN_PATH)

func _read_i32(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	# 4바이트 미만 = 부분쓰기 손상(강제종료 등) → 기본값 0 유지(C70 세이브 감사 가드, Main에서 이관).
	var v: int = f.get_32() if f.get_length() >= 4 else 0
	f.close()
	return v

func _save() -> void:
	_write_i32(SAVE_PATH, _best)

func _save_clean() -> void:
	_write_i32(CLEAN_PATH, _clean_best)

func _write_i32(path: String, v: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_32(v)
		f.close()

# --- 플랫폼 백엔드 (stub — 모바일 배관 단계에서 채움) ---
# TODO(모바일): Play Games / Game Center 로그인·리더보드 제출·친구 보드·퍼센타일 조회.
func _platform_available() -> bool:
	return false

func _platform_submit(_score: int) -> void:
	pass

func _platform_board() -> Array:
	return []

func _platform_percentile() -> int:
	return 0
