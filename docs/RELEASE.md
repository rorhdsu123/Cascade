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

## 2. 안드로이드 preset이 셋인 이유

| preset | 형식 | 서명 | 쓰임 |
|---|---|---|---|
| `Android` | **APK** (`export_format=0`) | 디버그 키 | 개발 반복 — `adb install`로 기기/에뮬에 바로 꽂는다 |
| `Android Release` | **AAB** (`export_format=1`) | **업로드 키**(환경변수) | Play 업로드. Play는 APK를 안 받는다 |
| `Android Submission` | **APK** (`export_format=0`) | **업로드 키**(환경변수) | 사이드로드 배포(GitHub 릴리스·심사자). AAB는 그대로 못 깐다 |

(네 번째 `Web` preset은 안드로이드와 공유하는 값이 `exclude_filter`뿐이라 이 표 밖에 있다.)

Godot은 preset 옵션을 CLI로 덮어쓸 수 없어서(형식·서명이 preset에 박혀 있다) 프리셋을 쪼갠 것이다.
그 대가는 **드리프트**다:

> ⚠**세 preset은 아래 값이 반드시 같아야 한다** — `version/code` · `version/name` · `package/unique_name` ·
> `exclude_filter` · `architectures/*` · `permissions/*` · `launcher_icons/*`.
> 다른 건 `export_format`과 서명 경로 **둘뿐**이다. 한쪽만 고치면 "디버그에선 되는데 릴리스에선 안 되는" 버그가 난다.
> (`exclude_filter`는 `Web`까지 **넷 전부** 같아야 한다 — C174에서 `build/*`를 넷에 함께 넣었다.)
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

# 사이드로드용 서명된 APK (심사자·체험용 배포 — Play는 이걸 안 받는다)
godot --headless --path . --export-release "Android Submission" build/android/blockcastle.apk

# 웹(itch.io) — 업로드는 build/web/ 통째로 zip
# ⚠굽기 전에 project.godot의 application/config/version 끝자리를 올릴 것(바로 아래 ⚠)
godot --headless --path . --export-release "Web" build/web/index.html
(cd build/web && zip -q -r -X ../blockcastle-web.zip .)

# 🔴올리기 직전에 반드시 — 산출물이 지금 소스로 구워진 것인지 확인한다
python3 tools/check_build_fresh.py build/web/index.pck
```

🔴**"라이브 == 로컬"을 대조해도 낡은 빌드는 못 잡는다.** 2026-08-14에 실제로 밟았다:
13:37에 구운 zip을 올리고, 14:00에 계측 두 칸을 더 넣고 다시 굽지 않았는데, 라이브 pck와
로컬 pck를 바이트로 대조해 **통과 판정을 냈다**. 낡은 로컬 산출물과 비교하면 언제나 통과한다.
게다가 버전을 안 올려서 **내용이 다른 두 빌드가 똑같이 `0.9.0-L1.3`을 달았다.**
그 뒤 실기기 검사에서 새 필드 두 개가 안 나와서야 드러났다. 비교 대상은 로컬 산출물이 아니라
**소스**여야 한다 — `check_build_fresh.py`가 그걸 본다.

⚠**웹을 다시 굽기 전에 `application/config/version`을 올린다.** 이 값이 계측의 `build_version`으로
그대로 나가고(`analytics.gd:273`), **비어 있으면 `0.0.0-dev`로 나간다** — 2026-08-12까지 실제로 그랬다.
형식은 `0.9.0-L<루프>.<그 루프의 몇 번째 배포>`(예: `0.9.0-L1.1`). 안 올리고 재배포하면 처방 전후가
한 덩어리로 섞여 **"고친 게 먹었나"를 못 읽는다** — 그게 루프 2·3의 유일한 질문이다.
⚠**이미 쌓인 데이터는 나중에 못 고친다.** 굽기 전에 올리는 것 말고 만회할 방법이 없다.
정본은 `ANALYTICS_TAXONOMY.md` §2.

⚠**계측을 켜서 내보내려면 `analytics_endpoint.txt`가 프로젝트 폴더에 있어야 한다.** git에 없으므로
새로 클론한 곳에서는 파일이 없고, 그러면 **원격이 조용히 꺼진 판**이 나간다(에러는 안 난다).
없으면 만들어 넣을 것 — 주소는 `rorhdsu123` 계정 앱스 스크립트 배포 화면에서 다시 볼 수 있다.

⚠**export가 실패해도 종료코드가 0이고 오류가 한 줄로만 스쳐 간다.** 산출물 존재만으로 성공을 판정하지 말고
아래 §5 검증을 매번 통과시킬 것. (`No project icon specified`가 이렇게 조용히 지나가서 기본 Godot 아이콘으로
출고될 뻔했다.)

⚠**아트를 바꿨으면 `godot --headless --import`를 먼저 1회 돌린다.** export는 `.godot/imported/`의 캐시를
그대로 담기 때문에, 다른 워크트리에서 갈아 끼운 그림은 트렁크 캐시가 낡은 채로 조용히 옛 판이 출고된다
(2026-08-10에 basic 스프라이트가 이 경로로 하마터면 나갈 뻔했다). 확인은 §5 ④.

---

## 5. 산출물 검증 (매 릴리스)

```bash
# ① 서명이 '업로드 키'인가 — 디버그 키로 서명된 AAB는 Play가 거부한다
LC_ALL=C jarsigner -verify -verbose:summary -certs build/android/blockcastle.aab | grep -iE "jar verified|CN="
#   기대: "jar verified." + CN=BlockCastle, OU=Games, O=yujin ...
#   "This jar contains entries whose signer certificate is self-signed" 경고는 정상(업로드 키는 자체 서명).

# ①-b ⚠APK는 이 명령으로 판정하면 안 된다 — Godot은 APK를 v2 스킴으로만 서명하는데
#   jarsigner는 v1(JAR 서명)만 본다. 멀쩡한 릴리스가 "jar is unsigned."로 나온다.
APKSIGNER=/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/apksigner
$APKSIGNER verify --print-certs build/android/blockcastle.apk | grep -iE "certificate DN|SHA-256 digest"
#   기대: DN=CN=BlockCastle,... + SHA-256이 키스토어 지문과 일치
keytool -list -v -keystore "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" \
  -storepass "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" | grep "SHA256:"

# ② 패키지·버전·권한 — AAB 매니페스트는 protobuf라 strings로 읽는다(aapt2는 AAB를 못 읽음)
unzip -o -q build/android/blockcastle.aab 'base/manifest/*' -d /tmp/aab
strings /tmp/aab/base/manifest/AndroidManifest.xml | grep -iE "com.yujin|0\.9|permission|ca-app-pub"
#   APK는 aapt2가 읽는다: aapt2 dump badging build/android/blockcastle.apk | grep -E "^package|native-code"
```

**③ 실기기 1회 실행** — 빌드 성공은 정상 실행을 뜻하지 않는다. `handheld` 전용 설정은 기기에서만 드러난다
(가로 고정 버그가 이렇게 일주일 방치됐다). AAB는 그대로 못 깔므로 같은 커밋의 디버그 APK로 확인한다.

**④ 바꾼 에셋이 실제로 들어갔나 — 눈이 아니라 바이트로.** 산출물 안의 임포트 결과물이 디스크의 것과
같은지 본다. 스프라이트를 갈아도 파일명·치수가 같으면 화면만 봐선 옛 판과 구별이 안 된다.

```python
# 웹: build/web/index.pck 안에 그대로 들어 있다 / APK·AAB: assets/ 밑에 낱개로 들어 있다
import zipfile, glob
ctex = glob.glob('.godot/imported/basic.png-*.ctex')[0]
z = zipfile.ZipFile('build/android/blockcastle.aab')
assert z.read('assetPackInstallTime/assets/' + ctex) == open(ctex, 'rb').read()
```

⚠**`build/`는 프로젝트 리소스가 아니다.** 네 preset의 `exclude_filter`에 `build/*`가 들어 있다 —
빠뜨리면 지난 빌드 산출물과 오디오 A/B 비교용 wav가 다음 빌드에 통째로 실린다(웹 pck 기준 586KB,
2026-08-10에 실측·제거).

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
| 1 | AAB 산출 + 업로드 키 서명 | ✅ 2026-07-30 (33MB, 검증 통과) · 2026-08-10 재산출 33.8MB(새 적 스프라이트 반영, §5 ①②④ 통과) |
| 2 | 앱 아이콘 | ✅ 2026-07-30 — `icons/` + `config/icon` + 두 preset 배선(§8) |
| 3 | 실 AdMob 유닛 ID | 🔀 **의도적으로 테스트 유닛 유지** — 클로즈드 테스트는 테스트 유닛이 맞다(자기 광고 클릭 = 계정 정지 사유). 전환 스위치·절차는 §9. 계정은 유저 몫 |
| 4 | UMP 동의 흐름 | ✅ 2026-07-30 — 동의-먼저 순서 · 개인정보 옵션 입구 · 타임아웃 · 계측(§9) |
| 5 | 개인정보처리방침 URL | ❌ 유저 몫(호스팅). 답안 초안은 `PRIVACY.md` |
| 6 | 데이터 안전성 · 콘텐츠 등급 | ❌ 답안은 `PRIVACY.md` **§2(데이터 안전성)·§3(등급)·§4(그 밖)** — 옛 표기 '§3~4'는 한 칸 밀려 있었다. ⚠§2는 2026-08-13에 우리 계측 반영해 개정됨 |
| 7 | 스토어 에셋(스크린샷·피처 그래픽) | ✅ 2026-07-30 — `store/` 5장 + 피처 그래픽. 실제 플레이 캡처(`tools/store_shots.gd`) |
| 8 | 업로드 키 백업 | ✅ 2026-07-30 — 암호화 DMG(AES-256) + 암호는 별도 보관. **복원 검증까지 통과**(위 §1 백업·복원) |
| 9 | Play 개발자 계정 $25 | ❌ 유저 몫 — 업로드의 전제 |
| 10 | 테스터 12명 × 14일 | ❌ 유저 몫 — **프로덕션 출시까지의 실제 임계경로** |
| 11 | DEV 치트 차단 | ✅ 2026-07-31 — 치트 3종 전부 `OS.is_debug_build()` 게이트(아래) |

### DEV 치트 (릴리스 빌드에서 죽는다)

플테용 단축키는 **삭제하지 않고 디버그 빌드 한정으로** 남긴다 — 지우면 다음 폴리싱에서 다시 만들게 된다.

| 키 | 화면 | 하는 일 | 왜 릴리스에서 막아야 하나 |
|---|---|---|---|
| `0` | 스테이지 선택 | 전 스테이지 해금 토글 | 선형 잠금(온보딩 순서)을 우회 |
| `8` | 플레이 | 콤보5 전멸 시퀀스 강제 | 보드를 조작 = 진행도·기록 위조 가능 |
| `9` | 무한 | 점수 +10,000 | **리더보드를 통째로 오염** |
| `DEV WIPE` 버튼 | 스테이지 선택 | 진행도 초기화 | (원래부터 게이트돼 있었음) |

⚠물리 키보드가 없는 폰에선 누를 수 없지만, 블루투스 키보드·데스크톱 빌드에선 눌린다. **실 리더보드가 붙는 순간
`9`키는 데이터 신뢰도를 통째로 깎는 종류의 구멍**이라 계정·호스팅과 무관하게 지금 막아 둔다.

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

---

## 10. 배포 현황 — 지금 사람들이 실제로 받는 것

**로컬에서 다시 뽑아도 배포된 물건은 안 바뀐다.** `build/` 안의 산출물과 itch·GitHub에 올라간 물건은
별개다. 아트나 밸런스를 고쳤으면 **다시 올려야** 플레이어에게 닿는다 — 여기가 그걸 놓치기 가장 쉬운 곳이다.

| 채널 | 무엇 | 올린 물건 | 갱신 방법 |
|---|---|---|---|
| itch.io — **제출용** | 웹 플레이 (`eggtart-studio.itch.io/blockcastle`) | `build/blockcastle-web.zip` (8/9판) | 🔒**심사 종료까지 갱신 금지** — 아래 참조 |
| itch.io — **플레이테스트용** | 웹 플레이 (`eggtart-studio.itch.io/blockcastle-playtest`) | `build/blockcastle-web.zip` (계측 포함) | 대시보드 → Edit game → Uploads에서 **기존 zip 교체** |
| GitHub 릴리스 | 사이드로드 APK (`releases/latest`) | `build/android/blockcastle.apk` | `gh release upload v0.9.0 build/android/blockcastle.apk --clobber` |
| Play Console | (미개설) | `build/android/blockcastle.aab` | §7 ⑨ 개발자 계정이 선행 |

🔒**제출용 페이지는 심사가 끝날 때까지 동결이다(2026-08-12 결정).** 대회 제출물의 웹 플레이 링크가
바로 이 주소고, 접수 마감 후에는 제출 내용을 바꿀 수 없으며 링크는 심사 종료까지 살아 있어야 한다.
zip을 갈면 URL은 그대로여도 **심사자가 보는 게임이 바뀐다** — 규정상 안 되고, 교체 중 임베드가 깨지면
제출물 하나가 통째로 죽는다. 동결 해제는 본행사 종료 이후(9/7~)다.

**그래서 계측 판은 itch 프로젝트를 따로 판다.** 같은 계정에 프로젝트를 여러 개 둘 수 있으므로
제출용을 건드리지 않고 플레이테스트를 돌릴 수 있다. 모집 링크는 어차피 따로 뿌리므로 손해가 없다.
⚠**GitHub Pages·Cloudflare 계열은 여전히 못 쓴다** — 파일당 25MiB 상한에 wasm 하나(37.7MB)가 걸린다.
총량이 아니라 파일당 한도가 문제라 쪼개서 우회할 수 없다.

⚠**itch 웹은 zip을 통째로 바꾸는 것 말고 부분 갱신이 없다.** 교체 시 기존 항목의 *Replace*를 쓸 것 —
새 항목으로 추가하면 임베드가 옛 zip을 계속 가리킨다. 임베드 설정(**전체화면 실행** · 치수 비우지 말 것)은
파일을 갈아도 유지되지만, 새 항목으로 올리면 다시 잡아야 한다.
⚠**새로 파는 플레이테스트 프로젝트는 임베드 설정을 처음부터 다시 잡아야 한다** — 전체화면 실행으로 두고
치수를 비우지 말 것(원본 800×1280을 페이지에 그대로 끼우면 노트북 화면에 안 들어가고, 치수가 비면
렌더 자체가 안 뜬다). 제출용에서 한 번 밟은 자리다.

⚠**GitHub는 같은 이름의 에셋을 자동으로 안 덮는다.** `--clobber` 없이 올리면 실패하거나 이름이 바뀐다.

### 마지막 대조 (2026-08-12)

| | 로컬 빌드 | 배포된 것 |
|---|---|---|
| APK | 80,872,559 B (8/12) | **80,872,559 B (8/12 업로드) — 일치** ✅ |
| 웹 (제출용) | `blockcastle-web.zip` 13.98 MB (8/10) | itch 8/9 업로드 — **어긋나 있고, 그대로 둔다** 🔒 |
| 웹 (플테용) | `blockcastle-web.zip` 13.33 MB (8/12) | **8/12 업로드 — 일치** ✅ `0.9.0-L1.1` |

**APK는 8/12에 맞췄다.** 8/8 배포본(81,337,048 B)이 옛 적 스프라이트였다. 검증은 §5 ①②④ 통과
(서명 지문이 키스토어와 일치 · `com.yujin.blockcastle` 0.9.0 arm64 · `basic.png` ctex 바이트 일치).
⚠**§5 ③(실기기 1회 실행)은 못 했다** — 기기 미연결. 직전 검증본 대비 실제 동작 차이는 C178의
원격 계측뿐이고 `REMOTE_URL`이 비어 있어 그 경로는 통째로 죽어 있다.

**제출용 웹은 8/9판이고, 앞으로도 8/9판이다.** 심사자는 옛 적 스프라이트를 본다 — 이건 이제
고칠 항목이 아니라 감수한 비용이다. 제출은 이미 끝났고, 바꾸는 쪽이 규정 위반이자 링크를 깰 위험이다.
이 줄이 ❌로 남아 있으면 다음에 여는 사람이 "밀린 일"로 읽고 올려버린다. 그래서 🔒로 바꿨다.

**웹 계측 사슬은 2026-08-12에 실측으로 검증됐다(C182).** ①비콘 발신 ②탭 닫을 때 `session_ended`
도착 ③`install_id`가 새로고침·즉시닫기 양쪽에서 유지 — 셋 다 통과. 검증 중에 **결함 하나를 잡아 고쳤다**:
웹에는 `NOTIFICATION_WM_CLOSE_REQUEST`가 오지 않아 `session_ended`가 아예 발화하지 않았고,
웹 배치가 4라(`REMOTE_BATCH_WEB`) 짧게 놀다 나간 사람은 버퍼째 사라지고 있었다. 지금은
`analytics.gd`가 `visibilitychange`·`pagehide`를 직접 건다.

⚠**웹에선 비콘이 로컬 JSONL보다 믿을 만하다 — 데스크톱 가정의 정반대다.** `user://`가 IndexedDB라
마지막 쓰기가 확정되기 전에 탭이 죽는다(재검증에서 `session_ended`가 비콘엔 있고 JSONL엔 없었다).
**"JSONL에 없다"만으로 미발화를 단정하면 안 된다** — 판정은 수신기 쪽을 기준선으로 삼고,
둘이 **같이** 비었을 때만 발화 자체가 없었다고 읽는다.

**차단 항목은 2026-08-12에 전부 닫혔다.** 수집기는 앱스 스크립트 웹 앱(구글 시트)이고, 주소는
`analytics_endpoint.txt`(gitignore·export 포함), 수집기 코드 사본은 `tools/analytics_sheet.gs`다.
**끝에서 끝까지 실측했다** — itch 페이지 → `Run game` → 게임 구동 → 탭 닫기 → 시트에 줄 도착
(`platform=web` · `build_version=0.9.0-L1.1`). 로컬 수신기가 아니라 실제 배포본 기준이다.

⚠**엔드포인트 요구사항**: POST를 받을 것. 웹은 `sendBeacon`을 `text/plain`으로 보내 단순 요청이
되므로 preflight(OPTIONS)가 안 붙고, 응답을 안 읽으니 CORS 응답 헤더는 사실상 필요 없다.
⚠**itch 내부 프레임 안의 전송은 브라우저 개발자도구로 안 잡힌다**(게임이 다른 출처에서 돈다).
**판정은 시트로 한다** — 안 보인다고 안 나간 게 아니다.

### 플레이테스트 itch 페이지 설정 (2026-08-12 개설)

| 항목 | 값 | 왜 |
|---|---|---|
| Kind of project | HTML | 이게 아니면 "브라우저에서 실행" 체크박스가 안 나타난다 |
| 업로드 파일 | `blockcastle-web.zip` + **"played in the browser" 체크** | 안 켜면 `No file provided to embed`로 페이지가 죽는다(실제로 밟았다) |
| Embed | **Click to launch in fullscreen** | 원본 800×1280이라 페이지에 끼우면 노트북 화면에 안 들어간다. 이 모드에선 치수 입력칸이 아예 안 나온다 |
| Frame options | `SharedArrayBuffer` 끔 · **`Mobile friendly` 켬**(2026-08-14~) | ⚠`SharedArrayBuffer`는 nothreads 빌드에 불필요하고 켜면 헤더가 붙어 깨진다. `Mobile friendly`는 웹 터치가 미검증이라 꺼뒀는데 **8/14 아이폰 실측으로 열었다** — 다만 그 실측이 C196 결함을 먼저 드러냈다(아래) |
| Pricing | **No payments** | 수급에서 실제로 문제되는 건 공개 여부가 아니라 수익 행위다. 여기가 방어선 |
| Visibility | **Public** | ⚠`Draft`는 공유용 secret 링크가 안 나와서 **남에게 404**였다(실측). `Restricted`는 HTML 게임에서 문제 보고가 있어 피했다 |
| Cover image | 630×500 · 로고+적 | 없으면 `og:image`가 비어 링크 미리보기에 그림이 안 뜬다 — 모집이 병목인 지금 손해가 크다 |

크기 81MB → 80.9MB는 C174의 `build/*` 제외 때문이다. **README·게임 소개 문서의 "81MB"는
그대로 맞다**(반올림 동일) — 버전도 `0.9.0`으로 안 바뀌었으므로 고칠 문구는 없다.

### 웹 저장소는 어디에 사는가 — 브라우저 실측 (2026-08-13, C192)

루프 3("다음 날 오나")이 성립하려면 `install_id`가 방문 사이에 살아남아야 한다. 배포된 페이지를
직접 열어 IndexedDB를 들여다봤다. **재방문 판정은 작동한다** — 같은 브라우저에서 세 번 열었을 때
`install_id`가 그대로였고 `session_count`가 1→2→3으로 올랐으며 `is_first_session`은 첫 번째만
`true`였다.

| 무엇 | 실측값 |
|---|---|
| 저장 위치 | IndexedDB `/userfs` (오브젝트 스토어 `FILE_DATA`) |
| 오리진 | `https://html-classic.itch.zone` — itch의 **모든** HTML 게임이 공유 |
| 키 | `/userfs/godot/app_userdata/BlockCastle/analytics.{meta,jsonl}` |

읽는 법(게임 오리진에서 실행 — itch 페이지에선 iframe이 교차 오리진이라 안 된다):

```js
const db = await new Promise(r=>{const q=indexedDB.open('/userfs');q.onsuccess=()=>r(q.result)});
const get = k => new Promise(r=>{const q=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA').get(k);q.onsuccess=()=>r(q.result)});
new TextDecoder().decode((await get('/userfs/godot/app_userdata/BlockCastle/analytics.meta')).contents)
```

**저장소는 오리진 단위라 업로드 ID와 무관하다.** 그래서 처방을 적용하고 재배포해도 `install_id`가
살아남는다 = **루프 1→2→3에 걸친 리텐션이 이어진다.** 루프 3이 성립하는 전제가 이것이다.

🔴**그런데 같은 이유로 제출용 빌드와 플레이테스트 빌드가 저장소를 공유한다.** 둘 다 `BlockCastle`
이라는 이름의 Godot 앱이고 오리진이 같아서 경로가 한 글자도 안 다르다. 결과:

- 제출 페이지(`/blockcastle`)를 먼저 해본 사람은 플레이테스트에서 **`is_first_session=false`**로 잡힌다.
  루프 1은 첫인상을 재는 판인데 그 사람은 첫인상이 아니다.
- 다만 **시트가 오염되지는 않는다** — 제출 빌드(업로드 18745783)의 pck에는 수집 주소가 없다(실측).
  오염되는 건 `install_id`·`session_count`뿐이다.
- ⚠**모집 문구에 "제출 페이지 말고 이 링크"를 넣고, 이미 해본 사람은 표본에서 뺀다.**
  섞였는지는 시트에서 `is_first_session=false`인 첫 방문자로 드러난다.

⚠**빌드 버전 한 줄이 `0.0.0-dev`로 찍힌 것을 봤다(2026-08-13, 원인 미상).** 콜드 캐시 첫 로드
한 번뿐이었고 그 뒤 네 번은 전부 `0.9.0-L1.1`이었다. 저장소를 비우고 다시 첫 세션을 만들어도
재현되지 않았다. 배포본 자체는 깨끗하다 — 업로드 18773835의 pck를 받아 훑으니 `0.9.0-L1.1`이
들어 있고 `0.0.0-dev` 문자열은 **없다**. 8/12에 배포를 여러 번 한 날이라(C185→C187→C188)
CDN 엣지의 옛 사본을 한 번 집었을 가능성이 가장 크다. **재현이 안 되므로 고칠 것은 없지만,
시트에 `0.0.0-dev` 줄이 섞여 있을 수 있으니 판독 때 거른다**(`tools/funnel.py`가 경고한다).

⚠**이 검증으로 시트에 시험 줄이 들어갔다.** `install_id` = `33e3c0a067d592d4`(4세션) ·
`0a2eaef2069e70a1`(1세션). 시트 메뉴의 '시험 줄 지우기'는 `probe-`로 시작하는 것만 지우므로
**이 둘은 손으로 지워야 한다** — 안 지우면 루프 1의 5세션이 내 브라우저다.

### 웹을 폰에서 미리 보는 법 — 로컬 HTTPS (2026-08-14)

itch에 올리기 전에 실기기로 확인하려면 서버가 **HTTPS여야 한다.** Godot 웹은 부팅 시
`isSecureContext`를 직접 검사하고, 아니면 게임 대신 이 화면을 띄운다:

> The following features required to run Godot projects on the Web are missing:
> Secure Context - Check web server configuration (use HTTPS)

`python3 -m http.server`로는 **안 된다**(이 함정을 2026-08-14에 실제로 밟았다). 자체 서명으로 세운다:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 7 \
  -subj "/CN=<LAN_IP>" -addext "subjectAltName=IP:<LAN_IP>"      # ⚠SAN 없으면 요즘 브라우저가 거부
ipconfig getifaddr en0                                            # LAN IP
```

그다음 `ssl.SSLContext`로 감싼 `ThreadingHTTPServer`를 `build/web`에서 띄우고
폰(같은 와이파이)에서 `https://<LAN_IP>:8443/`. Safari가 인증서 경고를 띄우면
**자세히 보기 → 이 웹사이트 방문**으로 넘어간다 — 넘어가면 보안 컨텍스트로 잡힌다.
⚠`.wasm`에 `Content-Type: application/wasm`을 붙일 것(스트리밍 컴파일).
⚠평문 HTTP에선 `AudioWorklet`도 같이 죽는다(보안 컨텍스트 전용) — 즉 소리까지 못 본다.

