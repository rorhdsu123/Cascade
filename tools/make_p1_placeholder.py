#!/usr/bin/env python3
"""P1 부품 **임시본** 생성기 — art/cell.png · art/plane.png · art/ui/<P1 9-slice>.

    python3 tools/make_p1_placeholder.py

P0 부품 생성기는 따로 있다: 블록=make_block_placeholder.py · 패널/버튼=make_ui_placeholder.py ·
적=make_enemy_placeholder.py. 여기는 C124에서 이음새를 판 나머지다.

목적은 예쁜 UI가 아니라 **이음새가 진짜 도는지 확인**하는 것이다. 그래서 지금 렌더와
**일부러 다르게** 그린다 — 비슷하게 그리면 텍스처가 안 붙었는데 붙은 줄 착각한다(C123에서 배운 것).
PNG는 커밋하지 않는다. 필요하면 이 스크립트를 한 번 돌리면 된다.

마진은 Main.gd의 UI_9S 표와 **짝**이다. 여기 숫자를 바꾸면 저기도 바꿔야 한다(텍스처 픽셀 기준).
⚠라운드 반경은 **마진 안에 들어와야 한다**. 넘으면 모서리 조각이 잘려 늘어난다(알약이 특히 위험).
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
UI = ART / "ui"
UI.mkdir(parents=True, exist_ok=True)

SS = 4        # 슈퍼샘플링 — 라운드 가장자리 계단 제거
SCALE = 2     # 납품 배율(§5). 텍스처 px = 화면 px × 2


def rounded(size, radius, fill, outline=None, ow=0):
    """라운드 사각 한 장(RGBA). size·radius·ow는 텍스처 픽셀."""
    w, h = size
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        [0, 0, w * SS - 1, h * SS - 1], radius=radius * SS, fill=fill,
        outline=outline, width=ow * SS)
    return img.resize((w, h), Image.LANCZOS)


# ── 빈 셀 배경(P0였는데 이음새가 없었다) — 180×180, 블록과 짝 ──────────────
# 틴트하지 않는다: 보드 셀은 존 색 전환에서도 원색을 지키는 '다크 아일랜드'라 색을 그림이 갖는다.
# 격자선은 **그림의 여백**이 만든다 — 코드는 텍스처 경로에서 선을 안 그린다.
rounded((180, 180), 22, (30, 30, 46, 255), outline=(52, 54, 76, 255), ow=3).save(ART / "cell.png")

# ── 종이비행기 — 180×180, 틴트 없음(접힘 명암이 정체라 2색 이상) ────────────
# 도형 렌더와 구분되게 **각도와 색을 일부러 다르게** 잡는다.
plane = Image.new("RGBA", (180 * SS, 180 * SS), (0, 0, 0, 0))
pd = ImageDraw.Draw(plane)
S = 180 * SS
nose, tail = (S * 0.50, S * 0.06), (S * 0.50, S * 0.70)
pd.polygon([nose, (S * 0.04, S * 0.94), tail], fill=(120, 214, 236, 255))   # 왼 날개(밝음)
pd.polygon([nose, (S * 0.96, S * 0.94), tail], fill=(58, 150, 178, 255))    # 오른 날개(어두움 = 접힘)
pd.line([nose, tail], fill=(232, 252, 255, 255), width=int(S * 0.012))      # 중앙 접힘선
plane.resize((180, 180), Image.LANCZOS).save(ART / "plane.png")

# ── 목표 카드(기준 310×104 → 620×208) ──────────────────────────────────────
# 본체는 다크 톤을 그림이 갖고(틴트 없음), 테는 accent 색 신호라 **같은 캔버스 레이어**로 나눈다.
rounded((620, 208), 40, (36, 36, 56, 255)).save(UI / "card.png")
rounded((620, 208), 40, (0, 0, 0, 0), outline=(255, 255, 255, 255), ow=6).save(UI / "card_edge.png")

# ── 거점 HP 바(폭 720×높이 32 화면 → 마진 [20,24,20,24]) ────────────────────
# ⚠반경 20 = 가로 마진과 같게. 더 키우면 HP가 줄어 목적지가 좁아질 때 캡이 뭉갠다.
rounded((200, 64), 20, (22, 10, 12, 255)).save(UI / "hp_track.png")
rounded((200, 64), 20, (255, 255, 255, 255)).save(UI / "hp_fill.png")   # 회색조 — 빨강↔초록은 코드

# ── 슬롯(트레이 120×100 · 비행기 90×90이 **같은 부품**) ─────────────────────
rounded((240, 200), 30, (255, 255, 255, 255)).save(UI / "slot.png")     # 회색조 — 상태색은 코드

# ── 보드 외곽 프레임 — ⚠가운데가 **투명**이어야 한다(보드를 덮으면 안 된다) ──
rounded((240, 240), 40, (0, 0, 0, 0), outline=(255, 255, 255, 255), ow=10).save(UI / "board_frame.png")

# ── 스테이지 타일 3종(126×126 화면 → 252×252) ───────────────────────────────
# 회색조 마스터 × 상태별 파일. 색(금색 테=현재 위치)은 코드가 계속 쥔다.
rounded((252, 252), 30, (255, 255, 255, 255)).save(UI / "tile.png")
rounded((252, 252), 30, (255, 255, 255, 255), outline=(210, 210, 210, 255), ow=6).save(UI / "tile_front.png")
rounded((252, 252), 30, (235, 235, 235, 255)).save(UI / "tile_off.png")

# ── 튜토리얼 말풍선(높이 36 화면 → 72) ─────────────────────────────────────
# ⚠**반드시 불투명** — 뒤에 보드가 비치면 글자가 안 읽힌다. 반경은 세로 마진(24) 이하로.
rounded((200, 72), 24, (23, 23, 36, 255)).save(UI / "tut_bubble.png")
rounded((200, 72), 24, (0, 0, 0, 0), outline=(255, 255, 255, 255), ow=4).save(UI / "tut_bubble_edge.png")

print("wrote", ART, "+", UI)
