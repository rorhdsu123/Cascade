#!/usr/bin/env python3
"""안드로이드 빌드 템플릿 패치 (Phase V W2 R2 — 광고 SDK 전제조건).

    실행: python3 tools/android_template_patch.py

왜 스크립트인가:
  `android/`는 Godot 에디터가 설치하는 200MB 빌드 템플릿이라 .gitignore 대상이다
  (재생성 가능·거대). 그래서 여기 손댄 내용은 저장소가 기억을 못 한다 →
  "다른 머신에선 빌드가 안 되는" 사고가 난다. 그 기억을 이 스크립트가 대신 진다.
  **템플릿을 재설치(에디터 > 프로젝트 > 안드로이드 빌드 템플릿 설치)할 때마다 다시 돌린다.**

무엇을 왜 바꾸나:
  AdMob 플러그인 v5.0.0의 aar(Google Mobile Ads **Next-Gen SDK** v25)이
  `compileSdk >= 36`을 요구한다. Godot 4.6.2가 깔아주는 템플릿은 35라서
  gradle이 "requires libraries ... to compile against version 36 or later"로 거절한다.
  compileSdk는 export preset으로 못 넘기는 값이라(min/target sdk만 노출) 템플릿을 직접 고친다.

  ⚠compileSdk 상향은 '더 새 API로 컴파일'일 뿐 런타임 동작(targetSdk 35)·설치 하한(minSdk 24)은
    안 건드린다. 그래서 기기 호환 범위는 그대로다.

선행: sdkmanager로 `platforms;android-36`·`build-tools;36.0.0` 설치.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "android" / "build" / "config.gradle"
PROPS = ROOT / "android" / "build" / "gradle.properties"

# AGP 8.6.1의 '권장 최대 compileSdk'는 35라, 36으로 올리면 경고를 띄운다. 빌드는 되지만
#   gradle.properties가 warning.mode=all이라 로그가 시끄러워진다 → 명시적으로 억제한다.
SUPPRESS_LINE = "android.suppressUnsupportedCompileSdk=36"

WANT = {"compileSdk": "36", "buildTools": "'36.0.0'"}


def patch_config() -> bool:
    if not CONFIG.is_file():
        sys.exit(
            "안드로이드 빌드 템플릿이 없다: %s\n"
            "  에디터에서 '프로젝트 > 안드로이드 빌드 템플릿 설치'를 먼저 실행할 것." % CONFIG
        )
    text = CONFIG.read_text()
    out = text
    for key, value in WANT.items():
        pattern = re.compile(r"^(\s*%s\s*):\s*(\S+?)(,?)$" % key, re.M)
        match = pattern.search(out)
        if not match:
            sys.exit("config.gradle에서 '%s' 항목을 못 찾았다 — 템플릿 형식이 바뀌었다." % key)
        out = pattern.sub(lambda m: "%s: %s%s" % (m.group(1), value, m.group(3)), out, count=1)
    if out != text:
        CONFIG.write_text(out)
        return True
    return False


def patch_props() -> bool:
    text = PROPS.read_text() if PROPS.is_file() else ""
    if SUPPRESS_LINE in text:
        return False
    suffix = "" if text.endswith("\n") or not text else "\n"
    PROPS.write_text(
        text
        + suffix
        + "\n# AdMob v5(Next-Gen SDK)가 compileSdk 36을 요구해 올렸다. AGP 8.6.1은 35까지만\n"
        + "# '권장'이라 경고를 내는데, 빌드에는 문제가 없으므로 억제한다(tools/android_template_patch.py).\n"
        + SUPPRESS_LINE
        + "\n"
    )
    return True


if __name__ == "__main__":
    changed_config = patch_config()
    changed_props = patch_props()
    for key, value in WANT.items():
        assert ("%s         : %s" % (key, value)) in CONFIG.read_text() or (
            "%s: %s" % (key, value)
        ) in CONFIG.read_text(), key
    print("config.gradle : %s (compileSdk=36, buildTools=36.0.0)" % ("패치함" if changed_config else "이미 패치됨"))
    print("gradle.properties : %s" % ("패치함" if changed_props else "이미 패치됨"))
