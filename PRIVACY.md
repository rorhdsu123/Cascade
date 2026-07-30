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

**결론: 우리가 서버로 가져가는 데이터는 없다.** 신고 대상은 전부 광고 SDK 몫이다.
Play 기준으로 **기기를 떠나지 않는 데이터는 "수집"이 아니다** — 그래서 게임 진행도·설정·로컬 통계는
데이터 안전성에 신고하지 않는다.

⚠**Firebase를 붙이는 날 이 문서를 반드시 고친다.** 그 순간 §0의 "송신 0건"이 거짓이 되고 데이터 안전성
신고(§2)도 틀린 신고가 된다. `analytics.gd`의 `_platform_log_event`가 no-op을 벗는 시점이 그 트리거다.

---

## 1. 개인정보처리방침 (호스팅용 본문 — 영어)

> 스토어가 영어 우선(`i18n.SUPPORTED=["en"]`, 소프트런치=Tier-1 영어권)이라 본문도 영어다.
> **필요한 것**: 공개 URL 하나(GitHub Pages·Notion 공개 페이지·구글 사이트 전부 가능, 무료).
> **`[  ]` 안은 유저가 채운다.**

---

**Privacy Policy for BlockCastle**

Last updated: [DATE] · Developer: [DEVELOPER NAME AS REGISTERED ON GOOGLE PLAY]

**Summary.** BlockCastle does not require an account, and we do not run any server that stores
your data. Your game progress and settings stay on your device. The only data that leaves your
device is what Google's advertising service needs in order to show ads.

**Information we store on your device.** The game saves your stage progress, high scores, sound
settings, and anonymous gameplay statistics locally on your device. It also generates a random
installation identifier that is used only to distinguish game sessions in those local statistics.
None of this is transmitted to us, and we have no way to access it. Uninstalling the app removes it.

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

**Data retention and deletion.** Because we do not collect or store your data on any server, there
is nothing for us to retain or delete. Data stored locally is removed when you uninstall the app.
For data processed by Google in connection with advertising, please refer to Google's policies above.

**Changes.** If this policy changes, the updated version will be posted at this URL with a new
"Last updated" date.

**Contact.** [CONTACT EMAIL] *(기본값 후보: `zeoksim@gmail.com`. 공개 문서에 개인 주소를 적는 게 걸리면*
*게임 전용 주소를 하나 만들어 쓰는 편이 낫다 — 스토어 등록 정보에도 같은 주소가 공개된다.)*

---

## 2. Play Console — 데이터 안전성(Data safety) 답안

§0 실측에 근거한 답. **"우리는 수집 안 하고, AdMob이 수집한다"**가 전체 구조다.

### 개요 질문

| 질문 | 답 | 근거 |
|---|---|---|
| 앱이 사용자 데이터를 수집·공유하나? | **예** | 우리는 아니지만 **AdMob이 한다.** SDK가 하는 수집도 신고 대상이다 |
| 전송 중 암호화되나? | **예** | GMA SDK는 HTTPS로 통신한다 |
| 사용자가 데이터 삭제를 요청할 수 있나? | **아니요** | 계정·서버 데이터가 없어 삭제할 대상이 없다. 로컬 데이터는 삭제(제거)로 사라진다 |
| 독립적 보안 검토를 받았나? | 아니요 | |
| Play Families 정책 대상인가? | **아니요** | 아동 대상 앱이 아니다(§1 Children) |

### 데이터 유형

| 데이터 유형 | 수집 | 공유 | 목적 | 필수/선택 | 비고 |
|---|---|---|---|---|---|
| **기기 또는 기타 ID** (광고 ID) | 예 | **예**(Google) | 광고 또는 마케팅 · 분석 | 필수 | 매니페스트에 `AD_ID` 권한이 실제로 들어 있다(RELEASE.md §7) |
| **대략적 위치** | 예 | 예(Google) | 광고 또는 마케팅 | 필수 | IP에서 파생. AdMob이 자체적으로 하는 것 |
| 앱 활동(광고 상호작용) | 예 | 예(Google) | 광고 또는 마케팅 · 분석 | 필수 | 광고 노출·클릭 측정 |
| 개인정보(이름·이메일 등) | **아니요** | — | — | — | 계정·로그인 없음 |
| 재무 정보 | **아니요** | — | — | — | IAP 없음(소프트런치 미포함) |
| 정확한 위치 · 연락처 · 사진 · 파일 · 메시지 · 통화 기록 · 건강 | **아니요** | — | — | — | 해당 권한 자체가 없다 |
| 앱 내 검색 기록 · 설치된 앱 목록 | **아니요** | — | — | — | |
| 게임 진행도 · 설정 · 로컬 통계 | **아니요** | — | — | — | **기기를 안 떠난다 = Play 기준 '수집' 아님**(§0) |

⚠**"필수"로 답하는 이유**: 광고를 보여주려면 이 처리가 필요하고, 유저가 앱 안에서 이걸 끄고도 앱을
쓸 수 있게 만들어 두지 않았다(광고 제거 IAP는 소프트런치 미포함). EEA/UK 동의 거부는 *개인화*를 끄는
것이고 광고 자체를 없애는 게 아니다.

⚠**Firebase 연결 시 추가될 항목**: 우리 쪽 수집이 생기므로 "앱 활동"·"기기 ID"에 우리 목적(분석)이
붙고, 삭제 요청 경로도 다시 판단해야 한다.

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
| 데이터 삭제 요청 URL | 해당 없음 — 서버 데이터가 없다 |

---

## 5. 제출 전 체크리스트

- [ ] §1을 공개 URL에 올린다 → Play Console '개인정보처리방침' 칸 + 스토어 등록정보
- [ ] `[DATE]` · `[DEVELOPER NAME]` · `[CONTACT EMAIL]` 채우기
- [ ] 데이터 안전성 양식을 §2대로 입력
- [ ] 콘텐츠 등급 설문을 §3대로 응답
- [ ] 광고 ID 신고 + '광고 포함' 체크(§4)
- [ ] **게임 안 설정 → Ad privacy 행이 EEA 기기에서 실제로 보이는지 1회 확인**(`RELEASE.md` §9의 `--ad-consent-eea`)
