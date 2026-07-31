extends RefCounted
# stage_data.gd — 캠페인 판 데이터(STAGES) + 조각 풀 프리셋을 Main.gd(god-object)에서 분리한 '저작 섬'.
#   Main.gd가 `const SD = preload("res://stage_data.gd")` + `const STAGES := SD.STAGES`로 별칭 참조한다
#   (전역 class_name 스캔 타이밍 비의존 — i18n.gd와 동일 패턴).
#   ⚠순수 데이터(로직·상태 결합 0). 값이 불변이면 회귀 byte-identical(tools/regress.gd).
#   스테이지 오소링(판 추가·튜닝)은 이 파일만 건드리면 되고 Main.gd를 안 만진다
#   → 병렬 트랙 충돌 감소([[parallel-work-worktrees]]가 '미래 옵션'으로 지목한 STAGES 추출).
#   POOL_* 프리셋은 STAGES가 참조하므로 여기 같이 산다(자기완결). ENEMY_TYPES는 엔진측이라 Main.gd 잔류.

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
# 기준 ⑦ plane_cd = 비행기 픽업이 다 쓰인 뒤 다음 것이 나오기까지의 배치 수(희소 손잡이).
#   한 사이클 = 보드 체류(≈7배치, 이 중 ~82%가 획득) + plane_cd → 판당 사용 ≈ P/(7+cd)×0.82.
#   ⚠체류가 짧은 이유: 픽업은 '우연히 지나가는 줄에 걸리는' 게 아니라 플레이어가 노려서 딴다.
#   클리어 분포가 픽업과 무관하다고 가정하면 체류를 13.7배치로 과대평가하게 된다(첫 산정의 오류).
#   ⇒ 산정은 반드시 실측으로: tools/plane_rate_probe.gd(클리어 빈도) + tools/plane_verify.gd(실사용).
#   현 배정 목표(사용/판): 초반 ~2회 → 후반 ~1회.
#   ⚠미해결: 비행기 도입으로 승률이 평균 +8.9pt 올랐고(판별 독립시드 A/B, N=40), 상승폭이 후반에
#   더 크다(st13 +22.5, st11 +22.5, st7 +17.5). 횟수는 후반에 줄여놨지만 '확정 처치 1회'의 값어치가
#   판이 어려울수록 커지기 때문 — 빈도를 낮춰도 가치 상승을 못 따라간다. 난이도 곡선을 되살리려면
#   후반 core_hp/total 재조정이 필요하다(캠페인 밸런스 재개 결정 사항이라 여기선 손대지 않았다).
#   수집·튜토리얼 판엔 아예 안 나온다(Main._plane_allowed) → 그 판들엔 plane_cd 자체가 없다.

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
		"plane_cd": 3,
		"total": 30, "core_hp": 3, "base_hp": 32, "hp_ramp": 0.4, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 4, "floor": 5, "surge_at": 0.82,
		"weights": {"basic": 40, "fast": 0, "tank": 0, "swarm": 60, "split": 0}, "pool": POOL_RICH,
	},
	{
		"name": "st3_name", "tag": "st3_tag",
		"plane_cd": 8,
		"total": 34, "core_hp": 4, "base_hp": 34, "hp_ramp": 0.5, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 5, "surge_at": 0.80,
		"weights": {"basic": 40, "fast": 50, "tank": 0, "swarm": 10, "split": 0}, "pool": POOL_STD,
	},
	{
		# 퍼즐 축 고립(C54): 새 적 없이 pool LEAN(I5 희소)만으로 압박 = '손이 곧 위협'.
		# 적은 basic/swarm(이미 배운 것)이라 난이도는 전적으로 조각 분포에서 나온다.
		# core_hp 5(C96): 온보딩 절벽 완화 — hp3=41% 거점사벽이라 누수 여유만 키움(막힘=퍼즐압은 불변).
		#   비대칭(st3=4, st4=5): st4가 pool-lean로 구조상 더 어려워 더 큰 보정. sim 41→67.5%.
		"name": "st4_name", "tag": "st4_tag",
		"plane_cd": 7,
		"total": 36, "core_hp": 5, "base_hp": 36, "hp_ramp": 0.4, "tank_mult": 2.5,
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
	# ── Defuse R1 도입(S6): 코어 방어(S1~4)+수집(S5) 배운 직후 새 동사. 격리(basic↔bomb)라 난이도가 전적으로 새 기전에서. ──
	# 점화 적(bomb)이 도화선(bomb_fuse=남은 배치 수)을 달고 온다. 0이 되기 전에 걷어내면 해체(깨끗한 처치),
	#   놓치면 제자리서 터져 거점 bomb_dmg 피해(일반 누수 -1보다 큼) = 데드라인 위협. 새 결정 = "이 라인을 폭탄에 쓸까".
	# 격리 도입(basic↔bomb만) = 난이도가 전적으로 새 기전에서(split 도입판 S7과 동형). core_hp 4 = 한두 번 실수 여유.
	{
		"name": "st11_name", "tag": "st11_tag", "bomb_fuse": 8, "bomb_dmg": 2,
		"plane_cd": 20,
		"total": 26, "core_hp": 6, "base_hp": 30, "hp_ramp": 0.2, "tank_mult": 2.5,
		"spawn_every": 3, "step_every": 3, "onboard": 3, "floor": 2, "surge_at": 0.80,
		"weights": {"basic": 85, "bomb": 15}, "pool": POOL_STD,
	},
	{
		# tank HP를 콤보3(240) 구간에 앉힌다: base 44~50 × 4.5 = 198~227 → 콤보2(180)로는 안 뚫림.
		"name": "st5_name", "tag": "st5_tag",
		"plane_cd": 21,
		"total": 44, "core_hp": 2, "base_hp": 44, "hp_ramp": 0.3, "tank_mult": 4.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 5, "surge_at": 0.80,
		"weights": {"basic": 40, "fast": 0, "tank": 55, "swarm": 5, "split": 0}, "pool": POOL_STD,
	},
	{
		# 복습판(전 4종 혼합). core_hp 3(C96): hp2=거점사벽 30%로 클라이맥스(st8, 21%)와 동률이라 스파이크 —
		#   클라이맥스 잠식·비단조 톱니 제거. sim 무릎: hp2→3 +15pt, 3→4 0(패배가 누수사→막힘으로 이동, core_hp 무효).
		#   복습판은 클라이맥스보다 확실히 위여야 깔때기가 산다. tank_mult/혼합은 성격이라 불변, 누수 여유만.
		"name": "st6_name", "tag": "st6_tag",
		"plane_cd": 16,
		"total": 48, "core_hp": 3, "base_hp": 46, "hp_ramp": 0.4, "tank_mult": 4.2,
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
		"plane_cd": 24,
		"total": 48, "core_hp": 3, "base_hp": 44, "hp_ramp": 0.35, "tank_mult": 4.2,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 6, "surge_at": 0.80,
		"weights": {"basic": 60, "fast": 0, "tank": 0, "swarm": 0, "split": 40}, "pool": POOL_STD,
	},
	{
		# act-3 클라이맥스 = 전 로스터 + 분열 + core_hp 2 (S1 '첫 방어선'과 수미상관 '최종 방어선').
		# 분열은 방어축 레버(거점사 지배)라 청소 처리량을 굶기는 tank/fast/swarm 위에 겹쳐 얹힌다.
		# split 25%(수확 시작점) — 100%가 아니라, 다른 위협과 섞여야 '전부 온다'가 성립.
		"name": "st8_name", "tag": "st8_tag",
		"plane_cd": 19,
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
		# gem_even_mix: 수요필터 OFF — 두 색을 균등 낙하시켜, 이미 채운 색을 흘려보내며 부족색을 붙잡는 결정이 실제로 생기게.
		#   (수요필터는 '필요한 색만' 띄워 이 결정을 원천 제거 → 2색이 1색 두배길이로 붕괴. 이 판만 끈다.)
		"name": "st10_name", "tag": "st10_tag", "collect": true, "collect_targets": [8, 8], "gem_every": 2, "gem_fast": true, "gem_even_mix": true,
		"total": 300, "core_hp": 3, "base_hp": 32, "hp_ramp": 0.2, "tank_mult": 3.0,
		"spawn_every": 3, "step_every": 3, "onboard": 2, "floor": 2, "surge_at": 0.0,
		"weights": {"basic": 45, "fast": 40, "tank": 15, "swarm": 0, "split": 0}, "pool": POOL_STD,
	},
	# ── Defuse R2: 통합 + 트리아지 — 폭탄이 방어 로스터(속공·무리)와 섞이고 밀도↑로 가끔 두 폭탄이 동시에 탄다. ──
	#   새 결정: ①클리어를 폭탄에 쓸까 밀려오는 적에 쓸까(위협 경제 합류) ②둘 다 못 잡을 때 어느 폭탄부터(트리아지).
	#   격리(R1)보다 fuse 조이고(7) spawn_every 2로 동시성↑. 2번째 rung이라 목표 승률 R1(71%)보다 낮게(~55%).
	{
		"name": "st12_name", "tag": "st12_tag", "bomb_fuse": 8, "bomb_dmg": 2,
		"plane_cd": 24,
		"total": 32, "core_hp": 6, "base_hp": 30, "hp_ramp": 0.25, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 3, "surge_at": 0.80,
		"weights": {"basic": 47, "fast": 20, "swarm": 15, "bomb": 18}, "pool": POOL_STD,
	},
	# ── Defuse R3: 연쇄 폭탄(bomb_chain) — 하나가 터지면 인접 폭탄(8방)도 도미노 폭발, HP 벌 합산 = 큰 한 방. ──
	#   새 결정: R1(제때 닿나)·R2(어느 걸 먼저)와 달리, "연쇄를 끊는 linchpin(임박한 하나)을 먼저 해체해 도미노를 막아라".
	#   폭탄 밀도↑(뭉쳐서 연쇄 성립)·spawn_every 2로 인접 유도. 연쇄가 -HP를 곱하니 core_hp 여유(연쇄 못 끊으면 급사).
	{
		"name": "st13_name", "tag": "st13_tag", "bomb_fuse": 8, "bomb_dmg": 2, "bomb_chain": true,
		"plane_cd": 23,
		"total": 32, "core_hp": 7, "base_hp": 30, "hp_ramp": 0.2, "tank_mult": 2.5,
		"spawn_every": 2, "step_every": 3, "onboard": 3, "floor": 3, "surge_at": 0.80,
		"weights": {"basic": 62, "bomb": 38}, "pool": POOL_STD,
	},
]


# ===== 파킹: 캠페인 밖으로 뺀 판 =====
# Protect(도둑) R1 — 2026-07-31 유저 판정으로 **캠페인에서 제외**했다.
#   사유: 실플레이서 "도둑이 뭐하는지 전혀 인지가 안 된다". 원본 프레임 확인 결과 근거 있음 —
#   몸이 웃는 얼굴로 읽히고, 훔친 상태(후광·자루·쉐브론)가 전부 미약하며, 무엇보다 **상단 금고 카드와
#   바닥의 도둑이 아무 인과로도 안 이어진다**(훔친 순간 카드에서 다이아만 조용히 꺼짐).
#   규칙이 안 읽히는 판이 캠페인 마지막(무한 깔때기 직전)에 있으면 안 되므로 뺐다.
#   ⚠재설계 전엔 여기에 밸런스 투자 금지. 데이터는 재설계 착수 시 출발점으로 남긴다.
#   ⚠campaign.save의 cleared 비트는 인덱스 기반이고 이 판이 배열 끝이었으므로, 빼도 기존 진행도는 안 밀린다.
#   프로브(tools/thief_probe.gd)는 STAGES가 아니라 이 상수를 직접 열어서 돈다.
# ── Protect R1 도입: 도둑(thief) 동사 = 상실(loss aversion). 거점 도달 시 거점을 안 때리고 금고서 훔쳐 되돌아 위로 도망. ──
#   3결과: 뺏기 전 처치=완전 저지 · 물고 도망칠 때 처치=회수(금고로 되돌림) · 위로 탈출=영구 손실.
#   승리 = 웨이브 소탕(탈출=leaked로 회계 보존) + 금고>0. 패 = 거점사 or 금고 전소(상실축, 거점사와 별개).
# ⚠설계 발견(thief_probe): Defuse식 '무압력 격리 R1'은 Protect엔 불가 — 막기(block)가 일반 클리어와 겹쳐 공짜라
#   좋은 봇이 도둑을 거의 다 걷어내 금고가 안 준다(동사가 죽은 리스킨화). 손실이 실제로 나려면 '두 전선 경쟁'이 필수:
#   thief_step 1(도둑 blitz하강=대개 막기 불가→낚아채기가 기본)로 낮은 전선을 뚫리게 하고, carry_step 1(빠른 도주)로
#   회수 창을 좁혀 도망을 위험케 → 게임이 '거점방어(아래) vs 회수추격(위)'의 공간적 기회비용이 된다. step_every 2(빠른 밀물)가
#   그 경쟁 압력. 격리 로스터(basic↔thief)는 유지.
# ⚠C104 thief_hp_mult 0.35 → 5.0: R1은 '저HP=포지셔닝 위협'이었지만 C102 줄서기(한 칸에 하나) 이후
#   도망 도둑이 위쪽 아군에 막혀 서고, 서 있는 놈은 공짜로 회수돼 **상실축이 패배를 안 만들었다**
#   (탈출 0.63→0.38회/판, 금고전소 17→2/200). carry_step은 이미 1(최속)이라 남은 레버가 HP였다.
#   ⚠HP는 최소 일격(120)을 넘겨야 비로소 레버가 된다 — 0.35×(hp 11)은 물론 1.3×(39)도 한방컷이라
#   스윕에서 '아무 차이 없음'으로 나온다([[cascade-damage-mult-is-meaningless]]). 5.0×에서 한 줄은
#   버티고 2줄·콤보엔 죽는 구간에 앉는다 = 회수하려면 좋은 수를 써야 함 → 회수 창이 좁아진다.
#   부수효과(의도): 도망 중 넉백은 위로 밀어 탈출을 돕는다 — 어설픈 한 대가 오히려 놓치는 값.
#   실측(thief_probe 시드고정 N=200, C101 이전 기준선 → 5.0): 승률 73.0→71.0%, 금고전소 17→22,
#   평균금고 3.10→3.05, 탈출 0.63→0.53 = 상실축 복원.
#   실측(thief_probe N80): 승률 71%·거점사6·금고전소7·막힘10, 금고 4→2.9(판당 −1.1 체감), 낚/회/탈 3.6/2.5/0.8(회수=생존 스킬, load-bearing).
const PARKED_PROTECT: Dictionary = {
	"name": "st14_name", "tag": "st14_tag", "protect": true, "vault_start": 4, "steal": 1,
	"thief_step": 1, "thief_carry_step": 1, "thief_hp_mult": 5.0,
	"total": 32, "core_hp": 5, "base_hp": 30, "hp_ramp": 0.2, "tank_mult": 2.5,
	"spawn_every": 2, "step_every": 2, "onboard": 3, "floor": 2, "surge_at": 0.80,
	"weights": {"basic": 52, "thief": 48}, "pool": POOL_STD,
}
