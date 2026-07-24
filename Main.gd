extends Node2D

# ===== 상수 =====
const COLS: int = 8
const ROWS: int = 8             # 8×8 (Block Blast와 동일). 줄=8칸이라 조각 유입 대비 수지가 조여짐
const CELL: int = 90            # 셀 크기(픽셀) → 보드 720×720. 폭 720/800=90% (Block Blast 원본 프레임 실측: 89.7%).
const BOARD_X: int = 40         # (800 - COLS*CELL)/2. 폭 800은 세로 고정(portrait+expand)이라 상수 유지.
# 세로 레이아웃은 런타임 파생(_relayout). 아래 초기값은 _ready의 _relayout()이 즉시 덮어씀(placeholder).
var board_y: int = 150          # 보드 상단 y (기본 150~662). 거점 띠·트레이가 전부 이 값에서 파생됨.
var bot_y: int = 700            # 하단 패널 상단 (거점 띠 아래, 트레이 시작)
var vh: float = 1000.0          # 현재 뷰포트 높이(리사이즈마다 갱신). 폭은 VW_BASE 고정.
const VW_BASE: float = 800.0    # 논리 폭(portrait+expand에서 항상 800)
const HUD_H: float = 144.0      # 상단 HUD 띠 높이(상단 고정)
const TRAY_PANEL_H: float = 300.0  # 하단 트레이 패널 높이(하단 고정) = 원본 1000-700
const CORE_BLOCK_H: float = 758.0  # 보드(720=ROWS*CELL)+거점 띠(strip 32+여백 6) = board_y부터 tray까지 확보할 세로

# 적 타입 (basic/fast/tank/swarm/split)
# ⚠split은 반드시 배열 끝 — pick_etype iteration 순서가 회귀 시드에 물려 있다(끝+weight0 = 무영향).
const ENEMY_TYPES: Array = ["basic", "fast", "tank", "swarm", "split"]
# 분열 자식 HP = 부모 maxhp × 이 비율(결정적 — randi 안 씀). 손자 없음(gen1은 안 쪼개짐).
const SPLIT_CHILD_FRAC: float = 0.5
# 분열선: gen0가 이 행에 닿으면 '죽여서'가 아니라 '너무 내려와서' 저절로 쪼개진다.
#   ⚠인센티브 축: 선 위(row<SPLIT_ROW)에서 잡으면 안 쪼개짐(깨끗한 처치=이득). 못 잡고 넘기면
#   그때 쌍둥이가 생겨 -2 위협이 됨(늦은 대가지 잡은 벌이 아님). 선 아래 ROWS-SPLIT_ROW행 = 레이스 창.
const SPLIT_ROW: int = 5
const SLIDE_SPEED: float = 8.0   # 적 전진 표시 이징 속도(칸/초)
const ROCKET_DUR: float = 0.16  # 로켓 비행 지속(빠르게 질주)
const CALLOUT_DUR: float = 1.6  # 첫 등장 콜아웃 배너 지속
# 스테이지 인트로 카드 — 캠페인 진입 시 중앙 팝업(이름·태그·목표)이 떠서 잠깐 머물다 상단
# 목표 카드로 축소·이동하며 녹아든다(BlockBlast 목표 배너 관찰). 탭하면 즉시 스킵.
const INTRO_APPEAR: float = 0.28
const INTRO_HOLD: float = 0.50    # BlockBlast 배너 실측 홀드 ~0.55s에 맞춤(1.2s는 정적 늘어짐)
const INTRO_DOCK: float = 0.35    # 상단 도킹 = 빠르게 톡(느리면 늘어진다)
const INTRO_TOTAL: float = 1.13   # APPEAR+HOLD+DOCK

# 라인클리어 폭발
const LINE_BASE: int = 120
const STREAK_STEP: float = 0.5
const BLAST_RING_DELAY: float = 0.4   # 링(추가 레인) 간 순차 발사 텀 (물결 확산 속도. 클수록 극적·느림)
const FLASH_DUR: float = 0.7
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
const PLACE_POP_DUR: float = 0.17   # 블록 착지 팝 지속(짧게 '탁')
const REVIVE_CLEAR_ROWS: int = 3    # 막힘 부활 시 비우는 하단 줄 수 (Block Blast식 부분 클리어)
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
# 기준 ⑤ 디펜스 축 손잡이는 core_hp(허용 누수) + total(적 수) 둘뿐이다. 나머지는 실측상 못 쓴다:
#   step_every 3→2 = 절벽(스5 승률 61%→2.5%). 누수 시계가 24→16배치로 줄면 그냥 안 됨.
#   spawn_every는 비단조 — 2→1로 조이면 스3이 오히려 쉬워졌다(63%→75%). 적이 뭉쳐 들어와
#   한 레인 청소에 더 많이 쓸려나가기 때문. '더 빨리 온다'가 '더 어렵다'가 아니다.
# 기준 ⑥ 퍼즐 축 손잡이 = pool(조각 분포, C51 축·기전 / C54 아크 authoring). line-maker(I5) 비율이 주 dial이고,
#   core_hp가 그 위에 단조로 겹쳐 얹힌다(2D 난이도면). 디펜스 축이 소진된 자리를 여기서 채운다.

# 조각 풀 프리셋 — {조각키: 가중치}. 공통 '변주 base'(테트로미노·직사각 = 손맛)에 I5만 다르게.
# sim(pool_probe, basic-only) 실측: I5 0%→50%면 승률 5%→84% 단조 상승. 공정성은 _pool_piece
# 의 fit-guard(지금 보드에 최소 1칸 놓이는 조각만 배급)가 보장 = 강제 즉사 draw 없음.
const POOL_RICH: Dictionary = {   # 줄-풍부: 온보딩·숨통 (I5 최다)
	"1": 1, "D2h": 3, "D2v": 3, "I3h": 5, "I3v": 5, "L3a": 3, "L3b": 3, "L3c": 3, "L3d": 3,
	"O": 4, "T": 4, "S": 3, "Z": 3, "L": 4, "J": 4, "R32": 3, "R23": 3, "I5h": 20, "I5v": 20}
const POOL_STD: Dictionary = {    # 표준: I5 중간
	"1": 1, "D2h": 3, "D2v": 3, "I3h": 5, "I3v": 5, "L3a": 3, "L3b": 3, "L3c": 3, "L3d": 3,
	"O": 4, "T": 4, "S": 3, "Z": 3, "L": 4, "J": 4, "R32": 3, "R23": 3, "I5h": 11, "I5v": 11}
const POOL_LEAN: Dictionary = {   # 줄-굶김: 퍼즐 축 압박 (I5 희소)
	"1": 1, "D2h": 3, "D2v": 3, "I3h": 5, "I3v": 5, "L3a": 3, "L3b": 3, "L3c": 3, "L3d": 3,
	"O": 4, "T": 4, "S": 3, "Z": 3, "L": 4, "J": 4, "R32": 3, "R23": 3, "I5h": 4, "I5v": 4}

const STAGES: Array = [
	{
		# 온보딩: basic만 + core_hp 넉넉 + pool RICH(I5 최다) = 퍼즐 무압박으로 '줄 완성' 코어만 가르침
		"name": "st1_name", "tag": "st1_tag",
		"total": 20, "core_hp": 7, "base_hp": 30, "hp_ramp": 0.0, "tank_mult": 2.5,
		"spawn_every": 3, "step_every": 3, "onboard": 20, "floor": 4, "surge_at": 0.85,
		"weights": {"basic": 100, "fast": 0, "tank": 0, "swarm": 0, "split": 0}, "pool": POOL_RICH,
	},
	{
		# desync로 무리 절반이 base_step−1로 더 빨리 전진 → 행·열로 흩어져 한 줄론 못 쓸어냄
		"name": "st2_name", "tag": "st2_tag",
		"total": 30, "core_hp": 3, "base_hp": 32, "hp_ramp": 0.4, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 4, "floor": 5, "surge_at": 0.82,
		"weights": {"basic": 40, "fast": 0, "tank": 0, "swarm": 60, "split": 0}, "pool": POOL_RICH,
	},
	{
		"name": "st3_name", "tag": "st3_tag",
		"total": 34, "core_hp": 3, "base_hp": 34, "hp_ramp": 0.5, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 5, "surge_at": 0.80,
		"weights": {"basic": 40, "fast": 50, "tank": 0, "swarm": 10, "split": 0}, "pool": POOL_STD,
	},
	{
		# 퍼즐 축 고립(C54): 새 적 없이 pool LEAN(I5 희소)만으로 압박 = '손이 곧 위협'.
		# 적은 basic/swarm(이미 배운 것)이라 난이도는 전적으로 조각 분포에서 나온다.
		"name": "st4_name", "tag": "st4_tag",
		"total": 36, "core_hp": 3, "base_hp": 36, "hp_ramp": 0.4, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 5, "surge_at": 0.80,
		"weights": {"basic": 55, "fast": 0, "tank": 0, "swarm": 45, "split": 0}, "pool": POOL_LEAN,
	},
	# ── 변주 슬롯 ①: 첫 보석 수집(S5) — 코어 방어 학습(S1~4) 직후 동사 전환('처치'→'수집'). ──
	#   ⚠name 키는 위치가 아니라 안정 ID(추가 순서). 이 판은 st9_* 문자열을 쓰지만 배열 위치는 5번.
	#   collect 기전 상세 주석은 하단 두 번째 보석판(Two Colors) 위 참조.
	{
		# 1종 수집. 보석이 전경이 되도록 튜닝: 보석 두껍게(gem_every 2) + 적 얇게(spawn_every 3·floor 2) = 적은 '가끔 끼는 세금'.
		# gem_fast=보석이 위협보다 한 단계 빨리 떨어져 데드라인 조임(전용 클리어 강제). 목표 15개(공급이 두꺼워 grind 아님).
		"name": "st9_name", "tag": "st9_tag", "collect": true, "collect_targets": [15], "gem_every": 2, "gem_fast": true,
		"total": 300, "core_hp": 3, "base_hp": 30, "hp_ramp": 0.2, "tank_mult": 2.5,
		"spawn_every": 3, "step_every": 3, "onboard": 3, "floor": 2, "surge_at": 0.0,
		"weights": {"basic": 50, "fast": 50, "tank": 0, "swarm": 0, "split": 0}, "pool": POOL_STD,
	},
	{
		# tank HP를 콤보3(240) 구간에 앉힌다: base 44~50 × 4.5 = 198~227 → 콤보2(180)로는 안 뚫림.
		"name": "st5_name", "tag": "st5_tag",
		"total": 44, "core_hp": 2, "base_hp": 44, "hp_ramp": 0.3, "tank_mult": 4.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 5, "surge_at": 0.80,
		"weights": {"basic": 40, "fast": 0, "tank": 55, "swarm": 5, "split": 0}, "pool": POOL_STD,
	},
	{
		"name": "st6_name", "tag": "st6_tag",
		"total": 48, "core_hp": 2, "base_hp": 46, "hp_ramp": 0.4, "tank_mult": 4.2,
		"spawn_every": 2, "step_every": 3, "onboard": 2, "floor": 6, "surge_at": 0.78,
		"weights": {"basic": 20, "fast": 35, "tank": 25, "swarm": 20, "split": 0}, "pool": POOL_STD,
	},
	# ── act-3: 하드 로스터 도입(분열) = 랭크 무한 예고편 (C57, C56 ⑥ 실행) ──
	{
		# 분열 격리 도입: 적은 basic↔split만(split_probe 믹스와 동형) = 난이도가 전적으로 새 기전에서.
		# 스킬 축 = 우선순위·템포(C56 ⑤): '높이 있을 때 잡아라 — 깊으면 자식이 거점 코앞에서 갈라진다'.
		# pool은 STD(퍼즐 굶김으로 이중 압박 안 함, S5 장갑이 tank를 STD로 격리한 것과 동형).
		# core_hp 3 = 새 위협을 배울 한 칸 여유(다음 스테이지에서 2로 조인다).
		# ⚠도입은 climax보다 물러야 한다: total·base_hp를 S5/S6 최댓값에서 내리고 split 40%로 격리 —
		#   split 55%+total52+hp48은 sim서 도입이 climax만큼 가혹(23→10 절벽). 새 기전만 변수로 세운다.
		"name": "st7_name", "tag": "st7_tag",
		"total": 48, "core_hp": 3, "base_hp": 44, "hp_ramp": 0.35, "tank_mult": 4.2,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 6, "surge_at": 0.80,
		"weights": {"basic": 60, "fast": 0, "tank": 0, "swarm": 0, "split": 40}, "pool": POOL_STD,
	},
	{
		# act-3 클라이맥스 = 전 로스터 + 분열 + core_hp 2 (S1 '첫 방어선'과 수미상관 '최종 방어선').
		# 분열은 방어축 레버(거점사 지배)라 청소 처리량을 굶기는 tank/fast/swarm 위에 겹쳐 얹힌다.
		# split 25%(수확 시작점) — 100%가 아니라, 다른 위협과 섞여야 '전부 온다'가 성립.
		"name": "st8_name", "tag": "st8_tag",
		"total": 56, "core_hp": 2, "base_hp": 50, "hp_ramp": 0.4, "tank_mult": 4.2,
		"spawn_every": 2, "step_every": 3, "onboard": 2, "floor": 6, "surge_at": 0.78,
		"weights": {"basic": 15, "fast": 25, "tank": 20, "swarm": 15, "split": 25}, "pool": POOL_STD,
	},
	# ── 변주 슬롯 ②: 두 번째 보석 수집(S10, 프런티어) — 보석 사다리 G2. 첫 보석판(S5)과 떨어뜨려 배치. ──
	# 받기형 수집 기전(C81, 첫 보석판과 공유): 보석(gem)이 적들 사이로 같이 내려온다. 블라스트가 닿으면 획득(collected++),
	#   거점 밑으로 빠지면 사라짐(거점 무피해). 적은 순수 위협(그리디의 비용) — 안 막으면 거점사. 다 잡을 필요 없음.
	# 승리 = 보석 collect_target개 수집. 실패 = 거점사. 새 결정 = "이 클리어를 보석에 쓸까 적에 쓸까"(주의 배분).
	#   긴장 급소: 보석과 적이 다른 열/타이밍에 오게 → 한 클리어로 둘 다 못 하게. gem_every 배치마다 보석 1개.
	{
		# 2종 수집(G2 심화). 보석은 S5처럼 전경(gem_every 2·floor 2)이되, 사다리는 물량이 아니라 '필요한 색 고르기 + tank 방어압'으로.
		# 두 색 quota 8+8을 동시에 채워야 = 아무 보석이나 못 줍고 '필요한 색'을 골라 조준(새 결정 深). tank↑로 질(質)의 압박.
		"name": "st10_name", "tag": "st10_tag", "collect": true, "collect_targets": [8, 8], "gem_every": 2, "gem_fast": true,
		"total": 300, "core_hp": 3, "base_hp": 32, "hp_ramp": 0.2, "tank_mult": 3.0,
		"spawn_every": 3, "step_every": 3, "onboard": 2, "floor": 2, "surge_at": 0.0,
		"weights": {"basic": 45, "fast": 40, "tank": 15, "swarm": 0, "split": 0}, "pool": POOL_STD,
	},
]

# 조각 색 키 (시각용만)
const COLORS: Array = ["R", "B", "Y"]

# 트레이 UI
const TRAY_SLOT_W: int = 120
const TRAY_SLOT_H: int = 100
const TRAY_SLOT_GAP: int = 20
const TRAY_PREVIEW_CELL: int = 17   # 최대 조각이 5칸(I5) → 85px, 슬롯 120×100 안에 여백 확보

# 드래그앤드롭 — 모바일이 최종 타깃. Godot이 터치를 마우스 이벤트로 에뮬레이트하므로
# 같은 코드가 PC 테스트와 모바일에서 그대로 동작한다.
const DRAG_LIFT: float = 80.0        # 조각을 포인터 위로 들어올리는 높이. 모바일에서 엄지가 조각을 가리지 않게.
const SNAPBACK_DUR: float = 0.14     # 못 놓는 자리에서 뗐을 때 트레이로 되돌아가는 시간

# 조각은 그리드에 스냅하지 않는다 — 포인터를 그대로 따라다닌다. 대신 놓일 칸에 '흐린 미리보기'가
# 계속 떠 있고, 못 놓는 자리로 가면 그 미리보기가 사라진다 (Block Blast 원본 프레임 확인).
# 조각을 스냅시키면 조각이 미리보기를 덮어버려서 미리보기가 보이질 않는다.
const PREVIEW_MIX: float = 0.33      # 착지 미리보기 = 셀 배경 위에 조각색을 이 비율로 (원본 픽셀 샘플링값)

# 입력 방식 토글 버튼 — PC 테스트 전용. 모바일 빌드의 기본은 드래그앤드롭.
# 트레이 패널 안(bot_y 아래 200px)에 얹히므로 _relayout에서 bot_y 기준으로 재배치.
var mode_btn := Rect2(596.0, 900.0, 184.0, 46.0)

# 설정 기어 — 플레이 중 우상단. 콤보 표시(우상단 y=26)와는 콤보를 왼쪽으로 밀어 비켜준다.
const SETTINGS_GEAR := Rect2(748.0, 30.0, 44.0, 44.0)

# 레전빌리티 연출
const RED_FLASH_DUR: float = 0.35
const SHAKE_DUR: float = 0.28
const SHAKE_AMP: float = 9.0
const FLOAT_DUR: float = 0.6

# '놓을 곳 없음' 죽음 — 빈 칸을 아래에서 위로 블록으로 메운다. 꽉 찬 보드 자체가 패배 사유의 진술이다.
# 수치는 레퍼런스(Block Blast) 원본 프레임 실측: 행 간격 50ms, 블록당 페이드인 50ms, 8행 = 0.4초.
# 채우는 색은 회색이 아니라 평범한 블록 팔레트 — 원본이 그렇고, 꽉 찬 컬러 보드가 "빈 칸 0"을 가장 직설적으로 말한다.
const STUCK_ROW_GAP: float = 0.05    # 한 행 → 다음 행
const STUCK_FADE: float = 0.05       # 블록 하나가 어둠에서 제 색으로
const STUCK_HOLD: float = 1.2        # 다 채운 보드를 응시하는 시간 (원본은 ~1.8초, 재도전 반복을 감안해 줄임)

# '거점 파괴' 죽음 — 위에서 아래로 무너진다. stuck의 '차오름'과 방향이 정반대라,
# 화면만 보고도 어느 쪽으로 죽었는지 안다. 방향이 곧 사유다.
# 레퍼런스가 없다(Block Blast엔 거점이 없다) — 실측이 아니라 설계값이다.
const CORE_HITSTOP: float = 0.12     # 뚫리는 순간 시간이 멎는다
const CORE_BURST: float = 0.26       # 거점 띠가 터진다 (기존 균열·섬광·흔들림을 여기 몰아준다)
const CORE_FALL_AT: float = 0.46     # 받칠 게 사라진 보드가 쏟아지기 시작
const CORE_COL_STAGGER: float = 0.04 # 열마다 시차 — 한 판이 아니라 우르르 무너지게
const CORE_FALL_DUR: float = 0.50    # 한 열이 화면 밖으로
const CORE_HOLD: float = 0.35        # 텅 빈 보드를 보는 시간
const CORE_GRAVITY: float = 6500.0   # px/s² — CORE_FALL_DUR 안에 화면을 벗어나는 세기

# 색상
const C_RED  := Color("#e5484d")
const C_BLUE := Color("#3b82f6")
const C_YELL := Color("#eab308")
const C_BG   := Color("#0d0d1a")
const C_BG_PB := Color("#2a2470")     # 넘음 배경 — 여백·상단바·하단바를 '한 색'으로 통일(밝은 인디고). 8×8 보드 셀은 원색 유지(다크 아일랜드).
const C_CELL := Color("#111122")
const C_GRID := Color(0.28, 0.28, 0.38, 0.55)
const C_HUD  := Color(0.06, 0.06, 0.12)
const C_GOLD := Color("#ffd700")
const C_BORD := Color(0.24, 0.24, 0.38)

# 적 타입별 대표 색 (한눈 구분)
#
# 적은 빨강 계열을 안 쓴다. 빨강은 조각(C_RED)과 위협 신호(피격 플래시·누수 −1·실패 테두리)가
# 이미 나눠 갖고 있어서, 적까지 빨강이면 빨간 블록 위의 빨간 적이 통째로 묻힌다(기본 적은
# C_RED과 헥스까지 같았고, 탱크의 마룬도 같은 버그의 조용한 버전이었다).
# → basic=바이올렛 / tank=딥 바이올렛으로 이동. 밝기 관계(밝은 기본 ↔ 어두운 무거운 변주)는
#   마룬-빨강 시절 그대로라, 플레이어가 배운 "탱크 = 육중한 기본"이 유지된다.
const C_E_BASIC := Color("#a855f7")   # 바이올렛
const C_E_FAST  := Color("#22d3ee")   # 시안
# tank=장갑 → 강철/건메탈(금속 = 장갑). 도착 순간 '장갑'이 실루엣만으로 읽히게(C73, basic 보라와 분리).
#   판·리벳·베벨은 아래 렌더에서. 딥바이올렛(#6d28d9) 시절엔 basic과 같은 보라라 '네모난 basic'으로 읽혔다.
const C_E_TANK    := Color("#64748b")   # 강철(쿨블루 슬레이트)
const C_E_TANK_HI := Color("#aab6c6")   # 상단 베벨 하이라이트
const C_E_TANK_DK := Color("#2f3b4d")   # 이음선·하단 그림자
const C_E_RIVET   := Color("#d7dee8")   # 코너 리벳
const C_E_SWARM := Color("#a3e635")   # 라임
const C_E_SPLIT := Color("#60a5fa")   # 파랑 — 로스터에서 유일한 한색(빨강 회피). 시안(fast)보다 확연히 파랑

# 잔해(감시자가 뻗는 뿌리 셀 "#") — 무채색 강철회색. 조각 3색·적 색과 모두 분리(죽은 칸임을 색으로 말함).
const C_DEBRIS := Color("#4a4a55")
# 감시자 머리 셀 "H" — 딥 바이올렛(보스 전용). 어두운 외곽선을 둘러 '보드 위 생명체'로 읽힌다(적 언어 재사용).
const C_BOSS := Color("#7c3aed")
# 보석(수집물) — 따뜻한 금빛 다이아. 위협색(바이올렛·강철·라임)·조각색(빨·파·노)과 분리 = '착한 보물'로 읽힘.
const C_GEM := Color("#ffd76b")
# 보석 타입별 색 — 다이아 form이 '보석'을 말하니 색은 타입 구분용. 서로 확연히 다른 보석톤(금/로즈/인디고).
#   타입 수는 스테이지 collect_targets 길이가 정한다(1종→2종→3종 = 난이도 램프).
const GEM_COLORS: Array = [Color("#ffd76b"), Color("#fb7185"), Color("#818cf8")]

# 적 외곽선 — 적은 언제나 어두운 테두리를 두르고 보드 위에 '떠' 있다.
# 색만으로 분리를 보장하면 팔레트가 하나 바뀔 때마다 같은 버그가 재발한다(두더지 잡기).
# 테두리는 조각 색이 무엇이든 적의 윤곽을 세우므로, 분리가 구조로 보장된다.
# 탱크가 이미 쓰던 문법(검은 4px 외곽선)을 전 타입으로 일반화한 것 — 새 언어가 아니다.
const C_E_RIM := Color(0.0, 0.0, 0.0, 0.85)
const C_E_RIM_W: float = 3.0

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
# mode: "menu"=메인 허브(Adventure/Classic), "select"=스테이지 선택, "play"=플레이 중(스테이지는 독립=보드·거점 초기화)
var mode: String = "menu"
var stage_idx: int = 0
var st: Dictionary = {}          # 현재 스테이지 정의(STAGES[stage_idx])
const GameMode = preload("res://modes/game_mode.gd")
const StageMode = preload("res://modes/stage_mode.gd")
const EndlessMode = preload("res://modes/endless_mode.gd")
const FeaturedMode = preload("res://modes/featured_mode.gd")
const LeaderboardService = preload("res://leaderboard.gd")   # 점수 저장·제출 이음새 (C64)
var director: GameMode = null    # 감독(스폰·난이도·종료 결정). _start_stage에서 st와 함께 세팅

# 무한모드(감독=EndlessMode) — 캠페인 스테이지와 형제. C52 설계·C56 game_rng 분리.
# ⚠관측 전용 마커(프로브·디버그가 get()으로 읽음). 코어는 이걸로 분기하지 말 것 — 점수·HUD·결과·
#   재도전·홈복귀는 전부 director.scores()/retry_kind()로 묻는다(C62). `if endless:`를 다시 넣으면 갈라짐.
var endless: bool = false          # (관측용) 무한/featured 진행 중
var endless_score: int = 0         # 이번 런 점수 = Σ(줄×기본점 + 처치×콤보×배수), C52+C58
var endless_best: int = 0          # 로컬 베스트(리더보드 서비스가 소유, 여기선 읽기 캐시로 미러)
var _leaderboard := LeaderboardService.new()   # 점수 저장·제출 이음새 — 파일/플랫폼 접근을 여기로만 (기획: endless-leaderboard-design)
var endless_prev_best: int = 0     # 런 시작 시점의 베스트(결과 팝업 델타 표시용)
var endless_new_best: bool = false # 이번 런이 신기록인가(결과 팝업 배지)
var endless_beat_best: bool = false # 판 중에 이미 최고를 넘었나(HUD 실시간 갱신 신호)
# 점수 계수(C58 손맛)는 감독 소유로 이관(C61 seam): EndlessMode.CLEAR_BASE/KILL_MULT.
#   코어는 director.clear_score()/kill_score()로 묻는다 — 모드 이름 대신 능력.
var _adv_hover: bool = false       # 메뉴: Adventure(스테이지) 버튼 호버
var _classic_hover: bool = false   # 메뉴: Classic(무한) 버튼 호버
var _lb_hover: bool = false        # 메뉴: 리더보드(우상단 트로피) 버튼 호버
var _lb_play_hover: bool = false   # 리더보드 화면: 하단 '무한 도전' CTA 호버
var _back_hover: bool = false      # select/리더보드: 뒤로가기(메뉴) 버튼 호버
# featured 결정적 트랙(오늘의 시드) — 무한의 변주. piece/spawn이 배치 인덱스만의 순수 함수라
#   같은 시드면 어떤 플레이 순서든 byte-identical 판(전원 동일 판 = 리더보드 공정성, C53 ⑤·C56 ⑧).
# ⚠관측 전용 마커. 코어는 이걸로 분기하지 말 것 — 조각·스폰의 결정적 트랙 여부는 director.deterministic_track()
#   으로 묻는다(C62). `if featured:`를 다시 넣으면 갈라짐. 트랙 인프라(_track_piece/_track_rng/game_seed)는 코어 소유.
var featured: bool = false         # (관측용) featured 결정적 트랙 진행 중
var piece_idx: int = 0             # featured: 지금까지 뽑은 트랙 조각 수(= 조각 시퀀스 인덱스)
var track_record: bool = false     # featured 시퀀스 기록(사후 점수 검증·결정성 probe용, 평소 off)
var track_log: Array = []          # [["P", idx, type, color] | ["S", depth, col, etype], ...]
var cleared: Dictionary = {}     # 스테이지 인덱스 → 클리어 여부 (세션 한정, 저장 없음)
var hover_stage: int = -1
var _play_hover: bool = false    # 하단 시작 버튼 호버
var _retry_hover: bool = false   # 결과 팝업 재도전 버튼 호버
var _home_hover: bool = false    # 결과 팝업 홈 버튼 호버

# 설정 모달 — 플레이 중 우상단 기어로 연다(게임 중 나가기/재시작 진입은 지금껏 죽은 뒤 결과팝업뿐이었다).
#   토글(소리·배경음)은 아직 오디오 시스템이 없어 소리를 내지 않는다 — user://에 '선호'만 저장해 두고,
#   오디오가 붙는 날 이 값을 소비한다(유저 결정: 미리 넣되 지속만). 죽은 토글이 아니라 예약된 선호다.
var settings_open: bool = false
var sound_on: bool = true        # SFX 선호(오디오 미구현 — 지속 저장만)
var bgm_on: bool = false          # BGM 선호(오디오 미구현 — 지속 저장만, 레퍼런스 기본값 OFF)
var _gear_hover: bool = false
var _set_close_hover: bool = false
var _set_home_hover: bool = false
var _set_replay_hover: bool = false
var _set_sound_hover: bool = false
var _set_bgm_hover: bool = false

# ===== 상태 =====
var board: Array = []
var enemies: Array = []
var core_hp: int = 0
var boss_hp: int = 0            # 보스(감시자) 스테이지 전용 — 잔해 낀 줄을 지울 때마다 감소. 0 = 클리어.
var boss_hp_max: int = 0
var collected_by_type: Array = []   # 받기형 수집 — 타입별 수집 수(길이=타입 수). 각 collect_targets[i] 도달 = 그 타입 완료, 전부 완료 = 클리어.
var gem_flights: Array = []          # 잡은 보석이 상단 카운터로 빨려가는 연출 {from,to,t,dur,gtype,color}. 도착 시 카운트+1.
var collect_pop: Array = []          # 타입별 카운터 도착 팝(스케일 바운스) 타이머
var place_count: int = 0        # 지금까지 배치 횟수(전진·스폰 스로틀 기준)
var spawned: int = 0
var killed: int = 0             # 실제 처치 수 (누수는 포함 안 함 — 진행도 오염 방지)
var leaked: int = 0             # 거점까지 흘려보낸 수. killed+leaked = 처리된 적(=더 이상 안 옴)
var score: int = 0
var combo: int = 0
var combo_miss: int = 0         # 콤보 유예 카운터: 줄 못 지운 연속 배치 수
var dda_enabled: bool = true    # DDA 온오프 (A/B용)
var floor_enabled: bool = true  # 밀도 하한(floor) 온오프 (density_probe A/B용)
var surge_enabled: bool = true  # 후반 서지 온오프 (surge_probe A/B용)
var dev_unlock_all: bool = false  # ⚠플테 전용: 전 스테이지 해금(선형 잠금 우회). 기본 false=출시 안전, 선택화면 '0'키 토글
var drought: int = 0            # 연속 무클리어 배치 수 (DDA의 '고전' 신호)
var fail_streak: Dictionary = {}  # 스테이지 인덱스 → 연속 실패 횟수 (갓 모드 트리거, 세션 한정)
var game_over: bool = false
var game_clear: bool = false
var stuck: bool = false
var revive_used: bool = false    # 이 판에서 광고 부활을 이미 썼나 (판당 1회 — C47 F2P)
var _cont_hover: bool = false    # 결과 팝업 '광고 이어하기' 버튼 호버

# 놓을 곳 없음 죽음 연출: 경과 시간(-1 = 비활성) + 메울 칸→색 (시작 시 확정, 매 프레임 흔들리지 않게)
var stuck_t: float = -1.0
var stuck_fill: Dictionary = {}   # Vector2i → 색 키

# 거점 파괴 죽음 연출: 경과 시간(-1 = 비활성) + 띠가 터지는 순간을 한 번만 실행하기 위한 래치
var core_t: float = -1.0
var core_burst_done: bool = false

# 3조각 트레이: 슬롯 = { "type", "color", "offsets" }, 빈 슬롯 = {}
var tray: Array[Dictionary] = [{}, {}, {}]
var sel: int = 0               # 현재 선택 슬롯

var hover_col: int = 0
var hover_row: int = 0

# 드래그 상태 — 조각은 '손에 들려' 포인터를 따라다닌다.
var dragging: bool = false
var drag_slot: int = -1
var drag_pos: Vector2 = Vector2.ZERO
var snapback: Dictionary = {}   # {slot, from(좌상단 px), t} — 못 놓고 뗀 조각이 트레이로 날아가는 중

# PC 테스트 편의용 입력 방식. true면 예전처럼 '조각 클릭 → 보드 클릭'.
# 화면 규칙은 두 모드가 동일하다 — 클릭 방식에서도 조각은 커서를 따라오고,
# 못 놓는 자리엔 아무 표시도 하지 않는다(빨간 고스트는 되살리지 않는다).
var click_mode: bool = false

# 연출 타이머
var flash_timer: float = 0.0
var flash_label: String = ""
var flash_lines: int = 0
var flash_combo: int = 0
var flash_climax: bool = false      # 화면 전체 도달(전멸) — 라벨 강조용
var climax_pending: float = -1.0    # 전멸 충격파 발사 예약 시각(resolve_timer 기준, -1=없음)
var surge_active: bool = false      # 후반 서지 중(진행도 > surge_at) — 전진 가속 + 텔레그래프용

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
var place_pops: Array = []     # [{pos, life, max, color}] 블록 착지 팝(사각형, 수축) — 소멸(부풂)과 방향 반대 = '도착'
var debris: Array = []         # [{pos, vel, life, max, color, size}] 사망 파편 버스트
var confetti: Array = []       # [{pos, vel, life, max, color, rot, spin, w, h, sway, phase}] 클리어 축하 색종이
var impacts: Array = []        # [{pos, life, max, color, radius}] 빔 임팩트/탱크 막음 링
var kill_pulse: float = 0.0    # 킬 순간 ENEMIES LEFT 헤드라인 펄스
var pb_pop_t: float = -1.0     # PB 돌파 '순간' 버스트 타이머(방사광+스티커 팝인). <0=대기. (스티커 자체는 이후에도 상주)
const PB_POP_DUR: float = 1.15 # 순간 버스트 길이(팝인·방사광). 스티커는 이 뒤로도 판 끝까지 붙어 있음.
var pb_bg_mix: float = 0.0     # 넘음 배경 전환 0→1(부드럽게 이징, 판 종료까지 지속). 넘으면 플레이씬 배경이 '기록 구간' 색으로.
var push_streaks: Array = []   # [{from, to, life, max}] 넉백 잔상
var aim_marks: Array = []      # [{c, r}] 조준 프리뷰 링 — 들고 있는 조각 '위'에 최상단 오버레이로 그린다
var rockets: Array = []        # [{dir, idx, t, dur, combo, ended}] 라인 따라 질주하는 로켓
var hitstop: float = 0.0       # 명중 순간 순간 멈칫(게임 타이머 전부 정지)
var core_hits: Array = []      # [{col, life}] 거점 피격 충격 플래시
var callout_text: String = ""  # 첫 등장 콜아웃 배너
var callout_timer: float = 0.0
var intro_t: float = -1.0  # 스테이지 인트로 카드 진행(초). <0 = 비활성(캠페인 진입에서만 켠다)
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
const I18N = preload("res://i18n.gd")   # UI 로컬라이제이션 테이블(en base + ko). 새 언어=로케일 추가.
var _font: Font = null
var _locale: String = I18N.DEFAULT_LOCALE   # 기기 언어에서 파생(_ready). 미지원이면 en. i18n.gd 참고.

# UI 문자열 조회 단축 헬퍼 — 각 draw 사이트가 이걸로 현재 로케일 문자열을 얻는다.
func _t(key: String) -> String:
	return I18N.t(_locale, key)

# 게임 결정성 전용 RNG — 조각 생성·적 스폰만 소비한다. 코스메틱(파편·셰이크·컨페티)은 전역 randf/randi로
# 분리 유지 → 프레임레이트·연출 변화가 게임 수열을 흔들지 않는다(데일리 시드 리더보드 공정성의 전제).
# ⚠회귀(tools/regress.gd)는 이 스트림만 시드 고정. Godot 전역 seed(x)와 RandomNumberGenerator.seed=x는
#   동일 PCG 수열(tools/rng_probe.gd로 실측), shuffle은 rng_shuffle로 동일 소비 패턴 재현.
var game_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var game_seed: int = 0   # 현재 게임 시드(featured 트랙 index-addressed rng의 기반)

# 게임 스트림 시드 고정(데일리 시드/회귀/sim). 코스메틱 전역 RNG는 건드리지 않는다.
func seed_game(s: int) -> void:
	game_seed = s
	game_rng.seed = s

# ── featured 결정적 트랙: 인덱스-주소 RNG ──
# 각 (인덱스, 채널)이 고유 시드의 fresh RNG를 받는다 → 한 채널의 가변 draw 수(swarm count·shuffle 등)가
#   다른 인덱스를 흔들지 못한다. 프리 무한의 보드-적응형 필터·밀도 하한(floor)은 featured에서 전부 끈다
#   = piece[i]/spawn[d]가 보드·처치수 무반응. (부작용 = 가끔 꽉 찬 보드에 큰 조각 → 막힘사가 '실력 실패'로
#    되살아남: [[failure-face-skill-dependent]] 패킹 숙련축 + 부활 정합. C53 ⑤ 의도.)
const _TRACK_PIECE_CH: int = 1   # 조각 티어·모양·색(하나의 rng에서 순차 소비)
const _TRACK_SPAWN_CH: int = 3   # 스폰 열·타입·swarm(한 스텝의 모든 draw를 이 rng가 소유)

func _track_rng(idx: int, channel: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = _mix3(game_seed, idx, channel)
	return g

# 결정적 64-bit 정수 믹스(FNV-1a 변형). 플랫폼 무관 재현 위해 builtin hash() 대신 명시 상수.
func _mix3(a: int, b: int, c: int) -> int:
	var h: int = a ^ 0x2545F4914F6CDD1D
	h = (h ^ b) * 1099511628211
	h = (h ^ c) * 1099511628211
	h = h ^ (h >> 29)
	return h

func _ready() -> void:
	randomize()          # 코스메틱 전역 RNG
	game_rng.randomize()  # 게임 스트림(프리플레이 기본; 데일리/회귀는 seed_game으로 덮어씀)
	_load_settings()
	_load_campaign()
	endless_best = _leaderboard.best()   # 로컬 베스트는 LeaderboardService가 소유·로드 — 여기선 캐시로 미러(C64 이음새)
	_locale = I18N.resolve_locale(OS.get_locale_language())
	# 번들 폰트(res://) — 시스템폰트 의존 제거. Noto Sans가 라틴/키릴/그리스를 커버(영어 우선 출시).
	# 라틴 밖 글리프(개발용 한글, 이모지 등)는 SystemFont fallback으로만 뜬다 → 영어 실기기엔 안 나옴.
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Apple SD Gothic Neo", "AppleGothic", "Noto Sans CJK KR", "Arial"])
	sf.allow_system_fallback = true   # 이모지(🏆 등)는 OS 이모지 폰트로 폴백
	var noto := load("res://fonts/NotoSans-Regular.ttf") as FontFile
	if noto != null:
		noto.fallbacks = [sf]
		_font = noto
	else:
		_font = sf   # 번들 로드 실패 시 안전망
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	mode = "menu"

# 세로 레이아웃을 현재 뷰포트 높이에서 파생한다. portrait+expand라 폭은 800 고정, 높이만 실기기 비율로 늘어난다.
# 앵커: HUD=상단 고정 · 트레이=하단 고정(엄지 그라운드) · 보드=그 사이 중앙. 폭 90%(CELL 90)로 키운 뒤
#   보드 상단이 ≈23.7%에 떨어져 BB 원본 프레임(23%)과 일치한다 — 남는 여백은 BB의 상단 목표젬/하단 광고
#   자리라 지금은 헤드룸·바닥 패널로 남는다(그 chrome가 붙으면 자연히 채워짐).
# 800×1280(데스크톱)에선 bot_y=980·board_y≈183. 긴 폰(≈1739)에선 board_y≈412(BB 23%와 일치).
# ⚠세이프에어리어(노치) 인셋은 실기기 배관에서 DisplayServer.get_display_safe_area()로 채운다 — 지금은 0.
func _relayout() -> void:
	vh = get_viewport_rect().size.y
	bot_y = int(vh - TRAY_PANEL_H)                 # 트레이 패널을 화면 맨 아래에 고정(그라운드)
	# 보드+거점 블록을 HUD 아래와 트레이 위 사이에 중앙 배치.
	var centered: int = int(HUD_H) + int(max(6.0, (float(bot_y) - HUD_H - CORE_BLOCK_H) * 0.5))
	# 720 보드는 짧은 창(<~1200)에선 다 안 들어간다 → 하한 HUD_H로 클램프해 음수/HUD 침범 방지.
	var upper: int = max(int(HUD_H), bot_y - int(CORE_BLOCK_H))
	board_y = clampi(centered, int(HUD_H), upper)
	mode_btn = Rect2(596.0, float(bot_y) + 200.0, 184.0, 46.0)  # 트레이 안, bot_y 기준
	queue_redraw()

# 메뉴·레벨선택은 1000 기준 고정 좌표로 authoring됨 — 뷰포트가 더 크면 이만큼 내려 세로 중앙에 둔다.
# 그리기는 draw_set_transform, 입력은 좌표에서 이 값을 빼 히트테스트한다(둘이 항상 같은 오프셋).
func _ui_dy() -> float:
	return (vh - 1000.0) * 0.5

# 로컬 베스트 영속·플랫폼 제출은 LeaderboardService(leaderboard.gd)가 소유 — Main은 파일/플랫폼
# API를 직접 만지지 않는다. 제출은 결과 팝업에서 _leaderboard.submit(), best는 캐시로 미러(C64 이음새).
# (C70 세이브 감사의 손상 가드 >=4는 LeaderboardService._read_i32로 이관됨.)

# 설정 선호 영속(user://). 지금은 소리/배경음 두 불린뿐 — 오디오가 붙으면 여기서 읽어 소비한다.
const SETTINGS_SAVE: String = "user://settings.save"

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_SAVE):
		return
	var f := FileAccess.open(SETTINGS_SAVE, FileAccess.READ)
	if f != null:
		# 2바이트 미만 = 부분쓰기 손상 → 기본값 유지(안 그러면 sound_on이 조용히 false로 뒤집힘).
		if f.get_length() >= 2:
			sound_on = f.get_8() != 0
			bgm_on = f.get_8() != 0
		f.close()

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_SAVE, FileAccess.WRITE)
	if f != null:
		f.store_8(1 if sound_on else 0)
		f.store_8(1 if bgm_on else 0)
		f.close()

# 캠페인 진행도 영속(user://). cleared 딕셔너리를 스테이지 비트마스크(비트 i = 스테이지 i 클리어)로 저장.
# ≤32스테이지면 32비트 하나에 담겨 store_32로 고정 4바이트 — 부분쓰기 내성이 가변길이보다 낫다.
# dev_unlock_all(플테 '0'키)은 cleared를 안 건드리므로 저장에 새지 않는다. fail_streak(DDA)는 세션 한정 유지.
const CAMPAIGN_SAVE: String = "user://campaign.save"

func _load_campaign() -> void:
	if not FileAccess.file_exists(CAMPAIGN_SAVE):
		return
	var f := FileAccess.open(CAMPAIGN_SAVE, FileAccess.READ)
	if f == null:
		return
	# 4바이트 미만 = 부분쓰기 손상 → 진행도 0에서 시작(홈/1스테이지는 항상 안전).
	if f.get_length() >= 4:
		var mask: int = f.get_32()
		for i in range(STAGES.size()):
			if (mask & (1 << i)) != 0:
				cleared[i] = true
	f.close()

func _save_campaign() -> void:
	var mask: int = 0
	for i in range(STAGES.size()):
		if bool(cleared.get(i, false)):
			mask |= (1 << i)
	var f := FileAccess.open(CAMPAIGN_SAVE, FileAccess.WRITE)
	if f != null:
		f.store_32(mask)
		f.close()

# 점수 가산 + 판 중 최고 갱신 감지(HUD 실시간 신호). best>0일 때만 = 첫 판(best 0)은 '갱신'이 무의미.
func _add_endless_score(pts: int) -> void:
	endless_score += pts
	# 넘는 '순간'(not-beat → beat 엣지)에 원샷 1회 발화 — 이후 프레임은 이미 beat라 재발화 없음.
	if endless_best > 0 and not endless_beat_best and endless_score > endless_best:
		endless_beat_best = true
		pb_pop_t = PB_POP_DUR   # 순간 버스트(방사광+스티커 팝인). 배경 전환은 pb_bg_mix가 이후 부드럽게.

# 선형 해금: 1스테이지는 항상 열려 있고, 그다음부턴 직전 스테이지를 깨야 열린다
func _is_unlocked(i: int) -> bool:
	if dev_unlock_all:
		return true   # 플테 전용 우회 (선택화면 '0'키 토글)
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

# 홈 = 허브(Adventure/Classic 선택 화면). 스테이지·무한 모두 '홈으로'는 허브로 나간다(유저 정의: 허브가 홈).
#   (구: 스테이지는 목록(select)이 홈이었으나 통일 — '홈'이 화면마다 다른 곳을 가리키면 헷갈린다.)
func _home_mode() -> String:
	return "menu"

# 스테이지 시작 — 독립 레벨이라 보드·거점·적을 전부 초기화하고 st만 갈아끼운다
func _start_stage(idx: int) -> void:
	endless = false             # DDA/surge/floor 플래그는 A/B 노브(regress·sim 소유) — 여기서 건드리지 않음
	featured = false            # ⚠featured에서 캠페인 복귀 시 트랙 경로 해제(안 그러면 조각/스폰이 트랙에 물림)
	stage_idx = clampi(idx, 0, STAGES.size() - 1)
	st = STAGES[stage_idx]
	director = StageMode.new(st)
	mode = "play"
	_init_game()
	intro_t = 0.0   # 캠페인 진입에서만 인트로 카드 재생(무한·featured는 _init_game이 -1로 둠)

# 무한모드 시작 — 스테이지 dict 없이 EndlessMode가 깊이로 스케줄. DDA off(리더보드 공정성, C52 ⑦).
func _start_endless() -> void:
	endless = true
	featured = false            # 프리 무한 = 보드-적응형 조각(_random_piece) + game_rng.randomize 랜덤 시드
	stage_idx = -1              # 스테이지 아님(fail_streak 키만 분리; DDA는 어차피 off)
	st = {}                     # pool 없음 → _random_piece 적응형 티어 경로(무한 기본)
	director = EndlessMode.new()
	# DDA는 dda_enabled를 건드리지 않고 endless 플래그로 게이팅(랭크 공정성, _make_piece 참조).
	# surge/floor는 게임플레이 기본값 true 유지(_start_endless는 게임플레이 전용, 하네스는 미호출).
	mode = "play"
	endless_new_best = false
	_init_game()

# 오늘의 featured 결정적 트랙 — 전원 동일 판(오늘의 시드), 무한 HUD/점수/부활 공유.
#   프리 무한과 다른 점: 조각·스폰이 배치 인덱스만의 함수(보드 무반응) + 밀도 하한 off + 재추첨 off.
# ⚠C60 보류: 첫 사람 플테서 '억울한 막힘사'(못 놓을 조각) 발견 → 프리 무한 먼저 제대로, 데일리는 후순위.
#   엔진(검증됨)은 미래 기반으로 보존, 플레이어 진입만 제거. 재개 시 = fit-필터 on 재설계(값싼 죽음 방지 복원,
#   'byte-동일' 포기하고 '같은 도전'으로) 또는 트레이에 항상 작은 조각 보장. 현재는 tools/featured_* probe로만 도달.
func _start_featured(seed: int) -> void:
	endless = true              # 무한 HUD·점수·결과·부활 경로 공유(enemy_total==-1 등)
	featured = true
	stage_idx = -1
	st = {}
	seed_game(seed)             # 게임 스트림 시드 = 오늘의 시드(전원 동일 판)
	piece_idx = 0
	track_log = []
	director = FeaturedMode.new()   # EndlessMode 램프 + floor 훅 off
	mode = "play"
	endless_new_best = false
	_init_game()

# 오늘의 featured 시드 = 달력 날짜(YYYYMMDD). 그날 플레이어 전원이 동일 판을 받는다(Wordle 모델).
func _today_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])

func _init_game() -> void:
	board = []
	for _r in range(ROWS):
		var row_arr: Array = []
		for _c in range(COLS):
			row_arr.append("")
		board.append(row_arr)
	enemies = []
	core_hp = director.core_hp_max()
	boss_hp = 0
	boss_hp_max = 0
	collected_by_type = []
	collect_pop = []
	for _gt in range((st.get("collect_targets", []) as Array).size()):
		collected_by_type.append(0)
		collect_pop.append(0.0)
	gem_flights = []
	if bool(st.get("boss", false)):
		_setup_boss_head()   # 머리 셀을 board에 심고 boss_hp = 머리 셀 수
	place_count = 0
	spawned = 0
	killed = 0
	leaked = 0
	score = 0
	endless_score = 0
	endless_prev_best = endless_best   # 판 시작 시점 베스트 스냅샷(결과 델타)
	endless_beat_best = false
	combo = 0
	combo_miss = 0
	drought = 0
	game_over = false
	game_clear = false
	settings_open = false
	_retry_hover = false
	_home_hover = false
	_cont_hover = false
	revive_used = false
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
	place_pops = []
	debris = []
	confetti = []
	impacts = []
	kill_pulse = 0.0
	pb_pop_t = -1.0
	pb_bg_mix = 0.0
	push_streaks = []
	rockets = []
	hitstop = 0.0
	core_hits = []
	callout_text = ""
	callout_timer = 0.0
	intro_t = -1.0   # 기본 off — _start_stage(캠페인)만 켠다
	seen_types = {}
	anim_t = 0.0
	red_flash = 0.0
	climax_pending = -1.0
	flash_climax = false
	surge_active = false
	shake_timer = 0.0
	dragging = false
	drag_slot = -1
	snapback = {}
	stuck_t = -1.0
	stuck_fill = {}
	core_t = -1.0
	core_burst_done = false
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
	# 보스 스테이지는 적이 없다(판-정리 격리) → 시작 적·RNG 소비 모두 건너뜀.
	if not bool(st.get("boss", false)):
		var start_cols: Array = []
		for c in range(COLS):
			start_cols.append(c)
		GameMode.rng_shuffle(start_cols, game_rng)
		_spawn_one(start_cols[0], "basic")    # 시작 적 1마리(row 0)
	if not _has_valid_placement():
		game_over = true
		stuck = true
		_begin_stuck_death()

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
	# 스테이지가 조각 풀을 명시하면(퍼즐 축 난이도 손잡이, C51) 그 풀에서만 뽑는다.
	#   풀 = {조각키: 가중치}. line-maker(I5) 비율이 주 dial — sim(pool_probe)에서
	#   0%→50% 섞으면 승률 5%→84%로 단조 상승, core_hp가 그 위에 겹쳐 얹힘(2D 난이도면).
	#   공정성은 tier 경로와 동일: 지금 보드에 최소 1칸 놓이는 조각만 배급(강제 즉사 배제).
	if st.has("pool"):
		return _pool_piece(st["pool"])
	var f: float = float(_free_cells()) / float(ROWS * COLS)
	var p_big: float = clampf((f - 0.50) / 0.35, 0.0, 1.0) * 0.16
	var p_mid: float = clampf((f - 0.25) / 0.30, 0.0, 1.0) * 0.60
	var r: float = game_rng.randf()
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
	var c: String = COLORS[game_rng.randi() % COLORS.size()]
	return {"type": ty, "color": c, "offsets": (PIECES[ty] as Array).duplicate()}

# 스테이지 지정 풀에서 가중추첨. 배치 가능한 조각만 후보로(꽉 차면 풀 전체 → 다음 턴 막힘 판정).
func _pool_piece(w: Dictionary) -> Dictionary:
	var fit: Array = []
	for t in w:
		if _piece_fits_at_least(PIECES[t], 1):
			fit.append(t)
	if fit.is_empty():
		fit = w.keys()
	var total: int = 0
	for t in fit:
		total += int(w[t])
	var r: int = game_rng.randi() % maxi(1, total)
	var ty: String = fit[fit.size() - 1]
	for t in fit:
		r -= int(w[t])
		if r < 0:
			ty = t
			break
	var c: String = COLORS[game_rng.randi() % COLORS.size()]
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
	return _weighted_pick_rng(pool, game_rng)

func _weighted_pick_rng(pool: Array, rng: RandomNumberGenerator) -> String:
	var total: int = 0
	for t in pool:
		total += int(PIECE_W[t])
	var r: int = rng.randi() % total
	for t in pool:
		r -= int(PIECE_W[t])
		if r < 0:
			return t
	return pool[pool.size() - 1]

# featured 조각 티어 분포(보드 무반응 = 고정 트랙). tools/featured_sweep로 확정.
#   BIG=R33(3×3) / MID=테트로미노·직사각·I5 / SMALL=1~3칸+O.
#   ★스윕 결과(中봇): p_big가 조금만 커도 막힘사가 폭증(보드를 못 봐서 꽉 찬 판에 큰 조각을 못 피함).
#     0.00/0.42/0.58 = 거점사 74.5% 지배 · 막힘 25.5% · 깊이중앙 140.
#     → 거점사 지배(C52 ⑥ 공유 코어 문법·부활 수익 보존) 유지하되, 막힘 25%로 프리(~1%)보다 25배 =
#       fit 필터 없앤 만큼 '패킹이 진짜 시험'(C53 ⑤ 의도). R33은 보드-맹목이면 즉사라 아예 뺌(p_big=0).
#   ⚠fit 필터·재추첨 없음: 자리 없는 조각도 그대로 배급(막힘사=실력 실패, 부활 가능 — C53 ⑤).
var TRACK_P_BIG: float = 0.00
var TRACK_P_MID: float = 0.42    # SMALL = 1 - BIG - MID = 0.58

# featured 트랙 조각 = 인덱스만의 함수(보드 여유·fit 필터·재추첨 전부 없음).
func _track_piece() -> Dictionary:
	var i: int = piece_idx
	piece_idx += 1
	var rg: RandomNumberGenerator = _track_rng(i, _TRACK_PIECE_CH)
	var rf: float = rg.randf()
	var tier: int = 0                      # 0=SMALL, 1=MID, 2=BIG
	if rf < TRACK_P_BIG:
		tier = 2
	elif rf < TRACK_P_BIG + TRACK_P_MID:
		tier = 1
	var ty: String = _weighted_pick_rng(_tier_pool(tier), rg)
	var c: String = COLORS[rg.randi() % COLORS.size()]
	if track_record:
		track_log.append(["P", i, ty, c])
	return {"type": ty, "color": c, "offsets": (PIECES[ty] as Array).duplicate()}

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
# TODO(감독): DDA 로직·god모드는 스테이지 전용(fail_streak[stage_idx]). 무한모드 도입 시
#   director.difficulty_bias(ctx)로 래핑해 모드별 난이도 보정을 분리할 것. 지금은 Main 유지(최저 위험).
func _dda_score() -> float:
	var fill: float = 1.0 - float(_free_cells()) / float(ROWS * COLS)
	var hp: float = float(core_hp) / float(maxi(1, director.core_hp_max()))
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
	if director.deterministic_track():   # 결정적 트랙: 인덱스-주소 조각(보드 무반응, 재추첨 없음)
		return _track_piece()
	if not dda_enabled or not director.allows_dda():   # 감독이 DDA 불허(무한·featured)면 게이팅, C52 ⑦·C61
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
	if director.deterministic_track():
		# 결정적 트랙은 재추첨 금지(보드-반응 = 결정성 파괴). 못 놓는 트레이도 그대로 → 막힘사(부활 가능).
		for i in range(3):
			tray[i] = _make_piece()
		sel = 0
		return
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
	return Rect2(sx, float(bot_y) + 15.0, float(TRAY_SLOT_W), float(TRAY_SLOT_H))

# ===== 유틸 =====
func _color_of(key: String) -> Color:
	match key:
		"R":
			return C_RED
		"B":
			return C_BLUE
		"Y":
			return C_YELL
		"#":
			return C_DEBRIS   # 뿌리(잠긴 셀) — 충전 연출 경로가 이 색을 읽는다
		"H":
			return C_BOSS     # 감시자 머리 셀
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
	return Vector2(BOARD_X + col * CELL + CELL * 0.5, board_y + row * CELL + CELL * 0.5)

# 적 몸통의 중심 = 셀 중심. E_BODY_DY는 0이다.
# C41은 상시 HP 게이지가 셀 위쪽을 차지하니 몸통을 아래로(=10) 내려 게이지가 머리를
# 잘라먹지 않게 했다. 이제 게이지는 '피격당하고 살아남은 적'에게만, 그것도 드물게 뜨므로
# (최소 일격이 대부분의 적을 원샷 — C41) 상시 자리를 비워둘 이유가 없다 → 몸통을 셀
# 한가운데로 되돌려 '외형만'인 평소 모습을 깔끔하게. 드물게 뜨는 바가 머리를 조금 덮는
# 건 '유닛 위 체력바'의 흔한 문법이라 모양 인지를 해치지 않는다.
# 사망 팝·파편·임팩트·데미지 숫자는 계속 이 좌표를 쓴다(이제 셀 중심과 같다).
const E_BODY_DY: float = 0.0

func _enemy_pos(col: int, row: int) -> Vector2:
	return _cell_center(col, row) + Vector2(0.0, E_BODY_DY)

# 조각이 차지하는 칸 크기 (offsets는 원점 (0,0) 기준 정규화되어 있다)
func _piece_bbox(offsets: Array) -> Vector2i:
	var mx: int = 0
	var my: int = 0
	for o in offsets:
		var ov: Vector2i = o as Vector2i
		mx = maxi(mx, ov.x)
		my = maxi(my, ov.y)
	return Vector2i(mx + 1, my + 1)

# 들고 있는 조각의 좌상단 픽셀 — 포인터 위로 DRAG_LIFT 만큼 띄우고 가로 중앙을 맞춘다
func _drag_origin_px() -> Vector2:
	var active: Dictionary = _active()
	if active.is_empty():
		return Vector2.ZERO
	var bb: Vector2i = _piece_bbox(active["offsets"])
	# 클릭 방식(마우스)에선 조각을 커서에 붙인다. 손가락이 가릴 일이 없으니 들어올릴 이유도 없다.
	var lift: float = 0.0 if click_mode else DRAG_LIFT
	var ctr: Vector2 = drag_pos - Vector2(0.0, lift)
	return ctr - Vector2(float(bb.x) * CELL, float(bb.y) * CELL) * 0.5

# 들고 있는 조각의 위치 → 앵커 칸. round이므로 '가장 가까운 칸'에 자석처럼 붙는다.
func _sync_hover_from_drag() -> void:
	var tl: Vector2 = _drag_origin_px()
	hover_col = roundi((tl.x - float(BOARD_X)) / float(CELL))
	hover_row = roundi((tl.y - float(board_y)) / float(CELL))


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
			return _t("ll_double")
		3:
			return _t("ll_triple")
		4:
			return _t("ll_tetris")
	if l >= 5:
		return _t("ll_mega")
	return ""

# ⚠뿌리("#")는 '벽' — 채운 칸으로 안 쳐서 줄을 완성시키지 않는다. 그래야 (a) 뿌리 옆에 놔도
#   안 터지고(헷갈림 제거), (b) 보스가 뿌릴수록 네 클리어를 거들지 못한다(압박이 단조로 작동).
#   머리("H")는 채운 칸으로 쳐서 그 줄을 완성하면 뜯긴다(딜). 빈 칸("")·뿌리("#")만 줄을 끊는다.
func _full_rows() -> Array:
	var out: Array = []
	for r in range(ROWS):
		var full: bool = true
		for c in range(COLS):
			if board[r][c] == "" or board[r][c] == "#":
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
			if board[r][c] == "" or board[r][c] == "#":
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

# ② 콤보=청소 범위: 완성 줄에서 매 콤보 '한 줄씩' 추가(총 레인 수 = combo).
#    추가 방향은 바깥으로 교대(줄0 → +1 → −1 → +2…) = 완성 줄 중심 확산, 보드 밖은 스킵.
#    링 = 추가 순서(0=완성 줄). 반환 값 col/row → ring.
#    전멸(combo 임계 or 밴드가 전 열/행 커버)이면 전 열을 ring 0으로 채운다.
# ★ 실제 처치(_begin_resolve)와 조준 프리뷰(_draw_board)가 이 한 함수를 공유한다 —
#   프리뷰가 '누가 죽나'를 실제와 어긋나지 않게 말하려면 같은 셈을 써야 한다(C31 원칙).
func _blast_band(rows: Array, cols: Array, combo_val: int) -> Dictionary:
	var lanes_n: int = maxi(1, combo_val)
	var band_cols: Dictionary = {}   # col -> ring(추가 순서)
	for c in cols:
		var added: int = 0
		var k: int = 0
		while added < lanes_n and k < COLS * 2:
			var off: int = 0 if k == 0 else ((k + 1) / 2) * (1 if (k % 2) == 1 else -1)
			k += 1
			var cc: int = int(c) + off
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
			var rr: int = int(r) + offr
			if rr < 0 or rr >= ROWS:
				continue
			if not band_rows.has(rr) or addedr < band_rows[rr]:
				band_rows[rr] = addedr
			addedr += 1
	var full_board: bool = combo_val >= CLIMAX_COMBO or band_cols.size() >= COLS or band_rows.size() >= ROWS
	if full_board:
		# 전 열을 ring 0으로 채움 → 모든 적 동시 피격
		band_cols.clear()
		band_rows.clear()
		for c2 in range(COLS):
			band_cols[c2] = 0
	return {"cols": band_cols, "rows": band_rows, "full_board": full_board}

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
		# 밴드(콤보=청소 범위)는 _blast_band가 계산 — 조준 프리뷰와 같은 셈을 공유한다.
		var band: Dictionary = _blast_band(rows, cols, combo)
		var band_cols: Dictionary = band["cols"]   # col -> ring(추가 순서)
		var band_rows: Dictionary = band["rows"]   # row -> ring(추가 순서)
		var full_board: bool = band["full_board"]  # 전멸: 순차 대신 '한 방 전멸'
		var max_ring: int = 0            # 실제 존재하는 가장 바깥 링(물결 시각 길이 보장용)
		for v in band_cols.values():
			max_ring = maxi(max_ring, v)
		for v in band_rows.values():
			max_ring = maxi(max_ring, v)
		if full_board:
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
	_add_endless_score(director.clear_score(flash_lines))   # 점수는 감독 소유(scored 모드만 >0). 클리어당 기본점=막힘사도 무보상 아니게, C58
	var head_hit: int = 0   # 이번 클리어로 뜯긴 머리("H") 셀 수 = 보스 피격량(뿌리 "#"는 HP 아님, 자리만)
	for ci in clear_cells:
		var cc: Vector2i = ci as Vector2i
		var mark: String = board[cc.y][cc.x]
		if mark == "H":
			head_hit += 1
		board[cc.y][cc.x] = ""
		var p: Vector2 = _cell_center(cc.x, cc.y)
		var pcol: Color = clear_tint            # 기본 = 놓은 조각 색
		if mark == "H":
			pcol = C_BOSS                       # 머리는 바이올렛으로 뜯겨나간다
		elif mark == "#":
			pcol = C_DEBRIS                     # 뿌리는 강철회색으로 잘려나간다
		cell_pops.append({"pos": p, "life": 0.16, "max": 0.16, "color": pcol})
		for _n in range(3):
			var ang: float = randf() * TAU
			var spd: float = randf_range(60.0, 170.0)
			var life: float = randf_range(0.22, 0.40)
			debris.append({
				"pos": p, "vel": Vector2(cos(ang), sin(ang)) * spd,
				"life": life, "max": life, "color": pcol, "size": randf_range(4.0, 8.0),
			})
	if head_hit > 0 and boss_hp > 0:
		boss_hp = maxi(0, boss_hp - head_hit)   # 머리 1칸당 1딜 — 한 줄에 머리 여럿 몰아 뜯으면 복리
		hitstop = maxf(hitstop, 0.10)           # 보스 피격 손맛(시간 살짝 멎음)
		shake_timer = maxf(shake_timer, SHAKE_DUR * 0.5)   # 보스가 움찔
		_recede_tendrils()                      # 피격 반동: 각 촉수 1칸 회수 = 뿌리 제거의 유일한 상시 경로(관리 가능한 압박)
	if bool(st.get("boss", false)):
		_retract_dead_mouths()                  # 머리 다 뜯긴 입 열의 촉수 전체 회수(자기-완화)
	clear_cells = []
	outline_timer = LINE_OUTLINE_DUR   # ④ 줄 자리에 남는 색 테두리 잔상
	# 보상 텍스트(COMBO xN)와 섬광은 파괴 순간에. 파괴가 이제 한순간이라 겹치지 않는다.
	flash_timer = FLASH_DUR
	hitstop = maxf(hitstop, 0.05)

# 전멸(화면 전체 청소) 클라이맥스 — 보드 중앙에서 퍼지는 큰 충격파 + 히트스톱(셰이크·전체화면 섬광 없음)
func _fire_climax() -> void:
	var ctr: Vector2 = Vector2(BOARD_X + COLS * CELL * 0.5, board_y + ROWS * CELL * 0.5)
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
	var ep: Vector2 = _enemy_pos(e["col"], e["row"])
	# 보석: 블라스트가 닿으면 낚아챈다 = 획득(처치 아님). 카운트는 보석이 상단 그 색 카운터에 '도착'할 때 오른다
	#   (연출·로직 일치) → 잡는 순간엔 작은 스파크 + 카운터로 빨려가는 비행만 띄운다.
	if etype == "gem":
		var gt: int = int(e.get("gtype", 0))
		var gcol: Color = GEM_COLORS[gt % GEM_COLORS.size()]
		impacts.append({"pos": ep, "life": 0.20, "max": 0.20, "color": gcol, "radius": CELL * 0.42, "star": true})
		gem_flights.append({"from": ep, "to": _collect_counter_pos(gt), "t": 0.0, "dur": 0.42, "gtype": gt, "color": gcol})
		kill_pulse = 0.35
		hitstop = maxf(hitstop, 0.05)
		enemies.remove_at(found)
		return
	e["hp"] -= h["dmg"]
	score += h["dmg"]
	# ② 로켓 명중 임팩트 버스트 (확 커졌다 꺼지는 별+링)
	impacts.append({"pos": ep, "life": 0.22, "max": 0.22, "color": Color(1.0, 0.98, 0.7), "radius": CELL * 0.30, "star": true})
	# 데미지 숫자: 크고 팡 (화면 유일 전투 숫자 — 확실히 보이게)
	var dmg_sz: int = clampi(34 + int(h["dmg"] / 15), 34, 64)
	_add_floater(ep + Vector2(0.0, -6.0), "-%d" % h["dmg"], Color(1.0, 0.95, 0.5), FLOAT_DUR, dmg_sz, true)
	if e["hp"] <= 0:
		# ① 극적 사망: 스케일 팝 + 파편 버스트 + 밝은 플래시 + 히트스톱
		_spawn_death(etype, ep)
		enemies.remove_at(found)
		# 분열은 이제 '처치'가 아니라 '분열선 도달'로 발동한다(advance_step). 여기선 안 뱉는다 —
		#   선 위에서 잡으면 쌍둥이가 아예 안 생김(잡는 게 이득). 웨이브 카운트엔 gen0만: gen1(쌍둥이)은
		#   순수 추가 위협이라 killed에서 뺀다(웨이브 총량을 안 줄여 '쉽게 쓸려 더 쉬워짐' 함정 회피).
		var is_primary: bool = not (etype == "split" and int(e.get("gen", 0)) == 1)
		if is_primary:
			killed += 1
		_add_endless_score(director.kill_score(combo))   # 처치×콤보(주 지표), 감독 소유. 쌍둥이도 팝하면 보상(잡는 게 이득 = 분열 재설계와 결), C52·C61
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
				"from": ep, "to": _enemy_pos(e["col"], new_row), "life": 0.3, "max": 0.3,
			})
		# 탱크가 버틸 때: 청록 방패링 + "BLOCK" 라벨 (역할 학습)
		if etype == "tank":
			impacts.append({"pos": ep, "life": 0.32, "max": 0.32, "color": C_E_FAST, "radius": CELL * 0.5})
			_add_floater(ep + Vector2(0.0, -CELL * 0.42), _t("tell_block"), C_E_FAST, 0.55, 18)

# 로켓 머리 위치 (prog 0=발사단 → 1=라인 끝)
func _rocket_pos(rocket: Dictionary, prog: float) -> Vector2:
	if rocket["dir"] == "col":
		var rx: float = BOARD_X + int(rocket["idx"]) * CELL + CELL * 0.5
		var b_bot: float = board_y + ROWS * CELL
		return Vector2(rx, b_bot + (board_y - b_bot) * prog)   # 아래→위
	var ry: float = board_y + int(rocket["idx"]) * CELL + CELL * 0.5
	return Vector2(BOARD_X + (COLS * CELL) * prog, ry)         # 좌→우

# 발사 지점 머즐 플래시 (밝은 섬광)
func _spawn_muzzle(dir: String, idx: int) -> void:
	var pos: Vector2
	if dir == "col":
		pos = Vector2(BOARD_X + idx * CELL + CELL * 0.5, board_y + ROWS * CELL)   # 아래 끝
	else:
		pos = Vector2(BOARD_X, board_y + idx * CELL + CELL * 0.5)                 # 좌 끝
	impacts.append({"pos": pos, "life": 0.16, "max": 0.16, "color": Color(1.0, 0.95, 0.6), "radius": CELL * 0.34, "star": false})

# 적 타입 → 이펙트용 선명한 색 (어두운 배경/마룬 가시성 보정)
func _etype_fx_color(etype: String) -> Color:
	match etype:
		"fast":
			return C_E_FAST
		"tank":
			return Color("#cbd5e1")   # 밝은 강철 (금속 파편 — 몸체 강철색과 일관, 배경에 안 묻힘). C73
		"swarm":
			return C_E_SWARM
		"split":
			return C_E_SPLIT
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
		"split":
			pieces = 6                                        # 갈라지며 흩는 느낌(자식은 별도 스폰)
			fade = 0.30
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
		_add_floater(Vector2(BOARD_X + int(col) * CELL + CELL * 0.5, board_y + ROWS * CELL + 16.0),
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
	# ⚠거점 파괴가 클리어보다 우선(모드-무관 불변식). 마지막 적이 누수로 total을 채우며 동시에
	#   core_hp를 0으로 만들면 _check_win이 killed+leaked>=total로 clear를 켜버린다 — 죽으며 클리어는 없다.
	#   그래서 _check_win보다 먼저 판정하고, 죽었으면 return해 clear 판정 자체를 건너뛴다.
	if pending_core_dead:
		game_over = true
		pending_core_dead = false
		_begin_core_death()
		fail_streak[stage_idx] = int(fail_streak.get(stage_idx, 0)) + 1   # 연속 실패 → 갓 모드 근접
		return
	_boss_foul()             # 보스 스테이지: 감시자가 이번 턴에 잔해를 떨굴 수 있다(막힘 판정 전 = 파울이 스터크 유발 가능)
	_check_win()
	if not game_clear and not _has_valid_placement():
		game_over = true
		stuck = true
		_begin_stuck_death()
		fail_streak[stage_idx] = int(fail_streak.get(stage_idx, 0)) + 1

# 감시자 머리 설치 — head_cols × head_rows 슬래브를 board 상단에 "H"로 심는다. boss_hp = 그 셀 수.
# ⚠머리가 한 행을 통째로 채우면 배치 순간 자동 클리어된다 → head_cols는 반드시 일부 열만(양옆 빈칸 남김).
func _setup_boss_head() -> void:
	var hrows: int = int(st.get("head_rows", 2))
	var hcols: Array = st.get("head_cols", [])
	var n: int = 0
	for c in hcols:
		var col: int = int(c)
		if col < 0 or col >= COLS:
			continue
		for r in range(mini(hrows, ROWS)):
			board[r][col] = "H"
			n += 1
	boss_hp = n
	boss_hp_max = n

# 감시자 파울 — 예측가능 직하 드립. debris_every 배치마다, 살아있는 각 '입' 열에서 머리 바로 아래
# 첫 빈 칸으로 뿌리("#")를 한 칸 뻗는다(촉수가 아래로 자란다). 입(=그 열의 머리 셀)을 뜯으면 그 열은
# 멈춘다(자기-완화). 무작위 없음 = 방어 계획이 서는 예측가능 압박. 뿌리는 HP가 아니라 자리만 먹는 장애물.
func _boss_foul() -> void:
	if not bool(st.get("boss", false)) or boss_hp <= 0:
		return
	var every: int = maxi(1, int(st.get("debris_every", 2)))
	if place_count % every != 0:
		return
	var hrows: int = int(st.get("head_rows", 2))
	var mouths: Array = st.get("mouths", [])
	var dripped: bool = false
	for mc in mouths:
		var col: int = int(mc)
		if col < 0 or col >= COLS:
			continue
		# 입이 살아있나 = 그 열에 머리 셀("H")이 남았나. 다 뜯겼으면 드립 정지(자기-완화).
		var alive: bool = false
		for r in range(mini(hrows, ROWS)):
			if board[r][col] == "H":
				alive = true
				break
		if not alive:
			continue
		# 직하: 머리 바로 아래부터 스캔해 첫 빈 칸에 뿌리 한 칸(촉수가 contiguous하게 아래로 자란다)
		for r in range(hrows, ROWS):
			if board[r][col] == "":
				board[r][col] = "#"
				place_pops.append({"pos": _cell_center(col, r), "life": PLACE_POP_DUR, "max": PLACE_POP_DUR, "color": C_DEBRIS})
				dripped = true
				break
	if dripped:
		shake_timer = maxf(shake_timer, SHAKE_DUR * 0.5)   # 가벼운 쿵

# 피격 반동 — 머리를 뜯을 때마다 살아있는 각 입 열의 촉수를 맨 아래 한 칸씩 회수한다.
# 뿌리(벽)를 없애는 유일한 상시 경로 = 진행(딜)에 묶여 있어, 잘 칠수록 숨통이 트인다(자기-균형 압박).
func _recede_tendrils() -> void:
	var mouths: Array = st.get("mouths", [])
	for mc in mouths:
		var col: int = int(mc)
		if col < 0 or col >= COLS:
			continue
		for r in range(ROWS - 1, -1, -1):   # 아래에서 위로 첫 뿌리 하나 회수(촉수 끝이 딸려 올라감)
			if board[r][col] == "#":
				board[r][col] = ""
				cell_pops.append({"pos": _cell_center(col, r), "life": 0.16, "max": 0.16, "color": C_DEBRIS})
				break

# 자기-완화 — 머리가 다 뜯긴 입 열은 더 이상 드립 못 하니 남은 촉수를 전부 회수(그 열이 열림).
func _retract_dead_mouths() -> void:
	var hrows: int = int(st.get("head_rows", 2))
	var mouths: Array = st.get("mouths", [])
	for mc in mouths:
		var col: int = int(mc)
		if col < 0 or col >= COLS:
			continue
		var alive: bool = false
		for r in range(mini(hrows, ROWS)):
			if board[r][col] == "H":
				alive = true
				break
		if alive:
			continue
		for r in range(ROWS):
			if board[r][col] == "#":
				board[r][col] = ""

# ===== 스텝 진행 =====
func advance_step() -> void:
	place_count += 1
	# 후반 서지: 진행도(spawned/total)가 surge_at을 넘으면 '밀물이 빨라진다'.
	#   ⚠레버는 전진 속도(step_every)지 스폰 주기가 아니다 — spawn_every를 조이면 적이 뭉쳐
	#   들어와 한 줄로 더 쓸려나가 오히려 쉬워진다(위 STAGES 주석의 비단조 실측). 실제로 거점을
	#   터뜨리는 유일한 축은 전진 속도(C25) → 서지 중 모든 적이 한 단계 빨리 내려온다.
	#   목적: 실패를 판 후반 30%에 몰아 '아까운 실패'를 만든다(F2P 광고 부활의 유인, C47).
	var ctx: Dictionary = _director_ctx()
	surge_active = director.is_surge_active(ctx)   # 렌더/텔레그래프도 읽는 Main 필드 → 스텝당 1회
	ctx["surge_active"] = surge_active
	# 전진 스로틀: step_every 배치마다 1칸. 서지 클램프(하한 2)는 director.effective_step_every가 캡슐화.
	for e in enemies:
		var base_step: int = e.get("step_every", director.hud_step_every())
		var step_every: int = director.effective_step_every(base_step, ctx)
		if place_count % step_every == 0:
			e["row"] += 1

	# 분열: gen0가 분열선(SPLIT_ROW)에 닿는 순간 갈라진다 — 죽여서가 아니라 너무 내려와서.
	#   부모는 절반 HP로 남아 gen0(=웨이브 카운트 유지)이되 split_done으로 재분열 봉쇄, 인접 열에
	#   절반 HP 쌍둥이(gen1=카운터 밖)를 하나 뱉는다. 선 위에서 잡으면 이 분기 자체가 안 옴(깨끗한 처치).
	var pre_split_n: int = enemies.size()   # 이 스텝에 새로 뱉는 쌍둥이는 재검사 안 함
	for si in range(pre_split_n):
		var se: Dictionary = enemies[si]
		if se["etype"] == "split" and int(se.get("gen", 0)) == 0 \
				and not bool(se.get("split_done", false)) and int(se["row"]) >= SPLIT_ROW:
			_split_enemy(se)

	# 누수(거점 도달): 로직은 즉시 반영, 시각 연출은 resolve 끝물로 지연.
	# ⚠누수는 killed가 아니라 leaked로 센다. (구버전은 killed++ 해서 '흘려보내도 목표 진행'
	#  = 진행도·승리조건이 못 막은 적한테 보상을 줬음.)
	var i: int = enemies.size() - 1
	pending_leaks = []
	while i >= 0:
		if enemies[i]["row"] >= ROWS:
			if enemies[i]["etype"] == "gem":
				# 보석 놓침 — 거점 무피해, 진행 손해일 뿐. 바닥에서 회색 파프로 '놓쳤다'를 짧게 알림(보석이 중요함을 학습).
				var gmp: Vector2 = _enemy_pos(int(enemies[i]["col"]), ROWS - 1)
				impacts.append({"pos": gmp, "life": 0.32, "max": 0.32, "color": Color(0.5, 0.5, 0.56), "radius": CELL * 0.42, "star": false})
				enemies.remove_at(i)
			else:
				core_hp -= 1                 # 자식도 거점은 깎는다(진짜 위협)
				if int(enemies[i].get("gen", 0)) == 0:
					leaked += 1              # 단 웨이브 카운터엔 gen0(원본)만
				pending_leaks.append(enemies[i]["col"])
				enemies.remove_at(i)
		i -= 1
	pending_core_dead = core_hp <= 0
	if pending_core_dead:
		return   # 거점 파괴 스텝: 블라스트 없이 누수 연출 후 게임오버

	# 스폰: 감독이 스케줄(밀도 하한 floor + 스로틀·온보딩·swarm 클러스터)을 결정하고, 코어는 spec을 실행만.
	#   ⚠감독의 randi 순서는 원본과 정확히 일치(floor=열→타입 / throttle=타입→(swarm:count→shuffle | col)).
	#   floor·swarm·surge의 설계 의도(밀도 손잡이, desync, 비단조)는 StageMode 주석 참조.
	var sctx: Dictionary = _director_ctx()   # 누수 반영된 현재 상태(enemy_count)
	if director.deterministic_track():
		# 결정적 트랙: 이 스텝의 모든 스폰 draw를 (시드, 깊이) 고유 rng가 소유 → spawn[d]가 인덱스만의 함수.
		#   floor 훅은 FeaturedMode에서 off(enemy_count 반응 = 결정성 파괴하는 유일한 스폰 경로).
		sctx["rng"] = _track_rng(place_count, _TRACK_SPAWN_CH)
	for spec in director.plan_floor_spawn(sctx):
		_spawn_one(spec["col"], spec["etype"], spec["step_override"])
	sctx["spawned"] = spawned                # floor 스폰이 올린 spawned를 스로틀이 읽도록
	for spec in director.plan_throttled_spawn(sctx):
		if track_record:
			track_log.append(["S", place_count, int(spec["col"]), spec["etype"]])
		_spawn_one(spec["col"], spec["etype"], spec["step_override"])

	# 받기형 수집: gem_every 배치마다 보석 1개를 '조용한 열'(다른 유닛 없는 곳)에 떨군다.
	#   ⚠무작위가 아니라 조용한 열이 핵심 — 보석이 위협과 다른 열에 떠야, 잡기가 '방어와 무관한 전용
	#   클리어'를 요구한다 → 순수 기회비용(줍기 vs 막기)이 운 아닌 구조로 보장된다. 없으면 우연히 겹쳐 공짜.
	if bool(st.get("collect", false)):
		var ge: int = maxi(1, int(st.get("gem_every", 3)))
		if not _collect_done() and place_count % ge == 0:
			_spawn_gem(_quiet_gem_col())

# _pick_etype는 StageMode.pick_etype로 이동(감독이 스폰 결정을 소유).

# 타입 i의 '확보량' = 이미 카운트됨 + 아직 카운터로 날아가는 중(곧 카운트됨). 스폰 판단이 이걸 써서 과스폰 방지.
func _gem_secured(i: int) -> int:
	var got: int = int(collected_by_type[i]) if i < collected_by_type.size() else 0
	for gfl in gem_flights:
		if int(gfl["gtype"]) == i:
			got += 1
	return got

# 상단 수집 카드에서 타입 t 카운터의 화면 위치(비행 도착점). _draw_hud/_draw_collect_goal 레이아웃과 동일 산식.
func _collect_counter_pos(t: int) -> Vector2:
	var gw: float = 250.0
	var start_x: float = (VW_BASE - (gw + 190.0 + 24.0)) * 0.5   # _draw_hud의 goal_r.x
	var n: int = maxi(1, (st.get("collect_targets", [1]) as Array).size())
	return Vector2(start_x + (gw / float(n)) * (float(t) + 0.5), 14.0 + 56.0)

# 모든 타입 quota를 확보(카운트+비행)했나 = 더 뱉을 필요 없나(스폰 게이트). 실제 승리는 is_cleared(카운트만).
func _collect_done() -> bool:
	var tgts: Array = st.get("collect_targets", [])
	for i in range(tgts.size()):
		if _gem_secured(i) < int(tgts[i]):
			return false
	return true

# 보석 1개 스폰 — 아직 확보 덜 된 타입 중에서 무작위(확보한 타입은 안 뱉음 = 쓸데없는 보석 방지).
#   gem_fast면 위협보다 한 단계 빨리 하강(데드라인 조임). 첫 등장만 콜아웃.
func _spawn_gem(col: int) -> void:
	var tgts: Array = st.get("collect_targets", [])
	var need: Array = []
	for i in range(tgts.size()):
		if _gem_secured(i) < int(tgts[i]):
			need.append(i)
	if need.is_empty():
		return
	var gt: int = int(need[game_rng.randi() % need.size()])
	var gstep: int = director.hud_step_every()
	if bool(st.get("gem_fast", false)):
		gstep = maxi(1, gstep - 1)
	enemies.append({"col": col, "row": 0, "vis_row": 0.0, "hp": 1, "maxhp": 1, "etype": "gem", "gtype": gt, "id": enemy_seq, "step_every": gstep})
	enemy_seq += 1
	if not seen_types.get("gem", false):
		seen_types["gem"] = true
		_set_callout(_t("callout_gem"))

# 보석 스폰 열 고르기 — 현재 유닛(위협·보석)이 없는 '조용한 열'을 우선. 그런 열이 없으면 무작위.
#   이러면 보석이 방어 전선과 다른 열에 떠서, 잡으려면 그 열에 전용 클리어를 써야 한다(순수 기회비용).
func _quiet_gem_col() -> int:
	var busy: Dictionary = {}
	for e in enemies:
		busy[int(e["col"])] = true
	var free: Array = []
	for c in range(COLS):
		if not busy.has(c):
			free.append(c)
	if free.is_empty():
		return game_rng.randi() % COLS
	return int(free[game_rng.randi() % free.size()])

# 적 1마리 스폰 (타입별 HP 배율 적용). step_override>0이면 전진 주기를 강제(무리 desync용)
func _spawn_one(col: int, etype: String, step_override: int = 0) -> void:
	# (보석 gem은 _spawn_gem이 따로 처리 — 타입·gem_fast·필요타입 필터가 붙는다)
	# HP·전진주기는 감독(StageMode)이 소유. spawned = 이 스폰의 인덱스(HP 램프에 사용).
	#   ctx = run-state(점수·best) — 무한모드 PB 너머 HP 발화가 스폰 시점 점수로 읽는다(다른 모드는 무시).
	var hp: int = director.enemy_hp(etype, spawned, _director_ctx())
	var step_every: int = step_override if step_override > 0 else director.enemy_step(etype)
	enemies.append({"col": col, "row": 0, "vis_row": 0.0, "hp": hp, "maxhp": hp, "etype": etype, "id": enemy_seq, "step_every": step_every})
	enemy_seq += 1
	spawned += 1
	# 첫 등장 콜아웃 (타입당 1회)
	if not seen_types.get(etype, false):
		seen_types[etype] = true
		match etype:
			"fast":
				_set_callout(_t("callout_fast"))
			"tank":
				_set_callout(_t("callout_tank"))
			"swarm":
				_set_callout(_t("callout_swarm"))
			"split":
				_set_callout(_t("callout_split"))   # 이제 파랑 점선이 실제로 보인다(공간 기준)

# 분열선 도달 → 부모는 절반 HP로 남고(gen0 유지=웨이브 카운트 불변, split_done로 재분열 봉쇄),
#   빈 인접 열 하나에 절반 HP 쌍둥이(gen1)를 뱉는다. 결정적 배치(randi 없음) = 회귀 시드 불변.
#   쌍둥이는 spawned/killed/leaked 카운터 밖(순수 추가 위협). 손자 없음(gen1·split_done 고정).
func _split_enemy(parent: Dictionary) -> void:
	var half: int = maxi(1, roundi(float(parent["maxhp"]) * SPLIT_CHILD_FRAC))
	parent["maxhp"] = half
	parent["hp"] = mini(int(parent["hp"]), half)   # 하나가 둘로 = 부모도 절반짜리 몸으로
	parent["split_done"] = true
	var pcol: int = int(parent["col"])
	var prow: int = int(parent["row"])
	var pstep: int = int(parent.get("step_every", director.hud_step_every()))
	var pvis: float = float(parent.get("vis_row", float(prow)))
	# 쌍둥이는 빈 인접 열 하나에(왼쪽 우선). 가장자리면 반대쪽. 결정적(randi 없음).
	for dc in [-1, 1]:
		var cc: int = pcol + dc
		if cc < 0 or cc >= COLS:
			continue
		enemies.append({
			"col": cc, "row": prow, "vis_row": pvis, "hp": half, "maxhp": half,
			"etype": "split", "id": enemy_seq, "step_every": pstep, "gen": 1, "split_done": true,
		})
		enemy_seq += 1
		break   # 쌍둥이는 딱 하나(부모 잔존 + 쌍둥이 = 예전과 같은 2몸)
	# 갈라지는 순간 파랑 링 버스트 = "지금 둘이 됐다"
	impacts.append({"pos": _enemy_pos(pcol, prow), "life": 0.24, "max": 0.24, "color": C_E_SPLIT, "radius": CELL * 0.42})

func _set_callout(text: String) -> void:
	callout_text = text
	callout_timer = CALLOUT_DUR

# 클리어 = 모든 적이 '처리'됨(처치 or 누수) = 더 이상 올 적도, 보드 위 적도 없음.
# 누수분은 거점 HP로 이미 값을 치렀고, core_hp를 total보다 훨씬 작게 잡아 '흘려보내며 이기기'를 봉쇄한다(기준 ③).
# 감독에 넘길 런타임 스냅샷. 감독은 이 값만 읽고 스폰·난이도·종료를 결정한다(코어 상태 직접 접근 X).
func _director_ctx() -> Dictionary:
	return {
		"place_count": place_count, "spawned": spawned, "killed": killed, "leaked": leaked,
		"core_hp": core_hp, "boss_hp": boss_hp, "collected_by_type": collected_by_type, "combo": combo, "drought": drought,
		"enemy_count": enemies.size(), "free_cells": _free_cells(),
		"fail_streak": int(fail_streak.get(stage_idx, 0)),
		"score": endless_score, "best": endless_best,   # PB 너머 발화 램프(감독이 소유). best>0일 때만 발화.
		"surge_enabled": surge_enabled, "floor_enabled": floor_enabled,
		"cols": COLS, "enemy_types": ENEMY_TYPES,
		"rng": game_rng,   # 감독 스폰 결정은 게임 스트림에서(코스메틱 분리)
	}

func _check_win() -> void:
	if director.is_cleared(_director_ctx()):
		game_clear = true
		cleared[stage_idx] = true
		_save_campaign()               # 진행도 즉시 영속 — 앱을 닫아도 해금 유지
		fail_streak[stage_idx] = 0     # 깼으니 갓 모드 해제
		_spawn_confetti()              # 클리어 축하 — 3색 색종이가 위에서 쏟아진다(경축, 공격 아님)

# 클리어 축하 색종이. 화면 위에서 3색(조각 색) 조각이 나풀나풀 떨어진다.
#   방향(위→아래)이 골드 충격파(중앙→바깥, 공격)와 반대라 '경축'으로 읽힌다. 색은 R/B/Y =
#   플레이어가 쓴 조각 색이라 '내가 놓은 색들의 축제'(C30 색 통일의 연장). 저아트 톤이라 절제.
func _spawn_confetti() -> void:
	confetti = []
	for _n in range(56):
		var key: String = COLORS[randi() % COLORS.size()]
		var life: float = randf_range(2.4, 4.2)
		confetti.append({
			"pos": Vector2(randf_range(0.0, 800.0), randf_range(-140.0, -10.0)),
			"vel": Vector2(randf_range(-24.0, 24.0), randf_range(70.0, 150.0)),
			"life": life, "max": life,
			"color": _color_of(key),
			"rot": randf_range(0.0, TAU),
			"spin": randf_range(-4.0, 4.0),
			"w": randf_range(6.0, 10.0),
			"h": randf_range(3.0, 5.0),
			"sway": randf_range(0.6, 1.5),     # 좌우 나풀 진폭
			"phase": randf_range(0.0, TAU),
		})


# ===== 놓을 곳 없음 죽음 =====
# 연출 총 길이: 마지막 행이 다 밝아질 때까지 + 응시
func _stuck_total() -> float:
	return float(ROWS - 1) * STUCK_ROW_GAP + STUCK_FADE + STUCK_HOLD

# 연출이 재생 중인가 (재생 중엔 결과 팝업을 띄우지 않는다)
func _death_playing() -> bool:
	if stuck_t >= 0.0 and stuck_t < _stuck_total():
		return true
	return core_t >= 0.0 and core_t < _core_total()

# ===== 거점 파괴 죽음 =====
func _core_total() -> float:
	return CORE_FALL_AT + float(COLS - 1) * CORE_COL_STAGGER + CORE_FALL_DUR + CORE_HOLD

func _begin_core_death() -> void:
	core_t = 0.0
	core_burst_done = false
	hitstop = maxf(hitstop, CORE_HITSTOP)   # 뚫리는 순간 시간이 멎는다 (hitstop 중엔 core_t도 멈춘다)

# 거점 띠가 터지는 순간 — 파편이 아래로 쏟아지고 화면이 붉게 흔들린다
func _core_burst() -> void:
	red_flash = RED_FLASH_DUR
	shake_timer = SHAKE_DUR * 2.0
	var sy: float = float(board_y + ROWS * CELL) + 4.0
	var sw: float = float(COLS * CELL)
	for _n in range(30):
		var px: float = float(BOARD_X) + randf() * sw
		var life: float = randf_range(0.35, 0.7)
		debris.append({
			"pos": Vector2(px, sy + randf_range(0.0, 32.0)),
			"vel": Vector2(randf_range(-120.0, 120.0), randf_range(-260.0, -40.0)),
			"life": life, "max": life,
			"color": Color(0.95, 0.3, 0.25).lerp(Color(1.0, 0.8, 0.4), randf()),
			"size": randf_range(4.0, 9.0),
		})

# 한 열이 무너지기 시작하는 시각 — 열마다 시차를 줘서 한 판이 아니라 우르르
func _core_fall_offset(col: int) -> float:
	if core_t < 0.0:
		return 0.0
	var dt: float = core_t - (CORE_FALL_AT + float(col) * CORE_COL_STAGGER)
	if dt <= 0.0:
		return 0.0
	return 0.5 * CORE_GRAVITY * dt * dt

# 거점 띠 자체의 낙하 — 보드보다 먼저 떨어진다 (거점이 무너지고 → 받칠 게 없어진 보드가 따라 쏟아진다)
func _core_strip_offset() -> float:
	if core_t < 0.0 or core_t <= CORE_BURST:
		return 0.0
	var dt: float = core_t - CORE_BURST
	return 0.5 * CORE_GRAVITY * dt * dt

# 메울 칸과 색을 지금 확정한다 — 매 프레임 randi()를 돌리면 색이 부글부글 끓는다
func _begin_stuck_death() -> void:
	stuck_fill = {}
	for r in range(ROWS):
		for c in range(COLS):
			if board[r][c] == "":
				stuck_fill[Vector2i(c, r)] = COLORS[randi() % COLORS.size()]
	stuck_t = 0.0

# 특정 칸이 메워지기 시작하는 시각 (맨 아랫줄 = 0)
func _stuck_cell_alpha(cell: Vector2i) -> float:
	var start: float = float(ROWS - 1 - cell.y) * STUCK_ROW_GAP
	return clampf((stuck_t - start) / STUCK_FADE, 0.0, 1.0)

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
	# 착지 팝: 놓은 칸마다 '탁' 들어앉는 신호. 완성 못 시킨 수(절반 이상)도 이제 손맛이 남는다.
	# 소멸 팝(밖으로 부풂)과 반대로 수축해 '도착'을 말한다. 숫자 없음(C9/C23: 목표는 '남은 적').
	var place_col: Color = _color_of(active["color"])
	for ci2 in cells:
		var pc2: Vector2i = ci2 as Vector2i
		place_pops.append({"pos": _cell_center(pc2.x, pc2.y), "life": PLACE_POP_DUR, "max": PLACE_POP_DUR, "color": place_col})
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
# 포인터 아래 트레이 조각을 집는다 (집었으면 true)
func _pick_up(pos: Vector2) -> bool:
	for i in range(3):
		if tray[i].is_empty():
			continue
		if _tray_slot_rect(i).has_point(pos):
			dragging = true
			drag_slot = i
			sel = i
			drag_pos = pos
			snapback = {}
			_sync_hover_from_drag()
			return true
	return false

# 들고 있던 조각을 트레이로 돌려보낸다 (못 놓는 자리에서 뗐거나, 모드를 바꿨을 때)
func _return_held() -> void:
	if not dragging:
		return
	snapback = {"slot": drag_slot, "from": _drag_origin_px(), "t": SNAPBACK_DUR}
	dragging = false
	drag_slot = -1

func _input(event: InputEvent) -> void:
	# ── 메인 메뉴(허브): Adventure(스테이지) / Classic(무한) ──
	# 세로 중앙 오프셋(_ui_dy)만큼 화면을 내려 그리므로, 입력 좌표는 그만큼 되돌려 히트테스트한다.
	if mode == "menu":
		var mdy: Vector2 = Vector2(0.0, _ui_dy())
		if event is InputEventMouseMotion:
			var mmp: Vector2 = (event as InputEventMouseMotion).position - mdy
			_adv_hover = MENU_ADV_BTN.has_point(mmp)
			_classic_hover = MENU_CLASSIC_BTN.has_point(mmp)
			_lb_hover = MENU_LB_BTN.has_point(mmp)
		elif event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				var mbp: Vector2 = mb.position - mdy
				if MENU_ADV_BTN.has_point(mbp):
					mode = "select"                # 스테이지 목록으로
				elif MENU_CLASSIC_BTN.has_point(mbp):
					_start_endless()               # 무한 모드 바로 시작
				elif MENU_LB_BTN.has_point(mb.position):
					mode = "leaderboard"           # 우상단 트로피 → 리더보드 peek
		elif event is InputEventKey:
			var mk: InputEventKey = event as InputEventKey
			if mk.pressed and (mk.keycode == KEY_SPACE or mk.keycode == KEY_ENTER):
				mode = "select"                    # 기본 = Adventure
			elif mk.pressed and (mk.keycode == KEY_E or mk.keycode == KEY_0):
				_start_endless()                   # E/0 = Classic(무한)
			elif mk.pressed and mk.keycode == KEY_L:
				mode = "leaderboard"               # L = 리더보드
		return

	# ── 리더보드 화면(peek): 뒤로=메뉴, 하단 CTA=무한 도전 ──
	if mode == "leaderboard":
		if event is InputEventMouseMotion:
			var lp: Vector2 = (event as InputEventMouseMotion).position
			_back_hover = BACK_BTN.has_point(lp)
			_lb_play_hover = LB_PLAY_BTN.has_point(lp)
		elif event is InputEventMouseButton:
			var lmb: InputEventMouseButton = event as InputEventMouseButton
			if lmb.pressed and lmb.button_index == MOUSE_BUTTON_LEFT:
				if BACK_BTN.has_point(lmb.position):
					mode = "menu"
				elif LB_PLAY_BTN.has_point(lmb.position):
					_start_endless()
		elif event is InputEventKey:
			var lk: InputEventKey = event as InputEventKey
			if lk.pressed and lk.keycode == KEY_ESCAPE:
				mode = "menu"
			elif lk.pressed and (lk.keycode == KEY_SPACE or lk.keycode == KEY_E):
				_start_endless()
		return

	# ── 레벨 선택 화면 ──
	if mode == "select":
		var sdy: Vector2 = Vector2(0.0, _ui_dy())
		if event is InputEventMouseMotion:
			var mp: Vector2 = (event as InputEventMouseMotion).position - sdy
			hover_stage = _stage_at(mp)
			_play_hover = PLAY_BTN.has_point(mp)
			_back_hover = BACK_BTN.has_point(mp)
		elif event is InputEventMouseButton:
			var sm: InputEventMouseButton = event as InputEventMouseButton
			if sm.pressed and sm.button_index == MOUSE_BUTTON_LEFT:
				var smp: Vector2 = sm.position - sdy
				if BACK_BTN.has_point(smp):
					mode = "menu"                       # 허브로 복귀(Classic은 메뉴에)
				elif PLAY_BTN.has_point(smp):
					_start_stage(_current_stage())      # 하단 큰 버튼 = 지금 도전할 스테이지
				else:
					var hit: int = _stage_at(smp)   # 이미 깬 스테이지 재도전(잠긴 건 -1)
					if hit >= 0:
						_start_stage(hit)
		elif event is InputEventKey:
			var sk: InputEventKey = event as InputEventKey
			if sk.pressed and (sk.keycode == KEY_SPACE or sk.keycode == KEY_ENTER):
				_start_stage(_current_stage())
			elif sk.pressed and sk.keycode == KEY_ESCAPE:
				mode = "menu"                          # 뒤로 = 허브
				# ⚠'오늘의 판'(featured) 진입은 C60에서 보류 — 플레이어 노출 제거. 엔진은 tools/probe로만 도달.
			elif sk.pressed and sk.keycode >= KEY_1 and sk.keycode < KEY_1 + STAGES.size():
				var pick: int = sk.keycode - KEY_1
				if _is_unlocked(pick):
					_start_stage(pick)
			elif sk.pressed and sk.keycode == KEY_0:
				dev_unlock_all = not dev_unlock_all   # ⚠플테 전용: 전 스테이지 해금 토글
				queue_redraw()
		return

	# ── 죽음 연출 재생 중: 아무 입력이나 누르면 건너뛴다 (재도전을 반복할 땐 매번 1.6초가 짐이 된다)
	if _death_playing():
		var skip: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
				or (event is InputEventKey and (event as InputEventKey).pressed)
		if skip:
			stuck_t = _stuck_total()
		return

	# ── 결과 팝업: 재도전 버튼(또는 SPACE) / 홈 버튼(또는 ESC) ──
	#    빈 곳 클릭은 무시한다 — 모달이므로, 잘못 누르고 홈으로 튕기는 사고를 막는다.
	if game_over or game_clear:
		var lay: Dictionary = _result_layout()
		var has_cont: bool = lay["revivable"]
		if event is InputEventMouseMotion:
			var rp: Vector2 = (event as InputEventMouseMotion).position
			_retry_hover = (lay["retry"] as Rect2).has_point(rp)
			_home_hover = (lay["home"] as Rect2).has_point(rp)
			_cont_hover = has_cont and (lay["cont"] as Rect2).has_point(rp)
		elif event is InputEventMouseButton:
			var mbe: InputEventMouseButton = event as InputEventMouseButton
			if mbe.pressed and mbe.button_index == MOUSE_BUTTON_LEFT:
				if has_cont and (lay["cont"] as Rect2).has_point(mbe.position):
					_revive()
				elif (lay["retry"] as Rect2).has_point(mbe.position):
					_result_advance()
				elif (lay["home"] as Rect2).has_point(mbe.position):
					mode = _home_mode()
		elif event is InputEventKey:
			var ke: InputEventKey = event as InputEventKey
			# SPACE = 주 동작. 부활 가능하면 '광고 이어하기', 아니면 재도전/다음.
			if ke.pressed and ke.keycode == KEY_SPACE:
				if has_cont:
					_revive()
				else:
					_result_advance()
			elif ke.pressed and ke.keycode == KEY_ESCAPE:
				mode = _home_mode()
		return

	# ── 설정 모달: 열려 있으면 모달 입력만 처리(닫힐 때까지 판 입력 차단) ──
	if settings_open:
		var slay: Dictionary = _settings_layout()
		if event is InputEventMouseMotion:
			var mp2: Vector2 = (event as InputEventMouseMotion).position
			_set_close_hover = (slay["close"] as Rect2).has_point(mp2)
			_set_home_hover = (slay["home_btn"] as Rect2).has_point(mp2)
			_set_replay_hover = (slay["replay_btn"] as Rect2).has_point(mp2)
			_set_sound_hover = (slay["sound_tog"] as Rect2).has_point(mp2)
			_set_bgm_hover = (slay["bgm_tog"] as Rect2).has_point(mp2)
		elif event is InputEventMouseButton:
			var sb: InputEventMouseButton = event as InputEventMouseButton
			if sb.pressed and sb.button_index == MOUSE_BUTTON_LEFT:
				_settings_click(sb.position, slay)
		elif event is InputEventKey:
			var sek: InputEventKey = event as InputEventKey
			if sek.pressed and sek.keycode == KEY_ESCAPE:
				settings_open = false   # ESC = 모달 닫기(홈 아님)
		return

	# 스테이지 인트로 재생 중 — 아무 입력이나 = 즉시 스킵(도킹 건너뜀). 판 입력은 차단(카드 뒤 오배치 방지).
	if intro_t >= 0.0:
		if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
				or (event is InputEventKey and (event as InputEventKey).pressed):
			intro_t = -1.0
		return

	if event is InputEventKey:
		var pk: InputEventKey = event as InputEventKey
		if pk.pressed and pk.keycode == KEY_ESCAPE:
			mode = _home_mode()  # 플레이 중 포기 → 홈(허브)으로
			return

	# resolve 재생 중에는 배치/선택 입력 정지 (연출 끝나면 자동 복귀)
	if resolving:
		return

	# 우상단 기어 호버 (플레이 중 언제나)
	if event is InputEventMouseMotion:
		_gear_hover = SETTINGS_GEAR.has_point((event as InputEventMouseMotion).position)

	# 들고 있는 조각은 두 모드 모두 포인터를 따라온다 — 화면 규칙(스냅=가능/부유=불가)이 같아진다.
	if event is InputEventMouseMotion and dragging:
		drag_pos = (event as InputEventMouseMotion).position
		_sync_hover_from_drag()

	if event is InputEventMouseButton:
		var mbe: InputEventMouseButton = event as InputEventMouseButton
		if mbe.button_index != MOUSE_BUTTON_LEFT:
			return

		# 설정 기어 → 모달 열기(들고 있던 조각은 트레이로 되돌림)
		if mbe.pressed and SETTINGS_GEAR.has_point(mbe.position):
			settings_open = true
			_return_held()
			return

		# 입력 방식 토글 버튼 (PC 테스트 편의용)
		if mbe.pressed and mode_btn.has_point(mbe.position):
			click_mode = not click_mode
			_return_held()   # 모드가 바뀌면 들고 있던 조각은 트레이로 돌려놓는다
			return

		if click_mode:
			# 클릭 방식: 조각 클릭해 집고 → 보드 클릭해 놓는다. 떼기(release)는 쓰지 않는다.
			if not mbe.pressed:
				return
			if not dragging:
				_pick_up(mbe.position)
				return
			if _pick_up(mbe.position):
				return   # 트레이의 다른 조각으로 갈아탐
			drag_pos = mbe.position
			_sync_hover_from_drag()
			if _can_place(_ghost_cells()):
				dragging = false
				drag_slot = -1
				_place_piece()
			# 못 놓는 자리를 클릭하면 조각을 계속 들고 있는다 (매번 다시 집게 하지 않는다)
			return

		# 드래그앤드롭: 트레이에서 집어 → 끌고 → 뗀다.
		if mbe.pressed:
			_pick_up(mbe.position)
		elif dragging:
			drag_pos = mbe.position
			_sync_hover_from_drag()
			if _can_place(_ghost_cells()):
				dragging = false
				drag_slot = -1
				_place_piece()
			else:
				# 못 놓는 자리 → 트레이로 튕겨 돌아간다. 거절은 색이 아니라 '되돌아감'으로 읽힌다.
				_return_held()

# ===== 프레임 =====
func _process(delta: float) -> void:
	if mode == "menu" or mode == "select" or mode == "leaderboard":
		queue_redraw()
		return
	# 스테이지 인트로 진행(중앙→상단 도킹). 적 전진은 배치 기반이라 인트로 중 판은 정지 상태.
	if intro_t >= 0.0:
		intro_t += delta
		if intro_t >= INTRO_TOTAL:
			intro_t = -1.0
		queue_redraw()
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
	if shake_timer > 0.0:
		shake_timer = maxf(0.0, shake_timer - delta)
	if callout_timer > 0.0:
		callout_timer = maxf(0.0, callout_timer - delta)
	if not snapback.is_empty():
		snapback["t"] = float(snapback["t"]) - delta
		if float(snapback["t"]) <= 0.0:
			snapback = {}
	if stuck_t >= 0.0 and stuck_t < _stuck_total():
		stuck_t += delta
		queue_redraw()
	if core_t >= 0.0 and core_t < _core_total():
		core_t += delta
		if not core_burst_done and core_t >= CORE_BURST:
			core_burst_done = true
			_core_burst()
		queue_redraw()
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
	# 보석 비행: 상단 카운터로 빨려간다. 도착하면 그 타입 카운트+1(cap), 카운터 팝, 마지막이면 클리어 발화.
	var gf: int = gem_flights.size() - 1
	while gf >= 0:
		gem_flights[gf]["t"] += delta
		if gem_flights[gf]["t"] >= float(gem_flights[gf]["dur"]):
			var gt2: int = int(gem_flights[gf]["gtype"])
			var tgts2: Array = st.get("collect_targets", [])
			if not game_over and gt2 < collected_by_type.size() and gt2 < tgts2.size() and int(collected_by_type[gt2]) < int(tgts2[gt2]):
				collected_by_type[gt2] += 1
			if gt2 < collect_pop.size():
				collect_pop[gt2] = 0.34   # 카운터 톡 튐
			kill_pulse = 0.35
			gem_flights.remove_at(gf)
			if not game_clear and not game_over:
				_check_win()              # 마지막 보석이 도착하며 클리어
		gf -= 1
	for pi in range(collect_pop.size()):
		if collect_pop[pi] > 0.0:
			collect_pop[pi] = maxf(0.0, collect_pop[pi] - delta)
	var cp: int = cell_pops.size() - 1
	while cp >= 0:
		cell_pops[cp]["life"] -= delta
		if cell_pops[cp]["life"] <= 0.0:
			cell_pops.remove_at(cp)
		cp -= 1
	var pp2: int = place_pops.size() - 1
	while pp2 >= 0:
		place_pops[pp2]["life"] -= delta
		if place_pops[pp2]["life"] <= 0.0:
			place_pops.remove_at(pp2)
		pp2 -= 1
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
	# 색종이 — 완만한 중력 + 좌우 나풀거림(sin) + 회전. 화면 아래로 나가거나 수명 다하면 제거.
	var cf: int = confetti.size() - 1
	while cf >= 0:
		var cc: Dictionary = confetti[cf]
		cc["life"] = float(cc["life"]) - delta
		var cv: Vector2 = cc["vel"]
		cv.y = minf(cv.y + 90.0 * delta, 175.0)   # 완만한 중력 + 종단속도
		cc["vel"] = cv
		cc["phase"] = float(cc["phase"]) + float(cc["sway"]) * delta * 4.0
		var sway_x: float = sin(float(cc["phase"])) * float(cc["sway"]) * 22.0
		cc["pos"] = (cc["pos"] as Vector2) + Vector2(cv.x + sway_x, cv.y) * delta
		cc["rot"] = float(cc["rot"]) + float(cc["spin"]) * delta
		if float(cc["life"]) <= 0.0 or (cc["pos"] as Vector2).y > 1040.0:
			confetti.remove_at(cf)
		cf -= 1
	# 임팩트/막음 링 감쇠
	var im: int = impacts.size() - 1
	while im >= 0:
		impacts[im]["life"] -= delta
		if impacts[im]["life"] <= 0.0:
			impacts.remove_at(im)
		im -= 1
	if kill_pulse > 0.0:
		kill_pulse = maxf(0.0, kill_pulse - delta)
	if pb_pop_t >= 0.0:
		pb_pop_t = maxf(-1.0, pb_pop_t - delta)   # 0 밑으로 떨어지면 대기(-1)로
	# 넘음 배경 전환 — beat면 1로, 아니면 0으로 0.6초에 걸쳐 이징(판 끝까지 지속). 죽음 연출 중엔 얼리지 않음.
	pb_bg_mix = move_toward(pb_bg_mix, 1.0 if endless_beat_best else 0.0, delta / 0.6)
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

	if mode == "menu":
		# 배경은 전체를 덮고, 콘텐츠만 세로 중앙으로 내린다(입력도 같은 오프셋으로 되돌림).
		draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), C_BG)
		draw_set_transform(Vector2(0.0, _ui_dy()))
		_draw_menu(fnt)
		draw_set_transform(Vector2.ZERO)
		return

	if mode == "select":
		draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), C_BG)
		draw_set_transform(Vector2(0.0, _ui_dy()))
		_draw_select(fnt)
		draw_set_transform(Vector2.ZERO)
		return

	if mode == "leaderboard":
		_draw_leaderboard(fnt)
		return

	if shake_timer > 0.0:
		var mag: float = SHAKE_AMP * (shake_timer / SHAKE_DUR)
		draw_set_transform(Vector2(randf_range(-mag, mag), randf_range(-mag, mag)))

	# 넘음 배경(여백) — 개인기록 넘으면 warm 플럼으로 solid 전환(pb_bg_mix 이징, 판 끝까지). 상·하단 바·셀도 같은
	#   방식으로 함께 전환(아래) → 화면 전체가 한 색으로 통일 + 반투명 veil 없어 haze 0. 어둠 유지로 대비 보존.
	#   폭·높이는 반응형(VW_BASE 고정폭 + vh)이라 긴 폰에서도 여백이 남지 않는다.
	draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), C_BG.lerp(C_BG_PB, pb_bg_mix))

	_draw_hud(fnt)
	_draw_board(fnt)
	_draw_core(fnt)
	_draw_bottom(fnt)
	_draw_collapse()
	_draw_held()
	_draw_aim_overlay()   # 조준 링은 들고 있는 조각 '위' = 최상단 (커서 아래 적도 신호가 안 가려지게)

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

	# 보석 비행: 잡은 자리 → 상단 그 색 카운터. 가속(빨려감) + 작아짐 + 꼬리광.
	for gfl in gem_flights:
		var gft: float = clampf(float(gfl["t"]) / float(gfl["dur"]), 0.0, 1.0)
		var gpos: Vector2 = (gfl["from"] as Vector2).lerp(gfl["to"] as Vector2, gft * gft)
		var gsz: float = lerpf(CELL * 0.55, CELL * 0.22, gft)
		var gfc: Color = gfl["color"]
		draw_circle(gpos, gsz * 0.5 + 4.0, Color(gfc.r, gfc.g, gfc.b, 0.28 * (1.0 - gft)))
		_draw_gem_icon(gpos, gsz, int(gfl["gtype"]))

	# 파편 버스트 (타입 색 작은 사각형)
	for dpart in debris:
		var dp: float = clampf(dpart["life"] / dpart["max"], 0.0, 1.0)
		var dcol: Color = dpart["color"]
		dcol.a = dp
		var dsz: float = dpart["size"]
		var dpos: Vector2 = dpart["pos"]
		draw_rect(Rect2(dpos - Vector2(dsz, dsz) * 0.5, Vector2(dsz, dsz)), dcol)

	# 블록 착지 팝 — 사각형이 '수축'하며 안착(소멸 팝의 부풂과 반대 = 도착). 놓은 색 → 흰 테두리.
	for ppop in place_pops:
		var qp: float = clampf(ppop["life"] / ppop["max"], 0.0, 1.0)   # 1→0
		var psz2: float = CELL * (1.0 + 0.30 * qp)                      # 크게 시작 → 셀 크기로 안착
		var pcol2: Color = ppop["color"]
		var ppos2: Vector2 = ppop["pos"]
		var prect2: Rect2 = Rect2(ppos2 - Vector2(psz2, psz2) * 0.5, Vector2(psz2, psz2))
		draw_rect(prect2, Color(pcol2.r, pcol2.g, pcol2.b, qp * 0.30))
		draw_rect(prect2, Color(1.0, 1.0, 1.0, qp * 0.85), false, 3.0)

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
		draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), Color(0.9, 0.05, 0.05, ra))

	if flash_timer > 0.0:
		var t: float = flash_timer / FLASH_DUR
		# 콤보↑ = 더 밝고 뜨거운 섬광(흰색→따뜻한 주황)
		var fint: float = 0.14 + 0.05 * float(mini(flash_combo, 6))
		var fcol: Color = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.68, 0.28), clampf(float(flash_combo - 2) / 5.0, 0.0, 1.0))
		draw_rect(Rect2(0, 0, VW_BASE, vh), Color(fcol.r, fcol.g, fcol.b, t * fint))
		if flash_combo >= 2:
			var cs: String = _t("combo_flash") % flash_combo
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

	# 스테이지 인트로 카드 (중앙 팝업 → 상단 목표 카드로 도킹). 캠페인 진입 1회.
	if intro_t >= 0.0 and not game_over and not game_clear:
		_draw_stage_intro(fnt)

	# 죽음 연출이 재생 중이면 팝업을 미룬다 — 보드가 메워지는 걸 먼저 보여준다
	if (game_over or game_clear) and not _death_playing():
		_draw_result(fnt)

	# 설정 모달 (플레이 중 기어로 열림) — 스크림째 최상단에 얹힌다
	if settings_open:
		_draw_settings(fnt)

	# 클리어 축하 색종이 — 팝업 '위'에 흩날린다(최상단). 회전한 작은 직사각형.
	for cc in confetti:
		var cpos: Vector2 = cc["pos"]
		var col: Color = cc["color"]
		col.a = clampf(float(cc["life"]) / float(cc["max"]) * 2.0, 0.0, 1.0)   # 수명 끝물에 페이드
		var ang: float = cc["rot"]
		var ca: float = cos(ang)
		var sa: float = sin(ang)
		var hw: float = float(cc["w"]) * 0.5
		var hh: float = float(cc["h"]) * 0.5
		draw_colored_polygon(PackedVector2Array([
			cpos + Vector2(-hw * ca + hh * sa, -hw * sa - hh * ca),
			cpos + Vector2(hw * ca + hh * sa, hw * sa - hh * ca),
			cpos + Vector2(hw * ca - hh * sa, hw * sa + hh * ca),
			cpos + Vector2(-hw * ca - hh * sa, -hw * sa + hh * ca),
		]), col)

	# PB 돌파 — 순간 버스트(방사광+링, 1회)는 pb_pop_t 창에서만. 스티커는 넘은 뒤 판 끝까지 상주(계속 갱신 중).
	if pb_pop_t >= 0.0:
		_draw_pb_burst()
	if endless_beat_best:
		_draw_pb_sticker(fnt)   # 버스트 위(최상단 헤드라인)

# PB 돌파 순간 버스트 — 방사광+shockwave 링(1회). 시선을 '점수' 카드로 끌어당긴다. 전부 오버레이(기본 UI 무간섭).
func _draw_pb_burst() -> void:
	var p: float = clampf(1.0 - pb_pop_t / PB_POP_DUR, 0.0, 1.0)   # 진행 0→1
	var a: float = 1.0
	if p < 0.06:
		a = p / 0.06
	elif p > 0.7:
		a = clampf((1.0 - p) / 0.3, 0.0, 1.0)
	var cc: Vector2 = Vector2((800.0 - 464.0) * 0.5 + 125.0, 56.0)   # 점수 카드 중심 (293,56)
	# ① shockwave 링 — 시선 유도. 옆 '적 이동' 카드(좌단 x=442) 안 넘게 반경 제한.
	for k in range(2):
		var rk: float = clampf((p - float(k) * 0.14) / 0.6, 0.0, 1.0)
		if rk <= 0.0 or rk >= 1.0:
			continue
		draw_arc(cc, lerp(28.0, 128.0 + float(k) * 34.0, rk), 0.0, TAU, 40,
				Color(1.0, 0.92, 0.6, a * (1.0 - rk) * 0.55), 3.0)
	# ② 방사광 — 더 밝게·짧게(near-white, 길이 42→84 → x최대 377 < 442). 피크 p≈0.1 뒤 빠르게 사그라듦(펀치).
	var ray_a: float = a * clampf(1.0 - absf(p - 0.1) / 0.18, 0.0, 1.0) * 0.85
	if ray_a > 0.01:
		for i in range(12):
			var ang: float = p * 0.35 + float(i) * TAU / 12.0
			var dir: Vector2 = Vector2(cos(ang), sin(ang))
			draw_line(cc + dir * 40.0, cc + dir * 84.0, Color(1.0, 0.98, 0.82, ray_a), 5.0)

# "👑 신기록!" 스티커 — 넘은 순간 카드 상단에 비스듬히 '붙어' 판 끝까지 상주(계속 갱신 중이라 안 뗀다).
#   팝인만 오버슛 원샷(pb_pop_t 창), 이후 고정. 기본 UI('점수' 라벨)를 '가릴' 뿐 안 바꾼다(occlude-don't-mutate).
func _draw_pb_sticker(fnt: Font) -> void:
	var ss: float = 1.0
	var wob: float = 0.0
	var a: float = 1.0
	if pb_pop_t >= 0.0:   # 팝인 구간만 애니
		var p: float = clampf(1.0 - pb_pop_t / PB_POP_DUR, 0.0, 1.0)
		if p < 0.06:
			a = p / 0.06
		if p < 0.14:
			var ip: float = p / 0.14
			ss = (1.0 - pow(1.0 - ip, 2.0)) + sin(clampf(ip, 0.0, 1.0) * PI) * 0.18   # 오버슛 팝인
			wob = sin(p * 26.0) * 0.03 * clampf(1.0 - p / 0.3, 0.0, 1.0)              # 진입 살짝 흔들
	var cx: float = (800.0 - 464.0) * 0.5 + 125.0   # 점수 카드 중심 x (293)
	var label: String = "👑 신기록!"
	var sfs: int = 22
	var lw: float = fnt.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	var sw: float = lw + 34.0
	var sh: float = 40.0
	draw_set_transform(Vector2(cx, 30.0), -0.12 + wob, Vector2(ss, ss))     # 카드 상단 걸치게, ~-7°
	draw_rect(Rect2(-sw * 0.5 + 2.0, -sh * 0.5 + 3.0, sw, sh), Color(0.0, 0.0, 0.0, 0.22 * a))   # 그림자
	draw_rect(Rect2(-sw * 0.5, -sh * 0.5, sw, sh), Color(0.82, 0.58, 0.06, a))                   # 골드 테두리
	draw_rect(Rect2(-sw * 0.5 + 3.0, -sh * 0.5 + 3.0, sw - 6.0, sh - 6.0), Color(1.0, 0.86, 0.3, a))  # 크림 속
	draw_string(fnt, Vector2(-lw * 0.5, sfs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(0.3, 0.15, 0.0, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ===== 결과 팝업 =====
# 화면을 통째로 덮는 텍스트 나열이 아니라, 어두워진 게임 위에 뜨는 '카드'.
# 시선 순서 = 판정(제목) → 사유 → 남은 적 → 재도전 버튼(착지점).
#
# 문자열은 적을수록 읽힌다(C39). 예전엔 8개를 띄웠는데 그중 셋이 같은 두 동작을 반복했다:
# 초록 버튼 "재도전" + 고스트 버튼 "홈으로" + 맨 아래 힌트 "SPACE 재도전 · ESC 홈".
# 힌트는 버튼 라벨을 그대로 다시 읽는 줄이라 지웠다(키 입력 자체는 그대로 받는다 — 글자만 뺀 것).
# 스테이지 이름("1. 첫 방어선")도 지웠다. 기본 동작이 재도전 = 같은 스테이지라, 방금까지
# 보던 이름을 다시 확인할 이유가 없다.
# 남은 넷은 크기 격차를 벌려 위계를 세운다: 64 / 20 / 18 / 52 — 예전엔 56·20·24·18·46이
# 다 엇비슷해서 무엇이 헤드라인인지 눈이 못 정했다.
# 결과 팝업 레이아웃 — 그리기(_draw_result)와 입력(_input)이 이 한 함수를 공유한다.
#   버튼이 상황에 따라 2개(재도전·홈)거나 3개(광고 이어하기·재도전·홈)라, 좌표를 두 곳에서
#   따로 적으면 어긋난다(C31 원칙). revivable = 실패(거점 파괴·막힘 둘 다) & 부활 미사용.
#   ※막힘도 부활한다 — 실패 경로 하나만 부활 가능하면 나머지 실패는 그냥 샌다(C48 플테 정정).
func _result_layout() -> Dictionary:
	var revivable: bool = game_over and not revive_used
	# 뷰포트가 1000보다 크면(실기기 세로) 팝업을 세로 중앙으로 내린다.
	var dy: float = (vh - 1000.0) * 0.5
	if revivable:
		var p: Rect2 = Rect2(170.0, 234.0 + dy, 460.0, 500.0)
		return {
			"revivable": true,
			"panel": p,
			"cont": Rect2(230.0, p.position.y + 268.0, 340.0, 86.0),   # 주: 광고 이어하기
			"retry": Rect2(275.0, p.position.y + 372.0, 250.0, 52.0),  # 부: 재도전
			"home": Rect2(300.0, p.position.y + 446.0, 200.0, 34.0),   # 고스트: 홈
		}
	var p2: Rect2 = Rect2(170.0, 264.0 + dy, 460.0, 430.0)
	return {
		"revivable": false,
		"panel": p2,
		"cont": Rect2(),
		"retry": Rect2(240.0, 526.0 + dy, 320.0, 88.0),   # 주: 재도전
		"home": Rect2(300.0, 630.0 + dy, 200.0, 40.0),
	}

# 광고 부활 — 세컨드 윈드. 실패 원인에 맞춰 하단 3줄만 손대 판을 살 만하게 하되 나머지는
#   그대로 이어받는다(진행도 spawned/killed/leaked 유지, 콤보만 초기화). 두 경로가 '하단 3줄'로
#   대칭이다: 거점 파괴=거점에 임박한 하단 적만 제거(위쪽 밀물은 유지), 막힘=하단 보드만 비워
#   공간 확보(위 구조·적 유지). 전멸/전체 초기화는 '새 판'이라 이어하는 느낌이 죽는다(Block Blast식
#   부분 개입). 단순 HP 복구만이면 서지 구간 즉사 재발(C47 경계). ⚠광고는 프로토 스텁.
func _revive() -> void:
	var was_stuck: bool = stuck
	revive_used = true
	game_over = false
	stuck = false
	pending_core_dead = false
	core_t = -1.0             # 거점 파괴 연출 취소
	core_burst_done = false
	stuck_t = -1.0            # 막힘 연출 취소
	core_hp = director.core_hp_max()   # 거점 HP 풀 복구
	pending_leaks = []
	combo = 0                 # 콤보 초기화 (부활은 새 국면 — 스트릭을 이어주지 않는다)
	combo_miss = 0
	if was_stuck:
		# 막힘 = 보드 때문에 죽었다 → 하단 몇 줄만 비워 공간만 되찾는다(부분 클리어). 위 구조도,
		#   내려오던 적도 그대로 이어받는다(적까지 지우면 보드는 남기면서 밀물만 리셋이라 비일관).
		for r in range(ROWS - REVIVE_CLEAR_ROWS, ROWS):
			for c in range(COLS):
				board[r][c] = ""
	else:
		# 거점 파괴 = 밀물에 밀려 죽었다 → 거점에 임박한 하단 3줄 적만 걷어낸다(즉사 위협 제거).
		#   위쪽 적은 유지 = 이어하는 밀물(전멸은 너무 관대 + '새 판' 느낌). 보드는 자산이라 유지.
		# ⚠걷어낸 gen0는 spawned에서 되돌린다 — 안 그러면 웨이브 회계(spawned==killed+leaked+onboard)가
		#   깨져, spawned가 total에 닿는 순간 스폰 캡이 걸려 '보드 비었는데 새 적 안 옴 + 남은 N 고정'
		#   소프트락이 된다(부활로 걷어낸 수만큼 remaining이 영영 안 줄어듦). 되돌리면 그만큼 다시 밀려온다.
		var kept: Array = []
		for e in enemies:
			if int(e["row"]) < ROWS - REVIVE_CLEAR_ROWS:
				kept.append(e)
			elif int(e.get("gen", 0)) == 0:
				spawned = maxi(0, spawned - 1)   # 웨이브로 환원(gen1 쌍둥이는 spawned 밖 → 제외)
		enemies = kept
	_cont_hover = false

# 재도전 = 실패면 같은 스테이지, 클리어면 다음(마지막이면 홈)
func _result_advance() -> void:
	# 재도전 종류는 감독이 선언(모드 이름 대신 능력, C61 seam).
	var kind: String = director.retry_kind()
	if kind == "same_seed":
		_start_featured(game_seed) # featured: 같은 오늘의 판 다시(데일리 = 원하는 만큼 시도, C53 ③ⓑ)
	elif kind == "new_run":
		_start_endless()          # 무한: 새 런
	elif game_clear:
		if stage_idx + 1 < STAGES.size():
			_start_stage(stage_idx + 1)
		else:
			# 마지막 스테이지 = 완주 아니라 '콘텐츠 따라잡음' → 리텐션 기둥(무한)으로 깔때기.
			# [[stage-last-clear-is-frontier-not-finale]]
			_start_endless()
	else:
		_start_stage(stage_idx)

# ===== 설정 모달 =====
# 좌표는 한 곳(_settings_layout)에서만 정의 — 그리기(_draw_settings)와 입력(_settings_click)이 공유(C31 원칙).
#   행 = 라벨(왼쪽) + 컨트롤(오른쪽), 전 행 동일 정렬. 800×1000 캔버스에 480폭 패널(좌우 160 여백).
func _settings_layout() -> Dictionary:
	# 뷰포트가 1000보다 크면(실기기 세로) 모달을 세로 중앙으로 내린다 — 나머지 좌표는 py에서 파생됨.
	var p: Rect2 = Rect2(160.0, 270.0 + (vh - 1000.0) * 0.5, 480.0, 410.0)
	var px: float = p.position.x
	var py: float = p.position.y
	var pw: float = p.size.x
	var ctrl_r: float = px + pw - 36.0    # 컨트롤 오른쪽 정렬 기준선
	var r1: float = py + 120.0            # 소리
	var r2: float = py + 190.0            # 배경음
	var r3: float = py + 288.0            # 홈
	var r4: float = py + 356.0            # 다시하기
	var tw: float = 66.0
	var th: float = 32.0
	var bw: float = 140.0
	var bh: float = 50.0
	return {
		"panel": p,
		"label_x": px + 36.0,
		"title_y": py + 50.0,
		"divider_y": py + 235.0,
		"close": Rect2(px + pw - 56.0, py + 16.0, 40.0, 40.0),
		"sound_tog": Rect2(ctrl_r - tw, r1 - th * 0.5, tw, th),
		"bgm_tog": Rect2(ctrl_r - tw, r2 - th * 0.5, tw, th),
		"home_btn": Rect2(ctrl_r - bw, r3 - bh * 0.5, bw, bh),
		"replay_btn": Rect2(ctrl_r - bw, r4 - bh * 0.5, bw, bh),
		"r1": r1, "r2": r2, "r3": r3, "r4": r4,
	}

func _settings_click(pos: Vector2, lay: Dictionary) -> void:
	if (lay["close"] as Rect2).has_point(pos):
		settings_open = false
	elif (lay["sound_tog"] as Rect2).has_point(pos):
		sound_on = not sound_on           # 지금은 소리를 안 내지만 선호를 저장(오디오 붙는 날 소비)
		_save_settings()
	elif (lay["bgm_tog"] as Rect2).has_point(pos):
		bgm_on = not bgm_on
		_save_settings()
	elif (lay["home_btn"] as Rect2).has_point(pos):
		settings_open = false
		mode = _home_mode()               # 홈 = 허브(결과팝업 '홈으로'와 동일 경로)
	elif (lay["replay_btn"] as Rect2).has_point(pos):
		settings_open = false
		_result_advance()                 # 재시작 = 감독이 정하는 재도전(스테이지=현 스테이지, 무한=새 런)
	# 그 밖(패널 빈 곳·스크림)은 무시 = 모달. 잘못 눌러 튕기는 사고 방지(결과팝업과 동일 원칙).

# 토글 스위치 — 초록 알약=켜짐(노브 오른쪽), 어두운 알약=꺼짐(노브 왼쪽). 색·위치 둘 다로 상태를 말한다.
func _draw_toggle(r: Rect2, on: bool, hot: bool) -> void:
	var mid_y: float = r.position.y + r.size.y * 0.5
	var rad: float = r.size.y * 0.5
	var base: Color = Color(0.28, 0.64, 0.36) if on else Color(0.19, 0.20, 0.29)
	if hot:
		base = base.lightened(0.10)
	draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - 2.0 * rad, r.size.y), base)
	draw_circle(Vector2(r.position.x + rad, mid_y), rad, base)
	draw_circle(Vector2(r.position.x + r.size.x - rad, mid_y), rad, base)
	var kx: float = (r.position.x + r.size.x - rad) if on else (r.position.x + rad)
	draw_circle(Vector2(kx, mid_y), rad - 4.0, Color(0.94, 0.94, 0.98))

# 모달 안 작은 액션 버튼(홈=회색빛 유틸 / 다시하기=초록 '진행'). 결과팝업 버튼 언어 계승.
func _draw_mini_button(fnt: Font, r: Rect2, label: String, hot: bool, accent: Color, ink: Color) -> void:
	draw_rect(Rect2(r.position.x, r.position.y + 5.0, r.size.x, r.size.y), accent.darkened(0.5))
	var base: Color = accent.lightened(0.12) if hot else accent
	draw_rect(r, base)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.32), Color(1.0, 1.0, 1.0, 0.14))
	draw_rect(r, accent.darkened(0.35), false, 3.0)
	var lw: float = fnt.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_draw_text_outlined(fnt, Vector2(r.position.x + r.size.x * 0.5 - lw * 0.5, r.position.y + r.size.y * 0.5 + 9.0), label, 24, ink)

# 기어 아이콘 — 이(teeth) 8개 + 링 + 중심점. 작은 크기라 형태로만 '설정'을 말한다.
func _draw_gear_icon(c: Vector2, rad: float, col: Color) -> void:
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(c + d * (rad * 0.66), c + d * (rad * 1.02), col, 5.0)
	draw_arc(c, rad * 0.66, 0.0, TAU, 28, col, 6.0)
	draw_circle(c, rad * 0.26, col)

func _draw_settings(fnt: Font) -> void:
	var lay: Dictionary = _settings_layout()
	var p: Rect2 = lay["panel"]
	# 스크림 — 뒤 판을 눌러 모달임을 알린다(결과팝업과 동일 톤)
	draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), Color(0.0, 0.0, 0.0, 0.68))
	# 패널(다크) — 그림자 + 본체 + 상단 강조바 + 테두리
	var accent: Color = Color(0.55, 0.58, 0.72)
	draw_rect(Rect2(p.position.x + 6.0, p.position.y + 10.0, p.size.x, p.size.y), Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(p, Color(0.11, 0.11, 0.18))
	draw_rect(Rect2(p.position.x, p.position.y, p.size.x, 8.0), accent)
	draw_rect(p, accent, false, 3.0)
	var cx: float = p.position.x + p.size.x * 0.5
	var lx: float = lay["label_x"]

	# 제목 + X 닫기
	var title: String = _t("settings")
	var tw: float = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	_draw_text_outlined(fnt, Vector2(cx - tw * 0.5, lay["title_y"]), title, 34, Color(0.92, 0.92, 0.98))
	var cb: Rect2 = lay["close"]
	var cc: Vector2 = cb.position + cb.size * 0.5
	var xcol: Color = Color.WHITE if _set_close_hover else Color(0.65, 0.67, 0.78)
	draw_line(cc + Vector2(-9, -9), cc + Vector2(9, 9), xcol, 4.0)
	draw_line(cc + Vector2(9, -9), cc + Vector2(-9, 9), xcol, 4.0)

	# 토글 행: 소리 · 배경음
	_draw_text_outlined(fnt, Vector2(lx, float(lay["r1"]) + 9.0), _t("sound"), 26, Color(0.86, 0.87, 0.95))
	_draw_toggle(lay["sound_tog"], sound_on, _set_sound_hover)
	_draw_text_outlined(fnt, Vector2(lx, float(lay["r2"]) + 9.0), _t("music"), 26, Color(0.86, 0.87, 0.95))
	_draw_toggle(lay["bgm_tog"], bgm_on, _set_bgm_hover)

	# 구분선
	draw_line(Vector2(lx, lay["divider_y"]), Vector2(p.position.x + p.size.x - 36.0, lay["divider_y"]), Color(1.0, 1.0, 1.0, 0.10), 2.0)

	# 액션 행: 홈(메뉴로) · 다시하기(재시작)
	_draw_text_outlined(fnt, Vector2(lx, float(lay["r3"]) + 9.0), _t("home"), 26, Color(0.86, 0.87, 0.95))
	_draw_mini_button(fnt, lay["home_btn"], _t("go_home"), _set_home_hover, Color(0.30, 0.33, 0.44), Color(0.92, 0.93, 1.0))
	_draw_text_outlined(fnt, Vector2(lx, float(lay["r4"]) + 9.0), _t("restart_label"), 26, Color(0.86, 0.87, 0.95))
	_draw_mini_button(fnt, lay["replay_btn"], _t("restart"), _set_replay_hover, Color(0.34, 0.72, 0.26), Color(0.98, 1.0, 0.94))

# 재생 삼각형(▶) — '광고 영상을 본다'는 뜻. 오른쪽을 향한 정삼각형.
func _draw_play_icon(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - r * 0.6, c.y - r * 0.85),
		Vector2(c.x - r * 0.6, c.y + r * 0.85),
		Vector2(c.x + r * 0.85, c.y),
	]), col)

# 시계방향 회전 화살표(재도전) — 링 + 끝단 삼각촉
func _draw_retry_icon(c: Vector2, r: float, col: Color) -> void:
	draw_arc(c, r, -PI * 0.35, PI * 1.15, 24, col, 5.0)
	var tip: Vector2 = c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r
	var t2: Vector2 = tip + Vector2(0.0, -r * 0.55)
	var t3: Vector2 = tip + Vector2(r * 0.55, 0.0)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.18, r * 0.18), t2, t3]), col)

# 실패 헤드라인 — 심판이 아니라 초대. 얼마나 아깝게 졌는지에 따라 말이 갈린다.
#
# 예전엔 "실패" 한 마디였다. 그건 판정을 내리고 대화를 닫는 말이라, 팝업의 일("이만큼
# 남았다 → 다시", C31)과 정반대로 민다. 매치3 관습도 심판형을 안 쓴다 — Royal Match는
# 사유를 말하고(`Out of Moves!`), Toon Blast는 재구성한다(`So Close!`).
# ⚠단 한국어 로컬라이즈 원문은 확인 못 했다(원본 화면 확보 실패) — 아래 문구는 레퍼런스
#   인용이 아니라 우리 팝업 구조에서 나온 설계값이다. 사람 플테로 판정.
#
# 갈리는 이유: 바로 아래에 '남은 적 N'이 찍힌다. 20마리 중 13마리를 남기고 지고서
# "아쉬워요"라고 하면 헤드라인과 숫자가 서로를 반박한다. 아까운 말은 아까울 때만 해야
# 힘을 갖는다. 크게 졌을 땐 위로 대신 초대로 넘긴다.
const FAIL_CLOSE: float = 0.15   # 남은 적이 총량의 15% 이하 = 한 끗 차이
const FAIL_NEAR: float = 0.40    # 40% 이하 = 아쉬운 판

func _fail_headline() -> String:
	var total: int = maxi(1, director.enemy_total())
	var remaining: int = maxi(0, total - killed - leaked)
	var ratio: float = float(remaining) / float(total)
	if ratio <= FAIL_CLOSE:
		return _t("fail_close")
	if ratio <= FAIL_NEAR:
		return _t("fail_near")
	return _t("fail_far")

# 스테이지 인트로 카드 — 중앙 큰 팝업(이름·태그·목표)이 떠서 머물다, 상단 목표 카드(goal_r)로
# 축소·이동하며 알파가 빠져 '녹아든다'. 텍스트는 카드 높이비로 함께 축소 → 도킹 끝에 목표 카드에 안착.
# BlockBlast의 목표 배너(중앙 등장 → 상단 HUD 도킹) 관찰. 목표는 판마다 같지만(적 N 처치) 이름·태그·수는
# 판별로 달라 진입 오리엔테이션 + 챕터 비트를 준다. [[transient-celebration-overlay-not-base-ui]] 순수 오버레이.
func _draw_stage_intro(fnt: Font) -> void:
	var t: float = intro_t
	var appear: float = clampf(t / INTRO_APPEAR, 0.0, 1.0)
	var dock_lin: float = clampf((t - INTRO_APPEAR - INTRO_HOLD) / INTRO_DOCK, 0.0, 1.0)
	var dock: float = dock_lin * dock_lin * (3.0 - 2.0 * dock_lin)   # smoothstep(부드러운 이징)

	# 밴드는 중앙 고정(이동 안 함) — 도킹 때 제자리에서 페이드. 대신 목표 칩(💀 N)만 상단 목표 카드로
	# 날아가 녹아든다(BlockBlast 관찰: 배너는 제자리 페이드, 타겟 아이콘만 HUD로 상승). 위협 글리프는
	# 착지할 자리가 없다(상단 카드는 '전 타입 소탕'이라 타입 중립 해골) → 밴드와 함께 제자리 페이드.
	var r: Rect2 = Rect2(-6.0, 356.0, 812.0, 188.0)
	var band_a: float = appear * (1.0 - dock)

	# 스크림·패널: 밴드와 함께 페이드
	draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), Color(0.0, 0.0, 0.0, 0.34 * band_a))
	draw_rect(Rect2(r.position.x + 4.0, r.position.y + 6.0, r.size.x, r.size.y), Color(0.0, 0.0, 0.0, 0.4 * band_a))
	draw_rect(r, Color(0.14, 0.14, 0.21, band_a))
	draw_rect(r, Color(0.85, 0.7, 0.3, band_a), false, 3.0)

	# 인트로는 핵심만 — 스테이지 N + 💀 처치 수. 타입(글리프·이름)은 뺐다(수가 목표의 전부).
	var cx: float = r.position.x + r.size.x * 0.5
	# ① 스테이지 N (상단, 작게) — 밴드와 함께 제자리 페이드
	var sn: String = _t("stage_n") % (stage_idx + 1)
	var sn_w: float = fnt.get_string_size(sn, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_draw_text_outlined(fnt, Vector2(cx - sn_w * 0.5, r.position.y + r.size.y * 0.35), sn, 24, Color(0.72, 0.74, 0.9, band_a))

	# 받기형 수집: 💀+적수 대신 '색별 보석 아이콘 + quota'를 선언(도킹은 상단 수집 카드로).
	if bool(st.get("collect", false)):
		var ctgts: Array = st.get("collect_targets", [1])
		var cn: int = maxi(1, ctgts.size())
		var c_hold: Vector2 = Vector2(cx, r.position.y + r.size.y * 0.62)
		var c_chip: Vector2 = c_hold.lerp(Vector2(293.0, 66.0), dock)
		var ccs: float = lerpf(1.0, 0.47, dock)
		var c_a: float = appear * (1.0 - clampf((dock - 0.72) / 0.28, 0.0, 1.0))
		var g_icon: float = 52.0 * ccs
		var g_fs: int = maxi(1, int(56.0 * ccs))
		var g_gap: float = 32.0 * ccs
		var g_ws: Array = []
		var g_total: float = 0.0
		for gi in range(cn):
			var gnw: float = fnt.get_string_size(str(int(ctgts[gi])), HORIZONTAL_ALIGNMENT_LEFT, -1, g_fs).x
			var gw2: float = g_icon + 8.0 * ccs + gnw
			g_ws.append(gw2)
			g_total += gw2
		g_total += g_gap * float(cn - 1)
		var gx0: float = c_chip.x - g_total * 0.5
		for gi2 in range(cn):
			_draw_gem_icon(Vector2(gx0 + g_icon * 0.5, c_chip.y), g_icon, gi2)
			_draw_text_outlined(fnt, Vector2(gx0 + g_icon + 8.0 * ccs, c_chip.y + float(g_fs) * 0.35), str(int(ctgts[gi2])), g_fs, Color(1.0, 0.92, 0.62, c_a))
			gx0 += float(g_ws[gi2]) + g_gap
		return

	# ② 💀 처치 수(히어로) + 작은 '처치' 접미사 — 도킹 동안 중앙 → 상단 목표 카드로 날아가 녹아든다.
	#    수는 크게(목표의 핵심), 접미사는 작게(무슨 수인지 못 박기). 인트로=목표 선언, HUD=남은 수 추적.
	var goal_s: String = str(director.enemy_total())
	var suf: String = _t("intro_kills")
	var num_fs: int = 60
	var skull_s: float = 48.0
	var chip_hold: Vector2 = Vector2(cx, r.position.y + r.size.y * 0.62)
	var chip_end: Vector2 = Vector2(293.0, 66.0)   # 상단 목표 카드(goal_r) skull+수 그룹
	var chip: Vector2 = chip_hold.lerp(chip_end, dock)
	var cs: float = lerpf(1.0, 0.47, dock)           # 60→~28 카드 크기로 축소
	var chip_a: float = appear * (1.0 - clampf((dock - 0.72) / 0.28, 0.0, 1.0))
	var nfs: int = maxi(1, int(num_fs * cs))
	var sfs: int = maxi(1, int(24.0 * cs))
	var ss: float = skull_s * cs
	var nw: float = fnt.get_string_size(goal_s, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	var sufw: float = fnt.get_string_size(suf, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	var baseline: float = chip.y + nfs * 0.35
	var cgl: float = chip.x - (ss + 12.0 * cs + nw + 8.0 * cs + sufw) * 0.5
	_draw_enemy_icon(Vector2(cgl + ss * 0.5, chip.y), ss)
	_draw_text_outlined(fnt, Vector2(cgl + ss + 12.0 * cs, baseline), goal_s, nfs, Color(0.98, 0.88, 0.5, chip_a))
	_draw_text_outlined(fnt, Vector2(cgl + ss + 12.0 * cs + nw + 8.0 * cs, baseline), suf, sfs, Color(0.86, 0.8, 0.56, chip_a))

# 결과 팝업 — 받기형 수집 지표: 색별 남은 보석(quota−수집). 다 채운 색은 초록, 남은 색은 빨강.
func _draw_result_collect(fnt: Font, p: Rect2, cx: float) -> void:
	var cap: String = _t("result_gems")
	var cap_fs: int = 18
	var cw: float = fnt.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	_draw_text_outlined(fnt, Vector2(cx - cw * 0.5, p.position.y + 176.0), cap, cap_fs, Color(0.95, 0.85, 0.5))
	var tgts: Array = st.get("collect_targets", [1])
	var n: int = maxi(1, tgts.size())
	var icon_s: float = 38.0
	var num_fs: int = 46
	var gap: float = 24.0
	var widths: Array = []
	var total_w: float = 0.0
	for i in range(n):
		var got: int = int(collected_by_type[i]) if i < collected_by_type.size() else 0
		var nw: float = fnt.get_string_size(str(maxi(0, int(tgts[i]) - got)), HORIZONTAL_ALIGNMENT_LEFT, -1, num_fs).x
		var w: float = icon_s + 8.0 + nw
		widths.append(w)
		total_w += w
	total_w += gap * float(n - 1)
	var x: float = cx - total_w * 0.5
	var row_y: float = p.position.y + 222.0
	for i in range(n):
		var got2: int = int(collected_by_type[i]) if i < collected_by_type.size() else 0
		var rem2: int = maxi(0, int(tgts[i]) - got2)
		_draw_gem_icon(Vector2(x + icon_s * 0.5, row_y), icon_s, i)
		var col: Color = Color(0.55, 0.95, 0.65) if rem2 <= 0 else Color(1.0, 0.55, 0.5)
		_draw_text_outlined(fnt, Vector2(x + icon_s + 8.0, row_y + 16.0), str(rem2), num_fs, col)
		x += float(widths[i]) + gap

func _draw_result(fnt: Font) -> void:
	# 스크림 — 팝업 뒤의 보드를 '멈춘 배경'으로 눌러둔다(모달 표시)
	draw_rect(Rect2(-20, -20, VW_BASE + 40.0, vh + 40.0), Color(0.0, 0.0, 0.0, 0.68))

	var lay: Dictionary = _result_layout()
	var p: Rect2 = lay["panel"]
	var accent: Color = C_GOLD if game_clear else Color(0.85, 0.35, 0.35)
	draw_rect(Rect2(p.position.x + 6.0, p.position.y + 10.0, p.size.x, p.size.y), Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(p, Color(0.13, 0.13, 0.2))
	draw_rect(Rect2(p.position.x, p.position.y, p.size.x, 8.0), accent)   # 상단 강조 바
	draw_rect(p, accent, false, 3.0)

	var cx: float = p.position.x + p.size.x * 0.5

	# 무한: 런 종료 시점에 베스트 확정(부활로 이어가면 다음 팝업서 재갱신). 신기록이면 배지.
	# 제출은 서비스로만 — 로컬 영속 + (모바일 때) 플랫폼 통지. best 캐시 미러 갱신.
	#   부활 안 쓴 판(revive_used==false)이면 '무부활 최고점'(개인기록)도 함께 갱신 — 이건
	#   메인 베스트를 못 넘어도 오를 수 있어(광고로 안 산 점수) 별도 가드로 본다.
	if director.scores():
		var can_main: bool = endless_score > endless_best
		var can_clean: bool = not revive_used and endless_score > _leaderboard.clean_best()
		if can_main or can_clean:
			var nb: bool = _leaderboard.submit(endless_score, revive_used)
			if can_main:
				endless_new_best = nb
				endless_best = _leaderboard.best()

	# ① 헤드라인. 혼자만 크다.
	#    폭에 맞춰 줄인다 — "아쉬워요!"는 5자라 64px가 넉넉하지만 "스테이지 클리어!"는 8자라
	#    같은 크기면 패널을 끝까지 밀어낸다. 글자 수가 아니라 패널이 크기를 정하게 한다.
	# 마지막 스테이지 클리어 = 완주(피날레) 아님 — 라이브 업데이트로 스테이지는 계속 늘어난다.
	# '콘텐츠 따라잡음(프런티어)'으로 다루고 무한으로 유도. [[stage-last-clear-is-frontier-not-finale]]
	var frontier: bool = game_clear and stage_idx + 1 >= STAGES.size()
	var msg: String
	var msg_col: Color
	if director.scores():
		msg = _t("score_headline") % _comma(endless_score)   # 점수 모드: 점수가 헤드라인(리더보드 지표)
		msg_col = C_GOLD
	elif game_clear:
		msg = _t("caught_up") if frontier else _t("stage_clear")
		msg_col = C_GOLD
	else:
		msg = _fail_headline()
		msg_col = Color.WHITE
	var mfs: int = 64
	var mw: float = fnt.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
	var max_w: float = p.size.x - 56.0
	if mw > max_w:
		mfs = maxi(40, int(float(mfs) * max_w / mw))
		mw = fnt.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
	_draw_text_outlined(fnt, Vector2(cx - mw * 0.5, p.position.y + 84.0), msg, mfs, msg_col)

	# ② 사유 — 판정을 받쳐주는 한 줄. 작게 둔다(헤드라인과 안 싸우게).
	if director.scores():
		var cause: String = _t("cause_stuck") if stuck else _t("cause_core")
		var er: String = _t("depth_cause") % [place_count, cause]
		var erw: float = fnt.get_string_size(er, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_draw_text_outlined(fnt, Vector2(cx - erw * 0.5, p.position.y + 124.0), er, 20, Color(0.8, 0.78, 1.0))
	elif game_over:
		var reason: String = _t("cause_stuck") if stuck else _t("cause_core")
		var rw: float = fnt.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_draw_text_outlined(fnt, Vector2(cx - rw * 0.5, p.position.y + 124.0), reason, 20, Color(1.0, 0.5, 0.5))
	elif frontier:
		# 프런티어: 완봉/처치 성적 대신 '새 스테이지는 계속 온다'는 안내(무한 유도는 주CTA가 담당).
		var fs: String = _t("frontier_sub")
		var fw: float = fnt.get_string_size(fs, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_draw_text_outlined(fnt, Vector2(cx - fw * 0.5, p.position.y + 124.0), fs, 20, Color(0.72, 0.78, 1.0))
	else:
		var res: String = _t("shutout") if leaked == 0 else _t("kills_leaks") % [killed, leaked]
		var rw2: float = fnt.get_string_size(res, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_draw_text_outlined(fnt, Vector2(cx - rw2 * 0.5, p.position.y + 124.0), res, 20,
				Color(0.45, 0.9, 0.6) if leaked == 0 else Color(0.85, 0.7, 0.5))

	# ── 버튼 바로 위: 점수 모드=최고 기록(신기록 배지), 캠페인=못 처치하고 남긴 적/처치.
	if director.scores():
		# 캡션 = 신기록이면 델타를 접어 넣음(획득감), 아니면 '최고'. 델타 별도 줄은 이어하기 버튼과 충돌.
		var ecap: String
		if endless_new_best:
			ecap = _t("first_record") if endless_prev_best <= 0 else _t("new_record") % _comma(endless_score - endless_prev_best)
		else:
			ecap = _t("best")
		var ecap_fs: int = 20 if endless_new_best else 18
		var ecap_col: Color = C_GOLD if endless_new_best else Color(0.72, 0.74, 0.9)
		var ecw: float = fnt.get_string_size(ecap, HORIZONTAL_ALIGNMENT_LEFT, -1, ecap_fs).x
		_draw_text_outlined(fnt, Vector2(cx - ecw * 0.5, p.position.y + 176.0), ecap, ecap_fs, ecap_col)
		var bnum: String = _comma(endless_best)
		var bnum_fs: int = 52
		var bnw: float = fnt.get_string_size(bnum, HORIZONTAL_ALIGNMENT_LEFT, -1, bnum_fs).x
		_draw_text_outlined(fnt, Vector2(cx - bnw * 0.5, p.position.y + 238.0), bnum, bnum_fs,
				C_GOLD if endless_new_best else Color(0.85, 0.85, 0.95))
	elif bool(st.get("collect", false)):
		# 받기형 수집: 남은 적이 아니라 '색별 남은 보석'을 보여준다(게임 중 목표 카드와 같은 언어).
		_draw_result_collect(fnt, p, cx)
	else:
		# 정의는 HUD 목표 카드와 동일(total - killed - leaked) → 게임 중 보던 그 숫자가 그대로.
		var remaining: int = maxi(0, director.enemy_total() - killed - leaked)
		var cap: String = _t("result_remaining") if game_over else _t("result_killed")
		var cap_fs: int = 18
		var cw: float = fnt.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
		_draw_text_outlined(fnt, Vector2(cx - cw * 0.5, p.position.y + 176.0), cap, cap_fs, Color(0.95, 0.85, 0.5))

		var num: String = str(remaining if game_over else killed)
		var num_fs: int = 52
		var icon_s: float = 44.0
		var nw2: float = fnt.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, num_fs).x
		var grp_w: float = icon_s + 12.0 + nw2
		var grp_l: float = cx - grp_w * 0.5
		var row_y: float = p.position.y + 222.0
		_draw_enemy_icon(Vector2(grp_l + icon_s * 0.5, row_y), icon_s)
		_draw_text_outlined(fnt, Vector2(grp_l + icon_s + 12.0, row_y + 16.0), num, num_fs,
				Color(1.0, 0.55, 0.5) if game_over else Color(0.55, 0.95, 0.65))

	# ── 광고 이어하기 버튼 (부활 가능할 때만 — 주 착지점, 금색 3D로 재도전 초록과 구분)
	#    F2P의 심장: 아까운 실패를 광고 한 편으로 이어받는다. 광고임을 'AD' 배지로 명시(정직).
	var revivable: bool = lay["revivable"]
	if revivable:
		var cb: Rect2 = lay["cont"]
		draw_rect(Rect2(cb.position.x, cb.position.y + 7.0, cb.size.x, cb.size.y), Color(0.4, 0.28, 0.05))
		var cbase: Color = Color(1.0, 0.86, 0.35) if _cont_hover else Color(0.95, 0.78, 0.25)
		draw_rect(cb, cbase)
		draw_rect(Rect2(cb.position.x, cb.position.y, cb.size.x, cb.size.y * 0.32), Color(1.0, 1.0, 1.0, 0.22))
		draw_rect(cb, Color(0.5, 0.38, 0.1), false, 4.0)
		# ▶ 아이콘 + "이어하기"
		var clab: String = _t("continue")
		var cfs: int = 34
		var clw: float = fnt.get_string_size(clab, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var pr: float = 15.0
		var cmid_y: float = cb.position.y + cb.size.y * 0.5
		var cin_w: float = pr * 1.7 + 16.0 + clw
		var cin_l: float = cb.position.x + cb.size.x * 0.5 - cin_w * 0.5
		_draw_play_icon(Vector2(cin_l + pr * 0.85, cmid_y), pr, Color(0.2, 0.15, 0.02))
		_draw_text_outlined(fnt, Vector2(cin_l + pr * 1.7 + 16.0, cmid_y + 12.0), clab, cfs, Color(0.2, 0.15, 0.02))
		# 'AD' 배지 — 우상단 코너. 이게 광고 시청임을 숨기지 않는다.
		var badge: Rect2 = Rect2(cb.position.x + cb.size.x - 42.0, cb.position.y - 9.0, 38.0, 20.0)
		draw_rect(badge, Color(0.18, 0.16, 0.22))
		draw_rect(badge, Color(1.0, 0.86, 0.35), false, 1.5)
		var adw: float = fnt.get_string_size("AD", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_draw_text_outlined(fnt, Vector2(badge.position.x + badge.size.x * 0.5 - adw * 0.5, badge.position.y + 16.0), "AD", 14, Color(1.0, 0.9, 0.5))

	# ── 재도전 버튼. 부활 가능하면 부차(작고 톤 다운), 아니면 주(초록 3D — 홈 시작 버튼 문법).
	var label: String = _t("retry")
	if game_clear:
		# 마지막 스테이지 클리어면 _result_advance()가 무한으로 보낸다(프런티어 깔때기) → 주CTA=무한 도전.
		# (예전엔 라벨 go_home인데 동작은 select라 오라벨 + 아래 고스트 홈과 중복이었다 — 버그 수정 겸 통합.)
		label = _t("next_stage") if stage_idx + 1 < STAGES.size() else _t("play_endless")
	var r: Rect2 = lay["retry"]
	var lfs: int = 26 if revivable else 38
	var icon_r: float = 13.0 if revivable else 17.0
	var mid_y: float = r.position.y + r.size.y * 0.5
	if revivable:
		# 부차: 어두운 초록 필(그림자·하이라이트 없음) — 광고(금색 주)와 홈(회색 고스트) 사이 위계
		var sbase: Color = Color(0.30, 0.5, 0.28) if _retry_hover else Color(0.22, 0.4, 0.22)
		draw_rect(r, sbase)
		draw_rect(r, Color(0.16, 0.34, 0.16), false, 2.0)
	else:
		draw_rect(Rect2(r.position.x, r.position.y + 7.0, r.size.x, r.size.y), Color(0.10, 0.28, 0.14))
		var base: Color = Color(0.42, 0.82, 0.32) if _retry_hover else Color(0.34, 0.72, 0.26)
		draw_rect(r, base)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.32), Color(1.0, 1.0, 1.0, 0.16))
		draw_rect(r, Color(0.16, 0.42, 0.18), false, 4.0)

	# 회전 화살표는 '다시 한다'는 뜻 — 실패(재도전)에만. 클리어는 앞으로 가는 것이라 아이콘 없이 글자만.
	var lw: float = fnt.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
	if game_over:
		var inner_w: float = icon_r * 2.0 + 12.0 + lw
		var inner_l: float = r.position.x + r.size.x * 0.5 - inner_w * 0.5
		_draw_retry_icon(Vector2(inner_l + icon_r, mid_y), icon_r, Color.WHITE)
		_draw_text_outlined(fnt, Vector2(inner_l + icon_r * 2.0 + 12.0, mid_y + lfs * 0.34), label, lfs, Color.WHITE,
				Color(0.10, 0.28, 0.14, 0.95))
	else:
		_draw_text_outlined(fnt, Vector2(r.position.x + r.size.x * 0.5 - lw * 0.5, mid_y + lfs * 0.34), label, lfs, Color.WHITE,
				Color(0.10, 0.28, 0.14, 0.95))

	# ── 홈 (부차 동작 — 고스트 버튼)
	var h: Rect2 = lay["home"]
	if _home_hover:
		draw_rect(h, Color(1.0, 1.0, 1.0, 0.08))
	draw_rect(h, Color(0.5, 0.52, 0.62, 0.9 if _home_hover else 0.5), false, 2.0)
	var hs: String = _t("go_home")
	var hfs: int = 20
	var hw2: float = fnt.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
	_draw_text_outlined(fnt, Vector2(h.position.x + h.size.x * 0.5 - hw2 * 0.5, h.position.y + h.size.y * 0.5 + 7.0), hs, hfs,
			Color.WHITE if _home_hover else Color(0.75, 0.77, 0.88))

	# 키 힌트는 없다(C39). SPACE=주 동작(부활 가능하면 이어하기)·ESC=홈은 그대로 받는다.

# ===== 스테이지 선택 화면 (Adventure) — 홈(허브) 아래 한 단계 =====
# Toon Blast식: 위쪽은 진행 상황(스테이지 목록·잠금), 시선의 착지점은 하단의 큰 시작 버튼.
# 좌상단 화살표('홈')로 허브 복귀. (구: 이 화면을 '홈(스테이지)'이라 불렀으나 홈=허브로 통일)
const SEL_X: float = 140.0
const SEL_W: float = 520.0
const SEL_Y0: float = 206.0   # 8스테이지 수용 위해 상향(C57). 소제목 y=166 아래 40px 여백
const SEL_H: float = 58.0     # 8타일이 PLAY_BTN(y=742) 위에 들어오게 70→58 (C57). 내부 텍스트도 상향(+28/+50)
const SEL_GAP: float = 8.0    # 8번째 타일 하단 = 206 + 7·66 + 58 = 726 < 742
const PLAY_BTN: Rect2 = Rect2(150.0, 742.0, 500.0, 126.0)

# ===== 메인 메뉴(허브) 화면 =====
# 앱을 켜면 처음 만나는 두 갈래: Adventure(=스테이지 모드) / Classic(=무한 모드).
#   레퍼런스(Block Blast)의 홈 = 위 로고, 아래 큰 버튼 두 개. select(스테이지 목록)는 Adventure 안쪽.
const MENU_ADV_BTN: Rect2 = Rect2(150.0, 600.0, 500.0, 116.0)     # 오렌지 = 스테이지(모험)
const MENU_CLASSIC_BTN: Rect2 = Rect2(150.0, 740.0, 500.0, 116.0) # 블루 = 무한(∞)
const MENU_LB_BTN: Rect2 = Rect2(560.0, 40.0, 216.0, 60.0)       # 우상단 트로피 = 리더보드(opt-in 천장, 모드 아님)
const BACK_BTN: Rect2 = Rect2(24.0, 24.0, 132.0, 54.0)           # select/리더보드 → 메뉴 복귀
const LB_PLAY_BTN: Rect2 = Rect2(150.0, 786.0, 500.0, 76.0)       # 리더보드 → 무한 도전(peek를 플레이로)

func _stage_rect(i: int) -> Rect2:
	return Rect2(SEL_X, SEL_Y0 + float(i) * (SEL_H + SEL_GAP), SEL_W, SEL_H)

# 잠긴 스테이지는 클릭 대상이 아니다(선형 진행)
func _stage_at(pos: Vector2) -> int:
	for i in range(STAGES.size()):
		if _stage_rect(i).has_point(pos) and _is_unlocked(i):
			return i
	return -1

# ── 메인 메뉴(허브): 위 로고, 아래 두 갈래 버튼 ──
func _draw_menu(fnt: Font) -> void:
	# 배경은 _draw()가 이미 그렸다(오프셋 밖). 여기선 콘텐츠만.

	# 로고: 게임명 + 태그라인(레퍼런스의 상단 로고 자리)
	var title: String = "CASCADE"
	var tfs: int = 84
	var tw: float = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	_draw_text_outlined(fnt, Vector2(400.0 - tw * 0.5, 300.0), title, tfs, C_GOLD)
	var tag: String = "PACKING DEFENSE"
	var tgfs: int = 22
	var tgw: float = fnt.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tgfs).x
	_draw_text_outlined(fnt, Vector2(400.0 - tgw * 0.5, 340.0), tag, tgfs, Color(0.55, 0.72, 0.95))

	_draw_menu_button(fnt, MENU_ADV_BTN, _adv_hover,
			Color(0.98, 0.62, 0.16), Color(0.86, 0.48, 0.10), Color(0.55, 0.30, 0.05),
			_t("adv_big"), _t("adv_sub"), "adv")
	_draw_menu_button(fnt, MENU_CLASSIC_BTN, _classic_hover,
			Color(0.42, 0.68, 0.92), Color(0.30, 0.56, 0.82), Color(0.10, 0.26, 0.44),
			_t("endless_big"), _t("endless_sub"), "classic")

	# 우상단 리더보드 진입(모드 아닌 peek — opt-in 경쟁 천장). 트로피 + 라벨(i18n).
	var lb: Rect2 = MENU_LB_BTN
	draw_rect(Rect2(lb.position.x, lb.position.y + 5.0, lb.size.x, lb.size.y), Color(0.30, 0.24, 0.05))
	draw_rect(lb, Color(0.24, 0.22, 0.14) if _lb_hover else Color(0.18, 0.17, 0.11))
	draw_rect(lb, C_GOLD if _lb_hover else Color(0.55, 0.48, 0.2), false, 2.0)
	var lb_mid: float = lb.position.y + lb.size.y * 0.5
	_draw_trophy(Vector2(lb.position.x + 34.0, lb_mid), 26.0, C_GOLD)
	_draw_text_outlined(fnt, Vector2(lb.position.x + 58.0, lb_mid + 7.0), _t("leaderboard"), 22,
			Color.WHITE if _lb_hover else Color(0.9, 0.88, 0.78))

	var hint: String = _t("menu_hint")
	var hw: float = fnt.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_draw_text_outlined(fnt, Vector2(400.0 - hw * 0.5, 910.0), hint, 17, Color(0.5, 0.52, 0.62))

# 메뉴 버튼 한 개(입체 그림자 → 본체 → 상단 하이라이트 → 테두리 + 좌측 아이콘 + 라벨)
func _draw_menu_button(fnt: Font, r: Rect2, hot: bool, base: Color, base_dim: Color, shadow: Color,
		big: String, sub: String, kind: String) -> void:
	draw_rect(Rect2(r.position.x, r.position.y + 8.0, r.size.x, r.size.y), shadow)
	draw_rect(r, base if hot else base_dim)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.32), Color(1.0, 1.0, 1.0, 0.16))
	draw_rect(r, shadow, false, 4.0)

	# 좌측 아이콘 원판 + 심볼
	var ic: Vector2 = Vector2(r.position.x + 70.0, r.position.y + r.size.y * 0.5)
	draw_circle(ic, 34.0, Color(1.0, 1.0, 1.0, 0.20))
	if kind == "classic":
		_draw_infinity(ic, 30.0, Color.WHITE)
	else:
		_draw_flag(ic, 30.0, Color.WHITE)

	# 라벨: 큰 제목 + 소제목. 무한은 우측에 최고점 후크.
	var lx: float = r.position.x + 128.0
	_draw_text_outlined(fnt, Vector2(lx, r.position.y + 54.0), big, 40, Color.WHITE, Color(shadow.r, shadow.g, shadow.b, 0.95))
	_draw_text_outlined(fnt, Vector2(lx, r.position.y + 88.0), sub, 18, Color(0.96, 0.98, 1.0, 0.9),
			Color(shadow.r, shadow.g, shadow.b, 0.95))
	if kind == "classic" and endless_best > 0:
		var bst: String = _t("best_score") % _comma(endless_best)
		var bfs: int = 22
		var bw: float = fnt.get_string_size(bst, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
		_draw_text_outlined(fnt, Vector2(r.position.x + r.size.x - bw - 24.0, r.position.y + r.size.y * 0.5 + 8.0),
				bst, bfs, C_GOLD, Color(shadow.r, shadow.g, shadow.b, 0.95))

# ∞ 심볼(두 원 윤곽) — 무한 모드 표식
func _draw_infinity(c: Vector2, s: float, col: Color) -> void:
	draw_arc(Vector2(c.x - s * 0.44, c.y), s * 0.40, 0.0, TAU, 20, col, 4.0)
	draw_arc(Vector2(c.x + s * 0.44, c.y), s * 0.40, 0.0, TAU, 20, col, 4.0)

# 깃발 심볼(폴 + 삼각기) — 스테이지(모험) 표식
func _draw_flag(c: Vector2, s: float, col: Color) -> void:
	draw_line(Vector2(c.x - s * 0.34, c.y - s * 0.5), Vector2(c.x - s * 0.34, c.y + s * 0.5), col, 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - s * 0.34, c.y - s * 0.5),
		Vector2(c.x + s * 0.5, c.y - s * 0.22),
		Vector2(c.x - s * 0.34, c.y + s * 0.06),
	]), col)

# 트로피 심볼(컵 + 손잡이 + 받침) — 리더보드 표식. c=중심, s=대략 높이 반경
func _draw_trophy(c: Vector2, s: float, col: Color) -> void:
	# 컵 볼(위 넓고 아래 좁은 사다리꼴)
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - s * 0.45, c.y - s * 0.6),
		Vector2(c.x + s * 0.45, c.y - s * 0.6),
		Vector2(c.x + s * 0.28, c.y + s * 0.05),
		Vector2(c.x - s * 0.28, c.y + s * 0.05),
	]), col)
	# 양쪽 손잡이(반원 윤곽)
	draw_arc(Vector2(c.x - s * 0.45, c.y - s * 0.42), s * 0.26, PI * 0.5, PI * 1.5, 10, col, 3.0)
	draw_arc(Vector2(c.x + s * 0.45, c.y - s * 0.42), s * 0.26, -PI * 0.5, PI * 0.5, 10, col, 3.0)
	# 기둥 + 받침
	draw_rect(Rect2(c.x - s * 0.09, c.y + s * 0.05, s * 0.18, s * 0.32), col)
	draw_rect(Rect2(c.x - s * 0.34, c.y + s * 0.37, s * 0.68, s * 0.16), col)

# ===== 리더보드 화면 =====
# 기획(endless-leaderboard-design): 친구 우선 + 글로벌은 퍼센타일로만, 부활 점수 인정(무표식),
#   무부활 최고점은 개인기록 배지로 살짝. 데이터는 전부 LeaderboardService에서만 읽는다
#   (지금 로컬 미리보기 → 모바일 배관 때 플랫폼 실값으로 승격).
func _draw_leaderboard(fnt: Font) -> void:
	draw_rect(Rect2(-20, -20, 840, 1040), C_BG)

	var best: int = _leaderboard.best()
	var clean: int = _leaderboard.clean_best()
	var pct: int = _leaderboard.percentile()
	var fr: Dictionary = _leaderboard.friend_rank()
	var rows: Array = _leaderboard.board()

	# ── 타이틀(트로피 + "리더보드") ──
	var ttl: String = "리더보드"
	var ttl_fs: int = 40
	var ttl_w: float = fnt.get_string_size(ttl, HORIZONTAL_ALIGNMENT_LEFT, -1, ttl_fs).x
	var grp_w: float = 44.0 + ttl_w
	var grp_l: float = 400.0 - grp_w * 0.5
	_draw_trophy(Vector2(grp_l + 18.0, 82.0), 26.0, C_GOLD)
	_draw_text_outlined(fnt, Vector2(grp_l + 44.0, 96.0), ttl, ttl_fs, C_GOLD)
	var sub: String = "무한 · 최고점 자랑 보드"
	var sub_w: float = fnt.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_draw_text_outlined(fnt, Vector2(400.0 - sub_w * 0.5, 126.0), sub, 16, Color(0.62, 0.64, 0.78))

	# ── 히어로: 글로벌 퍼센타일(운 편차를 뭉개는 대표 지표) ──
	var hero: Rect2 = Rect2(40.0, 150.0, 720.0, 122.0)
	draw_rect(Rect2(hero.position.x, hero.position.y + 6.0, hero.size.x, hero.size.y), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(hero, Color(0.16, 0.15, 0.10))
	draw_rect(hero, C_GOLD, false, 3.0)
	if best <= 0:
		# 빈 상태 — 압박 대신 초대(코지). 순위는 첫 기록부터 열린다.
		var e1: String = "첫 기록에 도전!"
		var e1w: float = fnt.get_string_size(e1, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		_draw_text_outlined(fnt, Vector2(400.0 - e1w * 0.5, 212.0), e1, 40, C_GOLD)
		var e2: String = "무한 모드에서 첫 점수를 남기면 순위가 열려요"
		var e2w: float = fnt.get_string_size(e2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_draw_text_outlined(fnt, Vector2(400.0 - e2w * 0.5, 250.0), e2, 18, Color(0.72, 0.74, 0.88))
	else:
		var ptxt: String = "상위 %d%%" % pct
		var pfs: int = 56
		var pw: float = fnt.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
		_draw_text_outlined(fnt, Vector2(400.0 - pw * 0.5, 216.0), ptxt, pfs, C_GOLD)
		var ftxt: String = "친구 %d명 중 %d위" % [int(fr["total"]), int(fr["rank"])]
		var ffw: float = fnt.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_draw_text_outlined(fnt, Vector2(400.0 - ffw * 0.5, 254.0), ftxt, 22, Color(0.85, 0.86, 0.96))

	# ── 내 기록: 최고(메인·부활 인정) + 무부활 최고(개인기록, 오른쪽에 살짝) ──
	var rec: Rect2 = Rect2(40.0, 288.0, 720.0, 92.0)
	draw_rect(rec, Color(0.13, 0.13, 0.2))
	draw_rect(rec, Color(0.4, 0.42, 0.56), false, 2.0)
	_draw_text_outlined(fnt, Vector2(rec.position.x + 24.0, 322.0), "내 최고", 16, Color(0.72, 0.74, 0.9))
	var bnum: String = _comma(best) if best > 0 else "—"
	_draw_text_outlined(fnt, Vector2(rec.position.x + 24.0, 366.0), bnum, 40, Color.WHITE)
	if clean > 0:
		# '광고로 안 산 점수' = 순수 실력 신호. 작고 조용하게(기획: 살짝).
		var cl_cap: String = "부활 없이"
		var cl_num: String = _comma(clean)
		var cl_cap_w: float = fnt.get_string_size(cl_cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var cl_num_w: float = fnt.get_string_size(cl_num, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var rr: float = rec.position.x + rec.size.x - 24.0
		_draw_text_outlined(fnt, Vector2(rr - cl_cap_w, 322.0), cl_cap, 14, Color(0.6, 0.72, 0.6))
		_draw_text_outlined(fnt, Vector2(rr - cl_num_w, 362.0), cl_num, 26, Color(0.7, 0.9, 0.72))

	# ── 친구 순위 리스트 ──
	_draw_text_outlined(fnt, Vector2(44.0, 408.0), "친구 순위", 20, Color(0.82, 0.84, 0.95))
	var ry: float = 424.0
	var rh: float = 46.0
	var rpitch: float = 52.0
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var you: bool = bool(row["you"])
		var rank: int = i + 1
		var rr2: Rect2 = Rect2(40.0, ry, 720.0, rh)
		# YOU 행은 금색 하이라이트 — 리스트에서 '내 자리'를 색으로 즉시 찾게(hud-signal-by-color)
		draw_rect(rr2, Color(0.20, 0.18, 0.08) if you else Color(0.12, 0.12, 0.18))
		draw_rect(rr2, C_GOLD if you else Color(0.28, 0.3, 0.4), false, 3.0 if you else 1.5)
		# 순위 원판(1~3위 메달색)
		var mc: Color = _medal_color(rank)
		var by: float = ry + rh * 0.5
		draw_circle(Vector2(72.0, by), 17.0, mc)
		var rn: String = str(rank)
		var rnw: float = fnt.get_string_size(rn, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_draw_text_outlined(fnt, Vector2(72.0 - rnw * 0.5, by + 7.0), rn, 20, Color(0.1, 0.1, 0.14))
		# 이름(YOU면 금색 + ★)
		var nm: String = ("★ " + String(row["name"])) if you else String(row["name"])
		_draw_text_outlined(fnt, Vector2(104.0, by + 7.0), nm, 22,
				C_GOLD if you else Color.WHITE)
		# 점수(우측 정렬)
		var sc_i: int = int(row["score"])
		var sc: String = _comma(sc_i) if sc_i > 0 else "—"
		var scw: float = fnt.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_draw_text_outlined(fnt, Vector2(740.0 - scw, by + 7.0), sc, 22,
				C_GOLD if you else Color(0.86, 0.88, 0.98))
		ry += rpitch

	# ── 하단 CTA: 무한 도전(peek를 플레이로) ──
	var cta: Rect2 = LB_PLAY_BTN
	draw_rect(Rect2(cta.position.x, cta.position.y + 7.0, cta.size.x, cta.size.y), Color(0.10, 0.28, 0.14))
	draw_rect(cta, Color(0.42, 0.82, 0.32) if _lb_play_hover else Color(0.34, 0.72, 0.26))
	draw_rect(Rect2(cta.position.x, cta.position.y, cta.size.x, cta.size.y * 0.32), Color(1.0, 1.0, 1.0, 0.16))
	draw_rect(cta, Color(0.16, 0.42, 0.18), false, 4.0)
	var clab: String = "무한 도전"
	var cfs: int = 34
	var clw: float = fnt.get_string_size(clab, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
	var cmid: float = cta.position.y + cta.size.y * 0.5
	var cin_w: float = 26.0 + 14.0 + clw
	var cin_l: float = cta.position.x + cta.size.x * 0.5 - cin_w * 0.5
	_draw_play_icon(Vector2(cin_l + 13.0, cmid), 14.0, Color.WHITE)
	_draw_text_outlined(fnt, Vector2(cin_l + 40.0, cmid + 12.0), clab, cfs, Color.WHITE, Color(0.10, 0.28, 0.14, 0.95))

	# ── 정직 주석: 친구·퍼센타일은 플랫폼 연결 전 미리보기 ──
	if not _leaderboard.has_platform():
		var note: String = "미리보기 · 폰에 연결하면 실제 친구 순위가 표시돼요"
		var nw: float = fnt.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_draw_text_outlined(fnt, Vector2(400.0 - nw * 0.5, 890.0), note, 14, Color(0.5, 0.52, 0.62))

	_draw_back_button(fnt)

# 순위 원판 색 — 1~3위 금/은/동, 그 외 어두운 회색
func _medal_color(rank: int) -> Color:
	match rank:
		1: return C_GOLD
		2: return Color(0.75, 0.76, 0.82)
		3: return Color(0.8, 0.55, 0.35)
		_: return Color(0.32, 0.34, 0.44)

# select → 메뉴 복귀 버튼(좌상단 화살표 + 라벨)
func _draw_back_button(fnt: Font) -> void:
	var r: Rect2 = BACK_BTN
	draw_rect(r, Color(0.20, 0.21, 0.30) if _back_hover else Color(0.15, 0.16, 0.24))
	draw_rect(r, Color(0.45, 0.47, 0.60), false, 2.0)
	var ax: float = r.position.x + 26.0
	var ay: float = r.position.y + r.size.y * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(ax + 7.0, ay - 9.0), Vector2(ax - 7.0, ay), Vector2(ax + 7.0, ay + 9.0),
	]), Color.WHITE)
	_draw_text_outlined(fnt, Vector2(r.position.x + 46.0, ay + 7.0), _t("home"), 20, Color.WHITE)

func _draw_select(fnt: Font) -> void:
	# 배경은 _draw()가 이미 그렸다(오프셋 밖). 여기선 콘텐츠만.

	var title: String = "CASCADE"
	var tw: float = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x
	_draw_text_outlined(fnt, Vector2(400.0 - tw * 0.5, 122.0), title, 60, C_GOLD)
	var done_n: int = 0
	for i in range(STAGES.size()):
		if bool(cleared.get(i, false)):
			done_n += 1
	var sub: String = _t("cleared_count") % [done_n, STAGES.size()]
	var sw: float = fnt.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_draw_text_outlined(fnt, Vector2(400.0 - sw * 0.5, 166.0), sub, 22, Color(0.7, 0.72, 0.85))

	# ⚠플테 전용: 전체 해금이 켜져 있으면 명시(진짜 진행과 안 헷갈리게). '0'키로 토글.
	if dev_unlock_all:
		_draw_text_outlined(fnt, Vector2(SEL_X, 200.0), _t("dev_unlock"), 16, Color(1.0, 0.55, 0.3))

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
		_draw_text_outlined(fnt, Vector2(nx, r.position.y + 28.0), _t(String(sd["name"])), 24, name_col)
		var line2: String = _t(String(sd["tag"])) if open else _t("unlock_req") % i
		_draw_text_outlined(fnt, Vector2(nx, r.position.y + 50.0), line2, 15,
				Color(0.68, 0.7, 0.82) if open else Color(0.4, 0.41, 0.5))

		if done:
			var ck: String = _t("done_badge")
			var cw: float = fnt.get_string_size(ck, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			_draw_text_outlined(fnt, Vector2(r.position.x + SEL_W - cw - 16.0, r.position.y + 40.0), ck, 16, Color(0.4, 0.9, 0.58))

	_draw_play_button(fnt, cur)
	_draw_back_button(fnt)

	var hint: String = _t("select_hint")
	var hw: float = fnt.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	# y=724는 8번 타일(668~726)과 겹쳤다(C57서 타일을 PLAY_BTN 위로 밀며 힌트 위치를 안 옮김).
	# PLAY_BTN(742~868) 아래로 내려 메뉴 힌트(y=910) 리듬과 맞춘다.
	_draw_text_outlined(fnt, Vector2(400.0 - hw * 0.5, 908.0), hint, 17, Color(0.5, 0.52, 0.62))

# 천 단위 콤마 (점수 가독성)
func _comma(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

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
	var big: String = _t("stage_n") % (cur + 1)
	var bfs: int = 46
	var bw: float = fnt.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
	_draw_text_outlined(fnt, Vector2(400.0 - bw * 0.5, r.position.y + 62.0), big, bfs, Color.WHITE,
			Color(0.10, 0.28, 0.14, 0.95))
	var nm: String = _t("all_cleared") if _all_cleared() else _t(String(sd["name"]))
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
	draw_rect(Rect2(0, 0, 800, 144), C_HUD.lerp(C_BG_PB, pb_bg_mix))   # 넘음: 상단 바도 여백과 '같은' warm 플럼으로(통일)
	# CORE HP는 보드 하단 방어선(_draw_core)에만 표시 — 상단 중복 제거.
	if combo >= 2:
		# 유예 중(헛수 1회)이면 경고색으로만 — 다음 헛수에 끊긴다는 신호(텍스트는 안 붙임)
		var risky: bool = combo_miss > 0
		var streak: String = _t("combo") % combo
		var stw: float = fnt.get_string_size(streak, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var scol: Color = Color(1.0, 0.45, 0.3) if risky else C_GOLD
		_draw_text_outlined(fnt, Vector2(736.0 - stw, 26.0), streak, 22, scol)   # 736: 우상단 기어에 자리를 비켜줌

	var step_every: int = director.hud_step_every()
	var remain: int = step_every - (place_count % step_every)
	var imminent: bool = remain <= 1
	# 남은 적 = 아직 처리 안 된 적(스폰 예정 + 보드 위). 누수분은 '더 이상 안 오니' 빠지지만
	# 그 대가는 거점 HP로 이미 치렀다.
	var remaining: int = director.enemy_total() - killed - leaked
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

	# 보스 스테이지: GOAL=감시자 HP, ADVANCE=다음 잔해 투척 카운트다운. 나머지 HUD(콤보·기어)는 공유.
	if bool(st.get("boss", false)):
		_draw_boss_cards(fnt, goal_r, adv_r, gw, aw, box_y)
		if not game_over and not game_clear:
			var gcb: Vector2 = SETTINGS_GEAR.position + SETTINGS_GEAR.size * 0.5
			_draw_gear_icon(gcb, 16.0, Color(0.9, 0.92, 1.0) if _gear_hover else Color(0.55, 0.58, 0.72))
		return

	# 받기형 수집: GOAL 카드 = 보석 수집(N/K). ADVANCE 카드(적 전진 시계)는 아래서 그대로 유지 — 적이 밀려오니까.
	if bool(st.get("collect", false)):
		_draw_collect_goal(fnt, goal_r, gw, box_y)
	elif director.scores():
		# 점수 모드: GOAL 카드 = 점수(리더보드 지표). 최고 넘으면 카드·제목·숫자가 금색으로(실시간 갱신 신호).
		#   깊이·최고는 좌상단, 콤보는 우상단.
		var beat: bool = endless_beat_best
		# 금색 위계 정리: 넘어도 점수 카드는 '중립' 유지 — 지속 기록 신호는 좌상단 크라운 락 + 스티커 + 배경이 전담.
		#   (카드까지 금색이면 금색 4중이라 위계가 뭉갠다.) 기본 UI 텍스트/크기/색 불변(kill-pulse 반짝만 유지).
		_draw_card(goal_r, Color(0.5, 0.42, 0.78))
		var ptitle: String = _t("score")
		var pt_w: float = fnt.get_string_size(ptitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - pt_w * 0.5, box_y + 24.0), ptitle, 16,
				Color(0.82, 0.78, 1.0))
		var sc_str: String = _comma(endless_score)
		var sc_fs: int = 40
		var sc_w: float = fnt.get_string_size(sc_str, HORIZONTAL_ALIGNMENT_LEFT, -1, sc_fs).x
		var sc_col: Color = Color.WHITE.lerp(C_GOLD, kp)
		_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - sc_w * 0.5, box_y + 70.0), sc_str, sc_fs, sc_col)
		# 좌상단: 깊이 + 크라운 락(BlockBlast 관찰). 넘기 전 = 옛 최고(추격 기준선, 회색). 넘은 뒤 = 👑 라이브
		#   신기록(점수에 잠겨 매 처치마다 상승, kp로 반짝) — "지금부터 전부 신기록". 이 숫자가 곧 발화선(적 HP 램프):
		#   영광과 벼랑이 같은 숫자다(endless_mode.gd '내 실력의 끝단이 늘 벼랑').
		_draw_text_outlined(fnt, Vector2(12.0, 30.0), _t("depth") % place_count, 22, Color(0.72, 0.74, 0.9))
		if endless_best > 0:
			var rec_lbl: String
			var rec_col: Color
			if beat:
				rec_lbl = "👑 %s" % _comma(maxi(endless_best, endless_score))
				rec_col = C_GOLD.lerp(Color.WHITE, kp * 0.6)   # 처치마다 흰빛 반짝 = 기록이 실시간으로 새로 쓰인다
			else:
				rec_lbl = _t("best_score") % _comma(endless_best)
				rec_col = Color(0.6, 0.62, 0.78)
			_draw_text_outlined(fnt, Vector2(12.0, 56.0), rec_lbl, 16, rec_col)
	else:
		# GOAL 카드 — 제목 "목표" + 내용 "💀 남은 적 N"(전 타입 소탕이 목표라 타입 중립 해골).
		_draw_card(goal_r, Color(0.85, 0.7, 0.3))
		var goal_lbl: String = _t("goal")
		var gt_w: float = fnt.get_string_size(goal_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - gt_w * 0.5, box_y + 24.0), goal_lbl, 16, Color(0.95, 0.85, 0.5))
		var rem_str: String = str(remaining)
		var rem_fs: int = 40
		var cap_fs: int = 18
		var icon_s: float = 34.0
		var enemies_lbl: String = _t("hud_enemies")
		var cap_w: float = fnt.get_string_size(enemies_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
		var rem_w: float = fnt.get_string_size(rem_str, HORIZONTAL_ALIGNMENT_LEFT, -1, rem_fs).x
		var grp_w: float = icon_s + 8.0 + cap_w + 8.0 + rem_w
		var grp_l: float = goal_r.position.x + gw * 0.5 - grp_w * 0.5
		_draw_enemy_icon(Vector2(grp_l + icon_s * 0.5, box_y + 56.0), icon_s)
		_draw_text_outlined(fnt, Vector2(grp_l + icon_s + 8.0, box_y + 62.0), enemies_lbl, cap_fs, Color(0.95, 0.85, 0.5))
		var rem_col: Color = Color.WHITE.lerp(C_GOLD, kp)
		_draw_text_outlined(fnt, Vector2(grp_l + icon_s + 8.0 + cap_w + 8.0, box_y + 70.0), rem_str, rem_fs, rem_col)

	# ADVANCE 카드 — 적 전진 카운트다운(임박 시 붉은 강조). 제목·숫자 중앙정렬
	var acc: Color = Color(0.85, 0.3, 0.28) if imminent else Color(0.4, 0.45, 0.6)
	_draw_card(adv_r, acc)
	var adv_tc: Color = Color(1.0, 0.6, 0.5) if imminent else Color(0.72, 0.74, 0.86)
	var adv_lbl: String = _t("advance")
	var at_w: float = fnt.get_string_size(adv_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_draw_text_outlined(fnt, Vector2(adv_r.position.x + aw * 0.5 - at_w * 0.5, box_y + 24.0), adv_lbl, 16, adv_tc)
	# 큰 숫자 + 작은 "턴" 을 한 덩어리로 중앙 정렬
	var n_str: String = str(remain)
	var n_fs: int = 44
	var u_fs: int = 18
	var n_col: Color = Color(1.0, 0.55, 0.3) if imminent else Color(0.9, 0.9, 0.95)
	var n_w: float = fnt.get_string_size(n_str, HORIZONTAL_ALIGNMENT_LEFT, -1, n_fs).x
	var turn_lbl: String = _t("turns")
	var u_w: float = fnt.get_string_size(turn_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, u_fs).x
	var grp_x: float = adv_r.position.x + aw * 0.5 - (n_w + 4.0 + u_w) * 0.5
	_draw_text_outlined(fnt, Vector2(grp_x, box_y + 72.0), n_str, n_fs, n_col)
	_draw_text_outlined(fnt, Vector2(grp_x + n_w + 4.0, box_y + 72.0), turn_lbl, u_fs, Color(0.72, 0.72, 0.8))

	# 처치 진행바는 제거했다 — 빨강/초록 가로 막대라 거점 HP 바(진짜 체력)와 색 언어가 겹쳐
	# 'HP가 바닥났다'로 오독됐다. 목표 카드의 '남은 적' 숫자만으로 진행도는 충분히 읽힌다.
	# 이로써 빨강은 거점 HP 전용이 된다.

	# 우상단 설정 기어 — 활성 플레이 중에만(결과/설정 모달은 자체 스크림이 이 위를 덮는다).
	if not game_over and not game_clear:
		var gc: Vector2 = SETTINGS_GEAR.position + SETTINGS_GEAR.size * 0.5
		_draw_gear_icon(gc, 16.0, Color(0.9, 0.92, 1.0) if _gear_hover else Color(0.55, 0.58, 0.72))

# 보스(감시자) HUD 카드 — GOAL 자리에 보스 HP, ADVANCE 자리에 '다음 잔해까지' 카운트다운.
# 기존 두-카드 레이아웃/셈을 그대로 재사용(새 위젯 없음). 남은 적 대신 boss_hp, 전진시계 대신 파울시계.
# 받기형 수집 GOAL 카드 — 보석 아이콘 + "N / K". 목표가 '처치'가 아니라 '수집'임을 금빛 다이아로 말한다.
func _draw_collect_goal(fnt: Font, goal_r: Rect2, gw: float, box_y: float) -> void:
	_draw_card(goal_r, C_GEM)
	var title: String = _t("collect")
	var t_w: float = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - t_w * 0.5, box_y + 24.0), title, 16, Color(1.0, 0.9, 0.6))
	# 타입별 '남은 개수' 카운터 — 각 슬롯 = 그 타입색 다이아 + 남은 수(quota−수집, 0이면 초록). 전부 0 = 클리어.
	var tgts: Array = st.get("collect_targets", [1])
	var n: int = maxi(1, tgts.size())
	var slot_w: float = gw / float(n)
	for i in range(n):
		var got: int = int(collected_by_type[i]) if i < collected_by_type.size() else 0
		var remaining: int = maxi(0, int(tgts[i]) - got)
		var gcol: Color = GEM_COLORS[i % GEM_COLORS.size()]
		var num_str: String = str(remaining)
		# 보석이 도착하면 그 카운터가 톡 튄다(collect_pop). 스케일 최대 1.4배 → 감쇠.
		var pop: float = clampf((collect_pop[i] if i < collect_pop.size() else 0.0) / 0.34, 0.0, 1.0)
		var pop_s: float = 1.0 + 0.4 * pop
		var icon_s: float = (24.0 if n >= 3 else 28.0) * pop_s
		var num_fs: int = int((28 if n >= 3 else 34) * pop_s)
		var num_w: float = fnt.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, num_fs).x
		var grp_w: float = icon_s + 6.0 + num_w
		var cx: float = goal_r.position.x + slot_w * (float(i) + 0.5)
		var gl: float = cx - grp_w * 0.5
		_draw_gem_icon(Vector2(gl + icon_s * 0.5, box_y + 56.0), icon_s, i)
		var done: bool = remaining <= 0
		var num_col: Color = Color(0.45, 0.85, 0.5) if done else Color.WHITE.lerp(gcol, clampf(kill_pulse / 0.35, 0.0, 1.0))
		_draw_text_outlined(fnt, Vector2(gl + icon_s + 6.0, box_y + 68.0), num_str, num_fs, num_col)

# 보석 타입별 실루엣 — 0=다이아(4각), 1=육각, 2=5각 별. 색(GEM_COLORS)과 함께 이중 신호(색맹에도 구분).
func _gem_shape_points(center: Vector2, h: float, shape: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	match shape:
		1:  # 육각(에메랄드 컷)
			for k in range(6):
				var a: float = -PI * 0.5 + float(k) * (TAU / 6.0)
				pts.append(center + Vector2(cos(a), sin(a)) * h)
		2:  # 5각 별(뾰족 5 + 안쪽 5)
			for k in range(10):
				var a2: float = -PI * 0.5 + float(k) * (TAU / 10.0)
				var r: float = h if k % 2 == 0 else h * 0.44
				pts.append(center + Vector2(cos(a2), sin(a2)) * r)
		_:  # 다이아(회전 사각)
			pts = PackedVector2Array([
				center + Vector2(0.0, -h), center + Vector2(h, 0.0),
				center + Vector2(0.0, h), center + Vector2(-h, 0.0)])
	return pts

# 보석 아이콘 — gtype이 색(GEM_COLORS)과 모양을 함께 정한다. HUD·보드·비행·결과 공용 form.
func _draw_gem_icon(center: Vector2, s: float, gtype: int = 0) -> void:
	var col: Color = GEM_COLORS[gtype % GEM_COLORS.size()]
	var shape: int = gtype % 3
	var h: float = s * 0.5
	var pts: PackedVector2Array = _gem_shape_points(center, h, shape)
	draw_colored_polygon(pts, col)
	# 안쪽 흰 하이라이트(같은 모양 축소·위로) = 컷면 반짝
	draw_colored_polygon(_gem_shape_points(center + Vector2(0.0, -h * 0.12), h * 0.42, shape), Color(1.0, 1.0, 1.0, 0.42))
	# 어두운 외곽선(닫힌 polyline)
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, col.darkened(0.6), 1.5)

func _draw_boss_cards(fnt: Font, goal_r: Rect2, adv_r: Rect2, gw: float, aw: float, box_y: float) -> void:
	# GOAL 카드 → 감시자 HP (바이올렛 = 보스, 조각 3원색과 분리)
	_draw_card(goal_r, Color(0.6, 0.35, 0.72))
	var btitle: String = _t("boss")
	var bt_w: float = fnt.get_string_size(btitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - bt_w * 0.5, box_y + 24.0), btitle, 16, Color(0.9, 0.78, 1.0))
	var hp_str: String = "%d / %d" % [boss_hp, boss_hp_max]
	var hp_fs: int = 40
	var hp_w: float = fnt.get_string_size(hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, hp_fs).x
	_draw_text_outlined(fnt, Vector2(goal_r.position.x + gw * 0.5 - hp_w * 0.5, box_y + 70.0), hp_str, hp_fs, Color.WHITE)

	# ADVANCE 카드 → 다음 잔해 투척까지 남은 턴(임박=1이면 강조)
	var every: int = maxi(1, int(st.get("debris_every", 2)))
	var din: int = every - (place_count % every)
	var imminent: bool = din <= 1
	var acc: Color = Color(0.62, 0.4, 0.72) if imminent else Color(0.4, 0.45, 0.6)
	_draw_card(adv_r, acc)
	var dlbl: String = _t("debris")
	var dt_w: float = fnt.get_string_size(dlbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var dt_col: Color = Color(0.9, 0.8, 1.0) if imminent else Color(0.72, 0.74, 0.86)
	_draw_text_outlined(fnt, Vector2(adv_r.position.x + aw * 0.5 - dt_w * 0.5, box_y + 24.0), dlbl, 16, dt_col)
	var dn_str: String = str(din)
	var dn_fs: int = 44
	var dn_w: float = fnt.get_string_size(dn_str, HORIZONTAL_ALIGNMENT_LEFT, -1, dn_fs).x
	var turn_lbl: String = _t("turns")
	var u_w: float = fnt.get_string_size(turn_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var grp_x: float = adv_r.position.x + aw * 0.5 - (dn_w + 4.0 + u_w) * 0.5
	var dn_col: Color = Color(1.0, 0.85, 0.6) if imminent else Color(0.92, 0.9, 0.98)
	_draw_text_outlined(fnt, Vector2(grp_x, box_y + 72.0), dn_str, dn_fs, dn_col)
	_draw_text_outlined(fnt, Vector2(grp_x + dn_w + 4.0, box_y + 72.0), turn_lbl, 18, Color(0.72, 0.72, 0.8))

# 하트 — HP 게이지가 체력임을 글자 없이 말하는 기호. 원 둘 + 아래로 뾰족한 삼각형.
# s = 하트의 폭(=높이). center는 하트의 시각적 중심.
func _draw_heart(center: Vector2, s: float, col: Color) -> void:
	var r: float = s * 0.28
	var top: float = center.y - s * 0.16
	draw_circle(Vector2(center.x - r * 0.92, top), r, col)
	draw_circle(Vector2(center.x + r * 0.92, top), r, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.x - r * 1.85, top + r * 0.18),
		Vector2(center.x + r * 1.85, top + r * 0.18),
		Vector2(center.x, center.y + s * 0.52),
	]), col)

func _draw_board(fnt: Font) -> void:
	draw_rect(Rect2(BOARD_X - 2, board_y - 2, COLS * CELL + 4, ROWS * CELL + 4), C_BORD, false)
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
			var ry: float = board_y + r * CELL
			draw_rect(Rect2(rx, ry, CELL, CELL), C_CELL)   # 8×8 보드 셀은 원색 유지 — 넘음 전환은 주변(바·여백)만, 보드는 다크 아일랜드
			draw_rect(Rect2(rx, ry, CELL, CELL), C_GRID, false)
			if board[r][c] == "" or charging.has(Vector2i(c, r)):
				continue
			# 거점 파괴로 떨어지기 시작한 블록은 여기서 안 그린다 — 하단 패널에 가리지 않게
			# 위 레이어(_draw_collapse)가 맡는다.
			if _core_fall_offset(c) > 0.0:
				continue
			if board[r][c] == "H":
				# 감시자 머리 — 바이올렛 블록 + 어두운 외곽선(적 언어 = '보드 위 생명체'). 눈·입으로 얼굴을 만든다.
				var hrct: Rect2 = Rect2(rx + bpad, ry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0)
				draw_rect(hrct, C_BOSS)
				draw_rect(hrct, Color(0.0, 0.0, 0.0, 0.6), false, 3.0)
				var hctr: Vector2 = _cell_center(c, r)
				# 눈: 최상단 행(r==0)의 eyes 열에만. 그 셀이 뜯기면 눈도 사라진다(상해).
				if r == 0 and st.get("eyes", []).has(c):
					draw_circle(hctr, CELL * 0.15, Color(0.95, 0.97, 1.0))
					draw_circle(hctr, CELL * 0.075, Color(0.05, 0.02, 0.1))
				# 입: 머리 최하단 행의 mouths 열에만 아래로 향한 어두운 삼각(드립 발원지 예고).
				if r == int(st.get("head_rows", 2)) - 1 and st.get("mouths", []).has(c):
					var mw: float = CELL * 0.17
					draw_colored_polygon(PackedVector2Array([
						Vector2(hctr.x - mw, hctr.y + CELL * 0.10),
						Vector2(hctr.x + mw, hctr.y + CELL * 0.10),
						Vector2(hctr.x, hctr.y + CELL * 0.30),
					]), Color(0.05, 0.02, 0.1, 0.85))
				continue
			if board[r][c] == "#":
				# 뿌리(감시자가 뻗은 잠긴 셀) — 강철회색 블록 + 안쪽 어두운 사각 테두리(잠김 표식).
				# 조각(3원색·꽉 찬 블록)과 한눈에 구분: 무채색 + '속이 빈' 룩 = 잘라내야 할 죽은 칸.
				draw_rect(Rect2(rx + bpad, ry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0), C_DEBRIS)
				var ins: float = bpad + 6.0
				draw_rect(Rect2(rx + ins, ry + ins, CELL - ins * 2.0, CELL - ins * 2.0), C_DEBRIS.darkened(0.45), false, 3.0)
				continue
			draw_rect(Rect2(rx + bpad, ry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0),
					_color_of(board[r][c]))

	# 분열선: gen0 분열체가 이 경계를 넘는 순간 갈라진다. 파랑 점선 = '균열 예정선' — 화면의 유일한
	#   파랑이라 분열체(같은 파랑)와 짝지어 읽힌다(글자 아닌 색으로 소속을 말함, [[hud-signal-by-color-not-text]]).
	#   보드 위 미분열 분열체(gen0·!split_done)가 있을 때만 뜬다 = 위협과 함께 등장/퇴장(무관 스테이지엔 안 보임).
	var has_pre_split: bool = false
	for e in enemies:
		if e["etype"] == "split" and int(e.get("gen", 0)) == 0 and not bool(e.get("split_done", false)):
			has_pre_split = true
			break
	if has_pre_split:
		var fy: float = float(board_y + SPLIT_ROW * CELL)   # row (SPLIT_ROW-1)↔SPLIT_ROW 경계 = 넘으면 분열
		var fpulse: float = 0.5 + 0.5 * sin(anim_t * 4.0)
		var fcol: Color = Color(C_E_SPLIT.r, C_E_SPLIT.g, C_E_SPLIT.b, 0.32 + 0.30 * fpulse)
		var f_right: float = float(BOARD_X + COLS * CELL)
		var fx: float = float(BOARD_X)
		while fx < f_right:
			draw_line(Vector2(fx, fy), Vector2(minf(fx + 14.0, f_right), fy), fcol, 3.0)
			fx += 23.0   # dash 14 + gap 9

	# 충전 연출: 원래 색 → 방금 놓은 조각 색으로 물듦(색 통일) → 흰색으로 달아오르며 부풂 → 터짐
	for ci2 in charging:
		var cc: Vector2i = ci2 as Vector2i
		var cx0: float = BOARD_X + cc.x * CELL
		var cy0: float = board_y + cc.y * CELL
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
			draw_rect(Rect2(BOARD_X, board_y + int(orow) * CELL, COLS * CELL, CELL), ocol, false, 3.0)
		for ocol_i in clear_cols:
			draw_rect(Rect2(BOARD_X + int(ocol_i) * CELL, board_y, CELL, ROWS * CELL), ocol, false, 3.0)

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

	# 착지 프리뷰 — 조각을 '들고 있고', 그 자리에 놓을 수 있을 때만 그린다 (Block Blast 방식).
	#
	# 못 놓는 자리에는 아무것도 그리지 않는다. 예전엔 빨간 고스트를 얹었는데, 그 빨강이
	# R 블록·기본 적과 헷갈렸다(당시 셋이 #e5484d로 같은 색. 적은 그 뒤 바이올렛으로 옮겼지만,
	# 무효 표시를 안 그리는 결정 자체는 유효하다). 원본 Block Blast는 무효 표시가
	# 아예 없다 — 조각이 그리드에 붙지 않고 손가락을 따라 그냥 떠 있을 뿐이고, 거절은
	# 그 '스냅과 프리뷰의 부재' + 놓았을 때 트레이로 되돌아감으로 읽힌다. 긍정 신호만 두면
	# 어떤 블록 색과도 충돌할 수 없다.
	#
	# resolve 중엔 숨긴다 — 충전 중인 셀 때문에 _can_place가 false가 되어 프리뷰가 깜빡인다.
	# 조준 프리뷰가 채운다: 지금 놓으면 죽을 적 id 집합. 아래 적 루프가 링 위치를 aim_marks에
	# 적재하고, _draw_aim_overlay가 '들고 있는 조각 위'에 그린다(커서 아래 적도 링이 안 가려지게).
	var doomed: Dictionary = {}
	aim_marks = []
	if dragging and not game_over and not game_clear and not resolving:
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
			if will_clear:
				# 조준 프리뷰: 지금 놓으면 콤보가 combo+1이 되고, 그 밴드에 걸리는 적이 죽는다.
				# 실제 처치와 같은 _blast_band를 써서 어긋나지 않는다. 표식이 하나도 안 뜨면
				# = 무표적 발동("이 수는 아무도 못 잡는다")이 배치 전에 그대로 보인다(C43).
				var pv_band: Dictionary = _blast_band(wl["rows"], wl["cols"], combo + 1)
				var pv_cols: Dictionary = pv_band["cols"]
				var pv_rows: Dictionary = pv_band["rows"]
				for de in enemies:
					var der: int = de["row"]
					if der < 0 or der >= ROWS:
						continue
					if pv_cols.has(de["col"]) or pv_rows.has(der):
						doomed[de["id"]] = true
			for pi in pre:
				var pv: Vector2i = pi as Vector2i
				if gset.has(pv):
					continue   # 조각이 놓일 칸은 아래 고스트가 진하게 그린다
				var prx: float = BOARD_X + pv.x * CELL
				var pry: float = board_y + pv.y * CELL
				# 조각 색으로 '완전히' 통일 — 부분 혼합(0.75)은 파랑→노랑 사이 올리브를 거쳐 탁해진다.
				# 실제 폭발의 색 통일 종착점과 같은 색이라, 프리뷰가 그대로 예고편이 된다.
				var tint: Color = pcol.lerp(Color.WHITE, 0.10 + 0.22 * pulse)
				var prect: Rect2 = Rect2(prx + bpad, pry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0)
				draw_rect(prect, tint)
				draw_rect(prect, Color(1.0, 1.0, 1.0, 0.30 + 0.40 * pulse), false, 2.0)

		# ② 착지 미리보기: 놓일 칸에 '조각색을 흐리게' 깔아둔다 (회색 아님 — 조각색 그대로 옅게).
		#    조각은 스냅하지 않고 포인터를 따라다니므로 이 미리보기가 계속 드러나 있다.
		#    못 놓는 자리로 가면 사라진다 — 미리보기의 유무가 곧 가부 신호다.
		if can:
			var shcol: Color = C_CELL.lerp(_color_of(active["color"]), PREVIEW_MIX)
			for gi2 in ghost:
				var gc: Vector2i = gi2 as Vector2i
				var rx: float = BOARD_X + gc.x * CELL
				var ry: float = board_y + gc.y * CELL
				var grect: Rect2 = Rect2(rx + bpad, ry + bpad, CELL - bpad * 2.0, CELL - bpad * 2.0)
				draw_rect(grect, shcol)
				# 줄이 터질 자리면 프리뷰 줄과 같은 세기로 맥동 = "이 한 수가 줄을 완성한다"
				if will_clear:
					draw_rect(grect, Color(1.0, 1.0, 1.0, 0.20 + 0.30 * pulse), false, 2.0)

	# 넉백 잔상 (밀쳐진 적의 이전→현재 위치 시안 스트릭)
	for st in push_streaks:
		var sa: float = clampf(st["life"] / st["max"], 0.0, 1.0)
		draw_line(st["from"], st["to"], Color(0.6, 0.95, 1.0, sa * 0.7), 4.0)

	# 적 (타입별 색·모양·크기 + 피격 생존 시에만 HP 바)
	for e in enemies:
		var ec: int = e["col"]
		var er: int = e["row"]
		# 놓을 곳 없음 죽음: 차오르는 물결이 지난 줄의 적은 통째로 사라진다.
		# 블록으로 덮기만 하면 HP 바가 블록 사이 여백으로 삐져나와 커튼에 구멍이 뚫린다.
		if stuck_t >= 0.0 and er >= 0 and er < ROWS and _stuck_cell_alpha(Vector2i(ec, er)) > 0.0:
			continue
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
		# 몸통은 셀 중심보다 E_BODY_DY 아래 — 위쪽은 HP 게이지 자리다(_enemy_pos와 같은 셈).
		var cy: float = board_y + vr * CELL + CELL * 0.5 + E_BODY_DY + jit.y
		var ratio: float = clampf(float(e["hp"]) / float(e["maxhp"]), 0.0, 1.0)
		var etype: String = e["etype"]
		# 몸통은 셀을 꽉 채운다 — 게이지가 상시로 없으니 자리를 양보할 이유가 없다(C41 복원).
		var rad: float = CELL * 0.33
		var bar_w: float = CELL * 0.60   # 하트 + 짧은 게이지만. 숫자가 빠져 예전(0.90)보다 좁다
		var bar_h: float = 14.0
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
				var closed: PackedVector2Array = pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, C_E_RIM, C_E_RIM_W)
				rad = s
				# 깜빡이는 "!" 긴급 마커 (머리 위)
				var blink: float = 0.5 + 0.5 * sin(anim_t * 10.0)
				_draw_text_outlined(fnt, Vector2(cx - 4.0, cy - s - 14.0), "!", 26,
						Color(1.0, 0.95, 0.3, 0.4 + 0.6 * blink))
			"tank":
				# 장갑 = 강철 판금 블록. 베벨 하이라이트 + 세로 이음선 2줄 + 코너 리벳 4개 + 두꺼운
				# 외곽선 → 색(강철)과 form(판·리벳)이 함께 "장갑"을 즉시 말한다(basic 보라 원과 분리). C73.
				var hs: float = CELL * 0.42
				var full: Rect2 = Rect2(cx - hs, cy - hs, hs * 2.0, hs * 2.0)
				draw_rect(full, C_E_TANK)
				draw_rect(Rect2(cx - hs, cy - hs, hs * 2.0, hs * 2.0 * 0.30), Color(C_E_TANK_HI.r, C_E_TANK_HI.g, C_E_TANK_HI.b, 0.55))  # 상단 베벨
				draw_rect(Rect2(cx - hs, cy + hs * 0.55, hs * 2.0, hs * 0.45), Color(C_E_TANK_DK.r, C_E_TANK_DK.g, C_E_TANK_DK.b, 0.45))  # 하단 그림자
				var seam_dk: Color = Color(C_E_TANK_DK.r, C_E_TANK_DK.g, C_E_TANK_DK.b, 0.9)
				draw_line(Vector2(cx - hs * 0.34, cy - hs), Vector2(cx - hs * 0.34, cy + hs), seam_dk, 1.8)  # 판 이음선
				draw_line(Vector2(cx + hs * 0.34, cy - hs), Vector2(cx + hs * 0.34, cy + hs), seam_dk, 1.8)
				var rv: float = CELL * 0.055
				var inset: float = hs * 0.72
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						var rc: Vector2 = Vector2(cx + sx * inset, cy + sy * inset)
						draw_circle(rc, rv, C_E_RIVET)
						draw_circle(rc, rv, seam_dk, false, 1.0)
				draw_rect(full, C_E_RIM, false, C_E_RIM_W + 1.0)                                  # 두꺼운 외곽선
				draw_rect(full.grow(-CELL * 0.05), Color(C_E_TANK_HI.r, C_E_TANK_HI.g, C_E_TANK_HI.b, 0.4), false, 1.3)  # 안쪽 베벨선
				rad = hs
				bar_w = CELL * 0.70   # 탱크는 게이지도 크다 = "버티는 게 보임"(C14)
				bar_h = 16.0
			"swarm":
				# 라임 작은 원 여럿 (군집)
				var offs: Array = [Vector2(-0.16, -0.12), Vector2(0.16, -0.10), Vector2(-0.02, 0.16)]
				for off in offs:
					var ov: Vector2 = off as Vector2
					var sp: Vector2 = Vector2(cx + ov.x * CELL, cy + ov.y * CELL)
					draw_circle(sp, CELL * 0.14, C_E_SWARM)
					draw_circle(sp, CELL * 0.14, C_E_RIM, false, C_E_RIM_W - 0.5)
				rad = CELL * 0.24
			"split":
				# 분열 전(gen0·!split_done): 좌우 쌍둥이 blob + 세로 균열. 분열선(SPLIT_ROW)에 가까울수록
				#   금이 벌어지고 부르르 떤다 = "곧 둘이 된다"를 몸이 말한다(글자 tell 없이).
				# 분열 후(gen1 or split_done): 흉터 하나 있는 단일 blob(다시 안 쪼개짐 = 정직한 tell).
				var pre_split: bool = int(e.get("gen", 0)) == 0 and not bool(e.get("split_done", false))
				if pre_split:
					var ct: float = clampf(vr / float(SPLIT_ROW), 0.0, 1.0)   # 0=스폰(잠잠)→1=분열 직전(활짝)
					var lobe: float = CELL * 0.22
					var dx: float = lerpf(CELL * 0.06, CELL * 0.20, ct)      # 벌어짐: 거의 붙음 → 활짝
					var shiv: float = sin(anim_t * 22.0) * CELL * 0.045 * (ct * ct * ct)   # 막판에만 티나는 떨림
					var lc: Vector2 = Vector2(cx - dx + shiv, cy)
					var rc: Vector2 = Vector2(cx + dx + shiv, cy)
					draw_circle(lc, lobe, C_E_SPLIT)
					draw_circle(rc, lobe, C_E_SPLIT)
					draw_circle(lc, lobe, C_E_RIM, false, C_E_RIM_W)
					draw_circle(rc, lobe, C_E_RIM, false, C_E_RIM_W)
					# 가운데 세로 균열(어두운 금) — 가까울수록 굵어진다(1.5→4.0px)
					var crack_w: float = lerpf(1.5, 4.0, ct)
					draw_line(Vector2(cx + shiv, cy - lobe * 0.85), Vector2(cx + shiv, cy + lobe * 0.85), C_E_RIM, crack_w)
					rad = lobe + dx
				else:
					var cr: float = CELL * 0.24
					draw_circle(Vector2(cx, cy), cr, C_E_SPLIT)
					draw_circle(Vector2(cx, cy), cr, C_E_RIM, false, C_E_RIM_W)
					# 흉터: 짧은 사선 하나(갈라진 흔적, 세로 균열 아님 = 더는 안 쪼개짐)
					draw_line(Vector2(cx - cr * 0.4, cy - cr * 0.3), Vector2(cx + cr * 0.2, cy + cr * 0.5), C_E_RIM, 2.0)
					rad = cr
			"gem":
				# 보석 = 타입색 다이아 + 맥동 반짝임. 위협(원·블록)과 form이 달라 '착한 보물', 색은 타입 구분.
				var gcol2: Color = GEM_COLORS[int(e.get("gtype", 0)) % GEM_COLORS.size()]
				var gpulse: float = 0.5 + 0.5 * sin(anim_t * 5.0)
				draw_circle(Vector2(cx, cy), CELL * (0.34 + 0.06 * gpulse), Color(gcol2.r, gcol2.g, gcol2.b, 0.20 + 0.15 * gpulse))  # 후광
				_draw_gem_icon(Vector2(cx, cy), CELL * 0.62, int(e.get("gtype", 0)))
				rad = CELL * 0.34
			_:
				# basic: 바이올렛 원 (hp 비율로 살짝 명암 — 어두워져도 빨강엔 안 닿는다)
				var bcol: Color = C_E_BASIC.lerp(Color(0.30, 0.10, 0.48), 1.0 - ratio)
				draw_circle(Vector2(cx, cy), rad, bcol)
				draw_circle(Vector2(cx, cy), rad, C_E_RIM, false, C_E_RIM_W)
		# 피격 흰 플래시 오버레이 (맞은 순간 강조)
		if flinch > 0.0:
			draw_circle(Vector2(cx, cy), rad, Color(1.0, 1.0, 1.0, 0.7 * clampf(flinch / 0.22, 0.0, 1.0)))
		# 조준 프리뷰: 이 적은 지금 놓으면 죽는다. 링은 여기서 안 그리고 위치만 적재 —
		# 실제 렌더는 _draw_aim_overlay(들고 있는 조각 위)가 맡아 커서에 안 가려진다.
		if doomed.has(e["id"]):
			aim_marks.append({"c": Vector2(cx, cy), "r": rad})
		# ── HP 게이지 = 하트 + 바. 숫자는 없다.
		#
		# 상시로 그리지 않는다 — '피격당하고 살아남은 적'(hp < maxhp)에게만 뜬다.
		# 최소 일격(120)이 basic/fast/swarm의 최대 HP(65/39/26)를 모든 스테이지에서 넘어
		# 대부분의 적이 원샷이다(C41). 그래서 상시 게이지는 한 번도 안 줄어드는 죽은 지표였고
		# (플테: "hp바가 거슬린다"), 숫자는 '이름표·ID'로 오독됐다. → 둘 다 걷어내고, 바가
		# '뜨는 것 자체'를 신호로 삼는다: 바가 보이면 = "얘는 한 방에 안 죽었다". 탱크처럼
		# 버티는 적에게만 나타나므로 게이지가 비로소 정보가 된다.
		#
		# 하트는 남긴다 — 숫자가 빠진 자리에서 '이건 체력이다'를 글자 없이 말하는 기호.
		# 셀에 못 박는다(머리 위에 띄우면 row 0 스폰 시 보드 밖으로 나가거나 세로로 붙은
		# 적끼리 포개진다). 몸통 머리를 조금 덮는 건 '유닛 위 체력바'의 흔한 문법이다.
		if e["hp"] < e["maxhp"]:
			var bx: float = cx - bar_w * 0.5
			var by: float = float(board_y) + vr * float(CELL) + 2.0 + jit.y
			# 채움은 어두운 초록. 배경은 거의 검정 → 채움이 있든 없든 대비가 선다.
			draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.07, 0.07, 0.09, 0.95))
			draw_rect(Rect2(bx, by, bar_w * ratio, bar_h), Color(0.20, 0.72, 0.30))
			draw_rect(Rect2(bx, by, bar_w, bar_h), C_E_RIM, false, 1.5)
			# 하트는 바 왼쪽 안에 — 바 밖으로 나가면 옆 셀 적과 부딪힌다
			var heart_s: float = bar_h * 0.60
			var heart_cx: float = bx + heart_s * 0.72 + 3.0
			_draw_heart(Vector2(heart_cx, by + bar_h * 0.5), heart_s, Color(0.55, 1.0, 0.55))

	# ── 놓을 곳 없음: 빈 칸이 아래에서 위로 메워진다. 꽉 찬 보드가 곧 패배 사유의 진술이다
	#    ("놓을 곳이 없다"를 글이 아니라 사실로 보여준다). 물결이 지난 줄의 적은 위에서 이미 지웠다.
	if stuck_t >= 0.0:
		for fi in stuck_fill:
			var cell: Vector2i = fi as Vector2i
			var fa: float = _stuck_cell_alpha(cell)
			if fa <= 0.0:
				continue
			var frect: Rect2 = Rect2(
					BOARD_X + cell.x * CELL + bpad, board_y + cell.y * CELL + bpad,
					CELL - bpad * 2.0, CELL - bpad * 2.0)
			# 셀 배경에서 제 색으로 밝아진다 — 원본의 '어둡게 나타나 밝아짐' (실측 페이드 50ms)
			draw_rect(frect, C_CELL.lerp(_color_of(stuck_fill[cell]), fa))

func _draw_core(fnt: Font) -> void:
	if bool(st.get("boss", false)):
		return   # 보스 스테이지: 방어선 없음(적 없음) → 거점 HP 바 숨김. 보스 HP는 상단 카드가 표시.
	var strip_h: float = 32.0
	var sx: float = BOARD_X
	# 거점 파괴: 띠가 보드보다 먼저 떨어져 나간다. 떨어지는 동안은 _draw_collapse가 그린다
	# (여기서 그리면 하단 패널에 덮여 '무너짐'이 안 보인다). 그 자리는 빈 채로 남는다.
	if _core_strip_offset() > 0.0:
		return
	var sy: float = board_y + ROWS * CELL + 4.0
	var sw: float = COLS * CELL
	var core_max: int = director.core_hp_max()
	var ratio: float = clampf(float(core_hp) / float(core_max), 0.0, 1.0)
	# HP바: 빈 트랙(어두움) + 체력 그라데이션(빨강↔초록) + 밝은 테두리
	draw_rect(Rect2(sx, sy, sw, strip_h), Color(0.08, 0.03, 0.04))
	var fill_col: Color = Color(0.86, 0.24, 0.20).lerp(Color(0.28, 0.82, 0.45), ratio)
	draw_rect(Rect2(sx, sy, sw * ratio, strip_h), fill_col)
	# 상단 하이라이트(입체감)
	draw_rect(Rect2(sx, sy, sw * ratio, strip_h * 0.4), Color(1.0, 1.0, 1.0, 0.18))
	draw_rect(Rect2(sx, sy, sw, strip_h), Color(1.0, 1.0, 1.0, 0.55), false, 2.0)
	# 라벨: 외곽선 흰 글자(트랙/체력 어느 색 위에서도 읽힘). 검정은 어두운 빈 구간서 안 보여 회피.
	var lbl: String = _t("core_hp") % [core_hp, core_max]
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

# 조각 한 덩이를 임의 위치·임의 셀 크기로 (드래그 중인 조각, 트레이로 돌아가는 조각 공용).
# 조각은 늘 보드 위에 '들려' 있으므로 드롭섀도를 항상 단다.
func _draw_piece_cells(tl: Vector2, cs: float, col: Color, offsets: Array) -> void:
	var pad: float = cs * 0.08
	for o in offsets:
		var ov: Vector2i = o as Vector2i
		var sx: float = tl.x + float(ov.x) * cs + 5.0
		var sy: float = tl.y + float(ov.y) * cs + 7.0
		draw_rect(Rect2(sx + pad, sy + pad, cs - pad * 2.0, cs - pad * 2.0), Color(0.0, 0.0, 0.0, 0.33))
	for o2 in offsets:
		var ov2: Vector2i = o2 as Vector2i
		var r: Rect2 = Rect2(
			tl.x + float(ov2.x) * cs + pad,
			tl.y + float(ov2.y) * cs + pad,
			cs - pad * 2.0, cs - pad * 2.0)
		draw_rect(r, col)
		draw_rect(r, Color(1.0, 1.0, 1.0, 0.5), false, maxf(1.5, cs * 0.03))

# 손에 들린 조각 — 모든 것 위에 뜬다. 그리드에 스냅하지 않고 포인터를 그대로 따라다닌다.
# 놓일 자리는 조각이 아니라 아래 깔린 '흐린 미리보기'가 알려준다. 그래서 조각을 스냅시키면 안 된다
# (조각이 미리보기를 덮어버린다).
func _draw_held() -> void:
	if not snapback.is_empty():
		var sslot: int = int(snapback["slot"])
		if sslot >= 0 and sslot < tray.size() and not tray[sslot].is_empty():
			var sp: Dictionary = tray[sslot]
			var offs: Array = sp["offsets"]
			var bb: Vector2i = _piece_bbox(offs)
			var k: float = 1.0 - clampf(float(snapback["t"]) / SNAPBACK_DUR, 0.0, 1.0)
			var e: float = k * k * (3.0 - 2.0 * k)   # smoothstep — 감속하며 안착
			var cs: float = lerpf(float(CELL), float(TRAY_PREVIEW_CELL), e)
			var src_c: Vector2 = (snapback["from"] as Vector2) + Vector2(float(bb.x), float(bb.y)) * CELL * 0.5
			var ctr: Vector2 = src_c.lerp(_tray_slot_rect(sslot).get_center(), e)
			_draw_piece_cells(ctr - Vector2(float(bb.x), float(bb.y)) * cs * 0.5, cs,
					_color_of(sp["color"]), offs)

	if not dragging or game_over or game_clear or resolving:
		return
	var active: Dictionary = _active()
	if active.is_empty():
		return
	_draw_piece_cells(_drag_origin_px(), float(CELL), _color_of(active["color"]), active["offsets"])

# 조준 프리뷰 링 — 들고 있는 조각보다 위에 그린다. 로켓과 같은 골드 2겹 글로우(넓은 은은한 +
# 좁은 밝은)로 맥동해 '이 적을 저 로켓이 친다'로 잇는다. 위치·반지름은 _draw_board 적 루프가
# aim_marks에 적재한 값(단일 출처) — 커서가 적을 덮어도 이 신호만은 안 가려진다.
func _draw_aim_overlay() -> void:
	if aim_marks.is_empty():
		return
	var dp: float = 0.5 + 0.5 * sin(anim_t * 7.0)
	for m in aim_marks:
		var c: Vector2 = m["c"]
		var dr: float = float(m["r"]) + 5.0 + 2.0 * dp
		draw_circle(c, dr + 2.0, Color(1.0, 0.9, 0.4, 0.16 + 0.12 * dp), false, 5.0)
		draw_circle(c, dr, Color(1.0, 0.98, 0.7, 0.8 + 0.2 * dp), false, 2.5)

# 붕괴 층 — 거점 파괴로 떨어지는 것들은 하단 패널 '위'에 그린다.
# 보드 층에서 그리면 트레이 패널이 덮어버려서 쏟아지는 게 화면 밖으로 나가는 걸 볼 수가 없다.
func _draw_collapse() -> void:
	if core_t < 0.0:
		return
	var sw: float = float(COLS * CELL)

	# ① 거점 띠 — 보드보다 먼저 떨어져 나간다 (무너지는 순서가 곧 인과다)
	var sf: float = _core_strip_offset()
	if sf > 0.0 and sf <= 400.0:
		var sy: float = float(board_y + ROWS * CELL) + 4.0 + sf
		draw_rect(Rect2(float(BOARD_X), sy, sw, 32.0), Color(0.20, 0.05, 0.06))
		draw_rect(Rect2(float(BOARD_X), sy, sw, 32.0), Color(1.0, 0.35, 0.30, 0.7), false, 2.0)

	# ② 받칠 게 사라진 블록이 열마다 시차를 두고 쏟아진다
	var bpad: float = 5.0
	for r in range(ROWS):
		for c in range(COLS):
			if board[r][c] == "":
				continue
			var fall: float = _core_fall_offset(c)
			if fall <= 0.0 or fall > vh:
				continue
			draw_rect(Rect2(
					BOARD_X + c * CELL + bpad, board_y + r * CELL + bpad + fall,
					CELL - bpad * 2.0, CELL - bpad * 2.0), _color_of(board[r][c]))

func _draw_bottom(fnt: Font) -> void:
	draw_rect(Rect2(0, bot_y, VW_BASE, vh - float(bot_y)), C_HUD.lerp(C_BG_PB, pb_bg_mix))   # 넘음: 하단 바도 여백과 '같은' warm 플럼으로(통일)

	# 3슬롯 트레이
	for i in range(3):
		var sr: Rect2 = _tray_slot_rect(i)
		var slot: Dictionary = tray[i]
		# 슬롯 배경
		var bg_col: Color = Color(0.18, 0.18, 0.28) if not slot.is_empty() else Color(0.10, 0.10, 0.16)
		draw_rect(sr, bg_col)
		# 드래그앤드롭이라 '선택된 슬롯'은 더 이상 플레이어가 다루는 개념이 아니다(sel은 내부 장부용).
		# 슬롯 강조를 남겨두면 집지도 않은 조각이 골라진 것처럼 보인다 → 테두리는 전부 동일하게.
		draw_rect(sr, Color(0.35, 0.35, 0.5, 0.6), false, 1.5)

		# 손에 들려 있거나 트레이로 되돌아가는 중인 조각은 슬롯에 그리지 않는다 (_draw_held가 그린다)
		var in_hand: bool = (dragging and i == drag_slot) or (
				not snapback.is_empty() and int(snapback["slot"]) == i)

		if not slot.is_empty() and not in_hand:
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
		elif slot.is_empty():
			# 빈 슬롯 표시 (손에 들려 있을 뿐인 슬롯은 배경만 두고 비워 둔다)
			var dash: String = "—"
			var dw: float = fnt.get_string_size(dash, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string(fnt, Vector2(sr.position.x + sr.size.x * 0.5 - dw * 0.5,
					sr.position.y + sr.size.y * 0.5 + 8.0),
					dash, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.3, 0.3, 0.4))

	# 입력 방식 토글 (PC 테스트용) — 눌러서 드래그/클릭 전환
	draw_rect(mode_btn, Color(0.20, 0.20, 0.31))
	draw_rect(mode_btn, Color(0.45, 0.45, 0.6, 0.85), false, 2.0)
	var mtxt: String = _t("mode_click") if click_mode else _t("mode_drag")
	var mw: float = fnt.get_string_size(mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(fnt, Vector2(mode_btn.get_center().x - mw * 0.5, mode_btn.position.y + 21.0),
			mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.88, 0.88, 0.95))
	var sub: String = _t("mode_switch")
	var sw: float = fnt.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(fnt, Vector2(mode_btn.get_center().x - sw * 0.5, mode_btn.position.y + 38.0),
			sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.62))

	# 조작 안내
	var inst_y: float = float(bot_y) + float(TRAY_SLOT_H) + 30.0
	var how: String = _t("how_click") if click_mode else _t("how_drag")
	draw_string(fnt, Vector2(20.0, inst_y), how,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.8, 0.8, 0.85))
	draw_string(fnt, Vector2(20.0, inst_y + 28.0), _t("rule_blast"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.55, 0.85, 0.6))
	draw_string(fnt, Vector2(20.0, inst_y + 54.0), _t("rule_combo"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.85, 0.75, 0.4))
