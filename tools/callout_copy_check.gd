extends SceneTree
# 콜아웃 문구 실측 — C160서 여섯 개를 다시 쓰면서, 길어진 문구가 접힌 뒤에도 **판 안에 앵커되는지**를
#   눈이 아니라 숫자로 본다([[drawn-position-vs-hit-rect]]).
#   godot --path . --script tools/callout_copy_check.gd
#
# 판정선 두 개(_draw 본문과 같은 식):
#   ① 접기 폭 = COLS*CELL - 44 = 676px. 여기서 몇 줄로 접히나(2줄까지가 선례 — 옛 도둑·비행기).
#   ② 말풍선 폭 bw = 최장줄 + 34. **bw > 712면 대상에 못 붙고 판 중앙으로 폴백한다**
#      (lo > hi 분기) = 꼬리가 가리키는 인과가 죽는다. 이게 진짜 실패 조건이다.
# 창 필수([[godot-pixel-verify-needs-window]]).

const WRAP_W: float = 676.0     # COLS(8) * CELL(90) - 44
const ANCHOR_MAX: float = 712.0 # 이 폭을 넘으면 앵커 포기(판 중앙 폴백)
const KEYS: Array = [
	"callout_fast", "callout_tank", "callout_swarm", "callout_split",
	"callout_bomb", "callout_thief", "callout_thief_stolen",
	"callout_gem", "callout_plane",
]

var g: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	g.set("persist_enabled", false)
	var fnt: Font = g.get("_font")
	if fnt == null:
		print("폰트 null — 중단")
		quit()
		return

	var worst: int = 0
	var fails: int = 0
	print("%-22s %5s %6s  %s" % ["key", "lines", "bw", "text"])
	for k in KEYS:
		var txt: String = g.call("_t", k)
		var lines: PackedStringArray = g.call("_wrap_callout", fnt, txt, WRAP_W)
		var cow: float = 0.0
		for ln in lines:
			cow = maxf(cow, fnt.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x)
		var bw: float = cow + 34.0
		var flag: String = ""
		if bw > ANCHOR_MAX:
			flag = "  ← 앵커 포기(중앙 폴백)"
			fails += 1
		worst = maxi(worst, lines.size())
		print("%-22s %5d %6.0f  %s%s" % [k, lines.size(), bw, txt, flag])
	print("")
	print("최대 줄수=%d · 앵커 포기=%d개" % [worst, fails])
	print("DONE")
	quit()
