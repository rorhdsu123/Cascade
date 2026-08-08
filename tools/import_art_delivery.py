#!/usr/bin/env python3
"""디자이너 납품분(2026-08-08, P1 잔여)을 게임의 이름 규약으로 옮긴다.

납품 파일명은 디자이너 쪽 이름이고, 게임은 `art/ui/<슬롯>.png` 같은 고정 이름만 본다
(Main.gd의 UI_9S · ICON_NAMES · ENEMY_NAMES). 그 대응을 손으로 복사하면 다음 납품 때
같은 짓을 다시 하게 되므로 표로 적어 둔다.

두 장은 **그대로 못 쓴다** — 코드가 색을 입히는 자리인데 채색본으로 왔다. 사양(§4)이
회색조를 요구한 이유가 그거다. 여기서 기계적으로 되돌린다(원본은 납품 폴더에 그대로 있다):

  board_frame: 청색 테 → 회색조. 무한 모드에서 **기록 갱신 중**이면 이 테가 금색으로 물든다.
            청색을 그림이 쥐면 금색×청색 = 탁한 연두가 된다(실제로 그렇게 나왔다).

⚠**HP바 두 장(`ui_base_hpbar_*`)은 일부러 안 옮긴다**(C163, 유저 판정). 붙여 봤더니 가독성이
  떨어졌다 — 알약에 두꺼운 남색 테가 둘려 있어 **띠가 실제보다 얇아 보이고**, 초록도 어두워져
  흰 라벨과의 대비가 같이 내려갔다. 코드 렌더는 사각형 전체가 색이고 상단 하이라이트가 있다.
  파일을 여기 되살리면 그 순간 다시 갈아탄다(이음새는 살아 있다) — 되살릴 땐 라벨 대비부터 볼 것.
  card_edge: 납품 카드에 **구워져 있는** 금색 테를 떼어내 별도 레이어로. 목표 카드의
            테 색은 동사 신호다(처치=금 / 수집=젬 / 방어=보라). 한 장으로 받으면
            모든 판이 처치판처럼 보인다.

사용: python3 tools/import_art_delivery.py <납품폴더>
"""
import sys
import shutil
from pathlib import Path

from PIL import Image

# 납품 이름 → 저장소 경로. 그대로 복사되는 것들.
COPY = {
    "icon/ICON_GEAR_96.png": "art/icons/gear.png",
    "icon/ICON_ENEMY_SKULL_96.png": "art/icons/skull.png",
    "icon/ICON_CLEAR_CHECK_96.png": "art/icons/check.png",
    "icon/ICON_LOCK_96.png": "art/icons/lock.png",
    "icon/ICON_ADVENTURE_FLAG_96.png": "art/icons/flag.png",
    "icon/ICON_ENDLESS_INFINITY_96.png": "art/icons/infinity.png",
    "icon/ICON_AD_PLAY_96.png": "art/icons/play.png",
    "icon/ICON_RETRY_96.png": "art/icons/retry.png",
    "icon_paper_airplane_special_180.png": "art/plane.png",
    "enemy_swarm_180x180.png": "art/enemies/swarm.png",
    "enemy_fast_180x180.png": "art/enemies/fast.png",
    "BTN_SM_NORMAL.png": "art/ui/btn_sm.png",
    "BTN_SM_PRESSED.png": "art/ui/btn_sm_press.png",
    "BTN_LG_GHOST.png": "art/ui/btn_ghost.png",
    "bg_tray_slot_240x200.png": "art/ui/slot.png",
    "ui_goal_card_bg_310x104.png": "art/ui/card.png",
    "ui_tutorial_instruction_yellow_9slice.png": "art/ui/tut_bubble.png",
    "ui_tutorial_warning_red_9slice.png": "art/ui/tut_bubble_warn.png",
}


def to_greyscale_master(src: Path, dst: Path) -> None:
    """채색본 → 회색조 마스터. 코드가 곱셈으로 색을 입히므로 **밝기 관계만** 남긴다.

    가장 밝은 화소를 흰색 근처(250)로 올린다 — 안 그러면 틴트 결과가 납품본보다 어두워진다
    (곱셈은 늘 어둡게만 만든다). 알파는 그대로 둔다.
    """
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    peak = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            peak = max(peak, int(0.299 * r + 0.587 * g + 0.114 * b))
    k = 250.0 / max(1, peak)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            v = min(255, int((0.299 * r + 0.587 * g + 0.114 * b) * k))
            px[x, y] = (v, v, v, a)
    im.save(dst)


def extract_edge_layer(src: Path, dst: Path, sat_min: int = 40) -> None:
    """본체에 구워진 채도 높은 테만 떼어 같은 캔버스의 회색조 레이어로.

    카드 본체는 채도 낮은 남색(27,30,50 → 채도차 23)이고 테는 금색(246,200,85 → 161)이라
    채도차 하나로 갈린다. 잘라낸 테는 회색조로 정규화한다 — 코드가 accent를 곱한다.
    남는 화소는 완전 투명(테만 있는 레이어여야 본체 라운드와 모서리가 정의상 일치한다).
    """
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    peak = 0
    keep = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8 or (max(r, g, b) - min(r, g, b)) < sat_min:
                continue
            v = int(0.299 * r + 0.587 * g + 0.114 * b)
            peak = max(peak, v)
            keep.append((x, y, v, a))
    k = 250.0 / max(1, peak)
    for x, y, v, a in keep:
        c = min(255, int(v * k))
        op[x, y] = (c, c, c, a)
    out.save(dst)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src_dir = Path(sys.argv[1]).expanduser()
    root = Path(__file__).resolve().parent.parent
    missing = []
    for name, rel in COPY.items():
        s = src_dir / name
        if not s.exists():
            missing.append(name)
            continue
        d = root / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(s, d)
        print(f"copy   {name:46s} → {rel}")

    for name, rel in (
        ("ui_board_outer_frame_9slice.png", "art/ui/board_frame.png"),
    ):
        s = src_dir / name
        if not s.exists():
            missing.append(name)
            continue
        to_greyscale_master(s, root / rel)
        print(f"grey   {name:46s} → {rel}")

    card = src_dir / "ui_goal_card_bg_310x104.png"
    if card.exists():
        extract_edge_layer(card, root / "art/ui/card_edge.png")
        print(f"edge   {card.name:46s} → art/ui/card_edge.png")

    if missing:
        print("\n⚠ 납품 폴더에 없는 파일: " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
