# i18n.gd — 게임 UI 로컬라이제이션 테이블 + 조회 헬퍼.
#
# 이 게임은 Control 노드가 아니라 커스텀 draw(_draw_text_outlined 등)로 UI를 그린다 →
# Godot의 자동 tr() 번역이 안 먹는다. 그래서 각 draw 사이트가 명시적으로 I18N.t(locale, key)로 조회한다.
#
# 새 언어 추가:
#   1) STR에 로케일 하나 추가(모든 키의 번역).
#   2) SUPPORTED에 로케일 코드 추가.
#   3) 라틴 밖 스크립트(CJK 등)면 fonts/ 서브셋 글리프 확장(그 로케일 문자열의 합집합).
#      라틴/키릴/그리스는 번들된 Noto Sans가 이미 커버 → 폰트 작업 불필요.
#
# 포맷 인자(%d·%s)는 키의 값에 그대로 두고, 호출부에서 `I18N.t(loc, key) % 인자`로 채운다.
# ⚠어떤 로케일이든 %인자 개수·종류는 동일해야 한다(안 그러면 % 연산이 런타임 에러).
# Main.gd가 `const I18N = preload("res://i18n.gd")`로 참조한다(전역 class_name 스캔 타이밍 비의존).
extends RefCounted

const DEFAULT_LOCALE: String = "en"          # 영어 우선(base). 미지원 로케일은 여기로 폴백.
const SUPPORTED: Array = ["en"]               # 영어 우선 출시(C75): 라틴 전용 폰트라 CJK는 두부 → en만 노출. ko 테이블은 아래 보존(CJK 폰트 번들 시 "ko" 복귀).

const STR: Dictionary = {
	"en": {
		# ── 스테이지 이름/태그(STAGES 데이터가 이 키를 담는다) ──
		"st1_name": "First Line",
		"st1_tag": "Complete lines to clear the lane",
		"st2_name": "Swarm",
		"st2_tag": "They scatter in — one line won't cut it",
		"st3_name": "Blitz",
		"st3_tag": "Fast — no time to think",
		"st4_name": "Line Famine",
		"st4_tag": "Straights run dry — your hand is the threat",
		# 이름은 콜아웃(callout_tank)과 같은 말을 써야 한다 — 스테이지가 "Armor", 적이 "TANK"면
		#   플레이어는 같은 적을 두 이름으로 본다(C160). 내부 etype이 "tank"라 표기를 그쪽으로 통일.
		#   '한 줄로는 안 뚫린다'는 인과는 콜아웃이 가져갔다 → 태그는 판 성격만 말한다.
		"st5_name": "Tank",
		"st5_tag": "Heavies roll in — save your biggest clears for them",
		"st6_name": "All-Out",
		"st6_tag": "Everything comes",
		"st7_name": "Split",
		"st7_tag": "They split — take them high",
		"st8_name": "Last Line",
		"st8_tag": "Everything comes — and it splits",
		"st9_name": "Gem Rush",
		"st9_tag": "Catch the falling gems — enemies are just the risk",
		"st10_name": "Two Colors",
		"st10_tag": "Two gem colors now — fill both, pick your shots",
		"st11_name": "Defuse",
		"st11_tag": "Bombs are counting down — clear them before they blow",
		"st12_name": "Under Fire",
		"st12_tag": "Bombs among the swarm — pick which to defuse first",
		"st13_name": "Chain Reaction",
		"st13_tag": "Bombs set off their neighbors — break the chain first",
		"st14_name": "Vault",
		"st14_tag": "Thieves loot your vault and flee — block them or chase them down",
		# ── 설정 모달 ──
		"settings": "Settings",
		"sound": "Sound",
		"haptic": "Vibration",       # 'Haptics'보다 폰 설정에서 익숙한 말(안드로이드·iOS 둘 다)
		"home": "Home",              # 라벨(설정 행 · 뒤로가기)
		"go_home": "Home",           # 버튼(설정 홈 · 결과 홈)
		"restart_label": "Restart",
		"restart": "Restart",
		# 개인정보 옵션(광고 동의 재설정) — EEA/UK에서 동의를 받은 유저에게만 노출(구글 요구사항).
		"privacy_label": "Ad privacy",
		"privacy_btn": "Manage",
		# ── 결과 팝업 ──
		"fail_close": "Almost had it!",
		"fail_near": "So close!",
		"fail_far": "Try again?",
		"score_headline": "%s",
		"stage_clear": "Stage Clear!",
		"cause_stuck": "No room left",
		"cause_core": "Castle destroyed",
		"shutout": "Shutout — not one got through",
		"kills_leaks": "Killed %d · Leaked %d",
		"first_record": "🏆 First record!",
		"new_record": "🏆 New best! +%s",
		"best": "Best",
		"gap_to_best": "%s to your best",   # 죽은 직후의 비교 한 줄 — 다음 판까지의 거리

		"result_remaining": "Enemies left",
		"result_gems": "Gems left",
		"result_killed": "Killed",
		"continue": "Continue",
		"ad_loading": "Loading ad...",   # 부활 광고 로드 중 — 버튼이 잠긴 이유를 말해준다(W2 R1)
		"retry": "Retry",
		"next_stage": "Next Stage",
		# 마지막 스테이지 클리어 = 완주 아님, '콘텐츠 따라잡음'(프런티어) → 무한 깔때기. 시점 약속 회피.
		"caught_up": "All caught up!",
		"frontier_sub": "New stages keep coming",
		"frontier_home": "Endless awaits back home",
		"play_endless": "Play Endless",
		# ── 메인 메뉴(허브) ── (소제목 adv_sub·endless_sub는 C82서 제거 — 유저 요청)
		"adv_big": "Adventure",
		"endless_big": "Endless",
		"endless_locked": "Clear Stage 1 to unlock",   # 무한 잠금(허브 버튼 소제목 + 리더보드 CTA)
		"best_score": "Best %s",     # 메뉴 · HUD 무한 최고점
		# ── 스테이지 선택 ── 제목은 모드 이름이라 허브 버튼 라벨(adv_big)을 그대로 쓴다(C156).
		#   ("cleared_count"는 C156서 삭제 — 진행도를 숫자로 안 보여준다)
		# 제목 아래 한 줄 = 상태별 한마디(_sel_message, C157). 셋 다 짧게 — 길면 두 줄로 넘쳐 그리드를 민다.
		"sel_msg_first": "Clear stages to raise your castle.",
		"sel_msg_go": "Keep the walls rising.",
		"sel_msg_retry": "So close. One more try.",
		"dev_unlock": "DEV: unlock all (0)",
		"unlock_req": "Clear stage %d to unlock",
		"done_badge": "Done",
		"select_hint": "SPACE or tap a button",
		"stage_n": "Stage %d",
		"all_cleared": "All clear! Play again",
		# ── 리더보드 화면 ──
		"lb_sub": "Endless · High score board",
		"lb_empty_big": "Set your first record!",
		"lb_empty_sub": "Post a score in Endless to open the ranking",
		"lb_percentile": "Top %d%%",
		"lb_friend_rank": "#%d of %d friends",   # ⚠인자 순서 = [순위, 총원] (로케일 공통)
		"lb_my_best": "My best",
		"lb_clean_cap": "No revive",
		"lb_friends": "Friends",
		"lb_you": "You",
		"lb_preview_note": "Preview · Connect your account to see real friends",
		"intro_kills": "kills",   # 인트로 💀 수 접미사(목표 프레이밍). 수 뒤에 작게.
		# ── HUD ──
		"combo": "Combo x%d",
		"leaderboard": "Leaderboard",   # 메뉴 우상단 진입 버튼
		"new_best_live": "New best!",
		"new_best_ribbon": "NEW BEST",   # PB 판전체 폭발 리본 배너 라벨(C90)
		"score": "Score",
		"goal": "Goal",
		"hud_enemies": "Enemies",    # 목표 카드 캡션(해골 아이콘 옆, 짧게)
		"advance": "Enemy move",   # '적이 N턴 뒤 전진'을 명시 — 'Advance'만으론 누가/어디로가 모호
		"turns": "turns",
		"turn_1": "turn",          # remain==1 단수(‘1 turns’ 오류 방지)
		# ── 보스(감시자) 스테이지 ──
		"boss": "Warden",
		"debris": "Debris",
		"collect": "Collect",
		"vault": "Vault",
		"result_vault": "Vault kept",
		# 픽업 둘도 콜아웃 잣대를 같이 받는다(C160).
		# ⚠옛 보석 문구 "catch them, don't just clear"는 **없는 구분을 지어냈다** — 보석을 낚아채는
		#   방법이 곧 그 줄을 지우는 것이다(_hit_one의 gem 분기: 블라스트가 닿으면 획득). '낚아채기 vs
		#   치우기'라는 두 동사가 있는 것처럼 읽혀서, 정작 뭘 눌러야 하는지는 안 말했다.
		#   대신 실패 모드를 붙였다 — 보석은 안 잡으면 바닥으로 빠져 사라진다(진행 손해).
		"callout_gem": "GEMS — clear their line, or they fall through",
		# ⚠"row or column"은 정확하지만 이 게임의 공용어가 아니다 — 나머지 문구가 전부 'line'을 쓴다
		#   (tut_kill "Clear a line" · TANK "one line" · SWARM "one line"). 블라스트는 지운 행·열을
		#   모두 훑으므로 'its line'이 둘 다 덮는다. 라벨도 적 콜아웃과 같은 대문자꼴로 맞췄다 —
		#   '위협이 아님'은 보드 위 form이 이미 말한다(흰 삼각형·청록 후광, _draw 주석).
		# ⚠라벨은 **물건 이름**이어야 한다 — 범주로 갈아끼웠더니("POWER-UP") 화면에 뜬 물건과 부르는
		#   이름이 어긋나 보였다(유저 확인). 대신 범주는 뒤 절 첫 낱말로 옮겨 "좋은 물건"임을 즉시 말한다.
		#   이름 + 범주 + 줍는 법이 한 줄에 다 들어간다.
		# ⚠효과(확정 처치)는 일부러 뺐다 — 아직 못 주운 물건의 사용법은 지금 쓸 데가 없다. 그 몫은
		#   슬롯 맥동(보유)과 조준 링(표적 지시)이 진다(_draw_bottom 주석: 색·테두리로만 구분).
		#   ⚠단 그 배움이 실제로 되는지는 사람 플테로 확인할 것 — 코드가 보장하는 건 링이 뜬다는 것뿐이다.
		"callout_plane": "PLANE — power-up! Clear its line to grab it",
		# ── 거점(보드 하단 방어선) ──
		"core_hp": "Castle HP  %d / %d",
		# ── 게임플레이 콜아웃/tell(원래 영어로 authored — 값 동일, 로케일 확장용으로만 키화) ──
		"tut_kill": "Enemy incoming! Clear a line to take it down",
		"tut_leak": "Enemy slipped through — the Castle took damage!",
		"combo_flash": "COMBO x%d",
		"tell_block": "BLOCK",
		# 콜아웃 = 그 적을 처음 만난 3.4초. 답해야 하는 건 "지금 이걸 어떻게 상대하나" 하나뿐이라
		#   이름은 라벨로만 두고 정보는 뒤 절에 싣는다. 이름을 형용사로 되풀이하면(옛 "FAST — quick!")
		#   글자만 차지하고 행동이 안 나온다. C160서 여섯 개 전부 '기전 → 할 일' 꼴로 다시 씀.
		"callout_fast": "FAST — it arrives first, so kill it first",
		# ⚠"big combo"는 모호했고("Combo x%d"는 연속 스트릭인데 동시 2줄과 다른 축), 그 뒤에 쓴
		#   "clear two at once"는 **첫 조우자에게 동시 삭제라는 고급 조작을 요구했다.** 실제 체험은
		#   훨씬 단순하다 — 한 대 때리면 안 죽고 HP 바가 뜬다(Main.gd `if e["hp"] < e["maxhp"]` 주석:
		#   "바가 보이면 = 얘는 한 방에 안 죽었다"). 문구가 그 바와 같은 말을 하게 맞췄다.
		# ⚠숫자를 안 박은 이유(tools/tank_hits_probe.gd 실측): 첫 조우판(st5) 탱크 HP 198~257 →
		#   줄을 **이어서** 지우면 2번(120+180=300), 스트릭이 끊기면 3번(120+120=240 < 257).
		#   후반 st8은 연속이어도 3번. "twice"는 늘 참이 아니라 약속하지 않는다.
		"callout_tank": "TANK — one line won't kill it; hit it again",
		# ⚠"weak, but many"의 '약하다'는 **스탯 설명**이지 할 일이 아니다(HP 0.4배). 지우고 결과만 남겼다 —
		#   한 줄로 무리째 잡힌다는 말 안에 '약하다'가 이미 들어 있다. 두 절 → 한 절.
		"callout_swarm": "SWARM — one line takes the whole group",
		# 파랑 점선은 미분열 개체가 있을 때만 뜬다 = 이 문구가 뜨는 순간 가리킬 선이 실제로 화면에 있다.
		#   ⚠단 "the line"만으론 어느 선인지 안 잡힌다 → 색을 부른다. 그 점선은 화면의 유일한 파랑이고
		#   분열체와 같은 파랑이라(_draw 주석 참조), 색을 부르는 것만으로 글자가 그 짝을 가리킨다.
		"callout_split": "SPLIT — kill above the blue line, or it doubles",
		# ⚠옛 "before the fuse runs out"은 **시간을 암시했다** — 실제 도화선은 남은 배치 수고(조각을 놓을
		#   때마다 1 감소) 이 게임엔 시간 압박이 없다. 그 뒤에 쓴 "that number counts your moves"는
		#   반대로 **UI를 가르치려 들었다**(탱크가 "clear two at once"로 헛디딘 것과 같은 실수).
		#   숫자는 몸통 한가운데 크게 그려져 있고 0에 가까울수록 붉게·빠르게 맥동한다 — 설명할 게 아니라
		#   가리킬 물건이다. '남은 수'라는 건 조각을 놓을 때마다 줄어드는 걸 보면 저절로 배운다.
		"callout_bomb": "BOMB — clear it before the number hits zero",
		# 도둑은 2단이다(C160). 등장 시점의 도둑은 아직 안 훔쳤으므로 '쫓아가 잡아라'는 아직 일어나지 않은
		#   일 — 그 절은 실제로 훔치는 순간(carrying=true, 자루 보석·상승 쉐브론이 붙는 그때)으로 옮겼다.
		"callout_thief": "THIEF — block it before it reaches your vault",
		"callout_thief_stolen": "STOLEN — kill it before it escapes!",
		# ── 입력 토글(PC 테스트용) ──
		# 상시 조작·규칙 안내 4줄(how_*/rule_*)은 C79에서 제거 — 키도 함께 지웠다.
		# 가르치는 몫은 스테이지1 튜토리얼과 화면이 보여주는 것들이 가져간다(_draw_bottom 주석 참조).
		"mode_click": "CLICK MODE",
		"mode_drag": "DRAG MODE",
		"mode_switch": "tap to switch",
	},
	"ko": {
		"st1_name": "첫 방어선",
		"st1_tag": "줄을 완성해 레인을 청소한다",
		"st2_name": "무리",
		"st2_tag": "흩어져 밀려온다 — 한 줄로는 못 쓴다",
		"st3_name": "속공",
		"st3_tag": "빠르다 — 시간이 없다",
		"st4_name": "줄 굶김",
		"st4_tag": "직선이 굶는다 — 손이 곧 위협",
		"st5_name": "탱크",
		"st5_tag": "무거운 것들이 온다 — 큰 삭제를 아껴 써라",
		"st6_name": "총력전",
		"st6_tag": "전부 온다",
		"st7_name": "분열",
		"st7_tag": "갈라진다 — 높이 있을 때 잡아라",
		"st8_name": "최종 방어선",
		"st8_tag": "전부 온다 — 그리고 갈라진다",
		"st9_name": "보석 러시",
		"st9_tag": "떨어지는 보석을 낚아채라 — 적은 위험일 뿐",
		"st10_name": "두 색",
		"st10_tag": "이제 보석 두 색 — 둘 다 채워라, 골라 쏴라",
		"st11_name": "해체",
		"st11_tag": "폭탄이 카운트다운 중 — 터지기 전에 걷어내라",
		"st12_name": "교전 중",
		"st12_tag": "무리 속의 폭탄 — 어느 걸 먼저 해체할지 골라라",
		"st13_name": "연쇄 반응",
		"st13_tag": "폭탄이 옆 폭탄을 터뜨린다 — 연쇄부터 끊어라",
		"st14_name": "금고",
		"st14_tag": "도둑이 금고를 털어 도망친다 — 막거나 쫓아가 되찾아라",
		"settings": "설정",
		"sound": "소리",
		"haptic": "진동",
		"home": "홈",
		"go_home": "홈으로",
		"restart_label": "다시하기",
		"restart": "재시작",
		"privacy_label": "광고 개인정보",
		"privacy_btn": "관리",
		"fail_close": "거의 다 왔어요!",
		"fail_near": "아쉬워요!",
		"fail_far": "다시 해볼까요?",
		"score_headline": "%s점",
		"stage_clear": "스테이지 클리어!",
		"cause_stuck": "놓을 곳이 없다",
		"cause_core": "성 파괴",
		"shutout": "완봉 — 한 마리도 놓치지 않았다",
		"kills_leaks": "처치 %d · 누수 %d",
		"first_record": "🏆 첫 기록!",
		"new_record": "🏆 신기록! +%s",
		"best": "최고",
		"gap_to_best": "최고까지 %s점",   # 죽은 직후의 비교 한 줄 — 다음 판까지의 거리

		"result_remaining": "남은 적",
		"result_gems": "남은 보석",
		"result_killed": "처치",
		"continue": "이어하기",
		"ad_loading": "광고 불러오는 중...",
		"retry": "재도전",
		"next_stage": "다음 스테이지",
		# 마지막 스테이지 클리어 = 완주 아님, '콘텐츠 따라잡음'(프런티어) → 무한 깔때기. 시점 약속 회피.
		"caught_up": "다 따라잡았어요!",
		"frontier_sub": "새 스테이지는 계속 추가돼요",
		"frontier_home": "그동안 무한은 홈에서",
		"play_endless": "무한 도전",
		"adv_big": "스테이지",
		"endless_big": "무한",
		"endless_locked": "스테이지 1을 깨면 열려요",
		"best_score": "최고 %s",
		"sel_msg_first": "판을 깨서 성을 쌓아 올려요",
		"sel_msg_go": "성벽을 계속 올려요",
		"sel_msg_retry": "아깝네요 — 한 번 더",
		"dev_unlock": "DEV: 전체 해금 (0)",
		"unlock_req": "%d 스테이지를 클리어하면 열림",
		"done_badge": "클리어",
		"select_hint": "SPACE 또는 버튼 클릭",
		"stage_n": "스테이지 %d",
		"all_cleared": "전부 클리어! 다시 도전",
		"lb_sub": "무한 · 최고점 자랑 보드",
		"lb_empty_big": "첫 기록에 도전!",
		"lb_empty_sub": "무한 모드에서 첫 점수를 남기면 순위가 열려요",
		"lb_percentile": "상위 %d%%",
		"lb_friend_rank": "%d위 / 친구 %d명",   # ⚠인자 순서 = [순위, 총원] (영어와 동일)
		"lb_my_best": "내 최고",
		"lb_clean_cap": "부활 없이",
		"lb_friends": "친구 순위",
		"lb_you": "나",
		"lb_preview_note": "미리보기 · 계정을 연결하면 실제 친구 순위가 표시돼요",
		"intro_kills": "처치",   # 인트로 💀 수 접미사(목표 프레이밍). 수 뒤에 작게.
		"combo": "콤보 x%d",
		"leaderboard": "리더보드",
		"new_best_live": "최고 갱신!",
		"new_best_ribbon": "신기록",   # PB 판전체 폭발 리본 배너 라벨(C90)
		"score": "점수",
		"goal": "목표",
		"hud_enemies": "남은 적",
		"advance": "적 이동",
		"turns": "턴",
		"turn_1": "턴",
		"boss": "감시자",
		"debris": "잔해",
		"collect": "수집",
		"vault": "금고",
		"result_vault": "지킨 금고",
		"callout_gem": "보석 — 그 줄을 지워라, 놓치면 빠져나간다",
		"callout_plane": "비행기 — 특수 아이템! 그 줄을 지우면 획득",
		"core_hp": "성 HP  %d / %d",
		# ⚠아래 콜아웃/tell·온보딩의 한국어는 초안(원문이 영어라 대응 한글이 없었음). 검수/조정 여지.
		"tut_kill": "적이 내려와요! 줄을 채워 잡으세요",
		"tut_leak": "적이 통과했어요 — 성이 깎였어요!",
		"combo_flash": "콤보 x%d",
		"tell_block": "버팀",
		"callout_fast": "속공 — 먼저 도착한다, 먼저 잡아라",
		"callout_tank": "탱크 — 한 줄로는 안 죽는다, 한 번 더",
		"callout_swarm": "무리 — 한 줄이면 한꺼번에 잡힌다",
		"callout_split": "분열 — 파란 선 위에서 잡아라, 넘기면 둘이 된다",
		"callout_bomb": "폭탄 — 숫자가 0이 되기 전에 걷어내라",
		"callout_thief": "도둑 — 금고에 닿기 전에 막아라",
		"callout_thief_stolen": "도난! — 도망치기 전에 잡아라",
		"mode_click": "클릭 모드",
		"mode_drag": "드래그 모드",
		"mode_switch": "눌러서 전환",
	},
}

# 로케일 클램프: 지원 목록에 있으면 그대로, 아니면 기본(en). OS.get_locale_language() 결과를 통과시킨다.
static func resolve_locale(raw: String) -> String:
	return raw if raw in SUPPORTED else DEFAULT_LOCALE

# 조회: 로케일에 키가 있으면 그 값, 없으면 기본 로케일, 그것도 없으면 키 자체(미번역 가시화).
static func t(locale: String, key: String) -> String:
	var table: Dictionary = STR.get(locale, STR[DEFAULT_LOCALE])
	if table.has(key):
		return table[key]
	var base: Dictionary = STR[DEFAULT_LOCALE]
	return base.get(key, key)
