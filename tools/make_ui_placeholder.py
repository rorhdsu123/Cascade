#!/usr/bin/env python3
"""패널·버튼 9-slice **임시본** 생성기 — art/ui/*.png.

    python3 tools/make_ui_placeholder.py [출력디렉터리]

목적은 예쁜 UI가 아니라 **이음새가 진짜 도는지 확인**하는 것이다(UI_ART_PLAN §4 P0 배선 검증).
디자이너 납품본이 오면 같은 이름으로 덮어쓰면 되고, 지우면 기존 draw_rect 렌더로 되돌아간다
— 어느 쪽이든 코드는 안 건드린다.

마진은 Main.gd의 UI_9S 표와 **짝**이다. 여기 숫자를 바꾸면 저기도 바꿔야 한다(텍스처 픽셀 기준).

버튼은 **회색조 마스터**다 — 코드가 modulate(곱셈)로 초록·금색·주황·파랑을 입힌다(블록과 같은 규약).
그래서 어두우면 색이 죽는다. 패널만 예외로 다크 톤을 그림이 갖는다(코드는 틴트 안 함).
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "art" / "ui"
OUT.mkdir(parents=True, exist_ok=True)

SS = 4        # 슈퍼샘플링 — 라운드 가장자리 계단 제거
SCALE = 2     # 납품 배율(§5). 텍스처 px = 화면 px × 2


def rounded(size, radius, fill, outline=None, ow=0):
    """라운드 사각 한 장(RGBA). size·radius·ow는 텍스처 픽셀."""
    w, h = size
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=radius * SS, fill=fill,
                        outline=outline, width=ow * SS)
    return img.resize((w, h), Image.LANCZOS)


def gloss_band(img, inset, height_frac, alpha):
    """상단 광택 — 현재 코드가 draw_rect로 얹던 하이라이트 띠를 그림 쪽으로 옮긴 것."""
    w, h = img.size
    band = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        [inset * SS, inset * SS, (w - inset) * SS - 1, int(h * height_frac) * SS],
        radius=int(h * 0.18) * SS, fill=(255, 255, 255, alpha))
    band = band.resize((w, h), Image.LANCZOS)
    out = img.copy()
    out.alpha_composite(Image.composite(band, Image.new("RGBA", img.size, (0, 0, 0, 0)),
                                        img.split()[3]))
    return out


def button(size, radius, body, edge, gloss):
    """버튼 마스터 한 장 = 라운드 본체 + 어두운 테두리 + 상단 광택."""
    img = rounded(size, radius, body, outline=edge, ow=4)
    return gloss_band(img, 10, 0.34, gloss)


# ── 패널(다크 톤 — 코드가 틴트하지 않는 유일한 부품) ────────────────────────
# 마진 56 → 화면에선 28px 모서리. 가운데를 늘려도 라운드가 안 부푼다.
panel = rounded((160, 160), 30, (33, 33, 51, 255), outline=(70, 72, 92, 255), ow=3)
panel.save(OUT / "panel.png")

# ── 상단 강조바(회색조 — accent를 코드가 입힌다) ────────────────────────────
# ⚠패널과 **같은 캔버스·같은 마진**이다. 8px 띠 한 조각으로 만들면 각진 양끝이 패널 라운드
#   밖으로 삐져나온다(실제로 그랬다). 같은 캔버스면 모서리가 정의상 일치한다.
bar = Image.new("RGBA", (160 * SS, 160 * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(bar)
d.rounded_rectangle([0, 0, 160 * SS - 1, 160 * SS - 1], radius=30 * SS, fill=(255, 255, 255, 255))
# 위 16px(화면 8px)만 남기고 아래를 지운다 — 9-slice 세로 마진(56) 안이라 늘어나도 두께가 고정된다
d.rectangle([0, 16 * SS, 160 * SS, 160 * SS], fill=(0, 0, 0, 0))
bar.resize((160, 160), Image.LANCZOS).save(OUT / "panel_bar.png")

# ── 큰 버튼 3상태 ───────────────────────────────────────────────────────────
# 기본/눌림/비활성. 눌림은 광택을 죽이고 살짝 어둡게(=들어간 느낌), 비활성은 채도 대신 명도로.
button((160, 160), 26, (255, 255, 255, 255), (150, 150, 150, 255), 46).save(OUT / "btn_lg.png")
button((160, 160), 26, (222, 222, 222, 255), (138, 138, 138, 255), 16).save(OUT / "btn_lg_press.png")
button((160, 160), 26, (150, 150, 150, 255), (110, 110, 110, 255), 10).save(OUT / "btn_lg_off.png")

# ── 작은 버튼 2상태 ─────────────────────────────────────────────────────────
button((110, 110), 18, (255, 255, 255, 255), (150, 150, 150, 255), 40).save(OUT / "btn_sm.png")
button((110, 110), 18, (222, 222, 222, 255), (138, 138, 138, 255), 14).save(OUT / "btn_sm_press.png")

# ── 고스트(보조 동작) — 속이 빈 테두리만. 채우면 부차 버튼이 주CTA만큼 무거워진다.
rounded((110, 110), 18, (0, 0, 0, 0), outline=(255, 255, 255, 255), ow=2).save(OUT / "btn_ghost.png")

print("wrote", OUT)
