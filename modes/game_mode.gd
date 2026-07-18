extends RefCounted
# 감독(director) 베이스 — 코어(Main.gd)는 스폰·난이도·종료를 이 인터페이스로만 묻는다.
# 기본 구현 = "연속·무승리(endless-shaped)": 미구현 모드도 안 터지고, 미래 EndlessMode가 대부분 상속.
# StageMode가 스테이지 dict로 전부 override한다.
# ctx = Main._director_ctx()가 만드는 Dictionary 스냅샷(런타임 카운터). 감독은 config+결정 로직만.

# ── 설정 접근자 (값 그대로 pass-through) ──
func core_hp_max() -> int:
	return 1

func enemy_total() -> int:
	return -1   # 고정 총량 없음 / 연속

func hud_step_every() -> int:
	return 1

func enemy_hp(_etype: String, _spawn_index: int) -> int:
	return 1

func enemy_step(_etype: String) -> int:
	return 1

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
