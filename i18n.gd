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
const SUPPORTED: Array = ["en", "ko"]         # 영어만 출시하려면 ["en"]으로 — ko 테이블은 보존됨.

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
		"st5_name": "Armor",
		"st5_tag": "One hit won't break it — build combos",
		"st6_name": "All-Out",
		"st6_tag": "Everything comes",
		"st7_name": "Split",
		"st7_tag": "They split — take them high",
		"st8_name": "Last Line",
		"st8_tag": "Everything comes — and it splits",
		# ── 설정 모달 ──
		"settings": "Settings",
		"sound": "Sound",
		"music": "Music",
		"home": "Home",              # 라벨(설정 행 · 뒤로가기)
		"go_home": "Home",           # 버튼(설정 홈 · 결과 홈)
		"restart_label": "Restart",
		"restart": "Restart",
		# ── 결과 팝업 ──
		"fail_close": "Almost had it!",
		"fail_near": "So close!",
		"fail_far": "Try again?",
		"score_headline": "%s",
		"stage_clear": "Stage Clear!",
		"cause_stuck": "No room left",
		"cause_core": "Core destroyed",
		"depth_cause": "Depth %d · %s",
		"shutout": "Shutout — not one got through",
		"kills_leaks": "Killed %d · Leaked %d",
		"first_record": "🏆 First record!",
		"new_record": "🏆 New best! +%s",
		"best": "Best",
		"result_remaining": "Enemies left",
		"result_killed": "Killed",
		"continue": "Continue",
		"retry": "Retry",
		"next_stage": "Next Stage",
		# 마지막 스테이지 클리어 = 완주 아님, '콘텐츠 따라잡음'(프런티어) → 무한 깔때기. 시점 약속 회피.
		"caught_up": "All caught up!",
		"frontier_sub": "New stages keep coming",
		"play_endless": "Play Endless",
		# ── 메인 메뉴(허브) ──
		"adv_big": "Adventure",
		"adv_sub": "Clear stages, one by one",
		"endless_big": "Endless",
		"endless_sub": "Endless run · High score",
		"menu_hint": "SPACE = Adventure · E = Endless",
		"best_score": "Best %s",     # 메뉴 · HUD 무한 최고점
		# ── 스테이지 선택 ──
		"cleared_count": "Cleared %d / %d",
		"dev_unlock": "DEV: unlock all (0)",
		"unlock_req": "Clear stage %d to unlock",
		"done_badge": "Done",
		"select_hint": "SPACE or tap a button",
		"stage_n": "Stage %d",
		"all_cleared": "All clear! Play again",
		# ── HUD ──
		"combo": "Combo x%d",
		"leaderboard": "Leaderboard",   # 메뉴 우상단 진입 버튼
		"new_best_live": "New best!",
		"score": "Score",
		"depth": "Depth %d",
		"goal": "Goal",
		"hud_enemies": "Enemies",    # 목표 카드 캡션(해골 아이콘 옆, 짧게)
		"advance": "Advance",
		"turns": "turns",
		# ── 거점(보드 하단 방어선) ──
		"core_hp": "Core  %d / %d",
		# ── 게임플레이 콜아웃/tell(원래 영어로 authored — 값 동일, 로케일 확장용으로만 키화) ──
		"ll_double": "DOUBLE!",
		"ll_triple": "TRIPLE!",
		"ll_tetris": "QUAD!",
		"ll_mega": "MEGA!",
		"tut_kill": "Enemy incoming! Clear a line to take it down",
		"combo_flash": "COMBO x%d",
		"tell_block": "BLOCK",
		"callout_fast": "FAST — quick!",
		"callout_tank": "TANK — big combo!",
		"callout_swarm": "SWARM — sweep them!",
		"callout_split": "SPLIT — kill above the line!",
		# ── 입력 토글 + 온보딩 안내(PC 테스트 토글 포함) ──
		"mode_click": "CLICK MODE",
		"mode_drag": "DRAG MODE",
		"mode_switch": "tap to switch",
		"how_click": "Click a piece, then click board to place",
		"how_drag": "Drag a piece onto the board to place",
		"rule_blast": "Fill a full row OR column -> blast!",
		"rule_combo": "Chain clears -> COMBO (wider blast)",
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
		"st5_name": "장갑",
		"st5_tag": "한 방으론 안 뚫린다 — 콤보를 쌓아라",
		"st6_name": "총력전",
		"st6_tag": "전부 온다",
		"st7_name": "분열",
		"st7_tag": "갈라진다 — 높이 있을 때 잡아라",
		"st8_name": "최종 방어선",
		"st8_tag": "전부 온다 — 그리고 갈라진다",
		"settings": "설정",
		"sound": "소리",
		"music": "배경음",
		"home": "홈",
		"go_home": "홈으로",
		"restart_label": "다시하기",
		"restart": "재시작",
		"fail_close": "거의 다 왔어요!",
		"fail_near": "아쉬워요!",
		"fail_far": "다시 해볼까요?",
		"score_headline": "%s점",
		"stage_clear": "스테이지 클리어!",
		"cause_stuck": "놓을 곳이 없다",
		"cause_core": "거점 파괴",
		"depth_cause": "깊이 %d · %s",
		"shutout": "완봉 — 한 마리도 놓치지 않았다",
		"kills_leaks": "처치 %d · 누수 %d",
		"first_record": "🏆 첫 기록!",
		"new_record": "🏆 신기록! +%s",
		"best": "최고",
		"result_remaining": "남은 적",
		"result_killed": "처치",
		"continue": "이어하기",
		"retry": "재도전",
		"next_stage": "다음 스테이지",
		# 마지막 스테이지 클리어 = 완주 아님, '콘텐츠 따라잡음'(프런티어) → 무한 깔때기. 시점 약속 회피.
		"caught_up": "다 따라잡았어요!",
		"frontier_sub": "새 스테이지는 계속 추가돼요",
		"play_endless": "무한 도전",
		"adv_big": "스테이지",
		"adv_sub": "차근차근 깨는 모험",
		"endless_big": "무한",
		"endless_sub": "끝없이 도전 · 최고점",
		"menu_hint": "SPACE = 스테이지 · E = 무한",
		"best_score": "최고 %s",
		"cleared_count": "클리어 %d / %d",
		"dev_unlock": "DEV: 전체 해금 (0)",
		"unlock_req": "%d 스테이지를 클리어하면 열림",
		"done_badge": "클리어",
		"select_hint": "SPACE 또는 버튼 클릭",
		"stage_n": "스테이지 %d",
		"all_cleared": "전부 클리어! 다시 도전",
		"combo": "콤보 x%d",
		"leaderboard": "리더보드",
		"new_best_live": "최고 갱신!",
		"score": "점수",
		"depth": "깊이 %d",
		"goal": "목표",
		"hud_enemies": "남은 적",
		"advance": "적 이동",
		"turns": "턴",
		"core_hp": "거점  %d / %d",
		# ⚠아래 콜아웃/tell·온보딩의 한국어는 초안(원문이 영어라 대응 한글이 없었음). 검수/조정 여지.
		"ll_double": "더블!",
		"ll_triple": "트리플!",
		"ll_tetris": "쿼드!",
		"ll_mega": "메가!",
		"tut_kill": "적이 내려와요! 줄을 채워 잡으세요",
		"combo_flash": "콤보 x%d",
		"tell_block": "버팀",
		"callout_fast": "속공 — 빠르다!",
		"callout_tank": "탱크 — 큰 콤보로!",
		"callout_swarm": "무리 — 쓸어버려!",
		"callout_split": "분열 — 선 위에서 잡아!",
		"mode_click": "클릭 모드",
		"mode_drag": "드래그 모드",
		"mode_switch": "눌러서 전환",
		"how_click": "조각을 고르고 보드를 눌러 놓기",
		"how_drag": "조각을 보드로 끌어 놓기",
		"rule_blast": "가로 또는 세로 한 줄 채우면 -> 폭발!",
		"rule_combo": "연쇄 클리어 -> 콤보 (터지는 범위↑)",
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
