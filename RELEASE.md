# BlockCastle — 릴리스 빌드·제출 파이프라인

> Phase V ⑥ 산출물. **정본 관계**: 출시 전략·일정은 `ROADMAP.md`, 광고 정책은 `AD_PLAN.md`, 계측 스키마는
> `ANALYTICS_TAXONOMY.md`. 이 문서는 **"소스에서 Play에 올릴 파일까지 어떻게 가는가"**만 소유한다.
>
> **이 문서가 존재하는 이유**: 빌드 템플릿(`android/`)이 `.gitignore` 대상이라 **저장소가 빌드 방법을 기억하지 못한다.**
> 이 프로젝트에서 같은 사고가 이미 세 번 났다(ETC2 설정 주석 유실 3회 · compileSdk 패치 · 가로 고정 버그).
> 설정 파일은 값만 갖고, 절차와 근거는 이 문서가 갖는다.

---

## 1. 업로드 키 (서명)

| 항목 | 값 |
|---|---|
| 키스토어 | `~/.android/blockcastle-upload.keystore` (RSA 4096 · SHA384withRSA · 2053-12-15까지) |
| 별칭 | `blockcastle-upload` |
| 비밀번호 | `~/.android/blockcastle-upload.env` (chmod 600) |
| 생성일 | 2026-07-30 |

**⚠저장소에 절대 들어가지 않는다.** Godot 4.6은 릴리스 서명 정보를 환경변수로 받으므로
(`GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}`), `export_presets.cfg`의 `keystore/release*` 3칸은
**빈 채로 커밋한다**. 채우면 비밀번호가 평문으로 저장소에 박힌다.

**⚠백업할 것.** 이 두 파일은 이 맥에만 있다. 잃으면 Play 업로드 키 재설정 절차(구글 지원 요청 + 며칠)를 밟아야 한다.

**Play 앱 서명과의 관계**: 우리가 만든 건 *업로드 키*다. Play에 올리면 구글이 별도의 *앱 서명 키*를 관리하고
기기에 배포되는 APK는 그 키로 다시 서명된다. 그래서 업로드 키 분실은 (앱 서명 키 분실과 달리) 복구 가능한 사고다.

키 확인:
```bash
source ~/.android/blockcastle-upload.env
PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH" LC_ALL=C \
  keytool -list -v -keystore "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" \
          -storepass "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"
```

---

## 2. 두 개의 export preset (왜 둘인가)

| preset | 형식 | 서명 | 쓰임 |
|---|---|---|---|
| `Android` | **APK** (`export_format=0`) | 디버그 키 | 개발 반복 — `adb install`로 기기/에뮬에 바로 꽂는다 |
| `Android Release` | **AAB** (`export_format=1`) | **업로드 키**(환경변수) | Play 업로드. Play는 APK를 안 받는다 |

Godot은 preset 옵션을 CLI로 덮어쓸 수 없어서(형식·서명이 preset에 박혀 있다) 프리셋을 둘로 나눈 것이다.
그 대가는 **드리프트**다:

> ⚠**두 preset은 아래 값이 반드시 같아야 한다** — `version/code` · `version/name` · `package/unique_name` ·
> `exclude_filter` · `architectures/*` · `permissions/*` · `launcher_icons/*`.
> 다른 건 `export_format`과 서명 경로 **둘뿐**이다. 한쪽만 고치면 "디버그에선 되는데 릴리스에선 안 되는" 버그가 난다.
>
> ⚠에디터가 `export_presets.cfg`를 재작성하면 주석이 사라지므로 이 규칙은 여기 산다(`project.godot` ETC2 주석이
> 3번 유실된 것과 같은 함정).

`exclude_filter`에 `tools/*`가 있는 이유: 그게 없으면 **개발 하네스 156개 파일(271KB)이 앱에 실려 나간다**
(회귀·프로브·시드 스윕 스크립트). 런타임이 `res://tools`를 참조하는 곳은 0이라 빼도 안전하다.

**아키텍처는 `arm64-v8a` 단독**이다. 64비트 전용이라 Play 정책은 통과하지만, 32비트 전용 구형 기기에는
설치되지 않는다. 소프트런치 타깃이 Tier-1 영어권이라 감수한 선택 — 도달률을 넓히려면 `armeabi-v7a`를
켜면 되고, 그때 두 preset을 함께 고칠 것.

---

## 3. 선행 조건 — 빌드 템플릿

`android/`는 Godot이 설치하는 ~200MB 빌드 템플릿이고 `.gitignore` 대상이다. **다른 머신·다른 워크트리에는 없다.**

```bash
# ① 템플릿 설치 (에디터: 프로젝트 > 안드로이드 빌드 템플릿 설치, 또는 export에 --install-android-build-template 동반)
# ② compileSdk 패치 — AdMob v5.0.0의 aar이 36을 요구하는데 Godot 4.6.2 템플릿은 35
python3 tools/android_template_patch.py
```
`sdkmanager "platforms;android-36" "build-tools;36.0.0"`가 선행. 근거·함정은 그 스크립트 docstring과 `AD_PLAN.md` §5.

이미 패치된 템플릿이 다른 워크트리에 있으면 복사가 더 빠르다(gradle 출력 캐시는 제외 — 780MB):
```bash
rsync -a --exclude 'build/build/' --exclude '.gradle/' /Users/im-yujin/Desktop/Cascade/android/ ./android/
```

---

## 4. 빌드

```bash
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"

# 개발용 디버그 APK
godot --headless --path . --export-debug "Android" build/android/cascade.apk
ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
$ADB install -r build/android/cascade.apk

# Play 업로드용 서명된 AAB
source ~/.android/blockcastle-upload.env
godot --headless --path . --export-release "Android Release" build/android/blockcastle.aab
```

⚠**export가 실패해도 종료코드가 0이고 오류가 한 줄로만 스쳐 간다.** 산출물 존재만으로 성공을 판정하지 말고
아래 §5 검증을 매번 통과시킬 것. (`No project icon specified`가 이렇게 조용히 지나가서 기본 Godot 아이콘으로
출고될 뻔했다.)

---

## 5. 산출물 검증 (매 릴리스)

```bash
# ① 서명이 '업로드 키'인가 — 디버그 키로 서명된 AAB는 Play가 거부한다
LC_ALL=C jarsigner -verify -verbose:summary -certs build/android/blockcastle.aab | grep -iE "jar verified|CN="
#   기대: "jar verified." + CN=BlockCastle, OU=Games, O=yujin ...
#   "This jar contains entries whose signer certificate is self-signed" 경고는 정상(업로드 키는 자체 서명).

# ② 패키지·버전·권한 — AAB 매니페스트는 protobuf라 strings로 읽는다(aapt2는 AAB를 못 읽음)
unzip -o -q build/android/blockcastle.aab 'base/manifest/*' -d /tmp/aab
strings /tmp/aab/base/manifest/AndroidManifest.xml | grep -iE "com.yujin|0\.9|permission|ca-app-pub"
```

**③ 실기기 1회 실행** — 빌드 성공은 정상 실행을 뜻하지 않는다. `handheld` 전용 설정은 기기에서만 드러난다
(가로 고정 버그가 이렇게 일주일 방치됐다). AAB는 그대로 못 깔므로 같은 커밋의 디버그 APK로 확인한다.

---

## 6. 버전 규칙

| 필드 | 규칙 |
|---|---|
| `version/code` | **업로드마다 +1**. Play는 이미 쓴 code의 재업로드를 거부한다. 두 preset에 같은 값을 쓴다 |
| `version/name` | 사람이 읽는 semver. 클로즈드 테스트 시작 = `0.9.0`, 프로덕션 = `1.0.0` |

---

## 7. 남은 출시 차단 항목

| # | 항목 | 상태 |
|---|---|---|
| 1 | AAB 산출 + 업로드 키 서명 | ✅ 2026-07-30 (33MB, 검증 통과) |
| 2 | 앱 아이콘 | ✅ 2026-07-30 — `icons/` + `config/icon` + 두 preset 배선(§8) |
| 3 | **실 AdMob 유닛 ID** | ❌ 매니페스트가 아직 구글 테스트 App ID(`…~3347511713`). 이대로 출고하면 **수익 0** |
| 4 | UMP 동의 흐름 | ❌ `ad_service.gd`에 consent 코드 0건. EEA/UK 필수 |
| 5 | 개인정보처리방침 URL | ❌ 유저 몫(호스팅). 답안 초안은 `PRIVACY.md` |
| 6 | 데이터 안전성 · 콘텐츠 등급 | ❌ 답안 초안은 `PRIVACY.md` §3~4 |
| 7 | 스토어 에셋(스크린샷·피처 그래픽) | ❌ |
| 8 | Play 개발자 계정 $25 | ❌ 유저 몫 — 업로드의 전제 |
| 9 | 테스터 12명 × 14일 | ❌ 유저 몫 — **프로덕션 출시까지의 실제 임계경로** |

### 광고 SDK가 주입하는 권한 (데이터 안전성 신고 근거)

우리가 preset에서 켠 건 `INTERNET`·`VIBRATE` 둘뿐이고, 나머지는 **GMA SDK가 매니페스트 병합으로 넣는다**:

`AD_ID` · `com.google.android.gms.permission.AD_ID` · `ACCESS_NETWORK_STATE` · `READ_BASIC_PHONE_STATE` ·
`ACCESS_ADSERVICES_TOPICS` · `ACCESS_ADSERVICES_AD_ID` · `ACCESS_ADSERVICES_ATTRIBUTION` · `WAKE_LOCK` ·
`FOREGROUND_SERVICE`

⚠`FOREGROUND_SERVICE`는 Play Console에서 **전경 서비스 사용 신고**를 요구할 수 있다(우리가 쓰는 게 아니라
SDK가 선언한 것이라고 답한다). `AD_ID`는 데이터 안전성에서 **"광고 ID 수집 = 예"**로 이어진다.

---

## 8. 앱 아이콘

디자이너 산출물이 아직 없어 **게임 자체의 form으로 코드 렌더**했다 — `tools/icon_gen.gd`(창 모드 필수).
나중에 아트 트랙 산출물로 교체하면 되고, 그때도 이 파일 5개만 갈아끼우면 배선은 그대로다.

```bash
godot --path . --script tools/icon_gen.gd              # 후보 비교 시트(48px 확대 포함)
godot --path . --script tools/icon_gen.gd -- --emit=E  # 확정안으로 에셋 산출
godot --headless --import                              # 새 PNG를 Godot에 import(.import 생성)
```

| 파일 | 쓰임 |
|---|---|
| `icons/icon_512.png` | Play 스토어 등록 아이콘 + `project.godot` `config/icon` |
| `icons/icon_192.png` | 레거시 런처 아이콘 |
| `icons/adaptive_fg_432.png` | 적응형 전경 |
| `icons/adaptive_bg_432.png` | 적응형 배경 |
| `icons/adaptive_mono_432.png` | Android 13+ 테마 아이콘 |

**form 근거**: 블록은 `Main._draw_piece_cells`의 실제 문법(pad 8% + 흰 내부선 + 드롭섀도), 해골은
`Main._draw_enemy_icon`의 '타입 중립 처치 대상' 기호를 그대로 쓴다. **성 실루엣·브릭 스터드는 기각된
시각 언어라 안 쓴다.** 블록이 해골 턱을 가려 두 요소가 한 덩이 마크로 붙는다(후보 A·B·D·F는 두 요소가
분리돼 48px에서 흩어졌다).

**밟은 함정 2개** — 둘 다 렌더를 실제로 깎아보고서야 드러났다:
1. **원형 마스크 클리핑** — 사각 안전영역(66%)만 맞추면 부족하다. Pixel 런처는 **원형**으로 깎아서 마크
   밑변의 좌우 블록 모서리가 잘렸다. 전경 스케일을 0.72까지 조여 해결(`check_masked_432.png`가 잘리는
   영역을 마젠타로 칠해 보여준다).
2. **모노 레이어가 둥근 덩어리** — 눈·코·이빨을 안 뚫으면 흰 실루엣이 형태 없는 blob이 된다. 2D 캔버스엔
   지우기가 없어 body/features를 따로 렌더한 뒤 Image에서 알파를 뺀다(`_mono_compose`).

⚠**아이콘이 없어도 export는 성공한다.** `No project icon specified`를 한 줄 흘리고 기본 Godot 아이콘으로
출고된다 — 종료코드는 0이다. §5 검증을 건너뛰면 못 잡는 사고.
