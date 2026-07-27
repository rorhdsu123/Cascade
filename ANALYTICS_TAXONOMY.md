# Cascade — 애널리틱스 이벤트 택소노미 (v1)

> Phase V W1 산출물. **코드 0의 설계 문서** — "이 코어가 사람을 붙잡느냐"를 숫자로 물을 질문지.
> 정본 결정은 확정 후 SPEC/결정로그에 승격. 작성 2026-07-24. 4개 확정(§8) 반영.

## 확정 결정 (2026-07-24)
1. **고빈도 이벤트 = 집계형.** `piece_placed`·`combo_triggered`는 매 발화 대신 판당 요약으로 `run_ended`에 접는다(무료 티어 볼륨·500 이벤트 상한).
2. **도구 = Firebase Analytics.** 안드로이드 먼저 → Firebase SDK가 자연스러움. (백엔드는 GA4와 동일.)
3. **think-aloud/관찰은 이 스키마 밖.** 사람 눈 몫은 ②번 플테 관찰 프로토콜로 분리.
4. **featured 이벤트 = 정의만·미배선.** 재개(C60 안전망-on) 전까지 스키마만 유지, 값 배선 안 함.

---

## 0. 원칙

1. **미검증 가정을 겨눈다.** 감사가 지목한 "가장 안 밝혀진 가정 = 이 코어 루프가 사람을 붙잡느냐". 이벤트는 예쁜 대시보드가 아니라 *이 질문에 답하도록* 설계.
2. **빌드 전에 심는다.** 지표는 소급 불가 — 첫 사람 플테 빌드에 P0 이벤트가 들어가 있어야 한다.
3. **무료 티어 안에서.** GA4/Firebase 무료. 이벤트/파라미터 상한(§6)을 처음부터 존중해 나중에 갈아엎지 않는다.
4. **질문 → 지표 → 이벤트 순서.** 이벤트를 먼저 나열하지 말 것. 각 이벤트는 §5의 파생지표 중 하나 이상을 떠받쳐야 존재 이유가 있다.

---

## 1. 명명 규약

- 이벤트/파라미터: `snake_case`. 이벤트는 `명사_동사`(과거형) — `stage_cleared`, `piece_placed`.
- 부울은 `is_`/`did_` 접두. 카운트는 `_count`, 지속은 `_ms`, 깊이/레벨은 `_depth`/`_level`.
- **예약어 회피**(GA4): `session_start`, `first_open`, `screen_view`, `ad_` 접두 일부는 GA 자동수집과 충돌 소지 → 커스텀은 `cc_` 없이도 이름을 구별되게(예: 광고는 아래 커스텀 스키마 사용, 자동수집과 병행).

---

## 2. 공통 파라미터 (모든 이벤트에 자동 첨부)

| 파라미터 | 예 | 왜 |
|---|---|---|
| `build_version` | `"0.9.3"` | 코호트 분리 |
| `platform` | `android` / `ios` / `web` | 배관 검증(웹 프리뷰 포함) |
| `mode` | `campaign` / `endless` / `featured` | 듀얼코어 어느 기둥인지 — **가장 중요한 축** |
| `session_id` | uuid | 세션 내 퍼널 연결 |
| `run_id` | uuid | 한 판(스테이지 1회/무한 1런) 단위 연결 |
| `seed` | int | featured/결정성 판 재현·버그 리포트 |
| `is_first_session` | bool | D0 이탈 분석 |

> `mode`와 `run_id`는 사실상 모든 코어 이벤트의 기본 좌표. 빠지면 퍼널이 안 이어진다.

---

## 3. 이벤트 카탈로그 (퍼널 순)

### 3-1. 세션 / 수명주기
| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `app_opened` | `is_first_session`, `cold_start` | D1/D7, 세션 빈도 |
| `session_ended` | `duration_ms`, `runs_played`, `screens_seen[]` | 세션 길이·판당 이탈 |
| `screen_viewed` | `screen`(home/select/hub/leaderboard/settings/game/result) | 셸 내비 이탈 지점 |

### 3-2. 온보딩 / FTUE  ⚠ D0 이탈 최대 리스크 구간
> 튜토리얼은 이미 main 병합(3박자, fc0bfca). **완주 퍼널만 계측하면 됨.**

| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `tutorial_beat_started` | `beat`(1/2/3) | 박자별 진입 |
| `tutorial_beat_completed` | `beat`, `time_to_complete_ms`, `retries` | **박자별 이탈률**(어느 개념에서 튕기나) |
| `tutorial_skipped` | `at_beat` | 스킵 압력 |
| `first_piece_placed` | `time_since_open_ms` | "손이 언제 움직이나"(TTFA) |
| `first_line_cleared` | `time_since_open_ms` | 첫 도파민까지 시간 |

### 3-3. 코어 루프 (판 진행)
| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `run_started` | `mode`, `stage_id`?, `goal_type`(kill/collect), `core_hp_max` | 판 시작·표본 |
| `piece_placed` | `piece_type`, `board_fill_pct`, `was_dda_assisted`(캠페인만) | 패킹 숙련·보드 압박 곡선 |
| `piece_stuck_warning` | `board_fill_pct` | **막힘 임박**(위협 인지 순간) |
| `combo_triggered` | `combo_len`, `band`(칭찬 등급), `is_full_board`(전멸), `lines_cleared` | 콤보 빈도·스펙터클 도달(밴드 분포) |
| `combo_peak` | `max_combo` (판 종료 시 1회) | 최대 콤보 분포(봇 ~7 대비 사람은?) |

> `combo_triggered`는 고빈도 이벤트 — **집계형 확정**(§8-1): 매 발화 대신 판당 밴드별 카운트를 `run_ended`에 접어넣는다. `piece_placed`도 동일.

### 3-4. 죽음 & 부활  ⚠ 로드맵이 지목한 진짜 리스크: "죽음의 질 + 부활 전환율"
| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `run_failed` | `cause`(**core_death**/**stuck**), `depth`or`stage_id`, `duration_ms`, `enemies_leaked`, `board_fill_pct` | **죽음의 질** — 거점사(숙련 실패)냐 막힘(패킹 실패)이냐 비율 |
| `revive_offered` | `cause`, `is_ad_ready` | 부활 기회 노출 |
| `revive_taken` | `cause`, `method`(ad_reward) | **부활 전환율**(핵심 수익 신호) |
| `revive_declined` | `cause`, `dismiss_type`(button/timeout/back) | *억울한 죽음* 신호 — 거절+즉시이탈이면 C60 재현 |
| `run_abandoned` | `where`, `duration_ms` | 중도 포기(≠죽음) — 지루함/좌절 구분 |

> **핵심 교차분석**: `run_failed.cause` × `revive_taken` × 직후 `run_abandoned`.
> 거절 후 세션 종료가 몰리는 cause가 있으면 그게 "억울한 죽음". 부활 아니라 이탈을 부른다.

### 3-5. 캠페인 진행 (StageMode)
| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `stage_selected` | `stage_id`, `is_locked_preview` | 선택화면 행동 |
| `stage_cleared` | `stage_id`, `goal_type`, `duration_ms`, `max_combo`, `dda_assist_count` | 스테이지별 클리어율·구제(DDA) 의존도 |
| `stage_failed` | `stage_id`, `cause`, `attempt_n` | **스테이지별 벽**(어디서 이탈·재도전 몇 번) |
| `frontier_reached` | `last_stage_id` | 마지막 스테이지→무한 깔때기 전환율 |
| `gem_collected` | `stage_id`, `gem_color`, `progress`(현/quota) | 수집형 목표 페이싱(줍기 난이도) |

### 3-6. 무한 (EndlessMode)
| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `endless_run_ended` | `score`, `max_depth`, `kills`, `max_combo`, `cause`, `beat_pb`(bool), `nightsky_zone`(도달 존) | 무한 표현·경쟁 코어 성과 |
| `pb_broken` | `old_pb`, `new_pb` | 개인기록 갱신 빈도(재도전 훅) |
| `leaderboard_viewed` | `scope`(local/friends/global) | 경쟁 셸 관심(현재 친구/퍼센타일 목업) |
| `score_submitted` | `score`, `is_stub` | 제출 배관(현재 로컬 stub→W3 실배선) |

### 3-7. 광고 (W2 배선 전 — 스키마 자리만 예약)
> 부활은 이미 리워드 광고 형태(스텁). **W1엔 스키마만 확정**, 값 배선은 W2.

| 이벤트 | 파라미터 | 목적 지표 |
|---|---|---|
| `ad_requested` | `format`(rewarded/interstitial), `placement`(revive/stage_transition), `mediation` | fill 요청 |
| `ad_filled` / `ad_no_fill` | `format`, `placement`, `latency_ms` | **no-fill율**(폴백 정책 검증) |
| `ad_shown` | `format`, `placement` | 노출 |
| `ad_rewarded` | `placement`, `reward_granted` | 리워드 완료→부활 성사 |
| `ad_closed` | `format`, `watched_pct` | 스킵/중단 |

### 3-8. 설정 / 메타 (얇게)
| 이벤트 | 파라미터 |
|---|---|
| `setting_changed` | `key`, `value` (음소거·언어 등) |
| `language_detected` | `locale`, `used_fallback`(en) |

---

## 4. featured / 오늘의 판
현재 플레이어 진입 제거(C60 보류). **엔진은 살아있음** → 이벤트 스키마는 무한과 공유(`mode:featured`, `seed` 필수). 재개 시 배선만.

---

## 5. 핵심 파생지표 (이벤트가 떠받쳐야 할 것)

| 지표 | 조립 |
|---|---|
| **D1 / D7 리텐션** | `app_opened.is_first_session` + 재방문 세션 |
| **튜토리얼 완주율** | `tutorial_beat_completed(3)` / `tutorial_beat_started(1)` — 박자별 드롭 |
| **첫 도파민까지 시간** | `first_line_cleared.time_since_open_ms` 분포 |
| **죽음의 질 믹스** | `run_failed.cause` 비율(core_death:stuck) × 모드 × 스테이지 |
| **부활 전환율** | `revive_taken` / `revive_offered`, cause별 |
| **억울한 죽음 신호** | `revive_declined` → 30초 내 `session_ended` 비율, cause별 |
| **콤보 빈도/스펙터클 도달** | `combo_triggered` 밴드 분포, `is_full_board`율 |
| **스테이지 벽** | `stage_failed` 재도전수 × stage_id — 이탈 절벽 |
| **깔때기 전환** | `frontier_reached` → 첫 `endless_run_ended` |
| **PB 재도전 훅** | `pb_broken` 후 즉시 재시작율 |
| **어느 기둥을 사랑하나** | 모드별 세션수·체류·리텐션 기여(듀얼코어 핵심 판정) |

---

## 6. GA4 / Firebase 제약 메모

- 이벤트당 **파라미터 최대 25개**, 이벤트 이름 40자·파라미터값 100자.
- 프로젝트당 커스텀 이벤트 **500종** 상한 → 고빈도(`piece_placed`,`combo_triggered`)는 **집계형 축소** 검토.
- 등록 필요: 커스텀 파라미터를 **custom dimension/metric**으로 등록해야 탐색에 뜸(자동 아님) → `mode`,`cause`,`stage_id`,`band`는 반드시 등록.
- `user_property`로 둘 것: `highest_stage`, `endless_pb`, `total_revives`(코호트 세분).
- 실시간 디버그: `DebugView`로 첫 배선 검증.

---

## 7. 우선순위 (첫 플테 빌드 = P0만)

**P0 — 첫 사람 플테 빌드에 반드시:**
`app_opened`, `session_ended`, `run_started`, `run_failed`(cause 필수), `revive_offered/taken/declined`, `stage_cleared/failed`, `tutorial_beat_completed`, `first_line_cleared`, `endless_run_ended`, `combo_peak`.
→ 이 10여 개로 §5의 리스크 지표 대부분이 조립됨.

**P1 — 실배선 여유 시:**
`piece_placed`(집계형), `combo_triggered`(집계형), `gem_collected`, `frontier_reached`, `pb_broken`, `leaderboard_viewed`, `screen_viewed`.

**P2 — W2 광고 붙일 때:**
§3-7 광고 전부, `score_submitted` 실값.

---

## 8. 확정 결정 상세 (2026-07-24)
1. **고빈도 이벤트 = 집계형** — `piece_placed`/`combo_triggered`는 개별 발화 안 함. 판당 `run_ended`에 밴드별·타입별 카운트로 접는다. (근거: 500 이벤트 상한·무료 티어 볼륨)
2. **도구 = Firebase Analytics** — 안드로이드 우선 → Firebase SDK. GA4와 백엔드 동일하니 대시보드는 그대로 사용.
3. **think-aloud는 분리** — 사람 눈으로 잡는 표정·주저·소리내어생각은 이 스키마 밖, ②번 플테 관찰 프로토콜 소관.
4. **featured 미배선** — `mode:featured` 이벤트는 스키마만 정의. C60 안전망-on 재설계로 플레이어 진입 재개할 때 값 배선.

## 9. 배선 상태 (2026-07-27) — **P0 전량 실배선 완료**

`analytics.gd`(이음새) + `Main.gd` 판 경계 호출 + 로컬 JSONL 싱크. leaderboard.gd와 같은 발상 —
게임 코드는 SDK·파일을 직접 안 만지고, Firebase는 `_platform_log_event` stub에 꽂기만 하면 된다(W2).

| 이벤트 | 배선 자리 |
|---|---|
| `app_opened` / `session_ended` | `_ready` / `_notification`(CLOSE·PAUSED·RESUMED — 모바일은 백그라운드 전환이 실제 세션 끝) |
| `run_started` | `_init_game`(시작-적 배치 전 — '시작하자마자 막힘'도 판에 묶이게) |
| `run_failed` (+`stage_failed` / `endless_run_ended`) | `_end_turn` 3분기 = `core_death` · `vault_lost` · `stuck` (+`stuck_at_start`) |
| `stage_cleared` | `_check_win` |
| `revive_offered` / `taken` / `declined` | 실패 판정 시 / `_revive()` / 팝업 이탈(retry·home·back) |
| `tutorial_beat_completed` | 박자1·2 전이(`_end_turn`) · 박자3 = 첫 누수 캡션 |
| `first_line_cleared` · `combo_peak` | 줄 완성 시(세션 1회 게이트) · 판 종료 |

- **수집 = `user://analytics.jsonl`**(1줄 1이벤트). 안드로이드는 `adb pull`로 뽑는다(경로는 리포트 도구 주석).
- **판독 = `tools/analytics_report.gd`** — §5 파생지표로 접는다(죽음의 질·부활 전환율·억울한 죽음 신호·기둥별 체류·스테이지 벽·콤보 분포).
- **검증 = `tools/analytics_probe.gd`**(창 모드) — 봇이 캠페인·무한을 실제로 굴려 P0 이벤트·공통 좌표·택소노미 밖 이름을 확인. 회귀 골든 byte-identical(계측은 게임 RNG를 안 쓰고 헤드리스에선 자동 off).
- **배선 중 프로브가 잡은 결함 1건**: 실패 시점에 판 좌표(`run_id`)를 닫으면 **광고 부활 뒤 이벤트가 판에서 떨어져 나가** 부활 퍼널이 끊긴다 → 좌표는 다음 판 시작 때만 교체하도록 수정.

## 다음 단계
- ~~②번 플테 관찰 프로토콜 설계~~ → 완료(`PLAYTEST_PROTOCOL.md`).
- ~~P0 실배선~~ → 완료(§9).
- **남은 것 = 계정·빌드(코드 밖)**: ① Firebase 프로젝트 개설 + custom dimension 등록(`mode`·`cause`·`stage_id`·`band`) ② 실기기(안드로이드) 플테 빌드 — JDK·Android SDK 설치가 선행 ③ W2에서 `_platform_log_event`에 Firebase SDK 연결.
