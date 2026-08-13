# BlockCastle — 개인정보처리방침 + Play 제출 답안

> 출시 제출물 초안. **정본 관계**: 빌드·서명은 `RELEASE.md`, 광고 정책은 `AD_PLAN.md`, 계측 스키마는
> `ANALYTICS_TAXONOMY.md`. 이 문서는 **"Play에 무엇을 신고하고 유저에게 무엇을 공지하는가"**만 소유한다.
>
> ⚠**법률 자문이 아니다.** 아래는 코드를 실제로 훑어 확인한 사실(§0)에 근거한 초안이고, 제출 전 유저가
> 읽고 판단할 것. 특히 §1은 **호스팅해서 URL이 생겨야** Play가 받아준다(코드 밖 = 유저 몫).

---

## 0. 사실 확인 — 이 앱이 실제로 무엇을 수집하나 (2026-07-30 코드 실측)

신고서를 쓰기 전에 코드를 훑어 확인한 것. **추정이 아니라 실측**이다.

| 확인 항목 | 결과 |
|---|---|
| 우리 코드의 네트워크 송신 | **0건** — `HTTPRequest`·`HTTPClient`·소켓 사용 없음(grep 확인) |
| 애널리틱스 백엔드 | **로컬 파일뿐** (`user://analytics.jsonl`). `_platform_log_event`는 no-op = Firebase **미연결** |
| 리더보드 백엔드 | **로컬뿐**. `_platform_*` 전부 no-op. 화면 자체도 `LEADERBOARD_ENABLED=false`로 비활성 |
| 기기 식별자 | `install_id` = 앱이 자체 생성한 난수. **기기 밖으로 안 나간다**(로컬 파일에만) |
| 계정·로그인 | 없음 |
| 저장 파일 | `campaign.save` · `endless.save` · `endless_clean.save` · `settings.save` · `analytics.jsonl` · `analytics.meta` — 전부 기기 내부 |
| **기기를 나가는 유일한 데이터** | **Google Mobile Ads(AdMob) SDK**가 광고를 가져오며 수집하는 것 |

~~**결론: 우리가 서버로 가져가는 데이터는 없다.**~~

### 🔴 위 표는 2026-08-12부로 낡았다 — 재실측 (2026-08-13)

**우리도 이제 수집한다.** C178에서 원격 싱크를 붙이고 C185에서 주소를 채웠다. 위 문단이 걸어둔
경보("Firebase를 붙이는 날 이 문서를 반드시 고친다")가 **이미 울렸는데 아무도 안 들었다** —
트리거를 Firebase로만 적어둔 탓이다. 실제로 온 건 우리 엔드포인트였고, `_platform_log_event`는
지금도 no-op이다. **경보는 '어떤 SDK를 붙였나'가 아니라 '기기 밖으로 뭐가 나가나'에 걸었어야 했다.**

| 확인 항목 | 재실측 결과 |
|---|---|
| 우리 코드의 네트워크 송신 | **있다** — `analytics.gd _remote_flush()`. 웹은 `sendBeacon`, 그 외는 `HTTPRequest` |
| 받는 곳 | **우리 소유** 구글 앱스 스크립트 웹 앱 → 구글 스프레드시트. 주소는 저장소 밖(`analytics_endpoint.txt`) |
| 나가는 값 | `install_id` · `session_id` · `run_id` · 이벤트 이름 · `t_ms`/`duration_ms` · `runs_played` · `stage_id` · `cause` · `beat` · `max_combo` · `build_version` · `platform` · `mode` · `seed` · `is_first_session` |
| 안 나가는 값 | 이름·이메일·계정·연락처·정확한 위치·기기 광고 ID. **우리가 IP를 기록하지 않는다**(수집기가 안 적는다) — 다만 구글 인프라가 요청을 받는 이상 전송 계층엔 남는다 |
| 언제 나가나 | 4건이 모이거나 `session_ended`·`run_failed`·`stage_cleared`·`endless_run_ended`에서 |
| 유저가 끌 수 있나 | **아니요** — 게임 안에 계측 옵트아웃 토글이 없다 |
| 하네스는? | 안 나간다. `--script`로 뜬 프로세스는 `_remote_on=false`(프로브 포함) |

`install_id`는 앱이 만든 난수이고 사람과 이어붙일 값이 아무것도 없다 = **가명 데이터**다.
그래도 **Play 기준으로는 "기기 또는 기타 ID" 수집이 맞다** — 기기 밖으로 나갔기 때문이다.
게임 진행도·설정 파일은 여전히 기기에만 있어 신고 대상이 아니다.

⚠**지금 이 순간 고지 없이 수집하고 있다.** 플레이테스트 웹 빌드(8/12 배포)가 낯선 사람의
플레이를 우리 시트로 보내는데 방침이 어디에도 게시돼 있지 않다. **8/23 모집 전에 itch 페이지
설명에 한 줄을 넣을 것** — 아래 §1-B가 그 문구다.

⚠**다음 경보는 '기기 밖으로 나가는 값이 바뀌는 날'에 울린다.** Firebase든 우리 엔드포인트든
필드를 하나 더 얹는 순간 위 표와 §1·§2가 같이 낡는다.

---

## 1. 개인정보처리방침 (호스팅용 본문 — 영어)

> 스토어가 영어 우선(`i18n.SUPPORTED=["en"]`, 소프트런치=Tier-1 영어권)이라 본문도 영어다.
> **필요한 것**: 공개 URL 하나(GitHub Pages·Notion 공개 페이지·구글 사이트 전부 가능, 무료).
> **`[  ]` 안은 유저가 채운다.**

---

**Privacy Policy for BlockCastle**

Last updated: [DATE] · Developer: [DEVELOPER NAME AS REGISTERED ON GOOGLE PLAY]

**Summary.** BlockCastle does not require an account and never asks for your name, email address,
or any other information that identifies you. Your game progress and settings stay on your device.
Two kinds of data do leave your device: anonymous gameplay statistics that we use to improve the
game, and whatever Google's advertising service needs in order to show ads.

**Information we store on your device.** The game saves your stage progress, high scores, and sound
settings locally on your device. Uninstalling the app (or clearing your browser's site data, if you
are playing in a browser) removes all of it.

**Gameplay statistics we collect.** The game generates a random installation identifier — a string
of digits with no connection to you, your device, or any account — and sends it along with anonymous
gameplay events: when a session starts and ends, how long it lasted, which stage was played, whether
it was cleared or lost and why, tutorial progress, and score-related numbers such as the highest
combo reached. We use this to answer questions like "where do players stop playing?" so we can fix
those places. It is stored in a private spreadsheet that only we can read.

We do **not** collect your name, email address, contacts, photos, files, precise location, or the
advertising identifier of your device, and we do not record your IP address. Because the records
carry only a random identifier, we cannot tell who you are or connect your play to any other service.

**Information collected by advertising.** BlockCastle shows rewarded video ads (which you choose to
watch in exchange for continuing a run) and may show interstitial ads. These are delivered by
**Google AdMob**. To provide and measure ads, Google may collect and process information such as
your device's advertising identifier, device and app information, IP address (from which an
approximate location may be derived), and ad interaction data. This processing is carried out by
Google, not by us. See Google's Privacy Policy at https://policies.google.com/privacy and
"How Google uses information from sites or apps that use our services" at
https://policies.google.com/technologies/partner-sites

**Your choices.** If you are in the European Economic Area, the United Kingdom, or Switzerland, the
app asks for your consent before personalized ads are used, and you can change your choice at any
time from **Settings → Ad privacy** inside the game. On Android you can also reset or delete your
advertising ID at any time in your device settings (Settings → Privacy → Ads), which limits ad
personalization system-wide.

**Children.** BlockCastle is not directed to children, and we do not knowingly collect personal
information from children. The app is not enrolled in Google Play's Designed for Families program.

**Data retention and deletion.** We keep the gameplay statistics described above for as long as they
are useful for improving the game. They contain nothing that identifies you, so we cannot look up
"your" records on request — the link between you and the random installation identifier exists only
on your own device. Removing the app (or clearing your browser's site data) deletes that identifier,
after which nothing we hold can be connected to you, and the game starts fresh as a new installation.
If you want records removed and can tell us the installation identifier, write to the address below
and we will delete them. For data processed by Google in connection with advertising, please refer
to Google's policies above.

**Changes.** If this policy changes, the updated version will be posted at this URL with a new
"Last updated" date.

**Contact.** [CONTACT EMAIL] *(기본값 후보: `zeoksim@gmail.com`. 공개 문서에 개인 주소를 적는 게 걸리면*
*게임 전용 주소를 하나 만들어 쓰는 편이 낫다 — 스토어 등록 정보에도 같은 주소가 공개된다.)*

---

## 1-B. 웹 플레이테스트 고지 (8/23 모집 전에 필요)

Play 앱이 아니라 itch 웹 빌드라 위 방침을 붙일 자리가 없다. 그런데 **낯선 사람의 플레이가
우리 시트로 오고 있다.** 페이지 설명(`RELEASE.md` §10 플레이테스트 페이지 설정)과 모집 글
양쪽에 아래 한 문단을 넣는다. 짧아야 읽힌다 — 방침 전문은 링크로 충분하다.

> **What this playtest records.** This build sends anonymous gameplay statistics so I can see where
> people get stuck: a random installation id, when a session starts and ends, how long you played,
> which stage you were on, and whether you cleared or lost it. No name, no email, no account, no
> location, no IP address — nothing that identifies you. Clearing your browser's site data for this
> page erases the id. Questions: [CONTACT EMAIL]

⚠**웹 빌드에는 광고가 없다**(AdMob은 네이티브) — 그래서 이 문구에 광고 얘기를 넣지 않는다.
넣으면 있지도 않은 것을 고지하는 셈이고, 참가자에게 괜한 경계를 만든다.

---

## 2. Play Console — 데이터 안전성(Data safety) 답안

⚠**2026-08-13 개정.** 옛 답은 "우리는 수집 안 하고, AdMob이 수집한다"였다. C185 이후로
**우리도 수집한다** — 그대로 제출하면 허위 신고가 된다(§0 재실측).

### 개요 질문

| 질문 | 답 | 근거 |
|---|---|---|
| 앱이 사용자 데이터를 수집·공유하나? | **예** | **우리(게임플레이 통계)와 AdMob 둘 다** |
| 전송 중 암호화되나? | **예** | 우리 엔드포인트는 HTTPS(`script.google.com`), GMA SDK도 HTTPS |
| 사용자가 데이터 삭제를 요청할 수 있나? | **예** | 방침 §1에 연락처와 절차를 뒀다. ⚠기록이 난수 id뿐이라 **본인 확인이 구조적으로 불가능**하다 — 유저가 id를 알려주면 지운다고 적었다. 이 답을 '아니요'로 하면 삭제 경로가 아예 없다고 신고하는 셈이라 '예'가 정직하다 |
| 독립적 보안 검토를 받았나? | 아니요 | |
| Play Families 정책 대상인가? | **아니요** | 아동 대상 앱이 아니다(§1 Children) |

### 데이터 유형

| 데이터 유형 | 수집 | 공유 | 목적 | 필수/선택 | 비고 |
|---|---|---|---|---|---|
| **기기 또는 기타 ID** (광고 ID) | 예 | **예**(Google) | 광고 또는 마케팅 · 분석 | 필수 | 매니페스트에 `AD_ID` 권한이 실제로 들어 있다(RELEASE.md §7) |
| **기기 또는 기타 ID** (`install_id`) | **예** | **아니요** | 분석 · 앱 기능 | 필수 | 🆕앱이 만든 난수. 우리 시트로 나간다. 앱스 스크립트·스프레드시트는 **우리를 대신해 처리하는 서비스 제공자**라 Play 기준 '공유' 아님 |
| **앱 활동**(게임플레이 이벤트) | **예** | **아니요** | 분석 | 필수 | 🆕판 시작·종료·클리어/실패와 사유·튜토리얼 박자·체류 시간·최고 콤보 |
| **대략적 위치** | 예 | 예(Google) | 광고 또는 마케팅 | 필수 | IP에서 파생. AdMob이 자체적으로 하는 것. **우리는 IP를 안 적는다** |
| 앱 활동(광고 상호작용) | 예 | 예(Google) | 광고 또는 마케팅 · 분석 | 필수 | 광고 노출·클릭 측정 |
| 개인정보(이름·이메일 등) | **아니요** | — | — | — | 계정·로그인 없음 |
| 재무 정보 | **아니요** | — | — | — | IAP 없음(소프트런치 미포함) |
| 정확한 위치 · 연락처 · 사진 · 파일 · 메시지 · 통화 기록 · 건강 | **아니요** | — | — | — | 해당 권한 자체가 없다 |
| 앱 내 검색 기록 · 설치된 앱 목록 | **아니요** | — | — | — | |
| 게임 진행도 · 설정 (세이브 파일) | **아니요** | — | — | — | **기기를 안 떠난다 = Play 기준 '수집' 아님** |

⚠**"필수"로 답하는 이유**: 광고 쪽은 광고를 보여주려면 필요한 처리이고, 유저가 앱 안에서 끄고도 앱을
쓸 수 있게 만들어 두지 않았다(광고 제거 IAP는 소프트런치 미포함). EEA/UK 동의 거부는 *개인화*를 끄는
것이고 광고 자체를 없애는 게 아니다. **계측 쪽도 '필수'다 — 옵트아웃 토글이 없기 때문이다.**

⚠**옵트아웃을 만들면 이 답이 '선택'으로 바뀐다.** 지금 안 만드는 건 판단이지 누락이 아니다:
설정에 스위치를 하나 더 얹으면 소프트런치 표본이 그만큼 깎이고, 수집하는 게 가명 플레이 기록뿐이라
비용 대비 이득이 낮다고 봤다. **다만 EEA에 열 때 다시 볼 것** — 거기선 계산이 달라질 수 있다.

⚠**Firebase를 붙이면**: 목적지가 하나 더 늘 뿐 위 답의 구조는 같다. 대신 구글이 **서비스 제공자가
아니라 별도 관제자**로 처리하는 부분이 생기면 '공유'가 예로 바뀔 수 있다 — 붙이는 날 다시 판단.

---

## 3. Play Console — 콘텐츠 등급(IARC) 설문 답안

카테고리: **게임**. 예상 결과 = 전체 이용가(ESRB Everyone / PEGI 3 / GRAC 전체이용가) + "광고 포함".

| 질문 영역 | 답 | 근거 |
|---|---|---|
| 폭력 — 사실적/피 표현 | **없음** | 적은 추상 도형이고 처치는 색 조각이 사라지는 연출뿐. 피·부상 묘사 0 |
| 폭력 — 인간·인간형 캐릭터 대상 | **없음** | 인간 캐릭터가 없다. UI의 해골 기호는 '처치 대상' 아이콘일 뿐 |
| 만화적/판타지 폭력 | **최소** | 굳이 답해야 하면 '만화적' 쪽. 무기·타격 애니메이션 없음 |
| 성적 내용 · 노출 | 없음 | |
| 욕설 · 비속어 | 없음 | 화면 문구는 게임 용어뿐 |
| 약물 · 알코올 · 담배 | 없음 | |
| 도박(실제/시뮬레이션) | **없음** | 확률 요소·룰렛·전리품 상자 없음. IAP 없음 |
| 공포 · 무서운 내용 | 없음 | |
| 사용자 간 상호작용 · 채팅 | **없음** | 멀티플레이·채팅·UGC 없음 |
| 위치 공유 | 없음 | |
| 개인정보 공유 | 없음 | |
| 디지털 구매 | **없음** | IAP 미포함 |
| **광고 포함** | **예** | 리워드 + (배관만 깔린) 인터스티셜 |

⚠**"광고 포함"을 반드시 예로 답한다.** 스토어 등록정보의 '광고 포함' 라벨과 한 쌍이고, 누락은 정책 위반이다.
⚠리더보드 화면이 지금 비활성(`LEADERBOARD_ENABLED=false`)이라 **'사용자 간 상호작용' 없음**이 맞다.
켜는 날(실 리더보드 배선) 이 답을 다시 봐야 한다 — 다른 사람의 이름이 보이면 답이 바뀔 수 있다.

---

## 4. 그 밖의 Play Console 신고

| 항목 | 답 |
|---|---|
| **광고 ID 권한** | 앱이 `AD_ID`를 선언한다고 신고. 용도 = 광고. 매니페스트 실측치는 `RELEASE.md` §7 |
| **전경 서비스** | 우리는 전경 서비스를 쓰지 않는다. 매니페스트의 `FOREGROUND_SERVICE`는 **GMA SDK가 병합해 넣은 것** — 콘솔이 신고를 요구하면 그렇게 답한다 |
| 앱 카테고리 | 게임 → 퍼즐 |
| 광고 포함 | 예 |
| 앱 내 구매 | 아니요 |
| 타깃 연령 | 13세 이상(아동 대상 아님) |
| 데이터 삭제 요청 URL | URL은 없다. 방침 §1의 **연락처 이메일**로 답한다 — Play는 URL 대신 이메일을 허용한다. ⚠옛 답('해당 없음')은 서버 데이터가 없던 시절 것이다 |

---

## 5. 제출 전 체크리스트

- [ ] **§0 재실측 표가 아직 맞는지 확인** — 기기 밖으로 나가는 값이 하나라도 바뀌었으면 §1·§2가 같이 낡는다
- [ ] §1을 공개 URL에 올린다 → Play Console '개인정보처리방침' 칸 + 스토어 등록정보
- [ ] `[DATE]` · `[DEVELOPER NAME]` · `[CONTACT EMAIL]` 채우기 — **유저 몫**(실명·주소는 대신 못 정한다)
- [ ] 데이터 안전성 양식을 §2대로 입력 — ⚠광고 항목만 넣고 **우리 계측 두 줄을 빠뜨리지 말 것**
- [ ] 콘텐츠 등급 설문을 §3대로 응답
- [ ] 광고 ID 신고 + '광고 포함' 체크(§4)
- [ ] **게임 안 설정 → Ad privacy 행이 EEA 기기에서 실제로 보이는지 1회 확인**(`RELEASE.md` §9의 `--ad-consent-eea`)

**웹 플레이테스트(11월 이전)에는 위 체크리스트가 아니라 §1-B 한 문단만 필요하다.** 8/23 모집 전에
itch 페이지 설명과 모집 글에 넣는다.
