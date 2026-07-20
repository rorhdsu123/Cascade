extends RefCounted

# 무한 리더보드 이음새 (기획: 메모리 endless-leaderboard-design).
# 게임 코드(Main.gd)는 user:// 파일이나 플랫폼 API를 직접 만지지 않고 이 서비스로만
# 점수를 넣고(submit) 뺀다(best). 감독 이음새(gamemode-director-seam)·game_rng 분리와 같은 발상:
# 나중에 Play Games / Game Center를 붙일 때 _platform_* stub만 채우면 게임 코드는 안 건드린다.
#
# ⚠지금은 '얇게' = 로컬 백엔드만 살아 있고 플랫폼은 no-op stub. top-N·친구 비교·퍼센타일·
#   '첫 시도 점수' UI는 기획엔 있으나 여기 미포함 — 데이터 경로만 이 인터페이스 뒤로 모은 상태.
#   플랫폼 SDK 실배선은 데스크톱 worktree에서 검증 불가(godot-pixel-verify-needs-window) = 모바일 배관 때.

const SAVE_PATH: String = "user://endless.save"   # 기존 포맷 유지(raw int32) — 마이그레이션·회귀 영향 0

var _best: int = 0

func _init() -> void:
	_load()

# 로컬 베스트 조회. 게임 HUD/메뉴/결과 팝업은 이 값을 캐시로 미러링해 읽는다.
func best() -> int:
	return _best

# 점수 제출 — 자동·무마찰(기획: 판 종료 시 자동). 부활 점수도 인정(별도 표식/제외 없음).
# 로컬 베스트 갱신 + 플랫폼에 통지. 신기록이면 true.
func submit(score: int) -> bool:
	_platform_submit(score)      # 지금 no-op, 모바일 때 Play Games/Game Center
	if score > _best:
		_best = score
		_save()
		return true
	return false

# --- 로컬 백엔드 (지금, 데스크톱 검증 가능) ---
func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		_best = f.get_32()
		f.close()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_32(_best)
		f.close()

# --- 플랫폼 백엔드 (stub — 모바일 배관 단계에서 채움) ---
# TODO(모바일): Play Games / Game Center 로그인·리더보드 제출·친구 보드·퍼센타일 조회.
func _platform_available() -> bool:
	return false

func _platform_submit(_score: int) -> void:
	pass
