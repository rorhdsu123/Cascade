# BlockCastle — 외부 에셋·오픈소스 출처

> 이 게임에 들어간 **우리가 만들지 않은 것 전부**의 목록이다. 대회 제출물 ④ AI 활용 기술 문서의
> "외부 에셋 / 오픈소스 출처" 항목에 그대로 옮겨 쓸 수 있게 정리했다.
>
> 각 항목의 **가공 이력과 선정 근거**는 `sfx/CREDITS.txt`·`fonts/CREDITS.txt`가 갖는다. 이 문서는
> 무엇을 어디서 가져왔고 어떤 라이선스인지만 갖는다.
>
> 작성 2026-08-03 · **⚠미결 3건은 맨 아래에 있다.**

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
| `fw_burst` · `logo_hit` ⚠ | OpenGameArt "25 CC0 bang / firework SFX" (rubberduck) | [opengameart.org](https://opengameart.org/content/25-cc0-bang-firework-sfx) |
| `sfx/inst/*.wav` ⚠ | VCSL (Versilian Community Sample Library) — 실악기 6종 | CC0 |

⚠ 표시 둘은 **`track/audio`에 있고 아직 트렁크에 병합되지 않았다**(8/7 예정). 병합 후 이 표를 확정할 것.

원본 그대로 쓴 파일은 하나도 없다 — 전부 `tools/sfx_prep.py`로 선행 무음 절단 · 크레스트 압축 ·
피크 정규화를 거쳤다. **가공은 CC0가 허용하는 범위이고**, 무엇을 왜 손봤는지는 `sfx/CREDITS.txt`에 있다.

## 4. 우리가 만든 것 — 외부 에셋이 아님

혼동을 막기 위해 같이 적는다. 아래는 전부 이 프로젝트에서 생성했다.

| 항목 | 어떻게 만들었나 |
|---|---|
| 게임 코드 전량 | 직접 작성 (AI 페어와의 협업 — 상세는 제출물 ④) |
| `icons/` (앱 아이콘 5종) | `tools/icon_gen.gd` — 게임 자체의 form(블록 문법 + 해골 기호)을 **코드로 렌더** |
| `store/` (스토어 스크린샷·피처 그래픽) | `tools/store_shots.gd` — 목업이 아니라 **실제 게임을 봇으로 굴려 캡처**(고정 시드로 재현 가능) |
| `art/block.png` · `art/cell.png` | `tools/make_block_placeholder.py`로 생성한 **임시 아트**. 디자이너 납품분으로 교체 예정 |

## 5. ⚠미결 3건

1. **디자이너 UI 아트의 AI 사용 내역** — 외주 디자이너 회신 대기(8/6). 이미지 생성 AI를 썼다면
   어떤 도구로 어디까지, 안 썼으면 안 썼다고 받아야 한다. **규정상 누락이 안 되는 항목이다.**
2. **`track/audio` 미병합분** — §3의 ⚠두 줄. 8/7 병합 직후 이 표를 확정한다.
3. **영상에 음악을 얹으면 그 라이선스도 여기 적어야 한다** — 게임에는 BGM을 넣지 않기로 확정했지만,
   트레일러 편집에서 음악을 깔면 제출물 ④에 출처·라이선스 기재가 필요하다.

정리 항목(라이선스와 무관): `sfx/pick/`·`sfx/inst/`는 후보 폴더라 최종 빌드 전에 채택본만
`sfx/`로 남기고 지운다.
