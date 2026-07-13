extends Node2D

# ===== 상수 =====
const COLS: int = 8
const ROWS: int = 8             # 8×8 (Block Blast와 동일). 줄=8칸이라 조각 유입 대비 수지가 조여짐
const CELL: int = 64            # 셀 크기(픽셀) → 보드 512×512 (6×6 시절 516과 거의 동일 면적)
const BOARD_X: int = 144        # (800 - COLS*CELL)/2
const BOARD_Y: int = 150        # 보드 상단 y (보드 150~662)
const BOT_Y: int = 700          # 하단 패널 상단 (거점 띠 670~696 아래, 트레이 700~1000)

# 적 타입 (basic/fast/tank/swarm)
const ENEMY_TYPES: Array = ["basic", "fast", "tank", "swarm"]
const SLIDE_SPEED: float = 8.0   # 적 전진 표시 이징 속도(칸/초)
const ROCKET_DUR: float = 0.16  # 로켓 비행 지속(빠르게 질주)
const CALLOUT_DUR: float = 1.6  # 첫 등장 콜아웃 배너 지속

# 라인클리어 폭발
const LINE_BASE: int = 120
const STREAK_STEP: float = 0.5
const BLAST_RING_DELAY: float = 0.4   # 링(추가 레인) 간 순차 발사 텀 (물결 확산 속도. 클수록 극적·느림)
const FLASH_DUR: float = 0.7
const CLIMAX_FLASH_DUR: float = 0.95   # 전멸(화면 전체 청소) 골드 섬광 길이(천천히 페이드)
# 전멸(클라이맥스) 임계 콤보. COMBO_GRACE 도입으로 스트릭이 실제로 자라기 시작(최대콤보 2.7→5.5)했고,
# 그 사다리의 꼭대기가 되도록 6에 앉힘 → 판당 1~2회(도달 가능하되 드묾). 유예 없던 시절의 3은
# 이제 판당 10회가 터져 클라이맥스가 아니게 됨.
const CLIMAX_COMBO: int = 5
# 콤보 유예: 줄을 못 지운 배치를 이만큼까지 봐준다(연속 GRACE+1회 헛수 = 리셋).
# Block Blast 실측: 클리어→헛수 1회→클리어에서 콤보가 3→4로 '이어짐'. 즉 한 수 쉬어도 안 끊김.
# 우리는 헛수 1회에 즉시 0이라 스트릭이 못 자랐고(봇 평균 최대콤보 2.6~3.0), 그게 클라이맥스가
# 안 터지는 근본 원인. 전체 수의 ~70%가 헛수인 게임에서 즉시 리셋은 사실상 스트릭 봉쇄.
const COMBO_GRACE: int = 1

# ===== 줄 폭발(충전 → 순차 파괴) =====
# 완성 줄은 즉시 사라지지 않는다. ① 충전(색 통일→달아오름) → ② 한쪽 끝부터 순차 파괴 → ③ 로켓 발사.
# 배치(플레이어 행동) → 줄 폭발(보상) → 로켓 → 적 사망 의 인과 사슬을 눈에 보이게 만드는 구간.
#
# ★ 충전 홀드 = 에스컬레이션 축(Block Blast 실측: 콤보2 ≈0.27s, 콤보4 ≈0.55s).
#   콤보가 클수록 '더 크게'가 아니라 '더 오래 참는다' — 셰이크를 금지(C24⑦)한 뒤 비어 있던
#   에스컬레이션 축을 시간이 메운다. 기대가 쌓이는 정지 구간이라, 길수록 터질 때 더 세게 느껴진다.
const CHARGE_BASE: float = 0.20        # 콤보 1의 홀드
const CHARGE_PER_COMBO: float = 0.12   # 콤보 1당 추가 홀드 (콤보4 ≈0.56s = BB 실측 0.55s에 맞춤)
const CHARGE_MAX: float = 0.60         # 홀드 상한(그 이상은 늘어짐)
# 충전 중 색 통일: 이 비율 지점까지 '원래 색 → 방금 놓은 조각 색'으로 물들고(줄이 한 색이 됨),
# 나머지 구간에서 흰색으로 달아오른다. Block Blast가 터지는 줄을 놓은 조각 색으로 통일하는 것과 같은 수법 —
# 알록달록한 보드에서 완성 줄만 도드라지게 하고, 폭발이 '내 조각의 결과'임을 색으로 잇는다.
const CHARGE_TINT: float = 0.45
# 블록 소멸은 '동시'다 — Block Blast 60fps 실측: 완성 줄 8칸이 단 1프레임(16.7ms)에 전부 증발한다.
# 칸을 하나씩 순차로 부수면 그게 곧 '느리다'로 체감된다(실제로 그랬음). 시간이 걸리는 연출은
# 전부 블록이 사라진 '뒤'에 온다(빛 바 스윕 → 파편 → 텍스트).
# 사라지는 순간 줄 자리에 색 테두리만 한 순간 남는다 = 소멸의 잔상.
const LINE_OUTLINE_DUR: float = 0.06
# 블록이 사라지고 로켓(=빛 바)이 나가기까지의 짧은 빈 줄 간격 (BB 실측 ~0.07s)
const BURST_GAP: float = 0.07

# ===== DDA (동적 난이도 조정) =====
# 조각을 '무작위 1개'가 아니라 '후보 N개 중 골라서' 준다. 고를 때의 편향을 플레이어 상태로 정한다:
#   고전 중(보드 빡빡·클리어 가뭄·거점 위험) → 지금 보드에 '잘 맞는' 조각(줄 완성 가능한 것 우선)
#   압도 중(보드 여유·콤보 상승·거점 만땅)   → 놓을 수는 있되 '까다로운' 조각
#   그 사이(데드존)                          → 그냥 무작위 (대부분의 시간)
# ⚠보이지 않아야 한다. 플레이어가 "봐줬다"고 느끼면 성취가 죽는다 → 데드존을 넓게, 개입은 약하게.
# (var: 시뮬레이터가 A/B 하려고 런타임에 끌 수 있게)
const DDA_CANDIDATES: int = 6     # 후보 조각 수(많을수록 개입이 세짐)
const DDA_DEADZONE: float = 0.34  # |dda|가 이보다 작으면 무개입(무작위)
const DDA_GOD_FAILS: int = 2      # 같은 스테이지 연속 실패 이 횟수부터 '갓 모드'(강한 구제)

# ===== 스테이지 (밸런스 정본) =====
# 기준 ① 데미지는 난이도 손잡이가 아니다.
#   일격 = LINE_BASE(120) × 동시줄배수 × 콤보배수 → 1줄 기준 콤보1=120 / 콤보2=180 / 콤보3=240.
#   basic HP는 어느 스테이지든 120 미만 = 항상 원샷. HP를 올려도 어느 순간 갑자기 안 죽는 '절벽'이라
#   손잡이로 못 씀. (C24: 증폭축 = 데미지 아닌 커버리지)
# 기준 ② 난이도는 '커버리지 요구'에서 온다. 적 타입이 서로 다른 걸 요구하는 게 난이도의 정체:
#   swarm = 인접 열 클러스터 → 1레인으론 못 쓸어냄 → 콤보 '레인 수'(범위) 요구
#   tank  = tank_mult로 HP를 콤보2~3 구간에 앉힘      → 콤보 '배수'(관통) 요구
#   fast  = 전진 2배(step_every 절반) → 누수 시계 압박 → '템포' 요구
# 기준 ③ 누수 봉쇄: 필요 처치 = total − (core_hp − 1). core_hp가 total에 가까우면
#   '흘려보내며 이기기'가 성립(구 25/28 = 파탄). core_hp는 '허용 누수 횟수 + 1'로 읽는다.
# 기준 ④ 누수 시계 = ROWS × step_every 배치 (fast는 절반). 유입 = spawn_every 배치당 1회.
# 기준 ⑤ 난이도 손잡이는 core_hp(허용 누수) + total(적 수) 둘뿐이다. 나머지는 실측상 못 쓴다:
#   step_every 3→2 = 절벽(스5 승률 61%→2.5%). 누수 시계가 24→16배치로 줄면 그냥 안 됨.
#   spawn_every는 비단조 — 2→1로 조이면 스3이 오히려 쉬워졌다(63%→75%). 적이 뭉쳐 들어와
#   한 레인 청소에 더 많이 쓸려나가기 때문. '더 빨리 온다'가 '더 어렵다'가 아니다.
const STAGES: Array = [
	{
		"name": "첫 방어선", "tag": "줄을 완성해 레인을 청소한다",
		"total": 20, "core_hp": 7, "base_hp": 30, "hp_ramp": 0.0, "tank_mult": 2.5,
		"spawn_every": 3, "step_every": 3, "onboard": 20,
		"weights": {"basic": 100, "fast": 0, "tank": 0, "swarm": 0},
	},
	{
		# desync로 무리 절반이 base_step−1로 더 빨리 전진 → 행·열로 흩어져 한 줄론 못 쓸어냄
		"name": "무리", "tag": "흩어져 밀려온다 — 한 줄로는 못 쓴다",
		"total": 30, "core_hp": 3, "base_hp": 32, "hp_ramp": 0.4, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 4,
		"weights": {"basic": 40, "fast": 0, "tank": 0, "swarm": 60},
	},
	{
		"name": "속공", "tag": "빠르다 — 시간이 없다",
		"total": 34, "core_hp": 3, "base_hp": 34, "hp_ramp": 0.5, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3,
		"weights": {"basic": 40, "fast": 50, "tank": 0, "swarm": 10},
	},
	{
		# tank HP를 콤보3(240) 구간에 앉힌다: base 44~50 × 4.5 = 198~227 → 콤보2(180)로는 안 뚫림.
		"name": "장갑", "tag": "한 방으론 안 뚫린다 — 콤보를 쌓아라",
		"total": 44, "core_hp": 2, "base_hp": 44, "hp_ramp": 0.3, "tank_mult": 4.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3,
		"weights": {"basic": 40, "fast": 0, "tank": 55, "swarm": 5},
	},
	{
		"name": "총력전", "tag": "전부 온다",
		"total": 48, "core_hp": 2, "base_hp": 46, "hp_ramp": 0.4, "tank_mult": 4.2,
		"spawn_every": 2, "step_every": 3, "onboard": 2,
		"weights": {"basic": 20, "fast": 35, "tank": 25, "swarm": 20},
	},
]

# 조각 색 키 (시각용만)
const COLORS: Array = ["R", "B", "Y"]

# 트레이 UI
const TRAY_SLOT_W: int = 120
const TRAY_SLOT_H: int = 100
const TRAY_SLOT_GAP: int = 20
const TRAY_PREVIEW_CELL: int = 17   # 최대 조각이 5칸(I5) → 85px, 슬롯 120×100 안에 여백 확보

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
	# --- 직선 5칸 (8열 보드에서 줄 완성의 주력. Block Blast 실측 최다 조각 = I5, 17.7%) ---
	"I5h": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
	"I5v": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)],
	# --- 직사각 (덩어리로 넓게 메움) ---
	"R32": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"R23": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"R33": [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	],
}

# 크기 티어 (보드 여유에 따라 티어 확률을 바꾼다 — _random_piece 참조)
# 8×8은 줄이 8칸이라 6×6보다 완성이 훨씬 어려움 → I5 같은 '직선 장척'이 콤보를 되살리는 핵심.
const SMALL_POOL: Array = ["1", "D2h", "D2v", "I3h", "I3v", "L3a", "L3b", "L3c", "L3d"]
const MID_POOL: Array = ["O", "I", "Iv", "T", "S", "Z", "L", "J", "I5h", "I5v", "R32", "R23"]
const BIG_POOL: Array = ["R33"]

# 풀 안에서도 균등추첨이 아니라 가중추첨. 균등이면 간판 조각(I5)이 테트로미노 8종에 희석돼
# MID의 1/6밖에 안 나오고, 1칸짜리가 SMALL의 1/9씩이나 나온다(= 손에 쓰레기 조각이 자주 잡힘).
# Block Blast 감각: I5가 최다(~18%), 1칸은 아주 드묾.
const PIECE_W: Dictionary = {
	"1": 1, "D2h": 3, "D2v": 3, "I3h": 6, "I3v": 6, "L3a": 4, "L3b": 4, "L3c": 4, "L3d": 4,
	"O": 6, "I": 4, "Iv": 4, "T": 4, "S": 3, "Z": 3, "L": 4, "J": 4,
	"I5h": 10, "I5v": 10, "R32": 7, "R23": 7,
	"R33": 1,
}

# ===== 스테이지 상태 =====
# mode: "select"=레벨 선택 화면, "play"=한 스테이지 플레이 중 (스테이지는 서로 독립 = 보드·거점 초기화)
var mode: String = "select"
var stage_idx: int = 0
var st: Dictionary = {}          # 현재 스테이지 정의(STAGES[stage_idx])
var cleared: Dictionary = {}     # 스테이지 인덱스 → 클리어 여부 (세션 한정, 저장 없음)
var hover_stage: int = -1
var _play_hover: bool = false    # 하단 시작 버튼 호버

# ===== 상태 =====
var board: Array = []
var enemies: Array = []
var core_hp: int = 0
var place_count: int = 0        # 지금까지 배치 횟수(전진·스폰 스로틀 기준)
var spawned: int = 0
var killed: int = 0             # 실제 처치 수 (누수는 포함 안 함 — 진행도 오염 방지)
var leaked: int = 0             # 거점까지 흘려보낸 수. killed+leaked = 처리된 적(=더 이상 안 옴)
var score: int = 0
var combo: int = 0
var combo_miss: int = 0         # 콤보 유예 카운터: 줄 못 지운 연속 배치 수
var dda_enabled: bool = true    # DDA 온오프 (A/B용)
var drought: int = 0            # 연속 무클리어 배치 수 (DDA의 '고전' 신호)
var fail_streak: Dictionary = {}  # 스테이지 인덱스 → 연속 실패 횟수 (갓 모드 트리거, 세션 한정)
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
var flash_climax: bool = false      # 화면 전체 도달(전멸) — 라벨/섬광 강조용
var climax_flash: float = 0.0       # 전멸 골드 섬광 타이머
var climax_pending: float = -1.0    # 전멸 충격파 발사 예약 시각(resolve_timer 기준, -1=없음)

# 터질 예정인 완성 줄 — 충전이 끝날 때까지 board에 그대로 남아 있다(즉시 삭제 금지).
# 충전이 끝나면 전 셀이 '동시에' 사라진다.
var clear_cells: Array = []         # [Vector2i] 터질 셀
var clear_rows: Array = []          # 완성된 행/열 (소멸 순간 테두리 플래시용)
var clear_cols: Array = []
var clear_tint: Color = Color.WHITE # 색 통일 목표색 = 방금 놓은 조각 색
var clear_done: bool = true         # 셀 소멸을 이미 실행했나
var charge_dur: float = CHARGE_BASE # 이번 폭발의 충전 홀드(콤보 비례)
var outline_timer: float = 0.0      # 소멸 직후 줄 자리에 남는 색 테두리 잔상
var last_color: String = ""         # 마지막으로 놓은 조각의 색 키

var floaters: Array = []
var death_flashes: Array = []  # [{pos, life, max, color}] 적 사망 스케일 팝(원형) — '적이 죽었다'의 시각 문법
var cell_pops: Array = []      # [{pos, life, max, color}] 블록 소멸 팝(사각형) — 적 사망과 형태로 구분
var debris: Array = []         # [{pos, vel, life, max, color, size}] 사망 파편 버스트
var impacts: Array = []        # [{pos, life, max, color, radius}] 빔 임팩트/탱크 막음 링
var kill_pulse: float = 0.0    # 킬 순간 ENEMIES LEFT 헤드라인 펄스
var push_streaks: Array = []   # [{from, to, life, max}] 넉백 잔상
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
var pending_leaks: Array = []      # 이번 스텝 누수 열 목록(공격 뒤 표시)
var pending_core_dead: bool = false
var enemy_seq: int = 0             # 적 고유 id 카운터

# ===== 초기화 =====
var _font: Font = null

func _ready() -> void:
	randomize()
	# 한글 렌더용 시스템 폰트(기본 fallback엔 한글 글리프 없음). ⚠배포 시엔 Noto Sans KR 등 번들 필요.
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Apple SD Gothic Neo", "AppleGothic", "Noto Sans CJK KR", "Arial"])
	_font = sf
	mode = "select"

# 선형 해금: 1스테이지는 항상 열려 있고, 그다음부턴 직전 스테이지를 깨야 열린다
func _is_unlocked(i: int) -> bool:
	if i <= 0:
		return true
	return bool(cleared.get(i - 1, false))

# 지금 도전할 스테이지 = 아직 안 깬 첫 스테이지 (전부 깼으면 마지막)
func _current_stage() -> int:
	for i in range(STAGES.size()):
		if not bool(cleared.get(i, false)):
			return i
	return STAGES.size() - 1

func _all_cleared() -> bool:
	for i in range(STAGES.size()):
		if not bool(cleared.get(i, false)):
			return false
	return true

# 스테이지 시작 — 독립 레벨이라 보드·거점·적을 전부 초기화하고 st만 갈아끼운다
func _start_stage(idx: int) -> void:
	stage_idx = clampi(idx, 0, STAGES.size() - 1)
	st = STAGES[stage_idx]
	mode = "play"
	_init_game()

func _init_game() -> void:
	board = []
	for _r in range(ROWS):
		var row_arr: Array = []
		for _c in range(COLS):
			row_arr.append("")
		board.append(row_arr)
	enemies = []
	core_hp = int(st["core_hp"])
	place_count = 0
	spawned = 0
	killed = 0
	leaked = 0
	score = 0
	combo = 0
	combo_miss = 0
	drought = 0
	game_over = false
	game_clear = false
	stuck = false
	flash_timer = 0.0
	flash_label = ""
	flash_lines = 0
	flash_combo = 0
	clear_cells = []
	clear_rows = []
	clear_cols = []
	clear_done = true
	charge_dur = CHARGE_BASE
	outline_timer = 0.0
	last_color = ""
	floaters = []
	death_flashes = []
	cell_pops = []
	debris = []
	impacts = []
	kill_pulse = 0.0
	push_streaks = []
	rockets = []
	hitstop = 0.0
	core_hits = []
	callout_text = ""
	callout_timer = 0.0
	seen_types = {}
	anim_t = 0.0
	red_flash = 0.0
	climax_flash = 0.0
	climax_pending = -1.0
	flash_climax = false
	shake_timer = 0.0
	resolving = false
	resolve_timer = 0.0
	resolve_total = 0.0
	resolve_hits = []
	resolve_rocket_plan = []
	resolve_fx_done = false
	pending_leaks = []
	pending_core_dead = false
	enemy_seq = 0
	tray = [{}, {}, {}]
	sel = 0
	_refill_tray()
	# 시작 시 적 몇 마리 배치 — 빈 보드에서 "ENEMIES ADVANCE IN N"이 어색하지 않게(전진 중인 전선처럼).
	var start_cols: Array = []
	for c in range(COLS):
		start_cols.append(c)
	start_cols.shuffle()
	_spawn_one(start_cols[0], "basic")    # 시작 적 1마리(row 0)
	if not _has_valid_placement():
		game_over = true
		stuck = true

# 진행도 가중 랜덤 조각 1개 생성 (초반 SMALL 편향, 후반 BIG 비중↑)
func _free_cells() -> int:
	var n: int = 0
	for r in range(ROWS):
		for c in range(COLS):
			if board[r][c] == "":
				n += 1
	return n

# 조각 크기 티어는 '보드 여유'에 연동한다 — 진행도가 아니라.
# 여유가 많으면 큰 조각(줄 완성 주력 = I5·직사각), 빡빡해지면 작은 조각으로 숨통.
# (구버전은 적 스폰 진행도에 묶여 있어 파편화된 보드에도 테트로미노를 퍼부었음 = 막힘사의 원인.)
#
# 단, 여유 연동을 너무 세게 걸면 반대로 과보호가 된다: 실측 f는 대부분 0.6~0.9인데
# 옛 계수(big은 f>0.62부터 최대 9%, mid는 상한 52%)로는 SMALL이 항상 40% 이상 깔려서
# 평균 조각이 3.56칸까지 내려갔고 3×3은 2%밖에 안 나왔다. 그 사이 막힘사는 300판 중 2~20판까지
# 줄어든 반면 패배의 대부분은 '적을 못 잡아서'(거점 함락)로 옮겨간 상태 → 조각을 키우는 게 곧 해법.
func _random_piece() -> Dictionary:
	var f: float = float(_free_cells()) / float(ROWS * COLS)
	var p_big: float = clampf((f - 0.50) / 0.35, 0.0, 1.0) * 0.16
	var p_mid: float = clampf((f - 0.25) / 0.30, 0.0, 1.0) * 0.60
	var r: float = randf()
	var tier: int = 0                      # 0=SMALL, 1=MID, 2=BIG
	if r < p_big:
		tier = 2
	elif r < p_big + p_mid:
		tier = 1
	# 빈칸 수(f)만으로는 '파편화'를 못 본다: 보드가 반이나 비었는데도 3×3·I5가 들어갈 자리가
	# 없는 상태가 실제 막힘사의 정체(사망 시 보드 점유 50%). 그래서 지금 보드에 놓을 자리가
	# 없는 조각은 아예 뽑지 않고, 티어가 통째로 안 맞으면 한 단계 작은 티어로 내린다.
	# 큰 조각일수록 여유 자리를 더 요구한다 — '딱 한 자리에만 간신히 맞는' 3×3을 쥐어주면
	# 그 자리를 다른 조각이 먼저 먹는 순간 死. 선택지가 남는 조각만 배급한다.
	# SMALL에는 1칸짜리가 있으니 빈칸이 하나라도 있으면 최소 하나는 반드시 맞는다.
	var need: Array = [1, 2, 4]            # SMALL / MID / BIG이 요구하는 최소 배치 가능 자리 수
	var pool: Array = []
	while tier >= 0:
		for t in _tier_pool(tier):
			if _piece_fits_at_least(PIECES[t], int(need[tier])):
				pool.append(t)
		if not pool.is_empty():
			break
		tier -= 1
	if pool.is_empty():
		pool = SMALL_POOL.duplicate()      # 보드가 꽉 참 — 어차피 다음 턴에 막힘 판정
	var ty: String = _weighted_pick(pool)
	var c: String = COLORS[randi() % COLORS.size()]
	return {"type": ty, "color": c, "offsets": (PIECES[ty] as Array).duplicate()}

func _tier_pool(tier: int) -> Array:
	match tier:
		2:
			return BIG_POOL
		1:
			return MID_POOL
		_:
			return SMALL_POOL

func _weighted_pick(pool: Array) -> String:
	var total: int = 0
	for t in pool:
		total += int(PIECE_W[t])
	var r: int = randi() % total
	for t in pool:
		r -= int(PIECE_W[t])
		if r < 0:
			return t
	return pool[pool.size() - 1]

# 이 조각을 지금 보드에 놓으면 줄이 완성되는 자리가 있나
func _would_clear(cells: Array) -> bool:
	var occ: Dictionary = {}
	for ci in cells:
		occ[ci] = true
	for r in range(ROWS):
		var full_r: bool = true
		for c in range(COLS):
			if board[r][c] == "" and not occ.has(Vector2i(c, r)):
				full_r = false
				break
		if full_r:
			return true
	for c2 in range(COLS):
		var full_c: bool = true
		for r2 in range(ROWS):
			if board[r2][c2] == "" and not occ.has(Vector2i(c2, r2)):
				full_c = false
				break
		if full_c:
			return true
	return false

# 이 조각을 지금 놓으면 완성될 줄 목록 (프리뷰 전용 — 그리기에서 프레임당 1회.
# _would_clear는 DDA가 조각마다 수백 번 부르는 뜨거운 경로라 조기반환을 유지하고 따로 둔다)
func _would_clear_lines(cells: Array) -> Dictionary:
	var occ: Dictionary = {}
	for ci in cells:
		occ[ci] = true
	var rows: Array = []
	var cols: Array = []
	for r in range(ROWS):
		var full_r: bool = true
		for c in range(COLS):
			if board[r][c] == "" and not occ.has(Vector2i(c, r)):
				full_r = false
				break
		if full_r:
			rows.append(r)
	for c2 in range(COLS):
		var full_c: bool = true
		for r2 in range(ROWS):
			if board[r2][c2] == "" and not occ.has(Vector2i(c2, r2)):
				full_c = false
				break
		if full_c:
			cols.append(c2)
	return {"rows": rows, "cols": cols}

# 이 조각을 놓아 '지금 당장' 줄을 완성할 수 있는 자리가 있나
func _piece_can_clear(offsets: Array) -> bool:
	for ar in range(ROWS):
		for ac in range(COLS):
			var cells: Array = []
			var ok: bool = true
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				var cc: Vector2i = Vector2i(ac + ov.x, ar + ov.y)
				if cc.x < 0 or cc.x >= COLS or cc.y < 0 or cc.y >= ROWS or board[cc.y][cc.x] != "":
					ok = false
					break
				cells.append(cc)
			if ok and _would_clear(cells):
				return true
	return false

# 플레이어 상태 → −1(고전) ~ +1(압도)
func _dda_score() -> float:
	var fill: float = 1.0 - float(_free_cells()) / float(ROWS * COLS)
	var hp: float = float(core_hp) / float(maxi(1, int(st["core_hp"])))
	var struggle: float = 0.0
	if fill > 0.6:
		struggle += 1.0          # 보드가 빡빡하다
	if drought >= 3:
		struggle += 1.0          # 줄이 안 터진 지 오래
	if hp < 0.4:
		struggle += 1.0          # 거점이 위험
	if int(fail_streak.get(stage_idx, 0)) >= DDA_GOD_FAILS:
		struggle += 2.0          # 갓 모드: 같은 스테이지를 연속으로 졌다 → 이탈 방지
	var mastery: float = 0.0
	if fill < 0.3:
		mastery += 1.0
	if combo >= 3:
		mastery += 1.0
	if hp > 0.8:
		mastery += 1.0
	return clampf((mastery - struggle) / 3.0, -1.0, 1.0)

# 후보 N개를 굴린 뒤, 플레이어 상태에 따라 '잘 맞는 것' ↔ '까다로운 것'을 고른다
func _make_piece() -> Dictionary:
	if not dda_enabled:
		return _random_piece()
	var d: float = _dda_score()
	var first: Dictionary = _random_piece()
	# 구제 전용: 고전 중일 때만 개입한다. ('압도 중 → 까다로운 조각'은 폐기 — 온보딩 막힘사만 3배)
	if d > -DDA_DEADZONE:
		return first
	# ⚠구제 = '지금 줄을 완성할 수 있는 조각'을 찾아주는 것뿐. 그 이상은 하지 않는다.
	#   '놓을 자리가 많은 조각'(=작은 조각)을 주면 막힘은 피하지만 줄을 못 만들어 공격이 굶는다.
	#   디펜스인 우리 게임에선 그게 곧 무장해제 → 실측 승률 28%→16%로 오히려 악화했음.
	#   Block Blast는 죽음의 원인이 막힘 하나뿐이라 그 구제가 통하지만, 우리는 실패 경로가 둘이다.
	if _piece_can_clear(first["offsets"]):
		return first
	for _i in range(DDA_CANDIDATES - 1):
		var cand: Dictionary = _random_piece()
		if _piece_can_clear(cand["offsets"]):
			return cand
	return first     # 줄을 낼 수 있는 후보가 없으면 개입하지 않음

# 트레이 중 하나라도 지금 보드에 놓을 수 있나
func _tray_any_placeable() -> bool:
	for i in range(3):
		if not tray[i].is_empty() and _piece_placeable(tray[i]["offsets"]):
			return true
	return false

# 3슬롯 전부 새 랜덤 조각으로 채움, sel=0 리셋.
# ⚠공정성: '받자마자 셋 다 못 놓는' 즉사(실측 막힘사망의 11~27%)는 플레이어 실수가 아니라 딜 사고.
#   최소 하나는 놓을 수 있는 트레이가 나올 때까지 다시 굴린다(막힘은 이제 '스스로 몰린 결과'로만).
func _refill_tray() -> void:
	for _attempt in range(24):
		for i in range(3):
			tray[i] = _make_piece()
		if _tray_any_placeable():
			break
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
	return _piece_fits_at_least(offsets, 1)

# 놓을 수 있는 자리가 n곳 이상인가 (n곳 찾으면 즉시 중단)
func _piece_fits_at_least(offsets: Array, n: int) -> bool:
	var found: int = 0
	for anchor_r in range(ROWS):
		for anchor_c in range(COLS):
			var cells: Array = []
			for o in offsets:
				var ov: Vector2i = o as Vector2i
				cells.append(Vector2i(anchor_c + ov.x, anchor_r + ov.y))
			if _can_place(cells):
				found += 1
				if found >= n:
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
# 시퀀스: ① 충전 홀드(색 통일→달아오름, 콤보 비례로 길어짐)
#      → ② 순차 파괴(한쪽 끝부터 셀이 차례로 부서짐)
#      → ③ 로켓 발사 → ④ 순차 피격 → (끝물) 누수.
# ①②가 없으면 조각을 놓는 순간 줄이 증발하고, 나머지 연출이 텅 빈 보드 위에서 재생된다
# (= 플레이어 행동의 보상이 화면에서 사라짐). 그래서 모든 전투 연출은 파괴가 끝난 뒤로 밀려 있다.
# COMBO 라벨도 파괴가 '다 끝난 뒤'에 뜬다 — 파괴와 텍스트를 겹치지 않게(Block Blast 원칙).

# 이번 폭발의 충전 홀드 = 콤보가 클수록 더 오래 참는다(에스컬레이션 = 시간)
func _charge_dur_for(streak: int) -> float:
	return minf(CHARGE_BASE + CHARGE_PER_COMBO * float(maxi(0, streak - 1)), CHARGE_MAX)

# 클리어(rows/cols) 결과를 미리 계획해 resolve 큐에 적재하고 시작
func _begin_resolve(rows: Array, cols: Array) -> void:
	resolving = true
	resolve_timer = 0.0
	resolve_hits = []
	resolve_rocket_plan = []
	resolve_fx_done = false

	var blast_len: float = 0.15
	var l: int = rows.size() + cols.size()
	if l > 0:
		# ① 충전(콤보 비례) → ② 충전이 끝나는 순간 전 셀이 '동시에' 소멸.
		charge_dur = _charge_dur_for(combo)
		var pend: Dictionary = {}
		for row in rows:
			for c in range(COLS):
				pend[Vector2i(c, row)] = true
		for col in cols:
			for r in range(ROWS):
				pend[Vector2i(col, r)] = true
		clear_cells = pend.keys()
		clear_rows = rows.duplicate()
		clear_cols = cols.duplicate()
		clear_tint = _color_of(last_color)
		clear_done = false
		# 블록이 사라지고 짧은 빈 줄을 거쳐 로켓(=빛 바)이 나간다
		var fire_t: float = charge_dur + BURST_GAP
		# ② 콤보=청소 범위: 완성 줄에서 매 콤보 '한 줄씩' 추가(총 레인 수 = combo).
		#    추가 방향은 바깥으로 교대(줄0 → +1 → −1 → +2…) = 완성 줄 중심 확산, 보드 밖은 스킵.
		#    링 = 추가 순서(0=완성 줄) → 한 줄씩 순차 발사(심지처럼 번지는 물결). 보드 셀 제거는 완성 줄만.
		var lanes_n: int = maxi(1, combo)
		var band_cols: Dictionary = {}   # col -> ring(추가 순서)
		for c in cols:
			var added: int = 0
			var k: int = 0
			while added < lanes_n and k < COLS * 2:
				var off: int = 0 if k == 0 else ((k + 1) / 2) * (1 if (k % 2) == 1 else -1)
				k += 1
				var cc: int = c + off
				if cc < 0 or cc >= COLS:
					continue
				if not band_cols.has(cc) or added < band_cols[cc]:
					band_cols[cc] = added
				added += 1
		var band_rows: Dictionary = {}   # row -> ring(추가 순서)
		for r in rows:
			var addedr: int = 0
			var kr: int = 0
			while addedr < lanes_n and kr < ROWS * 2:
				var offr: int = 0 if kr == 0 else ((kr + 1) / 2) * (1 if (kr % 2) == 1 else -1)
				kr += 1
				var rr: int = r + offr
				if rr < 0 or rr >= ROWS:
					continue
				if not band_rows.has(rr) or addedr < band_rows[rr]:
					band_rows[rr] = addedr
				addedr += 1
		var max_ring: int = 0            # 실제 존재하는 가장 바깥 링(물결 시각 길이 보장용)
		for v in band_cols.values():
			max_ring = maxi(max_ring, v)
		for v in band_rows.values():
			max_ring = maxi(max_ring, v)
		# 전멸(화면 전체 청소) = 콤보 임계 도달 or 밴드가 전 열/행 커버 → 순차 대신 '한 방 전멸'
		var full_board: bool = combo >= CLIMAX_COMBO or band_cols.size() >= COLS or band_rows.size() >= ROWS
		if full_board:
			# 전 열을 ring 0으로 채움 → 모든 적 동시 피격 + 세로 로켓 일제 발사
			band_cols.clear()
			band_rows.clear()
			for c2 in range(COLS):
				band_cols[c2] = 0
			max_ring = 0
			climax_pending = fire_t + 0.20   # 피격 착지에 맞춰 중앙 충격파 발사
		# 로켓 계획 — 파괴 물결이 끝난 직후(fire_t) 발사. 링 거리만큼 지연(0=먼저, 바깥 링일수록 늦게)
		for c in band_cols:
			resolve_rocket_plan.append({"dir": "col", "idx": c, "ring": band_cols[c], "launch": fire_t + 0.08 + float(band_cols[c]) * BLAST_RING_DELAY})
		for r in band_rows:
			resolve_rocket_plan.append({"dir": "row", "idx": r, "ring": band_rows[r], "launch": fire_t + 0.08 + float(band_rows[r]) * BLAST_RING_DELAY})
		# 일격량 (콤보 데미지 배수는 '탱커 관통용 부 증폭'으로 소폭 유지)
		var mult: float = _simul_mult(l) * _streak_mult(combo)
		var strike: int = roundi(LINE_BASE * mult)
		var kb: int = clampi(1 + int(combo / 3), 1, 3)
		# ③ 로켓 피격: 밴드가 지나는 적별 (열밴드+행밴드 교차=배수). 적의 링=가장 안쪽 밴드
		var hit_list: Array = []
		for e in enemies:
			var lines: int = 0
			var ering: int = 999
			if band_cols.has(e["col"]):
				lines += 1
				ering = mini(ering, band_cols[e["col"]])
			if band_rows.has(e["row"]):
				lines += 1
				ering = mini(ering, band_rows[e["row"]])
			if lines > 0:
				hit_list.append({"id": e["id"], "row": e["row"], "dmg": strike * lines, "kb": kb, "ring": ering})
		# 링 오름차순(안→밖 물결) → 같은 링 내에선 거점 가까운 순(row 큰 순)
		hit_list.sort_custom(func(a, b):
			if a["ring"] != b["ring"]:
				return a["ring"] < b["ring"]
			return a["row"] > b["row"])
		var t0: float = fire_t + 0.22
		var ring_seen: Dictionary = {}   # ring -> 이미 배치한 수(링 내 소폭 스태거)
		var max_at: float = t0
		for k in range(hit_list.size()):
			var ring: int = hit_list[k]["ring"]
			var within: int = ring_seen.get(ring, 0)
			ring_seen[ring] = within + 1
			var at: float = t0 + float(ring) * BLAST_RING_DELAY + float(within) * 0.04
			max_at = maxf(max_at, at)
			resolve_hits.append({
				"id": hit_list[k]["id"], "dmg": hit_list[k]["dmg"], "kb": hit_list[k]["kb"],
				"at": at, "done": false,
			})
		# 총길이 = 마지막 피격 or 마지막 링 로켓 비행 완료 중 늦은 것(바깥 링에 적 없어도 물결 끝까지 재생)
		var visual_end: float = fire_t + 0.08 + float(max_ring) * BLAST_RING_DELAY + ROCKET_DUR + 0.08
		blast_len = clampf(maxf(max_at + 0.28, visual_end), fire_t + 0.30, fire_t + 3.2)
		if full_board:
			blast_len = maxf(blast_len, fire_t + 1.35)   # 전멸은 세계 이동 전에 충격파가 충분히 breathe
		# COMBO xN 라벨용 (중앙 큰 숫자는 제거, 라벨만).
		# flash_timer는 여기서 켜지 않는다 — 블록이 실제로 소멸하는 순간(_burst_lines)에 켠다.
		# 충전 중에 미리 번쩍이면 원인 없는 섬광이 된다.
		flash_lines = l
		flash_combo = combo
		flash_climax = full_board
		flash_label = "" if full_board else _line_label(l)   # 전멸은 텍스트 없이 연출만

	# 공격만 재생. 적 이동·누수·스폰은 시퀀스가 끝난 뒤 _end_turn에서.
	resolve_total = blast_len

# ② 순차 파괴 — 차례가 된 셀만 부순다. 셀 하나가 board에서 사라지고 그 자리에 사각 팝 + 파편.
# 파편 색은 clear_tint(= 방금 놓은 조각 색) — 폭발이 '내 조각의 결과'임을 색으로 잇는다.
func _burst_lines() -> void:
	if clear_done:
		return
	clear_done = true
	for ci in clear_cells:
		var cc: Vector2i = ci as Vector2i
		board[cc.y][cc.x] = ""
		var p: Vector2 = _cell_center(cc.x, cc.y)
		cell_pops.append({"pos": p, "life": 0.16, "max": 0.16, "color": clear_tint})
		for _n in range(3):
			var ang: float = randf() * TAU
			var spd: float = randf_range(60.0, 170.0)
			var life: float = randf_range(0.22, 0.40)
			debris.append({
				"pos": p, "vel": Vector2(cos(ang), sin(ang)) * spd,
				"life": life, "max": life, "color": clear_tint, "size": randf_range(4.0, 8.0),
			})
	clear_cells = []
	outline_timer = LINE_OUTLINE_DUR   # ④ 줄 자리에 남는 색 테두리 잔상
	# 보상 텍스트(COMBO xN)와 섬광은 파괴 순간에. 파괴가 이제 한순간이라 겹치지 않는다.
	flash_timer = FLASH_DUR
	hitstop = maxf(hitstop, 0.05)

# 전멸(화면 전체 청소) 클라이맥스 — 보드 중앙에서 퍼지는 큰 충격파 + 골드 섬광 + 히트스톱(셰이크 없음)
func _fire_climax() -> void:
	var ctr: Vector2 = Vector2(BOARD_X + COLS * CELL * 0.5, BOARD_Y + ROWS * CELL * 0.5)
	climax_flash = CLIMAX_FLASH_DUR
	hitstop = maxf(hitstop, 0.12)
	impacts.append({"pos": ctr, "life": 1.0, "max": 1.0, "color": Color(1.0, 0.97, 0.65), "radius": CELL * 1.6, "star": true})
	impacts.append({"pos": ctr, "life": 0.85, "max": 0.85, "color": Color(1.0, 0.82, 0.32), "radius": CELL * 2.8, "star": false})
	impacts.append({"pos": ctr, "life": 0.7, "max": 0.7, "color": Color(1.0, 1.0, 0.92), "radius": CELL * 3.8, "star": false})

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

# 공격 시퀀스 종료 → 그 다음에 세계가 움직인다(적 이동·누수·스폰) → 판정
func _finish_resolve() -> void:
	resolving = false
	resolve_hits = []
	if not clear_done:
		_burst_lines()   # 안전망: 어떤 경로로든 안 터졌으면 여기서라도 셀을 비운다(보드 정합성)
	_end_turn()

# 턴 마무리: 적 전진/누수/스폰 → 누수 연출 → 승/패/공간부족 판정
# (공격이 있었으면 그 뒤에, 없었으면 배치 직후에 호출)
func _end_turn() -> void:
	advance_step()          # 적 이동(step_every 주기)·누수(거점 피해)·스폰
	_reveal_leaks()         # 누수 연출은 공격 뒤에 재생 (자기 감쇠 → 데드락 없음)
	_check_win()
	if pending_core_dead:
		game_over = true
		pending_core_dead = false
		fail_streak[stage_idx] = int(fail_streak.get(stage_idx, 0)) + 1   # 연속 실패 → 갓 모드 근접
		return
	if not game_clear and not _has_valid_placement():
		game_over = true
		stuck = true
		fail_streak[stage_idx] = int(fail_streak.get(stage_idx, 0)) + 1

# ===== 스텝 진행 =====
func advance_step() -> void:
	place_count += 1
	# 전진 스로틀: step_every 배치마다 1칸 (fast는 스테이지 주기의 절반 = 2배 빠름)
	for e in enemies:
		var step_every: int = e.get("step_every", int(st["step_every"]))
		if place_count % step_every == 0:
			e["row"] += 1

	# 누수(거점 도달): 로직은 즉시 반영, 시각 연출은 resolve 끝물로 지연.
	# ⚠누수는 killed가 아니라 leaked로 센다. (구버전은 killed++ 해서 '흘려보내도 목표 진행'
	#  = 진행도·승리조건이 못 막은 적한테 보상을 줬음.)
	var i: int = enemies.size() - 1
	pending_leaks = []
	while i >= 0:
		if enemies[i]["row"] >= ROWS:
			core_hp -= 1
			leaked += 1
			pending_leaks.append(enemies[i]["col"])
			enemies.remove_at(i)
		i -= 1
	pending_core_dead = core_hp <= 0
	if pending_core_dead:
		return   # 거점 파괴 스텝: 블라스트 없이 누수 연출 후 게임오버

	# 스폰 스로틀: spawn_every 배치마다 1회
	if place_count % int(st["spawn_every"]) != 0:
		return
	var total: int = int(st["total"])
	if spawned >= total:
		return
	var etype: String = "basic" if spawned < int(st["onboard"]) else _pick_etype()
	if etype == "swarm":
		# 클러스터 3~4마리. ⚠인접 열에 '나란히' 스폰하면 전원이 같은 row에 영원히 머물러
		#   가로줄 하나로 통째 전멸 = 가장 싸게 잡히는 적이 됨(설계 의도의 정반대, 실측 확인).
		#   → ① 열을 보드 전체에 흩고 ② 전진 주기를 멤버마다 엇갈려(desync) 행까지 벌어지게 한다.
		#   결과: 한 줄로는 못 쓸어내고 콤보 레인(범위)이 실제로 필요해짐 = '무리'의 정체성.
		var count: int = 3 + (randi() % 2)
		count = mini(count, total - spawned)
		count = mini(count, COLS)
		var pool: Array = []
		for c in range(COLS):
			pool.append(c)
		pool.shuffle()
		var base_step: int = int(st["step_every"])
		for k in range(count):
			# 절반은 한 칸 빠르게 → 몇 스텝 뒤엔 행이 서로 벌어진다(압박은 유지)
			var sstep: int = maxi(1, base_step - 1) if k % 2 == 0 else base_step
			_spawn_one(int(pool[k]), "swarm", sstep)
	else:
		_spawn_one(randi() % COLS, etype)

# 가중 랜덤 타입 선택
func _pick_etype() -> String:
	var w: Dictionary = st["weights"]
	var total: int = 0
	for t in ENEMY_TYPES:
		total += int(w[t])
	if total <= 0:
		return "basic"
	var r: int = randi() % total
	for t in ENEMY_TYPES:
		r -= int(w[t])
		if r < 0:
			return t
	return "basic"

# 적 1마리 스폰 (타입별 HP 배율 적용). step_override>0이면 전진 주기를 강제(무리 desync용)
func _spawn_one(col: int, etype: String, step_override: int = 0) -> void:
	var base: int = roundi(float(st["base_hp"]) + float(spawned) * float(st["hp_ramp"]))
	var hp: int = base
	match etype:
		"fast":
			hp = roundi(base * 0.6)
		"tank":
			hp = roundi(base * float(st["tank_mult"]))   # 콤보2~3 구간에 앉히는 게 목적(관통 요구)
		"swarm":
			hp = roundi(base * 0.4)
	hp = maxi(1, hp)
	# 전진 스로틀: fast는 스테이지 주기의 절반(2배 빠름), 나머지는 스테이지 주기
	var base_step: int = int(st["step_every"])
	var step_every: int = maxi(1, base_step - 1) if etype == "fast" else base_step
	if step_override > 0:
		step_every = step_override
	enemies.append({"col": col, "row": 0, "vis_row": 0.0, "hp": hp, "maxhp": hp, "etype": etype, "id": enemy_seq, "step_every": step_every})
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

# 클리어 = 모든 적이 '처리'됨(처치 or 누수) = 더 이상 올 적도, 보드 위 적도 없음.
# 누수분은 거점 HP로 이미 값을 치렀고, core_hp를 total보다 훨씬 작게 잡아 '흘려보내며 이기기'를 봉쇄한다(기준 ③).
func _check_win() -> void:
	if killed + leaked >= int(st["total"]):
		game_clear = true
		cleared[stage_idx] = true
		fail_streak[stage_idx] = 0     # 깼으니 갓 모드 해제


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
	last_color = active["color"]   # 색 통일용: 터질 줄이 이 색으로 물든다
	# 조각 소비: 트레이 슬롯 비우고 다음 슬롯/리필 (즉시 = 피드백)
	_consume_slot()
	# 완성 줄 감지 — 적은 아직 "현재 위치"(이동 전). 로켓이 그 자리 적을 먼저 타격.
	var rows: Array = _full_rows()
	var cols: Array = _full_cols()
	if rows.size() + cols.size() > 0:
		combo += 1
		combo_miss = 0
		drought = 0
		_begin_resolve(rows, cols)   # 공격 재생 → 끝나면 _finish_resolve→_end_turn
	else:
		# 헛수 1회는 유예(COMBO_GRACE) — 연속으로 더 놓치면 그때 스트릭이 끊긴다
		combo_miss += 1
		drought += 1
		if combo_miss > COMBO_GRACE:
			combo = 0
			combo_miss = 0
		_end_turn()                  # 공격 없음: 곧장 적 이동·누수·판정

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
	# ── 레벨 선택 화면 ──
	if mode == "select":
		if event is InputEventMouseMotion:
			var mp: Vector2 = (event as InputEventMouseMotion).position
			hover_stage = _stage_at(mp)
			_play_hover = PLAY_BTN.has_point(mp)
		elif event is InputEventMouseButton:
			var sm: InputEventMouseButton = event as InputEventMouseButton
			if sm.pressed and sm.button_index == MOUSE_BUTTON_LEFT:
				if PLAY_BTN.has_point(sm.position):
					_start_stage(_current_stage())      # 하단 큰 버튼 = 지금 도전할 스테이지
				else:
					var hit: int = _stage_at(sm.position)   # 이미 깬 스테이지 재도전(잠긴 건 -1)
					if hit >= 0:
						_start_stage(hit)
		elif event is InputEventKey:
			var sk: InputEventKey = event as InputEventKey
			if sk.pressed and (sk.keycode == KEY_SPACE or sk.keycode == KEY_ENTER):
				_start_stage(_current_stage())
			elif sk.pressed and sk.keycode >= KEY_1 and sk.keycode < KEY_1 + STAGES.size():
				var pick: int = sk.keycode - KEY_1
				if _is_unlocked(pick):
					_start_stage(pick)
		return

	# ── 결과 화면: 재시도(SPACE/클릭) or 스테이지 선택으로(ESC) ──
	if game_over or game_clear:
		if event is InputEventMouseButton:
			var mbe: InputEventMouseButton = event as InputEventMouseButton
			if mbe.pressed:
				mode = "select"
		elif event is InputEventKey:
			var ke: InputEventKey = event as InputEventKey
			if ke.pressed and ke.keycode == KEY_SPACE:
				# 클리어면 다음 스테이지로(선형 진행), 실패면 같은 스테이지 재시도
				if game_clear and stage_idx + 1 < STAGES.size():
					_start_stage(stage_idx + 1)
				elif game_clear:
					mode = "select"          # 마지막 스테이지 클리어 → 홈
				else:
					_start_stage(stage_idx)
			elif ke.pressed and ke.keycode == KEY_ESCAPE:
				mode = "select"
		return

	if event is InputEventKey:
		var pk: InputEventKey = event as InputEventKey
		if pk.pressed and pk.keycode == KEY_ESCAPE:
			mode = "select"      # 플레이 중 포기 → 선택 화면
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
	if mode == "select":
		queue_redraw()
		return
	# 히트스톱: 게임 타이머 전부 정지, 그림만(시간감소라 항상 해제 → 데드락 없음)
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - delta)
		queue_redraw()
		return

	# 전투 순차 연출 진행 (타이머는 항상 0으로 수렴 → 데드락 없음)
	if resolving:
		resolve_timer += delta
		# ② 충전 끝 → 전 셀이 동시에 소멸. 로켓은 짧은 빈 줄(BURST_GAP) 뒤에 나간다.
		if not clear_done and resolve_timer >= charge_dur:
			_burst_lines()
		# ③ 로켓 발사 — 링 거리만큼 지연(안쪽 링 먼저, 바깥으로 퍼짐). 발사 지점에 머즐 플래시
		for rp in resolve_rocket_plan:
			if not rp.get("launched", false) and resolve_timer >= rp["launch"]:
				rp["launched"] = true
				rockets.append({"dir": rp["dir"], "idx": rp["idx"], "t": 0.0, "dur": ROCKET_DUR, "combo": flash_combo})
				_spawn_muzzle(rp["dir"], rp["idx"])
		for h in resolve_hits:
			if not h["done"] and resolve_timer >= h["at"]:
				h["done"] = true
				_apply_hit(h)
		# 전멸 충격파 발사(예약 시각 도달 시 1회)
		if climax_pending >= 0.0 and resolve_timer >= climax_pending:
			climax_pending = -1.0
			_fire_climax()
		if resolve_timer >= resolve_total:
			_finish_resolve()

	if flash_timer > 0.0:
		flash_timer = maxf(0.0, flash_timer - delta)
	if outline_timer > 0.0:
		outline_timer = maxf(0.0, outline_timer - delta)
	if red_flash > 0.0:
		red_flash = maxf(0.0, red_flash - delta)
	if climax_flash > 0.0:
		climax_flash = maxf(0.0, climax_flash - delta)
	if shake_timer > 0.0:
		shake_timer = maxf(0.0, shake_timer - delta)
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
	var cp: int = cell_pops.size() - 1
	while cp >= 0:
		cell_pops[cp]["life"] -= delta
		if cell_pops[cp]["life"] <= 0.0:
			cell_pops.remove_at(cp)
		cp -= 1
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
	# 적 flinch 감쇠 + 전진/넉백 표시(vis_row) 부드럽게 이징
	for e in enemies:
		if e.get("flinch", 0.0) > 0.0:
			e["flinch"] = maxf(0.0, e["flinch"] - delta)
		var vr: float = e.get("vis_row", float(e["row"]))
		e["vis_row"] = move_toward(vr, float(e["row"]), SLIDE_SPEED * delta)
	queue_redraw()

# ===== 그리기 =====
func _draw() -> void:
	var fnt: Font = _font if _font != null else ThemeDB.fallback_font

	if mode == "select":
		_draw_select(fnt)
		return

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

	# 블록 소멸 팝 — 사각형이 부풀며 페이드(적 사망의 원형 팝과 형태로 구분: 네모=블록, 원=적)
	for cpop in cell_pops:
		var pp: float = clampf(cpop["life"] / cpop["max"], 0.0, 1.0)   # 1→0
		var pinv: float = 1.0 - pp
		var psz: float = CELL * (0.86 + 0.75 * pinv)
		var pc: Color = cpop["color"]
		var ppos: Vector2 = cpop["pos"]
		var prect: Rect2 = Rect2(ppos - Vector2(psz, psz) * 0.5, Vector2(psz, psz))
		draw_rect(prect, Color(pc.r, pc.g, pc.b, pp * 0.55))
		draw_rect(prect, Color(1.0, 1.0, 1.0, pp * pp * 0.85), false, 3.0)

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

	if climax_flash > 0.0:
		var cf: float = climax_flash / CLIMAX_FLASH_DUR
		draw_rect(Rect2(0, 0, 800, 1000), Color(1.0, 0.9, 0.55, cf * 0.42))
	if flash_timer > 0.0:
		var t: float = flash_timer / FLASH_DUR
		# 콤보↑ = 더 밝고 뜨거운 섬광(흰색→따뜻한 주황)
		var fint: float = 0.14 + 0.05 * float(mini(flash_combo, 6))
		var fcol: Color = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.68, 0.28), clampf(float(flash_combo - 2) / 5.0, 0.0, 1.0))
		draw_rect(Rect2(0, 0, 800, 1000), Color(fcol.r, fcol.g, fcol.b, t * fint))
		if flash_combo >= 2:
			var cs: String = "COMBO x%d" % flash_combo
			var cbase: int = 44 + mini(flash_combo, 8) * 8
			var csz: int = cbase + int(t * 14.0)
			var cw: float = fnt.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x
			var hot: float = clampf(float(flash_combo - 2) / 6.0, 0.0, 1.0)   # 콤보↑ = 골드→핫오렌지
			var ccol: Color = Color(1.0, 0.82, 0.1, t).lerp(Color(1.0, 0.4, 0.08, t), hot)
			_draw_text_outlined(fnt, Vector2(400.0 - cw * 0.5, 402.0), cs, csz, ccol)
		if flash_label != "":
			var ls: int = 96 if flash_climax else 40 + flash_lines * 6
			var lcol: Color = Color(1.0, 0.95, 0.5, t) if flash_climax else Color(1.0, 0.85, 0.1, t)
			var lw: float = fnt.get_string_size(flash_label, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
			_draw_text_outlined(fnt, Vector2(400.0 - lw * 0.5, 458.0), flash_label, ls, lcol)

	# 첫 등장 콜아웃 배너 (상단-중앙, 보드 위에 얹힘)
	if callout_timer > 0.0 and not game_over and not game_clear:
		var ca: float = clampf(callout_timer / 0.4, 0.0, 1.0)   # 마지막 0.4s 페이드
		var cow: float = fnt.get_string_size(callout_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		var cbx: float = 400.0 - cow * 0.5
		draw_rect(Rect2(cbx - 16.0, 150.0, cow + 32.0, 46.0), Color(0.05, 0.02, 0.08, 0.62 * ca))
		_draw_text_outlined(fnt, Vector2(cbx, 183.0), callout_text, 32, Color(1.0, 0.9, 0.4, ca))

	if game_over or game_clear:
		draw_rect(Rect2(0, 0, 800, 1000), Color(0.0, 0.0, 0.0, 0.72))
		var msg: String = "스테이지 클리어!" if game_clear else "실패"
		var mfs: int = 72
		var mw: float = fnt.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
		_draw_text_outlined(fnt, Vector2(400.0 - mw * 0.5, 420.0), msg, mfs,
				C_GOLD if game_clear else Color.WHITE)
		var sname: String = "%d. %s" % [stage_idx + 1, String(st["name"])]
		var snw: float = fnt.get_string_size(sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_draw_text_outlined(fnt, Vector2(400.0 - snw * 0.5, 460.0), sname, 26, Color(0.75, 0.77, 0.88))
		if game_over:
			var reason: String = "놓을 곳이 없다" if stuck else "거점 파괴"
			var rw: float = fnt.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			_draw_text_outlined(fnt, Vector2(400.0 - rw * 0.5, 506.0), reason, 30, Color(1.0, 0.5, 0.5))
		else:
			# 클리어 품질 = 얼마나 안 흘렸나 (누수 0 = 완봉)
			var res: String = "완봉 — 한 마리도 놓치지 않았다" if leaked == 0 else "처치 %d · 누수 %d" % [killed, leaked]
			var rw2: float = fnt.get_string_size(res, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			_draw_text_outlined(fnt, Vector2(400.0 - rw2 * 0.5, 506.0), res, 22,
					Color(0.45, 0.9, 0.6) if leaked == 0 else Color(0.85, 0.7, 0.5))
		var sub: String = "SPACE 다시 · 클릭/ESC 홈"
		if game_clear:
			sub = "SPACE 다음 스테이지 · 클릭/ESC 홈" if stage_idx + 1 < STAGES.size() else "SPACE·클릭 홈"
		var sw: float = fnt.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		_draw_text_outlined(fnt, Vector2(400.0 - sw * 0.5, 566.0), sub, 24, Color(0.75, 0.75, 0.75))

# ===== 홈(스테이지) 화면 =====
# Toon Blast식: 위쪽은 진행 상황(스테이지 목록·잠금), 시선의 착지점은 하단의 큰 시작 버튼.
const SEL_X: float = 140.0
const SEL_W: float = 520.0
const SEL_Y0: float = 232.0
const SEL_H: float = 76.0
const SEL_GAP: float = 12.0
const PLAY_BTN: Rect2 = Rect2(150.0, 742.0, 500.0, 126.0)

func _stage_rect(i: int) -> Rect2:
	return Rect2(SEL_X, SEL_Y0 + float(i) * (SEL_H + SEL_GAP), SEL_W, SEL_H)

# 잠긴 스테이지는 클릭 대상이 아니다(선형 진행)
func _stage_at(pos: Vector2) -> int:
	for i in range(STAGES.size()):
		if _stage_rect(i).has_point(pos) and _is_unlocked(i):
			return i
	return -1

func _draw_select(fnt: Font) -> void:
	draw_rect(Rect2(-20, -20, 840, 1040), C_BG)

	var title: String = "CASCADE"
	var tw: float = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x
	_draw_text_outlined(fnt, Vector2(400.0 - tw * 0.5, 122.0), title, 60, C_GOLD)
	var done_n: int = 0
	for i in range(STAGES.size()):
		if bool(cleared.get(i, false)):
			done_n += 1
	var sub: String = "클리어 %d / %d" % [done_n, STAGES.size()]
	var sw: float = fnt.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_draw_text_outlined(fnt, Vector2(400.0 - sw * 0.5, 166.0), sub, 22, Color(0.7, 0.72, 0.85))

	var cur: int = _current_stage()
	for i in range(STAGES.size()):
		var sd: Dictionary = STAGES[i]
		var r: Rect2 = _stage_rect(i)
		var done: bool = bool(cleared.get(i, false))
		var open: bool = _is_unlocked(i)
		var hot: bool = (i == hover_stage) and open
		var accent: Color = Color(0.28, 0.29, 0.36)          # 잠김
		if done:
			accent = Color(0.35, 0.8, 0.5)
		elif open:
			accent = C_GOLD if i == cur else Color(0.45, 0.5, 0.68)
		if hot:
			accent = C_GOLD
		draw_rect(r, Color(0.17, 0.17, 0.25) if hot else (Color(0.13, 0.13, 0.2) if open else Color(0.09, 0.09, 0.13)))
		draw_rect(r, accent, false, 3.0)

		# 번호 뱃지 (잠김이면 자물쇠)
		var bx: float = r.position.x + 30.0
		var by: float = r.position.y + SEL_H * 0.5
		draw_circle(Vector2(bx, by), 20.0, accent)
		if open:
			var nstr: String = str(i + 1)
			var nw: float = fnt.get_string_size(nstr, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			_draw_text_outlined(fnt, Vector2(bx - nw * 0.5, by + 8.0), nstr, 24, Color(0.08, 0.08, 0.12))
		else:
			_draw_lock(Vector2(bx, by), 18.0, Color(0.55, 0.57, 0.66))

		# 이름 + 태그. 잠김이면 내용은 숨기고 해금 조건만 (다음 목표를 명확히)
		var nx: float = r.position.x + 64.0
		var name_col: Color = Color.WHITE if open else Color(0.45, 0.46, 0.55)
		_draw_text_outlined(fnt, Vector2(nx, r.position.y + 32.0), String(sd["name"]), 24, name_col)
		var line2: String = String(sd["tag"]) if open else "%d 스테이지를 클리어하면 열림" % i
		_draw_text_outlined(fnt, Vector2(nx, r.position.y + 56.0), line2, 15,
				Color(0.68, 0.7, 0.82) if open else Color(0.4, 0.41, 0.5))

		if done:
			var ck: String = "클리어"
			var cw: float = fnt.get_string_size(ck, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			_draw_text_outlined(fnt, Vector2(r.position.x + SEL_W - cw - 16.0, r.position.y + 46.0), ck, 16, Color(0.4, 0.9, 0.58))

	_draw_play_button(fnt, cur)

	var hint: String = "SPACE 또는 버튼 클릭"
	var hw: float = fnt.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_draw_text_outlined(fnt, Vector2(400.0 - hw * 0.5, 902.0), hint, 17, Color(0.5, 0.52, 0.62))

# 하단 큰 시작 버튼 — 지금 도전할 스테이지를 크게 적는다(Toon Blast의 "Level N" 버튼)
func _draw_play_button(fnt: Font, cur: int) -> void:
	var hot: bool = _play_hover
	var r: Rect2 = PLAY_BTN
	# 입체감: 아래 그림자 → 본체 → 상단 하이라이트
	draw_rect(Rect2(r.position.x, r.position.y + 8.0, r.size.x, r.size.y), Color(0.10, 0.28, 0.14))
	var base: Color = Color(0.42, 0.82, 0.32) if hot else Color(0.34, 0.72, 0.26)
	draw_rect(r, base)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.32), Color(1.0, 1.0, 1.0, 0.16))
	draw_rect(r, Color(0.16, 0.42, 0.18), false, 4.0)

	var sd: Dictionary = STAGES[cur]
	var big: String = "스테이지 %d" % (cur + 1)
	var bfs: int = 46
	var bw: float = fnt.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
	_draw_text_outlined(fnt, Vector2(400.0 - bw * 0.5, r.position.y + 62.0), big, bfs, Color.WHITE,
			Color(0.10, 0.28, 0.14, 0.95))
	var nm: String = "전부 클리어! 다시 도전" if _all_cleared() else String(sd["name"])
	var nfs: int = 22
	var nw: float = fnt.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	_draw_text_outlined(fnt, Vector2(400.0 - nw * 0.5, r.position.y + 98.0), nm, nfs, Color(0.92, 1.0, 0.88),
			Color(0.10, 0.28, 0.14, 0.95))

# 자물쇠 아이콘(절차적) — 잠긴 스테이지 표시
func _draw_lock(c: Vector2, s: float, col: Color) -> void:
	draw_arc(Vector2(c.x, c.y - s * 0.18), s * 0.30, PI, TAU, 12, col, 3.0)
	draw_rect(Rect2(c.x - s * 0.40, c.y - s * 0.10, s * 0.80, s * 0.62), col)

# 상단 카드 패널(Toon Blast식) — 배경 + 강조 테두리
func _draw_card(r: Rect2, accent: Color) -> void:
	draw_rect(r, Color(0.14, 0.14, 0.21))
	draw_rect(r, accent, false, 3.0)

# 간단한 적 토큰 아이콘 — 붉은 사각 + 눈 2개(아트 전 임시)
func _draw_enemy_icon(center: Vector2, s: float) -> void:
	# 목표=밀려오는 적 전부 처치(타입 무관, 못 없애면 거점 hp↓). 특정 타입 대신
	# 타입 중립 "처치 대상" 기호=해골로 그린다. 뼈색+어두운 눈·코·이빨.
	var bone: Color = Color(0.93, 0.9, 0.82)
	var dark: Color = Color(0.14, 0.11, 0.1)
	var cx: float = center.x
	var cy: float = center.y
	# 아래턱(뼈색 사각) + 두개골(뼈색 원)
	draw_rect(Rect2(cx - s * 0.24, cy + s * 0.08, s * 0.48, s * 0.32), bone)
	draw_circle(Vector2(cx, cy - s * 0.06), s * 0.42, bone)
	draw_arc(Vector2(cx, cy - s * 0.06), s * 0.42, PI * 0.15, PI * 0.85, 20, Color(0.55, 0.5, 0.42), 1.5)
	# 눈구멍(비스듬한 사각으로 성난 느낌)
	var eye: float = s * 0.17
	draw_circle(Vector2(cx - s * 0.19, cy - s * 0.04), eye, dark)
	draw_circle(Vector2(cx + s * 0.19, cy - s * 0.04), eye, dark)
	# 코(작은 삼각) + 이빨(세로 분절)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy + s * 0.06),
		Vector2(cx - s * 0.06, cy + s * 0.17),
		Vector2(cx + s * 0.06, cy + s * 0.17),
	]), dark)
	for i in range(3):
		var tx: float = cx - s * 0.16 + float(i) * s * 0.16
		draw_rect(Rect2(tx - s * 0.015, cy + s * 0.22, s * 0.03, s * 0.16), dark)

func _draw_hud(fnt: Font) -> void:
	draw_rect(Rect2(0, 0, 800, 144), C_HUD)
	# CORE HP는 보드 하단 방어선(_draw_core)에만 표시 — 상단 중복 제거.
	if combo >= 2:
		# 유예 중(헛수 1회)이면 경고색으로만 — 다음 헛수에 끊긴다는 신호(텍스트는 안 붙임)
		var risky: bool = combo_miss > 0
		var streak: String = "콤보 x%d" % combo
		var stw: float = fnt.get_string_size(streak, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var scol: Color = Color(1.0, 0.45, 0.3) if risky else C_GOLD
		_draw_text_outlined(fnt, Vector2(788.0 - stw, 26.0), streak, 22, scol)

	var step_every: int = int(st["step_every"])
	var remain: int = step_every - (place_count % step_every)
	var imminent: bool = remain <= 1
	# 남은 적 = 아직 처리 안 된 적(스폰 예정 + 보드 위). 누수분은 '더 이상 안 오니' 빠지지만
	# 그 대가는 거점 HP로 이미 치렀다.
	var remaining: int = int(st["total"]) - killed - leaked
	var kp: float = clampf(kill_pulse / 0.35, 0.0, 1.0)

	# ── 두 카드: GOAL(남은 적=클리어 목표) + ADVANCE(적 전진 시계) ──
	var box_y: float = 14.0
	var box_h: float = 84.0
	var gw: float = 250.0
	var aw: float = 190.0
	var gap: float = 24.0
	var start_x: float = (800.0 - (gw + aw + gap)) * 0.5
	var goal_r: Rect2 = Rect2(start_x, box_y, gw, box_h)
	var adv_r: Rect2 = Rect2(start_x + gw + gap, box_y, aw, box_h)

	# GOAL 카드 — 제목 "목표" + 내용 "💀 남은 적 N"(전 타입 소탕이 목표라 타입 중립 해골).
	_draw_card(goal_r, Color(0.85, 0.7, 0.3))
	var gt_w: float = fnt.get_string_size("목표", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - gt_w * 0.5, box_y + 24.0), "목표", 16, Color(0.95, 0.85, 0.5))
	var rem_str: String = str(remaining)
	var rem_fs: int = 40
	var cap_fs: int = 18
	var icon_s: float = 34.0
	var cap_w: float = fnt.get_string_size("남은 적", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	var rem_w: float = fnt.get_string_size(rem_str, HORIZONTAL_ALIGNMENT_LEFT, -1, rem_fs).x
	var grp_w: float = icon_s + 8.0 + cap_w + 8.0 + rem_w
	var grp_l: float = goal_r.position.x + gw * 0.5 - grp_w * 0.5
	_draw_enemy_icon(Vector2(grp_l + icon_s * 0.5, box_y + 56.0), icon_s)
	_draw_text_outlined(fnt, Vector2(grp_l + icon_s + 8.0, box_y + 62.0), "남은 적", cap_fs, Color(0.95, 0.85, 0.5))
	var rem_col: Color = Color.WHITE.lerp(C_GOLD, kp)
	_draw_text_outlined(fnt, Vector2(grp_l + icon_s + 8.0 + cap_w + 8.0, box_y + 70.0), rem_str, rem_fs, rem_col)

	# ADVANCE 카드 — 적 전진 카운트다운(임박 시 붉은 강조). 제목·숫자 중앙정렬
	var acc: Color = Color(0.85, 0.3, 0.28) if imminent else Color(0.4, 0.45, 0.6)
	_draw_card(adv_r, acc)
	var adv_tc: Color = Color(1.0, 0.6, 0.5) if imminent else Color(0.72, 0.74, 0.86)
	var at_w: float = fnt.get_string_size("적 이동", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_draw_text_outlined(fnt, Vector2(adv_r.position.x + aw * 0.5 - at_w * 0.5, box_y + 24.0), "적 이동", 16, adv_tc)
	# 큰 숫자 + 작은 "턴" 을 한 덩어리로 중앙 정렬
	var n_str: String = str(remain)
	var n_fs: int = 44
	var u_fs: int = 18
	var n_col: Color = Color(1.0, 0.55, 0.3) if imminent else Color(0.9, 0.9, 0.95)
	var n_w: float = fnt.get_string_size(n_str, HORIZONTAL_ALIGNMENT_LEFT, -1, n_fs).x
	var u_w: float = fnt.get_string_size("턴", HORIZONTAL_ALIGNMENT_LEFT, -1, u_fs).x
	var grp_x: float = adv_r.position.x + aw * 0.5 - (n_w + 4.0 + u_w) * 0.5
	_draw_text_outlined(fnt, Vector2(grp_x, box_y + 72.0), n_str, n_fs, n_col)
	_draw_text_outlined(fnt, Vector2(grp_x + n_w + 4.0, box_y + 72.0), "턴", u_fs, Color(0.72, 0.72, 0.8))

	# ── 진행바(스타바 대응): 처치 진행도 ──
	var bx: float = start_x
	var by: float = box_y + box_h + 8.0
	var bw: float = (adv_r.position.x + aw) - start_x
	var bh: float = 12.0
	draw_rect(Rect2(bx, by, bw, bh), Color(0.12, 0.12, 0.18))
	# 처치(초록) + 누수(빨강)를 나눠 채운다 — 둘 다 '처리된 적'이지만 누수는 못 막은 것.
	# 붉은 구간이 남아 보여야 "흘려보내며 클리어"가 성취로 안 읽힌다.
	var tot: float = float(st["total"])
	var kfrac: float = clampf(float(killed) / tot, 0.0, 1.0)
	var lfrac: float = clampf(float(leaked) / tot, 0.0, 1.0 - kfrac)
	draw_rect(Rect2(bx, by, bw * kfrac, bh), Color(0.3, 0.78, 0.46))
	draw_rect(Rect2(bx + bw * kfrac, by, bw * lfrac, bh), Color(0.8, 0.25, 0.25))
	draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 1.0, 1.0, 0.4), false)

func _draw_board(fnt: Font) -> void:
	draw_rect(Rect2(BOARD_X - 2, BOARD_Y - 2, COLS * CELL + 4, ROWS * CELL + 4), C_BORD, false)
	# 충전 중인 셀. 그리드 위에 따로 그린다(부푼 블록이 옆 셀 배경에 잘리지 않게).
	var charging: Dictionary = {}
	var chg: float = 0.0
	if resolving and not clear_done:
		chg = clampf(resolve_timer / charge_dur, 0.0, 1.0)
		for ci in clear_cells:
			charging[ci] = true
	var bpad: float = 5.0
	for r in range(ROWS):
		for c in range(COLS):
			var rx: float = BOARD_X + c * CELL
			var ry: float = BOARD_Y + r * CELL
			draw_rect(Rect2(rx, ry, CELL, CELL), C_CELL)
			draw_rect(Rect2(rx, ry, CELL, CELL), C_GRID, false)
			if board[r][c] == "" or charging.has(Vector2i(c, r)):
				continue
			draw_rect(Rect2(rx + bpad, ry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0),
					_color_of(board[r][c]))

	# 충전 연출: 원래 색 → 방금 놓은 조각 색으로 물듦(색 통일) → 흰색으로 달아오르며 부풂 → 터짐
	for ci2 in charging:
		var cc: Vector2i = ci2 as Vector2i
		var cx0: float = BOARD_X + cc.x * CELL
		var cy0: float = BOARD_Y + cc.y * CELL
		var bcol: Color = _color_of(board[cc.y][cc.x]).lerp(clear_tint, clampf(chg / CHARGE_TINT, 0.0, 1.0))
		var hot: float = clampf((chg - CHARGE_TINT) / (1.0 - CHARGE_TINT), 0.0, 1.0)
		bcol = bcol.lerp(Color(1.0, 1.0, 1.0), hot * 0.75)
		var bsz: float = (CELL - bpad * 2.0) * (1.0 + 0.22 * chg)
		var boff: float = (CELL - bsz) * 0.5
		draw_rect(Rect2(cx0 + boff, cy0 + boff, bsz, bsz), bcol)
		# 달아오를수록 흰 테두리가 살아난다(터지기 직전이 가장 밝음)
		if hot > 0.0:
			draw_rect(Rect2(cx0 + boff, cy0 + boff, bsz, bsz), Color(1.0, 1.0, 1.0, hot * 0.9), false, 2.0)

	# ④ 소멸 잔상: 블록이 사라진 바로 그 줄 자리에 색 테두리만 한순간 남는다(BB 실측: 1프레임).
	#    "여기 있던 줄이 방금 증발했다"를 아주 짧게 못 박는 장치.
	if outline_timer > 0.0:
		var oa: float = clampf(outline_timer / LINE_OUTLINE_DUR, 0.0, 1.0)
		var ocol: Color = clear_tint.lerp(Color.WHITE, 0.5)
		ocol.a = oa
		for orow in clear_rows:
			draw_rect(Rect2(BOARD_X, BOARD_Y + int(orow) * CELL, COLS * CELL, CELL), ocol, false, 3.0)
		for ocol_i in clear_cols:
			draw_rect(Rect2(BOARD_X + int(ocol_i) * CELL, BOARD_Y, CELL, ROWS * CELL), ocol, false, 3.0)

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

	# 고스트 + 줄 완성 프리뷰 (게임 진행 중, active 슬롯이 채워져 있을 때만).
	# resolve 중엔 입력이 막혀 있으므로 고스트도 숨긴다 — 안 그러면 충전 중인 셀 때문에 _can_place가 false가 돼
	# 폭발 연출 한복판에 '못 놓음' 빨간 고스트가 얹힌다.
	if not game_over and not game_clear and not resolving:
		var active: Dictionary = _active()
		var ghost: Array = _ghost_cells()
		var can: bool = _can_place(ghost)
		var gset: Dictionary = {}
		for gi in ghost:
			gset[gi] = true
		var pulse: float = 0.5 + 0.5 * sin(anim_t * 7.0)
		var will_clear: bool = false

		# ① 줄 완성 프리뷰: 지금 놓으면 터질 줄을 '조각 색'으로 미리 물들여 맥동시킨다.
		#    실제 폭발의 색 통일 연출과 같은 색 → 프리뷰가 곧 예고편이 된다(Block Blast 방식).
		if can and not active.is_empty():
			var pcol: Color = _color_of(active["color"])
			var wl: Dictionary = _would_clear_lines(ghost)
			var pre: Dictionary = {}
			for pr in wl["rows"]:
				for pc in range(COLS):
					pre[Vector2i(pc, int(pr))] = true
			for pc2 in wl["cols"]:
				for pr2 in range(ROWS):
					pre[Vector2i(int(pc2), pr2)] = true
			will_clear = pre.size() > 0
			for pi in pre:
				var pv: Vector2i = pi as Vector2i
				if gset.has(pv):
					continue   # 조각이 놓일 칸은 아래 고스트가 진하게 그린다
				var prx: float = BOARD_X + pv.x * CELL
				var pry: float = BOARD_Y + pv.y * CELL
				# 조각 색으로 '완전히' 통일 — 부분 혼합(0.75)은 파랑→노랑 사이 올리브를 거쳐 탁해진다.
				# 실제 폭발의 색 통일 종착점과 같은 색이라, 프리뷰가 그대로 예고편이 된다.
				var tint: Color = pcol.lerp(Color.WHITE, 0.10 + 0.22 * pulse)
				var prect: Rect2 = Rect2(prx + bpad, pry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0)
				draw_rect(prect, tint)
				draw_rect(prect, Color(1.0, 1.0, 1.0, 0.30 + 0.40 * pulse), false, 2.0)

		# ② 고스트: 흐린 dim이 아니라 '실제로 놓인 것과 같은' 활성 색. 미리보기임은 흰 테두리로 표시.
		for gi2 in ghost:
			var gc: Vector2i = gi2 as Vector2i
			if gc.x < 0 or gc.x >= COLS or gc.y < 0 or gc.y >= ROWS:
				continue
			var rx: float = BOARD_X + gc.x * CELL
			var ry: float = BOARD_Y + gc.y * CELL
			var grect: Rect2 = Rect2(rx + bpad, ry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0)
			if not can:
				# 무효는 '빨간 금지'로 확실히. 반투명하게 깔면 밑의 파란 블록과 섞여 자홍색이 되어 안 읽히므로
				# 불투명하게 덮는다.
				draw_rect(grect, Color(0.62, 0.12, 0.15))
				draw_rect(grect, Color(1.0, 0.32, 0.32), false, 2.0)
				continue
			draw_rect(grect, _color_of(active["color"]))
			# 줄이 터질 자리면 프리뷰 줄과 같은 세기로 함께 맥동 = "이 한 수가 줄을 완성한다"
			var edge: float = (0.30 + 0.40 * pulse) if will_clear else 0.55
			draw_rect(grect, Color(1.0, 1.0, 1.0, edge), false, 2.0)

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
		# 표시 y는 vis_row(부드러운 이징) — 전진/넉백이 스르륵
		var vr: float = e.get("vis_row", float(er))
		var cx: float = BOARD_X + ec * CELL + CELL * 0.5 + jit.x
		var cy: float = BOARD_Y + vr * CELL + CELL * 0.5 + jit.y
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
	var strip_h: float = 32.0
	var sx: float = BOARD_X
	var sy: float = BOARD_Y + ROWS * CELL + 4.0
	var sw: float = COLS * CELL
	var core_max: int = int(st["core_hp"])
	var ratio: float = clampf(float(core_hp) / float(core_max), 0.0, 1.0)
	# HP바: 빈 트랙(어두움) + 체력 그라데이션(빨강↔초록) + 밝은 테두리
	draw_rect(Rect2(sx, sy, sw, strip_h), Color(0.08, 0.03, 0.04))
	var fill_col: Color = Color(0.86, 0.24, 0.20).lerp(Color(0.28, 0.82, 0.45), ratio)
	draw_rect(Rect2(sx, sy, sw * ratio, strip_h), fill_col)
	# 상단 하이라이트(입체감)
	draw_rect(Rect2(sx, sy, sw * ratio, strip_h * 0.4), Color(1.0, 1.0, 1.0, 0.18))
	draw_rect(Rect2(sx, sy, sw, strip_h), Color(1.0, 1.0, 1.0, 0.55), false, 2.0)
	# 라벨: 외곽선 흰 글자(트랙/체력 어느 색 위에서도 읽힘). 검정은 어두운 빈 구간서 안 보여 회피.
	var lbl: String = "거점  %d / %d" % [core_hp, core_max]
	var lw: float = fnt.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	_draw_text_outlined(fnt, Vector2(sx + sw * 0.5 - lw * 0.5, sy + 22.0), lbl, 19, Color.WHITE)

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
