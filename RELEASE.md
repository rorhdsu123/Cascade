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

### 백업·복원 (2026-07-30 검증)

**무결성 지표** — 옮긴 뒤 이 값으로 대조한다. 다르면 전송이 깨진 것이다.

| 항목 | 값 |
|---|---|
| keystore SHA-256 | `ba8177b776b3d5a5cf37153237f720d9ba3589328513ad87968565e388914e9b` |
| 인증서 지문 SHA-256 | `49:D4:94:C2:18:C2:DF:AE:2D:FF:16:96:F9:65:49:05:C3:0B:BE:BE:7B:DD:C1:7F:09:37:28:5C:83:9B:A7:23` |

인증서 지문은 **Play Console의 '업로드 인증서'와 대조하는 값**이다 — 나중에 "이 키가 그 앱의 업로드 키가 맞나"를
확인할 유일한 근거이므로 키 자체와 별개로 여기 남긴다(비밀이 아니라 공개돼도 무해한 값이다).

**보관 원칙: keystore와 비밀번호를 같은 곳에 두지 않는다.** 한쪽만 새도 서로 쓸모가 없게 갈라 둔다 —
keystore는 클라우드/외장, 비밀번호(`*.env` 내용)는 비밀번호 관리자 또는 물리 메모.

**복원 절차**:
```bash
# ① 두 파일을 ~/.android/ 로 되돌리고 권한을 조인다
chmod 600 ~/.android/blockcastle-upload.keystore ~/.android/blockcastle-upload.env
# ② 짝이 맞는지 = .env의 비밀번호로 keystore가 열리는지 확인 (이게 진짜 복원 검증이다)
source ~/.android/blockcastle-upload.env
PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH" LC_ALL=C keytool -list \
  -keystore "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" \
  -storepass "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" -alias blockcastle-upload
# ③ 지문이 위 표와 같은지 대조
```
⚠**파일 복사만으로 "백업했다"고 하지 말 것.** 비밀번호가 다른 짝이면 파일은 멀쩡한데 서명이 안 된다 —
②까지 통과해야 백업이다.

⚠**암호화 컨테이너로 묶으면 암호를 잊는 순간 백업이 곧 소실이다.** macOS 기본 도구로 만들 수 있다
(`hdiutil create -encryption AES-256 -stdinpass -srcfolder ~/.android ...`). 그 암호는 **반드시 비밀번호 관리자에.**

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
# ⚠런처 액티비티는 GodotAppLauncher다. GodotApp을 직접 지정하면 exported가 아니라
#   "Permission Denial"로 조용히 실패한다(구 문서 명령이 그랬다).
$ADB shell am start -n com.yujin.blockcastle/com.godot.game.GodotAppLauncher

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
| 3 | 실 AdMob 유닛 ID | 🔀 **의도적으로 테스트 유닛 유지** — 클로즈드 테스트는 테스트 유닛이 맞다(자기 광고 클릭 = 계정 정지 사유). 전환 스위치·절차는 §9. 계정은 유저 몫 |
| 4 | UMP 동의 흐름 | ✅ 2026-07-30 — 동의-먼저 순서 · 개인정보 옵션 입구 · 타임아웃 · 계측(§9) |
| 5 | 개인정보처리방침 URL | ❌ 유저 몫(호스팅). 답안 초안은 `PRIVACY.md` |
| 6 | 데이터 안전성 · 콘텐츠 등급 | ❌ 답안 초안은 `PRIVACY.md` §3~4 |
| 7 | 스토어 에셋(스크린샷·피처 그래픽) | ✅ 2026-07-30 — `store/` 5장 + 피처 그래픽. 실제 플레이 캡처(`tools/store_shots.gd`) |
| 8 | 업로드 키 백업 | ✅ 2026-07-30 — 암호화 DMG(AES-256) + 암호는 별도 보관. **복원 검증까지 통과**(위 §1 백업·복원) |
| 9 | Play 개발자 계정 $25 | ❌ 유저 몫 — 업로드의 전제 |
| 10 | 테스터 12명 × 14일 | ❌ 유저 몫 — **프로덕션 출시까지의 실제 임계경로** |

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

---

## 9. 광고 R3 — 실 유닛 전환 절차 (AdMob 계정 생긴 뒤)

동의(UMP) 배선은 끝났다(2026-07-30). 남은 건 **계정이 필요한 부분**뿐이다.

1. AdMob 계정 개설 → 앱 등록 → 리워드·인터스티셜 유닛 생성 (무료)
2. `ad_service.gd`의 `LIVE_UNIT_*` 4개 상수를 실 유닛 ID로 채우고 `LIVE_UNITS = true`
   - ⚠상수가 비어 있으면 `LIVE_UNITS`를 켜도 테스트 유닛으로 돈다(`live_units()`가 막는다). 빈 ID를
     넘겨 로드가 조용히 실패하는 사고 = 수익 0인데 원인이 안 보이는 상태를 구조적으로 차단한 것.
3. `project.godot`에 실 **App ID**를 적는다 — 지금은 값이 Godot 기본값(구글 테스트 App ID)과 같아서
   파일에 아예 없다. 플러그인 설정에서 바꾸면 `admob/general/*/app_id` 로 기록된다.
4. 본인 개발기기를 **테스트 기기로 등록**(`RequestConfiguration.test_device_ids`). 안 하면 실 광고가
   자기 기기에 뜨고, 그걸 누르는 게 계정 정지의 대표 사유("무효 트래픽")다.
5. Play Console: 데이터 안전성 + 광고 ID 권한 신고(`PRIVACY.md` §3)

**⚠클로즈드 테스트(테스터 12명)는 2~4를 하지 않는다** — 테스트 유닛으로 낸다. 수익 신호는 12명으로는
안 나오고 W4 유료 UA 코호트에서 재는 값이라, 실 유닛을 켜서 얻을 게 없고 잃을 것(계정 정지)만 있다.

### 동의(UMP) 배선 요약

| 무엇 | 어디 |
|---|---|
| 흐름 | 동의 정보 갱신 → 필요 시 폼 표시 → 상태 확인 → **그 다음** SDK 초기화·광고 요청 |
| 광고 요청 가능 조건 | 상태가 `NOT_REQUIRED`(예: 한국) 또는 `OBTAINED`. `REQUIRED`·`UNKNOWN`에선 요청 안 함 |
| 실패 시 | **게임은 안 막힌다**(불변식 ⑦) — 광고만 포기하고 부활은 공짜 폴백. 다음 실행에서 재시도 |
| 개인정보 옵션 입구 | 설정 모달의 조건부 행. SDK가 "필요하다"고 답한 지역에서만 붙는다 |
| 계측 | `ad_consent_updated`(status·form_shown·privacy_options_required·can_request_ads·unit_mode) |
| 타임아웃 | 60초. 넘기면 광고 포기 + `status="timeout"` 계측(폼이 떠 있는 동안은 시계 정지) |
| EEA 강제 테스트 | `--ad-consent-eea` + `consent_debug_device_id`(해시 ID는 첫 실행 logcat에 찍힌다) |

⚠**데스크톱 목 광고(`--ad-mock`)에선 동의를 건너뛴다.** 실 광고망을 안 타므로 동의 대상이 아니고,
거기서 동의를 요구하면 UMP 싱글턴이 없어 절차가 영영 안 끝나 광고가 통째로 죽는다(실제로 밟았다 —
`ad_mock_probe`가 5건 FAIL로 잡아냈다). 반대로 **실기기에서 UMP 싱글턴이 없으면 광고를 끈다** —
동의 없는 노출은 정책 위반이고, 페이크로 때우면 사고가 안 드러난다(GMA 플러그인 부재와 같은 처방).
