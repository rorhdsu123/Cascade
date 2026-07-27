extends RefCounted
# 감독(director) 베이스 — 코어(Main.gd)는 스폰·난이도·종료를 이 인터페이스로만 묻는다.
# 기본 구현 = "연속·무승리(endless-shaped)": 미구현 모드도 안 터지고, 미래 EndlessMode가 대부분 상속.
# StageMode가 스테이지 dict로 전부 override한다.
# ctx = Main._director_ctx()가 만드는 Dictionary 스냅샷(런타임 카운터). 감독은 config+결정 로직만.

# game_rng 기반 Fisher-Yates — Array.shuffle()(전역 RNG)과 동일 소비 패턴(i=size-1..1, randi%(i+1), swap).
# 게임 스트림을 코스메틱에서 분리하려면 shuffle도 game_rng로 돌려야 한다(rng_probe.gd로 동치 실측).
static func rng_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ── 설정 접근자 (값 그대로 pass-through) ──
func core_hp_max() -> int:
	return 1

func enemy_total() -> int:
	return -1   # 고정 총량 없음 / 연속

func hud_step_every() -> int:
	return 1

func enemy_hp(_etype: String, _spawn_index: int, _ctx: Dictionary = {}) -> int:
	return 1

func enemy_step(_etype: String) -> int:
	return 1

# 폭탄 설정 — 베이스는 무해 기본값(StageMode만 st에서 실값). bomb_dmg=1이면 일반 누수와 동일(안전).
func bomb_fuse() -> int:
	return 6

func bomb_dmg() -> int:
	return 1

func bomb_junk() -> int:
	return 0

func bomb_chain() -> bool:
	return false

# DDA(동적 난이도) 허용? 기본 = false(무한꼴: 랭크 공정성). StageMode만 true(캠페인 구제).
func allows_dda() -> bool:
	return false

# 결정적 트랙? true면 코어가 인덱스-주소 조각·스폰(보드 무반응·재추첨 없음)을 쓴다 = '전원 동일 판'.
#   featured만 true. 조각/스폰 draw가 (시드,인덱스)만의 함수라 어떤 플레이 순서든 byte-identical.
func deterministic_track() -> bool:
	return false

# ── 점수(scored 모드만) ──
# 코어는 "내가 무한인가?"(모드 이름)가 아니라 "감독이 점수 모드인가?"(능력)로 HUD·결과를 분기한다.
#   새 모드는 이 셋만 구현하면 코어의 렌더/점수 경로를 안 건드리고 꽂힌다([[gamemode-director-seam]]).
func scores() -> bool:
	return false   # 기본 = 무점수(스테이지꼴). 점수 모드(무한)가 override.

func clear_score(_lines: int) -> int:
	return 0   # 줄 클리어 점수 없음

func kill_score(_combo: int) -> int:
	return 0   # 처치 점수 없음

# 결과 팝업 '재도전'의 종류 — 코어가 모드 이름 대신 이 값으로 분기.
#   "new_run"(연속·무한꼴) / "stage"(스테이지 진행) / "same_seed"(오늘의 판 재도전).
func retry_kind() -> String:
	return "new_run"

# ── 결정 메서드 (ctx 인자) ──
func is_cleared(_ctx: Dictionary) -> bool:
	return false   # 승리 없음(연속)

func is_surge_active(_ctx: Dictionary) -> bool:
	return false

func effective_step_every(base_step: int, _ctx: Dictionary) -> int:
	return base_step

func plan_floor_spawn(_ctx: Dictionary) -> Array:
	return []

func plan_throttled_spawn(_ctx: Dictionary) -> Array:
	return []

# 미래 훅(미구현): func difficulty_bias(_ctx: Dictionary) -> float: return 0.0
