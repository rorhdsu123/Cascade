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
		"thief":
			# 도둑 HP = '회수 창'의 크기다. 낮으면 아무 클리어에나 쓸려 회수가 공짜가 되고(C102 줄서기
			#   이후 실제로 그랬다 — 막혀 선 도둑을 거저 주웠다), 높이면 한 줄로는 못 잡아 좋은 수를 요구한다.
			#   ⚠최소 일격(120)을 넘겨야 레버가 켜진다 — 그 아래는 배수를 뭘 넣든 한방컷이라 무의미.
			#   도망 중 넉백은 위로 밀어 탈출을 돕는다 = 어설픈 한 대의 대가(의도된 결). st14는 5.0×.
			hp = roundi(base * float(st.get("thief_hp_mult", 0.35)))
	return maxi(1, hp)

func enemy_step(etype: String) -> int:
	var base_step: int = int(st["step_every"])
	if etype == "fast":
		return maxi(1, base_step - 1)
	# 도둑 하강 속도 — thief_step>0이면 그 주기로 blitz(막기 어렵게 → 낚아채기가 기본, 게임은 회수-추격). 0=일반.
	if etype == "thief":
		var ts: int = int(st.get("thief_step", 0))
		if ts > 0:
			return maxi(1, ts)
	return base_step

# 폭탄(Defuse): 점화 적의 도화선 = 남은 배치 수(0이 되면 제자리서 터짐). 터짐 = 거점 bomb_dmg 피해(일반 누수 -1보다 큼).
func bomb_fuse() -> int:
	return int(st.get("bomb_fuse", 6))

func bomb_dmg() -> int:
	return int(st.get("bomb_dmg", 2))

# >0이면 폭발이 HP 대신(또는 겸해) 보드에 잡동사니 블록 N개를 쏟는다(dormant, 현재 미사용 — 매몰은 점착 몫).
func bomb_junk() -> int:
	return int(st.get("bomb_junk", 0))

# true면 폭탄이 연쇄 폭발(인접 폭탄 8방 도미노). R3 rung — linchpin 먼저 끊는 새 결정.
func bomb_chain() -> bool:
	return bool(st.get("bomb_chain", false))

# 도둑(Protect): 한 번 훔칠 때 금고 감소량 / 물고 도망칠 때 전진 주기(0=하강과 동일).
func steal_amount() -> int:
	return int(st.get("steal", 1))

func thief_carry_step() -> int:
	return int(st.get("thief_carry_step", 0))

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
		total += int(w.get(t, 0))   # 키 없는 타입(예: 신규 bomb)은 가중치 0 = 무영향(회귀 시드 보존)
	if total <= 0:
		return "basic"
	var r: int = ctx["rng"].randi() % total
	for t in types:
		r -= int(w.get(t, 0))
		if r < 0:
			return t
	return "basic"
