# BlockCastle — 외부 에셋·오픈소스 출처

> 이 게임에 들어간 **우리가 만들지 않은 것 전부**의 목록이다. 대회 제출물 ④ AI 활용 기술 문서의
> "외부 에셋 / 오픈소스 출처" 항목에 그대로 옮겨 쓸 수 있게 정리했다.
>
> 각 항목의 **가공 이력과 선정 근거**는 `sfx/CREDITS.txt`·`fonts/CREDITS.txt`가 갖는다. 이 문서는
> 무엇을 어디서 가져왔고 어떤 라이선스인지만 갖는다.
>
> 작성 2026-08-03 · 개정 2026-08-10(§5 아트 AI 사용 **단계** 정정 · §6 반입 소재 "없음" 확정)
> · **미결 0건.**

## 1. 엔진·플러그인

| 항목 | 라이선스 | 출처 | 비고 |
|---|---|---|---|
| Godot Engine 4.6 | MIT | [godotengine.org](https://godotengine.org/) | 게임 엔진. 저장소에 포함되지 않음(빌드 도구). 엔진이 함께 싣는 서드파티 목록은 Godot 배포본의 `COPYRIGHT.txt` |
| Godot AdMob Plugin (`addons/admob/`) | MIT · Poing Studios | 저장소에 `addons/admob/LICENSE` 동봉 | 광고 배관. **Google Mobile Ads SDK를 함께 내려받으며 그건 구글 약관이 따로 적용된다** |

## 2. 폰트

둘 다 **SIL Open Font License 1.1**. 전문은 `fonts/OFL.txt`, 저작권 표기는 `fonts/CREDITS.txt`.

| 파일 | 저작권 | 출처 |
|---|---|---|
| `fonts/NotoSans-Regular.ttf` | Copyright 2022 The Noto Project Authors | [notofonts/latin-greek-cyrillic](https://github.com/notofonts/latin-greek-cyrillic) |
| `fonts/Baloo2.ttf` | Copyright 2019 The Baloo 2 Project Authors | [EkType/Baloo2](https://github.com/EkType/Baloo2) |

## 3. 효과음 — 전부 CC0 1.0 (퍼블릭 도메인)

**출처 표기 의무가 없는 라이선스지만 전수 기록했다.** 나중에 "이 소리 어디서 났지"를 못 찾으면
교체·재라이선스 판단이 불가능해지기 때문이다.

| 파일 | 원본 | 출처 |
|---|---|---|
| `pop_low` · `pop_high` | OpenGameArt "Pop sounds" (pop9 · pop3) | [opengameart.org](https://opengameart.org/content/pop-sounds-0) |
| `chip_low` · `chip_high` | Kenney "Casino Audio" (chip-lay-3 · chips-collide-1) | [kenney.nl](https://kenney.nl/assets/casino-audio) |
| `clear_hit` · `clear_note` | Kenney "Impact Sounds" (impactMetal_medium_004 · impactGlass_light_002) | [kenney.nl](https://kenney.nl/assets/impact-sounds) |
| `rocket` | Kenney "Digital Audio" (phaserUp7) | [kenney.nl](https://kenney.nl/assets/digital-audio) |
| `fw_burst` · `logo_hit` · `fw_launch` | OpenGameArt "25 CC0 bang / firework SFX" (fw_03 · cannon_04 · shot_02, rubberduck) | [opengameart.org](https://opengameart.org/content/25-cc0-bang-firework-sfx) |
| `melody` | VCSL (Versilian Community Sample Library) — 글로켄슈필 C5 | [github.com/sgossner/VCSL](https://github.com/sgossner/VCSL) |

**병합 완료(8/3) — 이 표가 곧 `sfx/` 폴더의 전부다.** 후보 폴더(`sfx/pick/`·`sfx/inst/`)는
채택본만 남기고 지웠으므로 빌드에 안 들어간다.

원본 그대로 쓴 파일은 하나도 없다 — 전부 `tools/sfx_prep.py`로 선행 무음 절단 · 크레스트 압축 ·
피크 정규화를 거쳤다. **가공은 CC0가 허용하는 범위이고**, 무엇을 왜 손봤는지는 `sfx/CREDITS.txt`에 있다.

## 3-B. 제출 영상(제출물 ②) 배경음악 — CC0 1.0

**게임 빌드에는 안 들어간다.** 제출용 60초 영상에만 얹은 트랙이다.

| 항목 | 내용 |
|---|---|
| 작품 | OpenGameArt **"Banana Track"** (`banana_track.ogg`) |
| 작곡 | skrjablin |
| 라이선스 | **CC0 1.0** |
| 출처 | [opengameart.org/content/banana-track](https://opengameart.org/content/banana-track) |
| 가공 | 원곡 123.8초 중 **83.0~123.6초 구간**만 사용 · **−17dB 감쇠** · 앞 0.9초 페이드인 · 뒤 1.5초 페이드아웃 · 게임 효과음을 키로 한 **사이드체인 덕킹**(문턱 0.015 · 비율 8:1 · 어택 12ms · 릴리스 260ms) |

구간을 이렇게 고른 이유는 **곡의 굴곡과 영상의 굴곡을 포개기 위해서**다 — 곡이 100~112초에서
한 번 가라앉는데 그 자리가 영상의 조용한 대목(보석·비행기)이고, 곡의 정점(114~118초)이 클리어
연출 위에, 곡의 마무리가 로고 정지컷 위에 떨어진다.

후보 7곡을 CC0로 추려 같은 음량으로 발췌 비교한 뒤 고른 것이다. 1차로 붙였던
"Free Music Pack"의 `Warped`(Alexander Ehlers, CC0)는 **판타지·록 색이 강해 기각**했다.

## 4. 우리가 만든 것 — 외부 에셋이 아님

혼동을 막기 위해 같이 적는다. 아래는 전부 이 프로젝트에서 생성했다.

| 항목 | 어떻게 만들었나 |
|---|---|
| 게임 코드 전량 | 직접 작성 (AI 페어와의 협업 — 상세는 제출물 ④) |
| `icons/` (앱 아이콘 5종) | `tools/icon_gen.gd` — 게임 자체의 form(블록 문법 + 해골 기호)을 **코드로 렌더** |
| `store/` (스토어 스크린샷·피처 그래픽) | `tools/store_shots.gd` — 목업이 아니라 **실제 게임을 봇으로 굴려 캡처**(고정 시드로 재현 가능) |
| `art/cell.png` (빈 셀 판) | `tools/make_cell_plate.py` — 레퍼런스의 빈 칸엔 그릴 것이 없어(색 편차 ±2) **코드 생성으로 확정**했다 |
| `art/studio.png` (스튜디오 마크) | `tools/studio_shot.gd` — 에그타르트 마크를 코드로 렌더 |
| 그 외 `art/` 그림 전량 | 팀의 **아트 담당**이 **Adobe Photoshop 22.5.1에서 직접 제작**. 이미지 생성 AI는 **참고 시안 단계에만** 썼다 — 상세는 아래 §5 |

## 5. AI로 만든 것 — 무엇을 어디까지

**게임 코드·문서** — Claude Code(Opus 4.8 → Opus 5)를 페어로 썼다. 전량이 이 경로다.
상세는 제출물 ④ AI 활용 기술 문서가 갖는다.

**UI 아트** — 아트 담당이 **ChatGPT의 이미지 생성 기능**으로 **참고 시안(컨셉 시트)** 을 만들고,
납품 리소스는 **Adobe Photoshop 22.5.1 한국어판**에서 다시 그렸다. 사용 단계는 **전 파일이
① 아이디어·러프까지**다 — 생성 이미지를 불러와 그 위에 리터치하거나(②) 생성 결과를 거의 그대로
쓴(③) 파일은 없다. Photoshop의 **생성형 채우기도 쓰지 않았고**, 형태는 펜 도구·도형 레이어·
그라디언트·레이어 스타일로 그렸다.

AI 시안을 **파일 단위로 참고한 범위는 7종**: 블록 · 빈 셀 · 패널 · 강조바 · 큰 버튼 · 적-basic ·
종이비행기. 적 `swarm`·`fast`와 스테이지 타일 · 튜토리얼 말풍선은 **별도의 AI 이미지 생성 없이**
앞선 시안의 방향만 이어받아 직접 제작했다. (빈 셀은 납품본을 받았지만 **출고본은 코드 생성판**
`art/cell.png`이다 — §4.)

대표 프롬프트 원문 5건(한국어 2 · 영문 3)은 제출물 ④ 6장에 실었다. **오간 전부가 아니라
대표 예시다** — 규정이 요구하는 것이 "대표적인 것 2~3개"라 그렇게 요청해 받았고, 단계마다
한 건씩(1차 시안 요청 · 작업 방법 질의 · 방향 수정 3건) 고른 것이다.

**이미지 생성을 쓰지 **않은** 자리** — 앱 아이콘(`tools/icon_gen.gd`)과 스토어 스크린샷
(`tools/store_shots.gd`)은 생성이 아니라 **게임 엔진으로 렌더**한 것이고, 빈 셀 판과
스튜디오 마크도 코드로 그렸다(§4).

## 6. 미결 — **전부 해소(2026-08-10)**

1. ~~아트 작업에 반입된 외부 소재~~ — **해소(8/10).** 아트 담당 회신: **외부 브러시·외부 텍스처·
   스톡 이미지·외부 아이콘 세트·별도 다운로드 폰트 모두 사용 기록 없음** → 아트 쪽에 **별도 라이선스
   표기 대상이 없다.** 레퍼런스로 본 **Block Blast**와 인게임 캡처는 스타일·크기감·배치 방향 파악용
   **시각적 참고**로만 썼고, 해당 게임의 이미지를 추출하거나 최종 리소스에 삽입한 기록은 없다.
2. ~~UI 아트의 AI 사용 내역~~ — **해소(8/9, 8/10 파일별 단계까지 확정).** §5로 옮겼다.
3. ~~`track/audio` 미병합분~~ — **완료(8/3 병합, §3 표 확정).**
4. ~~영상 음악 라이선스~~ — **8/9에 "음악 없음"으로 닫았다가 8/10에 다시 열고 재해소.** 편집본이
   심심하다는 판단으로 배경음악을 얹기로 뒤집었고, CC0 트랙을 골라 **§3-B에 기재**했다. 게임 빌드에는
   안 들어가므로 §3(효과음) 표는 그대로다.

