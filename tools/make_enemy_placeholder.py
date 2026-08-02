#!/usr/bin/env python3
"""적 스프라이트 **임시본** 생성기 — art/enemies/{basic,swarm,fast}.png (각 180×180).

    python3 tools/make_enemy_placeholder.py [출력디렉터리]

목적은 아트가 아니라 **이음새가 실제로 도는지 확인**하는 것이다(UI_ART_PLAN §4 basic=P0 · swarm·fast=P1).
납품본이 오면 같은 이름으로 덮어쓰면 되고, 지우면 기존 도형 렌더로 되돌아간다 — 코드는 안 건드린다.

일부러 **지금 도형과 다르게** 그린다(눈·링·꼬리). 안 그러면 텍스처가 안 붙었는데 붙은 줄 착각한다
— 이 저장소에서 실제로 그렇게 한 번 속았다(--import를 안 돌려 조용히 폴백이었다).

⚠**밝은 기준 상태 1장씩만** 만든다. HP가 닳는 명암과 전진 직후 밝은 링은 코드가 유지하므로
손상 상태를 그리면 이중으로 어두워진다.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "art" / "enemies"
OUT.mkdir(parents=True, exist_ok=True)

S = 180        # 한 칸(90px)의 2배 = §5 배율 규칙
SS = 4         # 슈퍼샘플링
W = S * SS
RIM = (10, 8, 18, 220)   # 어두운 외곽선 — 밝은 보드 위에서도 윤곽이 서게


def canvas():
    return Image.new("RGBA", (W, W), (0, 0, 0, 0))


def save(img, name):
    img.resize((S, S), Image.LANCZOS).save(OUT / (name + ".png"))
    print("wrote", name)


def circle(d, cx, cy, r, fill, outline=None, ow=0):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=ow)


# ── basic — 바이올렛 덩어리 + 눈 두 개. 코드가 HP 명암을 곱하므로 밝게 둔다 ──
img = canvas()
d = ImageDraw.Draw(img)
r = int(W * 0.36)
c = W // 2
circle(d, c, c, r, (176, 102, 255, 255), outline=RIM, ow=5 * SS)
circle(d, c, int(c - r * 0.28), int(r * 0.74), (200, 145, 255, 255))    # 위쪽 하이라이트
for sx in (-0.34, 0.34):
    circle(d, int(c + r * sx), int(c + r * 0.06), int(r * 0.17), (255, 255, 255, 255))
    circle(d, int(c + r * sx), int(c + r * 0.06), int(r * 0.08), (32, 12, 52, 255))
save(img, "basic")

# ── swarm — 라임 작은 원 3개(군집). 셋을 **한 장으로** 받는 게 이 적의 form이다 ──
img = canvas()
d = ImageDraw.Draw(img)
for ox, oy, k in ((-0.20, -0.15, 1.0), (0.20, -0.12, 0.92), (-0.02, 0.20, 1.06)):
    rr = int(W * 0.155 * k)
    circle(d, int(c + ox * W), int(c + oy * W), rr, (176, 235, 84, 255), outline=RIM, ow=4 * SS)
    circle(d, int(c + ox * W - rr * 0.3), int(c + oy * W - rr * 0.3), int(rr * 0.34), (226, 255, 170, 255))
save(img, "swarm")

# ── fast — 시안 화살촉(아래 향함) + 속도선 꼬리 ──
img = canvas()
d = ImageDraw.Draw(img)
s = W * 0.34
head = [(c, c + s), (c - s * 0.92, c - s * 0.55), (c, c - s * 0.16), (c + s * 0.92, c - s * 0.55)]
d.polygon(head, fill=(70, 220, 245, 255), outline=RIM, width=5 * SS)
for dx in (-0.42, 0.0, 0.42):
    x = c + s * dx
    d.line([(x, c - s * 0.72), (x, c - s * 1.05)], fill=(190, 245, 255, 235), width=5 * SS)
save(img, "fast")
