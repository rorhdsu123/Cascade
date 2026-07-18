extends "res://modes/game_mode.gd"
# 무한모드 감독 — 스테이지 dict 없이 깊이(place_count)가 스케줄을 만든다.
# 램프 3구간(SPEC 설계 논의 정본):
#   A. 코지 플래토 (d<D1)  : 전진 3 고정, HP 완만(내내 한방컷 가능), basic+fast만. 서지 없음.
#   B. 물기 시작 (D1≤d<D2) : 서지 주기 등장(간격이 깊이 따라 좁아짐 → 평균 전진 3→2), 로스터 다양화.
#   C. 종말 (d≥D2)         : 전진 2 바닥, HP램프가 주 압력 → 한방컷 깨짐 → 콤보 강제. 여기서 판이 끝난다.
# ⚠전진 레버 하한 2(C47): fast·swarm은 base_step=2라 서지·종말 클램프(maxi(2,·))에 면제 = 2배 점프 봉쇄.
# ⚠randi 순서는 StageMode와 동일(floor=열→타입 / throttle=타입→(swarm:count→shuffle | col)) — 회귀 전제.
# 여기 const는 전부 sim 튜닝 대상(tools/endless_sim.gd).

# ⚠튜닝 파라미터는 var(sim이 인스턴스별로 덮어씀). 확정 후 const로 굳혀도 됨.
var CORE_HP: int = 14            # 닳는 여유 게이지(나이프 아님). sim 스윕 확정: 中 ~64% 거점사·판길이·밴드 절충. 부활이 복구.
var BASE_HP: float = 26.0        # 시작 적 HP(기준). 한방컷 임계 = LINE_BASE 120.
var HP_RAMP: float = 1.1         # 스폰 인덱스당 HP 증가 = 깊이 압력의 주축(C구간에서 콤보 강제).
var TANK_MULT: float = 2.6

var D1: int = 40                 # 코지 플래토 끝(place_count)
var D2: int = 90                 # 종말 진입 = 전진 2 바닥
const SPAWN_EVERY: int = 2       # 스폰 주기(밀도는 비단조라 고정, 레버 아님 — cascade-difficulty)
const ONBOARD: int = 8           # 첫 N스폰 basic만(온보딩)
const FLOOR_N: int = 4           # 밀도 하한(보드에 최소 N마리 유지)

const SURGE_PERIOD_FAR: int = 22 # 서지 간격(D1 근처, 넓음)
const SURGE_PERIOD_NEAR: int = 9 # 서지 간격(D2 이후, 좁음)
const SURGE_LEN: int = 5         # 서지 창 길이(place_count 스텝)

# ── 설정 접근자 ──
func core_hp_max() -> int:
	return CORE_HP

func enemy_total() -> int:
	return -1

func hud_step_every() -> int:
	return 3   # 기준 전진(A·B구간의 base). 깊이·서지 가속은 effective_step_every가 소유.

func enemy_hp(etype: String, spawn_index: int) -> int:
	var base: int = roundi(BASE_HP + float(spawn_index) * HP_RAMP)
	var hp: int = base
	match etype:
		"fast":
			hp = roundi(base * 0.6)
		"tank":
			hp = roundi(base * TANK_MULT)
		"swarm":
			hp = roundi(base * 0.45)
	return maxi(1, hp)

func enemy_step(etype: String) -> int:
	return 2 if etype == "fast" else 3   # fast만 base 2(=면제 대상). 나머지 3.

# ── 결정 메서드 ──
func is_cleared(_ctx: Dictionary) -> bool:
	return false

func is_surge_active(ctx: Dictionary) -> bool:
	if not bool(ctx.get("surge_enabled", true)):
		return false
	var d: int = int(ctx["place_count"])
	if d < D1:
		return false   # 코지 플래토: 서지 없음
	# 서지 간격이 D1→D2 사이에서 FAR→NEAR로 선형 수축(들숨/날숨이 점점 빨라짐)
	var t: float = clampf(float(d - D1) / float(maxi(1, D2 - D1)), 0.0, 1.0)
	var period: int = maxi(SURGE_LEN + 1, roundi(lerp(float(SURGE_PERIOD_FAR), float(SURGE_PERIOD_NEAR), t)))
	return (d % period) < SURGE_LEN

func effective_step_every(base_step: int, ctx: Dictionary) -> int:
	# 종말(d≥D2)이거나 서지 창이면 한 단계 빨리(하한 2). fast·swarm(base 2)은 자동 면제.
	var d: int = int(ctx["place_count"])
	if d >= D2 or bool(ctx.get("surge_active", false)):
		return maxi(2, base_step - 1)
	return base_step

func plan_floor_spawn(ctx: Dictionary) -> Array:
	if not bool(ctx["floor_enabled"]):
		return []
	if int(ctx["enemy_count"]) < FLOOR_N:
		var col: int = randi() % int(ctx["cols"])   # 열 먼저(원본 인자 평가 순서)
		var et: String = pick_etype(ctx)
		return [{"col": col, "etype": et, "step_override": 0}]
	return []

func plan_throttled_spawn(ctx: Dictionary) -> Array:
	if int(ctx["place_count"]) % SPAWN_EVERY != 0:
		return []
	var cols: int = int(ctx["cols"])
	var etype: String = "basic" if int(ctx["spawned"]) < ONBOARD else pick_etype(ctx)
	if etype == "swarm":
		var count: int = mini(3 + (randi() % 2), cols)
		var pool: Array = []
		for c in range(cols):
			pool.append(c)
		pool.shuffle()
		var specs: Array = []
		for k in range(count):
			var sstep: int = 2 if k % 2 == 0 else 3   # 무리 내 desync(짝수만 빠름)
			specs.append({"col": int(pool[k]), "etype": "swarm", "step_override": sstep})
		return specs
	return [{"col": randi() % cols, "etype": etype, "step_override": 0}]

func pick_etype(ctx: Dictionary) -> String:
	var w: Dictionary = _weights(int(ctx["place_count"]))
	var types: Array = ctx["enemy_types"]
	var total: int = 0
	for t in types:
		total += int(w.get(t, 0))
	if total <= 0:
		return "basic"
	var r: int = randi() % total
	for t in types:
		r -= int(w.get(t, 0))
		if r < 0:
			return t
	return "basic"

func _weights(d: int) -> Dictionary:
	if d < D1:
		return {"basic": 65, "fast": 35, "tank": 0, "swarm": 0}    # 코지: basic+온건한 fast
	if d < D2:
		return {"basic": 35, "fast": 35, "tank": 10, "swarm": 20}  # 다양화
	return {"basic": 20, "fast": 35, "tank": 25, "swarm": 20}      # 풀 믹스
