extends Node2D

# ===== 상수 =====
const COLS: int = 6
const ROWS: int = 6             # 6×6 정사각 보드 (조준해 잡기 좋게 좁힘)
const CELL: int = 86            # 셀 크기(픽셀) → 보드 516×516
const BOARD_X: int = 142        # (800 - COLS*CELL)/2
const BOARD_Y: int = 150        # 보드 상단 y (보드 150~666)
const BOT_Y: int = 700          # 하단 패널 상단 (거점 띠 670~696 아래, 트레이 700~1000)
const CORE_HP_MAX: int = 25
const BASE_HP: int = 28
const HP_RAMP: float = 2.0
const TOTAL_ENEMIES: int = 28

# 적 타입 (basic/fast/tank/swarm) — 스폰 가중치·온보딩
const ENEMY_TYPES: Array = ["basic", "fast", "tank", "swarm"]
const SPAWN_WEIGHTS: Dictionary = {"basic": 45, "fast": 20, "tank": 15, "swarm": 20}
const ONBOARD_COUNT: int = 8    # 이 수까지 basic만 스폰(온보딩)
const ENEMY_STEP_EVERY: int = 2 # 일반 적 전진 스로틀(2배치당 1칸). fast는 1
const SPAWN_EVERY: int = 2       # 스폰 스로틀(2배치당 1회)
const SWEEP_DUR: float = 0.35   # 폭발 스윕 밴드 지속
const ROCKET_DUR: float = 0.16  # 로켓 비행 지속(빠르게 질주)
const CALLOUT_DUR: float = 1.6  # 첫 등장 콜아웃 배너 지속

# 라인클리어 폭발
const LINE_BASE: int = 120
const STREAK_STEP: float = 0.5
const FLASH_DUR: float = 0.7
const LINE_FLASH_DUR: float = 0.45

# 조각 색 키 (시각용만)
const COLORS: Array = ["R", "B", "Y"]

# 트레이 UI
const TRAY_SLOT_W: int = 120
const TRAY_SLOT_H: int = 100
const TRAY_SLOT_GAP: int = 20
const TRAY_PREVIEW_CELL: int = 20

# 레전빌리티 연출
const RED_FLASH_DUR: float = 0.35
const SHAKE_DUR: float = 0.28
const SHAKE_AMP: float = 9.0
const FLOAT_DUR: float = 0.6

# 색상
const C_RED  := Color("#e5484d")
const C_BLUE := Color("#3b82f6")
const C_YELL := Color("#eab308")
const C_BG   := Color("#0d0d1a")
const C_CELL := Color("#111122")
const C_GRID := Color(0.28, 0.28, 0.38, 0.55)
const C_HUD  := Color(0.06, 0.06, 0.12)
const C_GOLD := Color("#ffd700")
const C_BORD := Color(0.24, 0.24, 0.38)

# 적 타입별 대표 색 (한눈 구분)
const C_E_BASIC := Color("#e5484d")   # 빨강
const C_E_FAST  := Color("#22d3ee")   # 시안
const C_E_TANK  := Color("#7a1f3d")   # 어두운 마룬
const C_E_SWARM := Color("#a3e635")   # 라임

# 조각 오프셋 (Vector2i, 원점=(0,0) 기준 정규화)
const PIECES: Dictionary = {
	# --- SMALL 풀: 단일·도미노·트로미노·2×2 ---
	"1":   [Vector2i(0, 0)],
	"D2h": [Vector2i(0, 0), Vector2i(1, 0)],
	"D2v": [Vector2i(0, 0), Vector2i(0, 1)],
	"I3h": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"I3v": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
	"L3a": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
	"L3b": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)],
	"L3c": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"L3d": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"O":   [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	# --- BIG 풀: 테트로미노 ---
	"I":   [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"Iv":  [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
	"T":   [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"S":   [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"Z":   [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	"L":   [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)],
	"J":   [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)],
}

# 티어별 shape id 풀 (초반 SMALL 편향 가중 랜덤용)
const SMALL_POOL: Array = ["1", "D2h", "D2v", "I3h", "I3v", "L3a", "L3b", "L3c", "L3d", "O"]
const BIG_POOL: Array = ["I", "Iv", "T", "S", "Z", "L", "J"]

# ===== 상태 =====
var board: Array = []
var enemies: Array = []
var core_hp: int = CORE_HP_MAX
var place_count: int = 0        # 지금까지 배치 횟수(전진·스폰 스로틀 기준)
var spawned: int = 0
var killed: int = 0
var score: int = 0
var combo: int = 0
var game_over: bool = false
var game_clear: bool = false
var stuck: bool = false

# 3조각 트레이: 슬롯 = { "type", "color", "offsets" }, 빈 슬롯 = {}
var tray: Array[Dictionary] = [{}, {}, {}]
var sel: int = 0               # 현재 선택 슬롯

var hover_col: int = 0
var hover_row: int = 0

# 연출 타이머
var flash_timer: float = 0.0
var flash_label: String = ""
var flash_lines: int = 0
var flash_combo: int = 0
var line_flash_rows: Array = []
var line_flash_cols: Array = []
var line_flash_timer: float = 0.0

var floaters: Array = []
var death_flashes: Array = []  # [{pos, life, max, color}] 사망 스케일 팝+플래시
var debris: Array = []         # [{pos, vel, life, max, color, size}] 사망 파편 버스트
var impacts: Array = []        # [{pos, life, max, color, radius}] 빔 임팩트/탱크 막음 링
var kill_pulse: float = 0.0    # 킬 순간 ENEMIES LEFT 헤드라인 펄스
var push_streaks: Array = []   # [{from, to, life, max}] 넉백 잔상
var sweep_timer: float = 0.0   # 폭발 스윕 밴드
var rockets: Array = []        # [{dir, idx, t, dur, combo, ended}] 라인 따라 질주하는 로켓
var hitstop: float = 0.0       # 명중 순간 순간 멈칫(게임 타이머 전부 정지)
var core_hits: Array = []      # [{col, life}] 거점 피격 충격 플래시
var callout_text: String = ""  # 첫 등장 콜아웃 배너
var callout_timer: float = 0.0
var seen_types: Dictionary = {}  # etype -> 이미 콜아웃 봤나
var anim_t: float = 0.0        # 깜빡임 등 연출용 누적 시간
var red_flash: float = 0.0
var shake_timer: float = 0.0

# 전투 순차 연출(resolve) — 배치→전진→클리어→빔→넉백→거점을 짧게 순서대로 재생
var resolving: bool = false
var resolve_timer: float = 0.0
var resolve_total: float = 0.0
var resolve_hits: Array = []       # [{id, dmg, kb, at, done}] 거점 가까운 순 순차 피격
var resolve_rocket_plan: Array = []  # [{dir, idx}] 로켓은 충전 뒤에 발사
var resolve_fx_done: bool = false    # 로켓 발사 트리거됐나
var resolve_leak_at: float = 0.0
var resolve_leak_done: bool = false
var pending_leaks: Array = []      # 이번 스텝 누수 열 목록(블라스트 뒤 표시)
var pending_core_dead: bool = false
var enemy_seq: int = 0             # 적 고유 id 카운터

# ===== 초기화 =====
func _ready() -> void:
	randomize()
	_init_game()

func _init_game() -> void:
	board = []
	for _r in range(ROWS):
		var row_arr: Array = []
		for _c in range(COLS):
			row_arr.append("")
		board.append(row_arr)
	enemies = []
	core_hp = CORE_HP_MAX
	place_count = 0
	spawned = 0
	killed = 0
	score = 0
	combo = 0
	game_over = false
	game_clear = false
	stuck = false
	flash_timer = 0.0
	flash_label = ""
	flash_lines = 0
	flash_combo = 0
	line_flash_rows = []
	line_flash_cols = []
	line_flash_timer = 0.0
	floaters = []
	death_flashes = []
	debris = []
	impacts = []
	kill_pulse = 0.0
	push_streaks = []
	sweep_timer = 0.0
	rockets = []
	hitstop = 0.0
	core_hits = []
	callout_text = ""
	callout_timer = 0.0
	seen_types = {}
	anim_t = 0.0
	red_flash = 0.0
	shake_timer = 0.0
	resolving = false
	resolve_timer = 0.0
	resolve_total = 0.0
	resolve_hits = []
	resolve_rocket_plan = []
	resolve_fx_done = false
	resolve_leak_at = 0.0
	resolve_leak_done = false
	pending_leaks = []
	pending_core_dead = false
	enemy_seq = 0
	tray = [{}, {}, {}]
	sel = 0
	_refill_tray()
	if not _has_valid_placement():
		game_over = true
		stuck = true

# 진행도 가중 랜덤 조각 1개 생성 (초반 SMALL 편향, 후반 BIG 비중↑)
func _make_piece() -> Dictionary:
	var p: float = clampf(float(spawned) / float(TOTAL_ENEMIES), 0.0, 1.0)
	var big_chance: float = lerp(0.12, 0.5, p)
	var pool: Array = BIG_POOL if randf() < big_chance else SMALL_POOL
	var t: String = pool[randi() % pool.size()]
	var c: String = COLORS[randi() % COLORS.size()]
	return {"type": t, "color": c, "offsets": (PIECES[t] as Array).duplicate()}

# 3슬롯 전부 새 랜덤 조각으로 채움, sel=0 리셋
func _refill_tray() -> void:
	for i in range(3):
		tray[i] = _make_piece()
	sel = 0

# 현재 선택 슬롯 반환. 빈 슬롯이면 {} 반환 — .is_empty()로 판별
func _active() -> Dictionary:
	if sel >= 0 and sel < tray.size():
		return tray[sel]
	return {}

# 트레이 슬롯 화면 영역
func _tray_slot_rect(i: int) -> Rect2:
	var total_w: float = float(3 * TRAY_SLOT_W + 2 * TRAY_SLOT_GAP)
	var start_x: float = (800.0 - total_w) * 0.5
	var sx: float = start_x + float(i) * float(TRAY_SLOT_W + TRAY_SLOT_GAP)
	return Rect2(sx, float(BOT_Y) + 15.0, float(TRAY_SLOT_W), float(TRAY_SLOT_H))

# ===== 유틸 =====
func _color_of(key: String) -> Color:
	match key:
		"R":
			return C_RED
		"B":
			return C_BLUE
		"Y":
			return C_YELL
	return Color.WHITE

# 선택 슬롯 offsets을 hover 앵커 기준으로 변환 (빈 슬롯이면 빈 배열)
func _ghost_cells() -> Array:
	var active: Dictionary = _active()
	if active.is_empty():
		return []
	var out: Array = []
	for o in active["offsets"]:
		var ov: Vector2i = o as Vector2i
		out.append(Vector2i(hover_col + ov.x, hover_row + ov.y))
	return out

func _cell_center(col: int, row: int) -> Vector2:
	return Vector2(BOARD_X + col * CELL + CELL * 0.5, BOARD_Y + row * CELL + CELL * 0.5)

func _add_floater(pos: Vector2, text: String, color: Color, life: float, size: int = 22, pop: bool = false) -> void:
	floaters.append({"pos": pos, "text": text, "color": color, "life": life, "max": life, "size": size, "pop": pop})

func _draw_text_outlined(fnt: Font, pos: Vector2, text: String, size: int, fill: Color, outline: Color = Color(0.0, 0.0, 0.0, 0.9)) -> void:
	var offs: Array = [
		Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2),
		Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2),
	]
	var o_col: Color = outline
	o_col.a = outline.a * fill.a
	for off in offs:
		draw_string(fnt, pos + (off as Vector2), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, o_col)
	draw_string(fnt, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)

func _can_place(cells: Array) -> bool:
	for ci in cells:
		var c: Vector2i = ci as Vector2i
		if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= ROWS:
			return false
		if board[c.y][c.x] != "":
			return false
	return true

# 주어진 조각 offsets을 어떤 앵커에든 놓을 수 있으면 true
func _piece_placeable(offsets: Array) -> bool:
	for anchor_r in range(ROWS):
		for anchor_c in range(COLS):
			var cells: Array = []
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				cells.append(Vector2i(anchor_c + ov.x, anchor_r + ov.y))
			if _can_place(cells):
				return true
	return false

# 트레이의 non-empty 조각 중 하나라도 어딘가 놓을 수 있으면 true
func _has_valid_placement() -> bool:
	for i in range(tray.size()):
		if tray[i].is_empty():
			continue
		if _piece_placeable(tray[i]["offsets"]):
			return true
	return false

# ===== 라인클리어 폭발 =====
func _simul_mult(l: int) -> float:
	match l:
		1:
			return 1.0
		2:
			return 2.5
		3:
			return 4.5
		4:
			return 7.0
	return 7.0 + float(l - 4) * 3.0

func _streak_mult(streak: int) -> float:
	return 1.0 + STREAK_STEP * float(streak - 1)

func _line_label(l: int) -> String:
	match l:
		2:
			return "DOUBLE!"
		3:
			return "TRIPLE!"
		4:
			return "TETRIS!"
	if l >= 5:
		return "MEGA!"
	return ""

func _full_rows() -> Array:
	var out: Array = []
	for r in range(ROWS):
		var full: bool = true
		for c in range(COLS):
			if board[r][c] == "":
				full = false
				break
		if full:
			out.append(r)
	return out

func _full_cols() -> Array:
	var out: Array = []
	for c in range(COLS):
		var full: bool = true
		for r in range(ROWS):
			if board[r][c] == "":
				full = false
				break
		if full:
			out.append(c)
	return out

# ===== 전투 순차 연출(resolve) =====
# 로직 결과(HP감소·사망·넉백·score·killed)는 hit가 재생되는 그 시점에 반영.
# 시퀀스: ① 충전 플래시 → ② 로켓 발사(라인) → ③ 순차 피격 → ④ 폭탄(교차 3×3) → (끝물) 누수.
# Match-3 특수사탕식: 로켓=완성 라인 관통, 폭탄=가로·세로 교차 시 3×3 추가.

# 클리어(rows/cols) 결과를 미리 계획해 resolve 큐에 적재하고 시작
func _begin_resolve(rows: Array, cols: Array) -> void:
	resolving = true
	resolve_timer = 0.0
	resolve_hits = []
	resolve_rocket_plan = []
	resolve_fx_done = false
	resolve_leak_done = false

	var blast_len: float = 0.15
	var l: int = rows.size() + cols.size()
	if l > 0:
		# ① 충전 플래시
		line_flash_rows = rows.duplicate()
		line_flash_cols = cols.duplicate()
		line_flash_timer = LINE_FLASH_DUR
		# ② 로켓 계획 (0.08s 뒤 발사): 완성 세로줄=아래→위, 가로줄=좌→우
		for c in cols:
			resolve_rocket_plan.append({"dir": "col", "idx": c})
		for r in rows:
			resolve_rocket_plan.append({"dir": "row", "idx": r})
		# 일격량
		var mult: float = _simul_mult(l) * _streak_mult(combo)
		var strike: int = roundi(LINE_BASE * mult)
		var kb: int = clampi(1 + int(combo / 3), 1, 3)
		# ③ 로켓 피격: 완성 줄이 지나는 적별 (교차=배수), 거점 가까운 순(row 큰 순)
		var hit_list: Array = []
		for e in enemies:
			var lines: int = 0
			for c in cols:
				if e["col"] == c:
					lines += 1
			for r in rows:
				if e["row"] == r:
					lines += 1
			if lines > 0:
				hit_list.append({"id": e["id"], "row": e["row"], "dmg": strike * lines, "kb": kb})
		hit_list.sort_custom(func(a, b): return a["row"] > b["row"])
		var t0: float = 0.22
		for k in range(hit_list.size()):
			resolve_hits.append({
				"id": hit_list[k]["id"], "dmg": hit_list[k]["dmg"], "kb": hit_list[k]["kb"],
				"at": t0 + float(k) * 0.04, "done": false,
			})
		blast_len = clampf(0.30 + 0.04 * float(hit_list.size()), 0.30, 0.9)
		# 완성 줄 셀 제거
		for row in rows:
			for c in range(COLS):
				board[row][c] = ""
		for col in cols:
			for r in range(ROWS):
				board[r][col] = ""
		# COMBO xN 라벨용 (중앙 큰 숫자는 제거, 라벨만)
		flash_lines = l
		flash_combo = combo
		flash_label = _line_label(l)
		flash_timer = FLASH_DUR
		if l >= 2 or combo >= 3:
			shake_timer = maxf(shake_timer, SHAKE_DUR * 0.7)

	# 누수 표시는 블라스트 뒤로 분리(겹쳐 묻히지 않게)
	if pending_leaks.size() > 0:
		resolve_leak_at = blast_len + 0.15
		resolve_total = blast_len + 0.15 + 0.25
	else:
		resolve_leak_at = 1.0e9
		resolve_total = blast_len

# 예약된 한 hit를 실제 반영 (그 시점에 데미지·floater·사망/넉백)
func _apply_hit(h: Dictionary) -> void:
	var found: int = -1
	for k in range(enemies.size()):
		if enemies[k]["id"] == h["id"]:
			found = k
			break
	if found == -1:
		return
	var e: Dictionary = enemies[found]
	var etype: String = e["etype"]
	e["hp"] -= h["dmg"]
	score += h["dmg"]
	var ep: Vector2 = _cell_center(e["col"], e["row"])
	# ② 로켓 명중 임팩트 버스트 (확 커졌다 꺼지는 별+링)
	impacts.append({"pos": ep, "life": 0.22, "max": 0.22, "color": Color(1.0, 0.98, 0.7), "radius": CELL * 0.30, "star": true})
	# 데미지 숫자: 크고 팡 (화면 유일 전투 숫자 — 확실히 보이게)
	var dmg_sz: int = clampi(34 + int(h["dmg"] / 15), 34, 64)
	_add_floater(ep + Vector2(0.0, -6.0), "-%d" % h["dmg"], Color(1.0, 0.95, 0.5), FLOAT_DUR, dmg_sz, true)
	if e["hp"] <= 0:
		# ① 극적 사망: 스케일 팝 + 파편 버스트 + 밝은 플래시 + 히트스톱
		_spawn_death(etype, ep)
		enemies.remove_at(found)
		killed += 1
		kill_pulse = 0.35   # ④ 킬 → 헤드라인 펄스
		hitstop = maxf(hitstop, 0.045)   # 처치 순간 멈칫(손맛)
	else:
		# ③ 생존 flinch(흰 플래시+떨림 강화) + 넉백 강화 + 짧은 히트스톱
		e["flinch"] = 0.22
		hitstop = maxf(hitstop, 0.02)
		var old_row: int = e["row"]
		var new_row: int = maxi(0, old_row - int(h["kb"]))
		if new_row != old_row:
			e["row"] = new_row
			push_streaks.append({
				"from": ep, "to": _cell_center(e["col"], new_row), "life": 0.3, "max": 0.3,
			})
		# 탱크가 버틸 때: 청록 방패링 + "BLOCK" 라벨 (역할 학습)
		if etype == "tank":
			impacts.append({"pos": ep, "life": 0.32, "max": 0.32, "color": C_E_FAST, "radius": CELL * 0.5})
			_add_floater(ep + Vector2(0.0, -CELL * 0.42), "BLOCK", C_E_FAST, 0.55, 18)
	sweep_timer = SWEEP_DUR

# 로켓 머리 위치 (prog 0=발사단 → 1=라인 끝)
func _rocket_pos(rocket: Dictionary, prog: float) -> Vector2:
	if rocket["dir"] == "col":
		var rx: float = BOARD_X + int(rocket["idx"]) * CELL + CELL * 0.5
		var b_bot: float = BOARD_Y + ROWS * CELL
		return Vector2(rx, b_bot + (BOARD_Y - b_bot) * prog)   # 아래→위
	var ry: float = BOARD_Y + int(rocket["idx"]) * CELL + CELL * 0.5
	return Vector2(BOARD_X + (COLS * CELL) * prog, ry)         # 좌→우

# 발사 지점 머즐 플래시 (밝은 섬광)
func _spawn_muzzle(dir: String, idx: int) -> void:
	var pos: Vector2
	if dir == "col":
		pos = Vector2(BOARD_X + idx * CELL + CELL * 0.5, BOARD_Y + ROWS * CELL)   # 아래 끝
	else:
		pos = Vector2(BOARD_X, BOARD_Y + idx * CELL + CELL * 0.5)                 # 좌 끝
	impacts.append({"pos": pos, "life": 0.16, "max": 0.16, "color": Color(1.0, 0.95, 0.6), "radius": CELL * 0.34, "star": false})

# 적 타입 → 이펙트용 선명한 색 (어두운 배경/마룬 가시성 보정)
func _etype_fx_color(etype: String) -> Color:
	match etype:
		"fast":
			return C_E_FAST
		"tank":
			return Color("#e05a7d")   # 마룬 밝은 변주 (파편이 배경에 묻히지 않게)
		"swarm":
			return C_E_SWARM
	return C_E_BASIC

# 극적 사망 연출: 스케일 팝 + 파편 + 리워드 팝 (타입 flavor)
func _spawn_death(etype: String, ep: Vector2) -> void:
	var col: Color = _etype_fx_color(etype)
	var pieces: int = 8
	var fade: float = 0.40
	match etype:
		"tank":
			pieces = 14
			fade = 0.5
			shake_timer = maxf(shake_timer, SHAKE_DUR * 0.5)   # 큰 적은 살짝 흔들림
		"swarm":
			pieces = 4
			fade = 0.30
		"fast":
			pieces = 7
			fade = 0.24                                       # 빠른 페이드
	# 스케일 팝 + 밝은 플래시
	death_flashes.append({"pos": ep, "life": fade, "max": fade, "color": col})
	# 파편 버스트 (사방으로)
	for _n in range(pieces):
		var ang: float = randf() * TAU
		var spd: float = randf_range(70.0, 190.0)
		var life: float = randf_range(0.3, 0.6) * (0.7 if etype == "fast" else 1.0)
		debris.append({
			"pos": ep, "vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": life, "max": life, "color": col, "size": randf_range(3.0, 6.0),
		})

# 누수(거점 피격) 연출을 지금 터뜨림
func _reveal_leaks() -> void:
	for col in pending_leaks:
		core_hits.append({"col": col, "life": 0.5})
		_add_floater(Vector2(BOARD_X + int(col) * CELL + CELL * 0.5, BOARD_Y + ROWS * CELL + 16.0),
				"-1", Color(1.0, 0.25, 0.25), 0.9, 40)
	if pending_leaks.size() > 0:
		red_flash = RED_FLASH_DUR
		shake_timer = maxf(shake_timer, SHAKE_DUR * 1.6)
	pending_leaks = []

# resolve 종료: 승패 판정·게임오버 확정 (표시 지연이 끝난 뒤 로직 마무리)
func _finish_resolve() -> void:
	resolving = false
	resolve_hits = []
	if not resolve_leak_done and pending_leaks.size() > 0:
		_reveal_leaks()
	_check_win()
	if pending_core_dead:
		game_over = true
		pending_core_dead = false
		return
	if not game_clear and not _has_valid_placement():
		game_over = true
		stuck = true

# ===== 스텝 진행 =====
func advance_step() -> void:
	place_count += 1
	# 전진 스로틀: step_every 배치마다 1칸 (fast=매 배치, 나머지=2배치당 1칸)
	for e in enemies:
		var step_every: int = e.get("step_every", ENEMY_STEP_EVERY)
		if place_count % step_every == 0:
			e["row"] += 1

	# 누수(거점 도달): 로직은 즉시 반영, 시각 연출은 resolve 끝물로 지연
	var i: int = enemies.size() - 1
	pending_leaks = []
	while i >= 0:
		if enemies[i]["row"] >= ROWS:
			core_hp -= 1
			killed += 1
			pending_leaks.append(enemies[i]["col"])
			enemies.remove_at(i)
		i -= 1
	pending_core_dead = core_hp <= 0
	if pending_core_dead:
		return   # 거점 파괴 스텝: 블라스트 없이 누수 연출 후 게임오버

	# 스폰 스로틀: SPAWN_EVERY 배치마다 1회, per_step=1 (밀도 낮춤)
	if place_count % SPAWN_EVERY != 0:
		return
	var per_step: int = 1
	for _s in range(per_step):
		if spawned >= TOTAL_ENEMIES:
			break
		var etype: String = "basic" if spawned < ONBOARD_COUNT else _pick_etype()
		if etype == "swarm":
			# 클러스터: 3~4마리 인접 열에 동시 (남은 수·보드폭에 맞춰 축소)
			var count: int = 3 + (randi() % 2)
			count = mini(count, TOTAL_ENEMIES - spawned)
			count = mini(count, COLS)
			var start_col: int = randi() % maxi(1, COLS - count + 1)
			for k in range(count):
				_spawn_one(start_col + k, "swarm")
		else:
			_spawn_one(randi() % COLS, etype)

# 가중 랜덤 타입 선택
func _pick_etype() -> String:
	var total: int = 0
	for t in ENEMY_TYPES:
		total += SPAWN_WEIGHTS[t]
	var r: int = randi() % total
	for t in ENEMY_TYPES:
		r -= SPAWN_WEIGHTS[t]
		if r < 0:
			return t
	return "basic"

# 적 1마리 스폰 (타입별 HP 배율 적용)
func _spawn_one(col: int, etype: String) -> void:
	var base: int = roundi(BASE_HP + spawned * HP_RAMP)
	var hp: int = base
	match etype:
		"fast":
			hp = roundi(base * 0.6)
		"tank":
			hp = roundi(base * 2.5)
		"swarm":
			hp = roundi(base * 0.4)
	hp = maxi(1, hp)
	# 전진 스로틀: fast는 매 배치(1), 나머지는 2배치당 1칸
	var step_every: int = 1 if etype == "fast" else ENEMY_STEP_EVERY
	enemies.append({"col": col, "row": 0, "hp": hp, "maxhp": hp, "etype": etype, "id": enemy_seq, "step_every": step_every})
	enemy_seq += 1
	spawned += 1
	# 첫 등장 콜아웃 (타입당 1회)
	if not seen_types.get(etype, false):
		seen_types[etype] = true
		match etype:
			"fast":
				_set_callout("FAST — quick!")
			"tank":
				_set_callout("TANK — big combo!")
			"swarm":
				_set_callout("SWARM — sweep them!")

func _set_callout(text: String) -> void:
	callout_text = text
	callout_timer = CALLOUT_DUR

func _check_win() -> void:
	if killed >= TOTAL_ENEMIES:
		game_clear = true

# ===== 조각 배치 =====
func _place_piece() -> void:
	if resolving:
		return
	var active: Dictionary = _active()
	if active.is_empty():
		return
	var cells: Array = _ghost_cells()
	if not _can_place(cells):
		return
	for ci in cells:
		var c: Vector2i = ci as Vector2i
		board[c.y][c.x] = active["color"]
	# 조각 소비: 트레이 슬롯 비우고 다음 슬롯/리필 (즉시 = 피드백)
	_consume_slot()
	# 적 전진 + 스폰 (누수는 pending에 기록)
	advance_step()
	if pending_core_dead:
		# 거점 파괴 스텝: 블라스트 없이 누수 연출 후 게임오버
		combo = 0
		_begin_resolve([], [])
		return
	var rows: Array = _full_rows()
	var cols: Array = _full_cols()
	var has_clear: bool = rows.size() + cols.size() > 0
	if has_clear:
		combo += 1
	else:
		combo = 0
	if not has_clear and pending_leaks.is_empty():
		# 연출할 게 없으면 즉시 마무리 (승패·공간부족 판정)
		_finish_resolve()
		return
	_begin_resolve(rows, cols)

# 배치한 슬롯 비우고 다음 non-empty로 이동, 다 비면 리필
func _consume_slot() -> void:
	tray[sel] = {}
	var next_sel: int = -1
	for i in range(sel + 1, tray.size()):
		if not tray[i].is_empty():
			next_sel = i
			break
	if next_sel == -1:
		for i in range(sel):
			if not tray[i].is_empty():
				next_sel = i
				break
	if next_sel != -1:
		sel = next_sel
	else:
		_refill_tray()

# ===== 입력 =====
func _input(event: InputEvent) -> void:
	if game_over or game_clear:
		if event is InputEventMouseButton:
			var mbe: InputEventMouseButton = event as InputEventMouseButton
			if mbe.pressed:
				get_tree().reload_current_scene()
		elif event is InputEventKey:
			var ke: InputEventKey = event as InputEventKey
			if ke.pressed and ke.keycode == KEY_SPACE:
				get_tree().reload_current_scene()
		return

	# resolve 재생 중에는 배치/선택 입력 정지 (연출 끝나면 자동 복귀)
	if resolving:
		return

	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		hover_col = int((pos.x - BOARD_X) / CELL)
		hover_row = int((pos.y - BOARD_Y) / CELL)

	if event is InputEventMouseButton:
		var mbe: InputEventMouseButton = event as InputEventMouseButton
		if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
			var in_board: bool = (
				mbe.position.x >= BOARD_X and
				mbe.position.x < BOARD_X + COLS * CELL and
				mbe.position.y >= BOARD_Y and
				mbe.position.y < BOARD_Y + ROWS * CELL
			)
			if in_board:
				_place_piece()
			else:
				# 트레이 슬롯 선택
				for i in range(3):
					var sr: Rect2 = _tray_slot_rect(i)
					if sr.has_point(mbe.position) and not tray[i].is_empty():
						sel = i
						break

# ===== 프레임 =====
func _process(delta: float) -> void:
	# 히트스톱: 게임 타이머 전부 정지, 그림만(시간감소라 항상 해제 → 데드락 없음)
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - delta)
		queue_redraw()
		return

	# 전투 순차 연출 진행 (타이머는 항상 0으로 수렴 → 데드락 없음)
	if resolving:
		resolve_timer += delta
		# ② 로켓 발사 (충전 0.08s 뒤) — 발사 지점에 머즐 플래시
		if not resolve_fx_done and resolve_timer >= 0.08:
			resolve_fx_done = true
			for rp in resolve_rocket_plan:
				rockets.append({"dir": rp["dir"], "idx": rp["idx"], "t": 0.0, "dur": ROCKET_DUR, "combo": flash_combo})
				_spawn_muzzle(rp["dir"], rp["idx"])
		for h in resolve_hits:
			if not h["done"] and resolve_timer >= h["at"]:
				h["done"] = true
				_apply_hit(h)
		if not resolve_leak_done and resolve_timer >= resolve_leak_at:
			resolve_leak_done = true
			_reveal_leaks()
		if resolve_timer >= resolve_total:
			_finish_resolve()

	if flash_timer > 0.0:
		flash_timer = maxf(0.0, flash_timer - delta)
	if line_flash_timer > 0.0:
		line_flash_timer = maxf(0.0, line_flash_timer - delta)
	if red_flash > 0.0:
		red_flash = maxf(0.0, red_flash - delta)
	if shake_timer > 0.0:
		shake_timer = maxf(0.0, shake_timer - delta)
	if sweep_timer > 0.0:
		sweep_timer = maxf(0.0, sweep_timer - delta)
	if callout_timer > 0.0:
		callout_timer = maxf(0.0, callout_timer - delta)
	anim_t += delta
	var k: int = push_streaks.size() - 1
	while k >= 0:
		push_streaks[k]["life"] -= delta
		if push_streaks[k]["life"] <= 0.0:
			push_streaks.remove_at(k)
		k -= 1
	var rk: int = rockets.size() - 1
	while rk >= 0:
		rockets[rk]["t"] += delta
		if rockets[rk]["t"] >= rockets[rk]["dur"]:
			# 라인 끝 도달 → 작은 소멸 폭발 플래시
			impacts.append({"pos": _rocket_pos(rockets[rk], 1.0), "life": 0.18, "max": 0.18, "color": Color(1.0, 0.9, 0.5), "radius": CELL * 0.28, "star": false})
			rockets.remove_at(rk)
		rk -= 1
	var ch: int = core_hits.size() - 1
	while ch >= 0:
		core_hits[ch]["life"] -= delta
		if core_hits[ch]["life"] <= 0.0:
			core_hits.remove_at(ch)
		ch -= 1
	var i: int = floaters.size() - 1
	while i >= 0:
		floaters[i]["life"] -= delta
		var fp: Vector2 = floaters[i]["pos"]
		floaters[i]["pos"] = Vector2(fp.x, fp.y - 34.0 * delta)
		if floaters[i]["life"] <= 0.0:
			floaters.remove_at(i)
		i -= 1
	var j: int = death_flashes.size() - 1
	while j >= 0:
		death_flashes[j]["life"] -= delta
		if death_flashes[j]["life"] <= 0.0:
			death_flashes.remove_at(j)
		j -= 1
	# 파편 이동·감쇠 (마찰 + 약한 중력)
	var d: int = debris.size() - 1
	while d >= 0:
		debris[d]["life"] -= delta
		var dv: Vector2 = debris[d]["vel"]
		dv = dv * maxf(0.0, 1.0 - 4.0 * delta) + Vector2(0.0, 140.0 * delta)
		debris[d]["vel"] = dv
		debris[d]["pos"] = (debris[d]["pos"] as Vector2) + dv * delta
		if debris[d]["life"] <= 0.0:
			debris.remove_at(d)
		d -= 1
	# 임팩트/막음 링 감쇠
	var im: int = impacts.size() - 1
	while im >= 0:
		impacts[im]["life"] -= delta
		if impacts[im]["life"] <= 0.0:
			impacts.remove_at(im)
		im -= 1
	if kill_pulse > 0.0:
		kill_pulse = maxf(0.0, kill_pulse - delta)
	# 적 flinch 감쇠
	for e in enemies:
		if e.get("flinch", 0.0) > 0.0:
			e["flinch"] = maxf(0.0, e["flinch"] - delta)
	queue_redraw()

# ===== 그리기 =====
func _draw() -> void:
	var fnt: Font = ThemeDB.fallback_font

	if shake_timer > 0.0:
		var mag: float = SHAKE_AMP * (shake_timer / SHAKE_DUR)
		draw_set_transform(Vector2(randf_range(-mag, mag), randf_range(-mag, mag)))

	draw_rect(Rect2(-20, -20, 840, 1040), C_BG)

	_draw_hud(fnt)
	_draw_board(fnt)
	_draw_core(fnt)
	_draw_bottom(fnt)

	for fl in floaters:
		var fa: float = clampf(fl["life"] / fl["max"], 0.0, 1.0)
		var fcol: Color = fl["color"]
		fcol.a = fa
		var ftxt: String = fl["text"]
		var fpos: Vector2 = fl["pos"]
		var fsize: int = fl["size"]
		# 스폰 순간 스케일 팝 (초반 18% 동안 최대 1.5배)
		if fl.get("pop", false):
			var age: float = 1.0 - fa   # 0=갓 생성 → 1=소멸
			var pop_s: float = 1.0 + 0.5 * clampf(1.0 - age / 0.18, 0.0, 1.0)
			fsize = int(float(fsize) * pop_s)
		var ftw: float = fnt.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		_draw_text_outlined(fnt, fpos - Vector2(ftw * 0.5, 0.0), ftxt, fsize, fcol)

	# 파편 버스트 (타입 색 작은 사각형)
	for dpart in debris:
		var dp: float = clampf(dpart["life"] / dpart["max"], 0.0, 1.0)
		var dcol: Color = dpart["color"]
		dcol.a = dp
		var dsz: float = dpart["size"]
		var dpos: Vector2 = dpart["pos"]
		draw_rect(Rect2(dpos - Vector2(dsz, dsz) * 0.5, Vector2(dsz, dsz)), dcol)

	# 사망 스케일 팝 (타입 색 디스크가 부풀며 페이드) + 밝은 흰 코어
	for df in death_flashes:
		var dp2: float = clampf(df["life"] / df["max"], 0.0, 1.0)   # 1→0
		var inv: float = 1.0 - dp2
		var dpos2: Vector2 = df["pos"]
		var dcol2: Color = df["color"]
		draw_circle(dpos2, CELL * 0.34 * (1.0 + 0.8 * inv), Color(dcol2.r, dcol2.g, dcol2.b, dp2 * 0.7))
		draw_circle(dpos2, CELL * 0.30 * (1.0 + 0.35 * inv), Color(1.0, 1.0, 1.0, dp2 * dp2 * 0.9))

	# 타격 임팩트 (팽창 링 + 별 버스트 마크) / 탱크 막음 링
	for imp in impacts:
		var ip: float = clampf(imp["life"] / imp["max"], 0.0, 1.0)
		var irr: float = imp["radius"] * (1.0 + (1.0 - ip) * 0.9)
		var icol: Color = imp["color"]
		icol.a = ip
		draw_arc(imp["pos"], irr, 0.0, TAU, 22, icol, 3.0)
		# 별 버스트 스파이크 (타격 순간 강조)
		if imp.get("star", false):
			var ic: Vector2 = imp["pos"]
			var spike: float = irr * 1.35
			var scol: Color = Color(1.0, 1.0, 0.85, ip)
			for a in range(4):
				var ang: float = float(a) * PI * 0.5 + PI * 0.25
				var dir: Vector2 = Vector2(cos(ang), sin(ang))
				draw_line(ic + dir * (irr * 0.4), ic + dir * spike, scol, 2.5)

	if red_flash > 0.0:
		var ra: float = (red_flash / RED_FLASH_DUR) * 0.5
		draw_rect(Rect2(-20, -20, 840, 1040), Color(0.9, 0.05, 0.05, ra))

	if flash_timer > 0.0:
		var t: float = flash_timer / FLASH_DUR
		draw_rect(Rect2(0, 0, 800, 1000), Color(1.0, 1.0, 1.0, t * 0.15))
		if flash_combo >= 2:
			var cs: String = "COMBO x%d" % flash_combo
			var cbase: int = 44 + mini(flash_combo, 8) * 8
			var csz: int = cbase + int(t * 14.0)
			var cw: float = fnt.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x
			_draw_text_outlined(fnt, Vector2(400.0 - cw * 0.5, 402.0), cs, csz, Color(1.0, 0.82, 0.1, t))
		if flash_label != "":
			var ls: int = 40 + flash_lines * 6
			var lw: float = fnt.get_string_size(flash_label, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
			_draw_text_outlined(fnt, Vector2(400.0 - lw * 0.5, 458.0), flash_label, ls, Color(1.0, 0.85, 0.1, t))

	# 첫 등장 콜아웃 배너 (상단-중앙, 보드 위에 얹힘)
	if callout_timer > 0.0 and not game_over and not game_clear:
		var ca: float = clampf(callout_timer / 0.4, 0.0, 1.0)   # 마지막 0.4s 페이드
		var cow: float = fnt.get_string_size(callout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		var cbx: float = 400.0 - cow * 0.5
		draw_rect(Rect2(cbx - 16.0, 150.0, cow + 32.0, 46.0), Color(0.05, 0.02, 0.08, 0.62 * ca))
		_draw_text_outlined(fnt, Vector2(cbx, 183.0), callout_text, 32, Color(1.0, 0.9, 0.4, ca))

	if game_over or game_clear:
		draw_rect(Rect2(0, 0, 800, 1000), Color(0.0, 0.0, 0.0, 0.72))
		var msg: String = "ALL CLEARED!" if game_clear else "GAME OVER"
		var mfs: int = 80
		var mw: float = fnt.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
		draw_string(fnt, Vector2(400.0 - mw * 0.5, 440.0), msg,
				HORIZONTAL_ALIGNMENT_LEFT, -1, mfs, Color.WHITE)
		if game_over:
			var reason: String = "NO SPACE" if stuck else "CORE DESTROYED"
			var rw: float = fnt.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			draw_string(fnt, Vector2(400.0 - rw * 0.5, 482.0), reason,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.5, 0.5))
		var sub: String = "Click or SPACE to restart"
		var sw: float = fnt.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_string(fnt, Vector2(400.0 - sw * 0.5, 558.0), sub,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.75, 0.75, 0.75))

func _draw_hud(fnt: Font) -> void:
	draw_rect(Rect2(0, 0, 800, 140), C_HUD)
	var hp_col: Color = Color(1.0, 0.38, 0.38) if core_hp <= 5 else Color(0.8, 0.55, 0.55)
	draw_string(fnt, Vector2(20.0, 40.0), "CORE HP  %d / %d" % [core_hp, CORE_HP_MAX],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, hp_col)
	if combo >= 2:
		var streak: String = "STREAK x%d" % combo
		var stw: float = fnt.get_string_size(streak, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_draw_text_outlined(fnt, Vector2(780.0 - stw, 46.0), streak, 30, C_GOLD)
	# ENEMIES LEFT — 킬 순간 펄스(스케일↑ + 금색 플래시)
	var remaining: int = TOTAL_ENEMIES - killed
	var head: String = "ENEMIES LEFT  %d / %d" % [remaining, TOTAL_ENEMIES]
	var kp: float = clampf(kill_pulse / 0.35, 0.0, 1.0)
	var head_fs: int = 40 + int(kp * 10.0)
	var head_col: Color = Color.WHITE.lerp(C_GOLD, kp)
	var hw: float = fnt.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_fs).x
	_draw_text_outlined(fnt, Vector2(400.0 - hw * 0.5, 96.0), head, head_fs, head_col)
	var bx: float = 20.0
	var by: float = 112.0
	var bw: float = 760.0
	var bh: float = 20.0
	draw_rect(Rect2(bx, by, bw, bh), Color(0.12, 0.12, 0.18))
	var frac: float = clampf(float(killed) / float(TOTAL_ENEMIES), 0.0, 1.0)
	draw_rect(Rect2(bx, by, bw * frac, bh), Color(0.3, 0.78, 0.46))
	draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 1.0, 1.0, 0.4), false)

func _draw_board(fnt: Font) -> void:
	draw_rect(Rect2(BOARD_X - 2, BOARD_Y - 2, COLS * CELL + 4, ROWS * CELL + 4), C_BORD, false)
	for r in range(ROWS):
		for c in range(COLS):
			var rx: float = BOARD_X + c * CELL
			var ry: float = BOARD_Y + r * CELL
			draw_rect(Rect2(rx, ry, CELL, CELL), C_CELL)
			draw_rect(Rect2(rx, ry, CELL, CELL), C_GRID, false)
			if board[r][c] != "":
				var pad: float = 5.0
				draw_rect(Rect2(rx + pad, ry + pad, CELL - pad * 2.0, CELL - pad * 2.0),
						_color_of(board[r][c]))

	# (레이저 밴드 제거 — 공격 연출은 로켓만)

	# 로켓 (라인 질주: 굵고 밝은 머리 + 길고 강한 발광 꼬리). 세로줄=아래→위, 가로줄=좌→우.
	for rocket in rockets:
		var prog: float = clampf(rocket["t"] / rocket["dur"], 0.0, 1.0)
		var cmb: int = mini(int(rocket["combo"]), 8)
		var thick: float = 7.0 + float(cmb) * 2.5   # 콤보 클수록 굵게
		var head: Vector2 = _rocket_pos(rocket, prog)
		var tlen: float = CELL * 1.7                 # 길고 강한 꼬리
		var back: Vector2
		if rocket["dir"] == "col":
			back = head + Vector2(0.0, tlen)         # 꼬리는 진행 반대(아래)
		else:
			back = head - Vector2(tlen, 0.0)         # 꼬리는 진행 반대(좌)
		# 발광 꼬리 (두 겹: 넓은 은은한 + 좁은 밝은)
		draw_line(back, head, Color(1.0, 0.6, 0.15, 0.35), thick * 1.4)
		draw_line((back + head) * 0.5, head, Color(1.0, 0.9, 0.5, 0.7), thick * 0.9)
		# 밝은 볼트 머리 (외곽 글로우 + 흰 코어)
		draw_circle(head, thick * 1.35, Color(1.0, 0.85, 0.4, 0.5))
		draw_circle(head, thick, Color(1.0, 0.98, 0.7, 0.98))
		draw_circle(head, thick * 0.5, Color.WHITE)

	# 고스트 (게임 진행 중, active 슬롯이 채워져 있을 때만)
	if not game_over and not game_clear:
		var active: Dictionary = _active()
		var ghost: Array = _ghost_cells()
		var can: bool = _can_place(ghost)
		for gi in ghost:
			var gc: Vector2i = gi as Vector2i
			if gc.x < 0 or gc.x >= COLS or gc.y < 0 or gc.y >= ROWS:
				continue
			var rx: float = BOARD_X + gc.x * CELL
			var ry: float = BOARD_Y + gc.y * CELL
			var pad: float = 5.0
			var gcol: Color
			if can:
				gcol = _color_of(active["color"])
				gcol.a = 0.42
			else:
				gcol = Color(1.0, 0.18, 0.18, 0.32)
			draw_rect(Rect2(rx + pad, ry + pad, CELL - pad * 2.0, CELL - pad * 2.0), gcol)

	# (가로 스윕 밴드 제거 — 공격 연출은 로켓만)

	# 넉백 잔상 (밀쳐진 적의 이전→현재 위치 시안 스트릭)
	for st in push_streaks:
		var sa: float = clampf(st["life"] / st["max"], 0.0, 1.0)
		draw_line(st["from"], st["to"], Color(0.6, 0.95, 1.0, sa * 0.7), 4.0)

	# 적 (타입별 색·모양·크기 + HP 바 + HP 텍스트)
	for e in enemies:
		var ec: int = e["col"]
		var er: int = e["row"]
		if er < 0 or er >= ROWS:
			continue
		# 피격 flinch: 잠깐 떨림
		var flinch: float = e.get("flinch", 0.0)
		var jit: Vector2 = Vector2.ZERO
		if flinch > 0.0:
			var jm: float = 5.0 * clampf(flinch / 0.22, 0.0, 1.0)
			jit = Vector2(randf_range(-jm, jm), randf_range(-jm, jm))
		var cx: float = BOARD_X + ec * CELL + CELL * 0.5 + jit.x
		var cy: float = BOARD_Y + er * CELL + CELL * 0.5 + jit.y
		var ratio: float = clampf(float(e["hp"]) / float(e["maxhp"]), 0.0, 1.0)
		var etype: String = e["etype"]
		var rad: float = CELL * 0.33
		var bar_w: float = CELL * 0.66
		var bar_h: float = 5.0
		match etype:
			"fast":
				# 시안 화살촉(아래 향함) = 속도감
				var s: float = CELL * 0.26
				var pts: PackedVector2Array = PackedVector2Array([
					Vector2(cx, cy + s),
					Vector2(cx - s, cy - s * 0.7),
					Vector2(cx + s, cy - s * 0.7),
				])
				draw_colored_polygon(pts, C_E_FAST)
				rad = s
				# 깜빡이는 "!" 긴급 마커 (머리 위)
				var blink: float = 0.5 + 0.5 * sin(anim_t * 10.0)
				_draw_text_outlined(fnt, Vector2(cx - 4.0, cy - s - 14.0), "!", 26,
						Color(1.0, 0.95, 0.3, 0.4 + 0.6 * blink))
			"tank":
				# 어두운 마룬 큰 사각형 + 두꺼운 외곽선
				var hs: float = CELL * 0.42
				draw_rect(Rect2(cx - hs, cy - hs, hs * 2.0, hs * 2.0), C_E_TANK)
				draw_rect(Rect2(cx - hs, cy - hs, hs * 2.0, hs * 2.0), Color(0.0, 0.0, 0.0, 0.85), false, 4.0)
				rad = hs
				bar_w = CELL * 0.78
				bar_h = 8.0
			"swarm":
				# 라임 작은 원 여럿 (군집)
				var offs: Array = [Vector2(-0.16, -0.12), Vector2(0.16, -0.10), Vector2(-0.02, 0.16)]
				for off in offs:
					var ov: Vector2 = off as Vector2
					draw_circle(Vector2(cx + ov.x * CELL, cy + ov.y * CELL), CELL * 0.14, C_E_SWARM)
				rad = CELL * 0.24
			_:
				# basic: 빨강 원 (hp 비율로 살짝 명암)
				var bcol: Color = C_E_BASIC.lerp(Color(0.55, 0.12, 0.12), 1.0 - ratio)
				draw_circle(Vector2(cx, cy), rad, bcol)
		# 피격 흰 플래시 오버레이 (맞은 순간 강조)
		if flinch > 0.0:
			draw_circle(Vector2(cx, cy), rad, Color(1.0, 1.0, 1.0, 0.7 * clampf(flinch / 0.22, 0.0, 1.0)))
		# HP 바 (타입 색과 구분되게 녹색 유지)
		var bx: float = cx - bar_w * 0.5
		var by: float = cy - rad - 9.0
		draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.85))
		draw_rect(Rect2(bx, by, bar_w * ratio, bar_h), Color(0.35, 0.9, 0.35))
		# HP 텍스트 (탱크는 크게 노출 = "버티는 게 보임" 텔레그래프)
		var hp_str: String = str(e["hp"])
		var hp_fs: int = 18
		if etype == "tank":
			hp_fs = 26
		elif etype == "swarm":
			hp_fs = 14
		var tw: float = fnt.get_string_size(hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, hp_fs).x
		var hp_yoff: float = float(hp_fs) * 0.34
		draw_string(fnt, Vector2(cx - tw * 0.5 + 1.0, cy + hp_yoff + 1.0), hp_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, hp_fs, Color(0.0, 0.0, 0.0, 0.8))
		draw_string(fnt, Vector2(cx - tw * 0.5, cy + hp_yoff), hp_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, hp_fs, Color.WHITE)

func _draw_core(fnt: Font) -> void:
	var strip_h: float = 26.0
	var sx: float = BOARD_X
	var sy: float = BOARD_Y + ROWS * CELL + 4.0
	var sw: float = COLS * CELL
	var ratio: float = clampf(float(core_hp) / float(CORE_HP_MAX), 0.0, 1.0)
	var low: bool = core_hp <= 5
	draw_rect(Rect2(sx, sy, sw, strip_h), Color(0.15, 0.05, 0.07))
	var fill_col: Color = Color(0.9, 0.2, 0.2) if low else Color(0.2, 0.8, 0.7)
	draw_rect(Rect2(sx, sy, sw * ratio, strip_h), fill_col)
	draw_rect(Rect2(sx, sy, sw, strip_h), Color(1.0, 1.0, 1.0, 0.7), false)
	var lbl: String = "CORE   %d / %d" % [core_hp, CORE_HP_MAX]
	draw_string(fnt, Vector2(sx + 8.0, sy + 19.0), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)

	# 거점 피격: 그 열 충격 플래시 + 균열 지그재그 (HP 잃는 게 확 무섭게)
	for hit in core_hits:
		var ha: float = clampf(hit["life"] / 0.5, 0.0, 1.0)
		var hx: float = sx + int(hit["col"]) * CELL + CELL * 0.5
		draw_rect(Rect2(hx - CELL * 0.5, sy, CELL, strip_h), Color(1.0, 0.85, 0.85, ha * 0.8))
		var zpts: PackedVector2Array = PackedVector2Array()
		var zsteps: int = 4
		for zs in range(zsteps + 1):
			var zy: float = sy + strip_h * float(zs) / float(zsteps)
			var zx: float = hx + (CELL * 0.18 if zs % 2 == 0 else -CELL * 0.18)
			zpts.append(Vector2(zx, zy))
		draw_polyline(zpts, Color(1.0, 0.2, 0.2, ha), 3.0)

func _draw_bottom(fnt: Font) -> void:
	draw_rect(Rect2(0, BOT_Y, 800, 1000 - BOT_Y), C_HUD)

	# 3슬롯 트레이
	for i in range(3):
		var sr: Rect2 = _tray_slot_rect(i)
		var slot: Dictionary = tray[i]
		# 슬롯 배경
		var bg_col: Color = Color(0.18, 0.18, 0.28) if not slot.is_empty() else Color(0.10, 0.10, 0.16)
		draw_rect(sr, bg_col)
		# 선택 슬롯 테두리 강조
		var border_w: float = 3.0 if i == sel else 1.5
		var border_c: Color = Color(1.0, 0.88, 0.2, 0.9) if i == sel else Color(0.35, 0.35, 0.5, 0.6)
		draw_rect(sr, border_c, false, border_w)

		if not slot.is_empty():
			# 조각 미니 렌더 — 슬롯 중앙 정렬
			var offsets: Array = slot["offsets"]
			# 못 놓는 조각은 회색으로 (Block Blast식 명확화)
			var pcol: Color = _color_of(slot["color"]) if _piece_placeable(offsets) else Color(0.35, 0.35, 0.4)
			var min_x: int = 999
			var min_y: int = 999
			var max_x: int = -999
			var max_y: int = -999
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				if ov.x < min_x:
					min_x = ov.x
				if ov.y < min_y:
					min_y = ov.y
				if ov.x > max_x:
					max_x = ov.x
				if ov.y > max_y:
					max_y = ov.y
			var piece_w: int = max_x - min_x + 1
			var piece_h: int = max_y - min_y + 1
			var ps: int = TRAY_PREVIEW_CELL
			var ox: float = sr.position.x + (sr.size.x - float(piece_w * ps)) * 0.5
			var oy: float = sr.position.y + (sr.size.y - float(piece_h * ps)) * 0.5
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var px: float = ox + float(ov.x - min_x) * float(ps)
				var py: float = oy + float(ov.y - min_y) * float(ps)
				draw_rect(Rect2(px, py, float(ps) - 2.0, float(ps) - 2.0), pcol)
		else:
			# 빈 슬롯 표시
			var dash: String = "—"
			var dw: float = fnt.get_string_size(dash, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string(fnt, Vector2(sr.position.x + sr.size.x * 0.5 - dw * 0.5,
					sr.position.y + sr.size.y * 0.5 + 8.0),
					dash, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.3, 0.3, 0.4))

	# 조작 안내
	var inst_y: float = float(BOT_Y) + float(TRAY_SLOT_H) + 30.0
	draw_string(fnt, Vector2(20.0, inst_y), "Click a piece, then click board to place",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.8, 0.8, 0.85))
	draw_string(fnt, Vector2(20.0, inst_y + 28.0), "Fill a full row OR column -> blast!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.55, 0.85, 0.6))
	draw_string(fnt, Vector2(20.0, inst_y + 54.0), "Chain clears -> COMBO streak (bigger dmg)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.85, 0.75, 0.4))
