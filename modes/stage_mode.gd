extends "res://modes/game_mode.gd"
# 스테이지 모드 감독 — STAGES[idx] dict 1개를 래핑, 기존 Main 스테이지 로직을 그대로 재현.
# ⚠randi 호출 순서·횟수를 원본과 정확히 일치시킬 것(시드 byte-identical 회귀의 전제):
#   - floor 스폰: 열(randi%cols) 먼저, 그다음 pick_etype
#   - throttled: (basic이 아니면) pick_etype 먼저, swarm이면 count(randi%2)→shuffle, 아니면 col(randi%cols)
#   - pick_etype: 정확히 randi 1회

var st: Dictionary

func _init(stage: Dictionary) -> void:
	st = stage

# ── 설정 접근자 ──
func core_hp_max() -> int:
	return int(st["core_hp"])

func enemy_total() -> int:
	return int(st["total"])

func hud_step_every() -> int:
	return int(st["step_every"])

func enemy_hp(etype: String, spawn_index: int, _ctx: Dictionary = {}) -> int:
	var base: int = roundi(float(st["base_hp"]) + float(spawn_index) * float(st["hp_ramp"]))
	var hp: int = base
	match etype:
		"fast":
			hp = roundi(base * 0.6)
		"tank":
			hp = roundi(base * float(st["tank_mult"]))
		"swarm":
			hp = roundi(base * 0.4)
	return maxi(1, hp)

func enemy_step(etype: String) -> int:
	var base_step: int = int(st["step_every"])
	return maxi(1, base_step - 1) if etype == "fast" else base_step

# 재도전 = 같은/다음 스테이지(코어가 game_clear로 분기). scores()/*_score는 base 상속(무점수).
func retry_kind() -> String:
	return "stage"

func allows_dda() -> bool:
	return true   # 캠페인만 DDA 구제(무한·featured는 base 상속 false)

# ── 결정 메서드 ──
func is_cleared(ctx: Dictionary) -> bool:
	# 받기형 수집: 타입별 quota(collect_targets)를 전부 채우면 승리(웨이브 소탕과 무관 — 적은 순수 위협).
	if bool(st.get("collect", false)):
		var cbt: Array = ctx.get("collected_by_type", [])
		var tgts: Array = st.get("collect_targets", [])
		for i in range(tgts.size()):
			if i >= cbt.size() or int(cbt[i]) < int(tgts[i]):
				return false
		return true
	# 보스(감시자) 스테이지: 잔해를 지워 boss_hp를 0으로 만들면 승리(웨이브 소탕 대신).
	if bool(st.get("boss", false)):
		return int(ctx.get("boss_hp", 1)) <= 0
	return int(ctx["killed"]) + int(ctx["leaked"]) >= int(st["total"])

func is_surge_active(ctx: Dictionary) -> bool:
	if not bool(ctx["surge_enabled"]):
		return false
	var surge_at: float = float(st.get("surge_at", 0.0))
	return surge_at > 0.0 and float(ctx["spawned"]) >= surge_at * float(int(st["total"]))

func effective_step_every(base_step: int, ctx: Dictionary) -> int:
	# surge_active는 Main이 스텝당 1회 계산해 ctx에 넣어준다(렌더 필드와 공유).
	if bool(ctx.get("surge_active", false)):
		return maxi(2, base_step - 1)   # 서지: 한 단계 빨리(하한 2)
	return base_step

func plan_floor_spawn(ctx: Dictionary) -> Array:
	if not bool(ctx["floor_enabled"]):
		return []
	var floor_n: int = int(st.get("floor", 0))
	if floor_n > 0 and int(ctx["enemy_count"]) < floor_n and int(ctx["spawned"]) < int(st["total"]):
		var col: int = ctx["rng"].randi() % int(ctx["cols"])   # 열 먼저(원본 인자 평가 순서)
		var et: String = pick_etype(ctx)
		return [{"col": col, "etype": et, "step_override": 0}]
	return []

func plan_throttled_spawn(ctx: Dictionary) -> Array:
	var total: int = int(st["total"])
	if int(ctx["place_count"]) % int(st["spawn_every"]) != 0:
		return []
	if int(ctx["spawned"]) >= total:
		return []
	var cols: int = int(ctx["cols"])
	var etype: String = "basic" if int(ctx["spawned"]) < int(st["onboard"]) else pick_etype(ctx)
	if etype == "swarm":
		var count: int = 3 + (ctx["rng"].randi() % 2)
		count = mini(count, total - int(ctx["spawned"]))
		count = mini(count, cols)
		var pool: Array = []
		for c in range(cols):
			pool.append(c)
		rng_shuffle(pool, ctx["rng"])
		var base_step: int = int(st["step_every"])
		var specs: Array = []
		for k in range(count):
			var sstep: int = maxi(1, base_step - 1) if k % 2 == 0 else base_step
			specs.append({"col": int(pool[k]), "etype": "swarm", "step_override": sstep})
		return specs
	return [{"col": ctx["rng"].randi() % cols, "etype": etype, "step_override": 0}]

func pick_etype(ctx: Dictionary) -> String:
	var types: Array = ctx["enemy_types"]
	var w: Dictionary = st["weights"]
	var total: int = 0
	for t in types:
		total += int(w[t])
	if total <= 0:
		return "basic"
	var r: int = ctx["rng"].randi() % total
	for t in types:
		r -= int(w[t])
		if r < 0:
			return t
	return "basic"
