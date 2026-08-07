extends SceneTree
# 탱크는 몇 번 때려야 죽나 — 콜아웃 문구가 약속해도 되는 횟수를 실측한다(C160).
#   godot --path . --script tools/tank_hits_probe.gd
#
# 왜 재나: "한 번에 두 줄"은 동시 삭제를 요구하는 고급 조작이라 첫 조우 문구로 무겁다. 대신
#   "한 줄로는 안 죽는다, 한 번 더"로 갈 거면 **정말 두 번이면 죽는지**가 사실이어야 한다.
#   HP는 스폰 순서로 램프하므로 판 초반 탱크와 막판 탱크가 다르다 → 양 끝을 다 본다.
#
# 딜 = LINE_BASE(120) × 동시줄배수 × 스트릭배수(1 + 0.5*(콤보-1)). 단발 삭제만 이어친 경우로 센다
#   (가장 흔하고 가장 약한 길 = 하한). 스트릭이 끊긴 최악(매번 120)도 같이 낸다.

const SD = preload("res://stage_data.gd")
const SM = preload("res://modes/stage_mode.gd")
const LINE_BASE: int = 120
const STREAK_STEP: float = 0.5

func _initialize() -> void:
	print("%-6s %-8s %5s %5s   %s" % ["판", "이름", "첫탱크", "막탱크", "필요 타수(연속 / 끊김)"])
	for i in range(SD.STAGES.size()):
		var st: Dictionary = SD.STAGES[i]
		if int(st.get("weights", {}).get("tank", 0)) <= 0:
			continue
		var m = SM.new(st)
		var total: int = int(st["total"])
		var hp_first: int = m.enemy_hp("tank", 0)
		var hp_last: int = m.enemy_hp("tank", total - 1)
		print("%-6s %-8s %5d %5d   %s / %s" % [
			"S%d" % (i + 1), String(st["name"]).replace("_name", ""),
			hp_first, hp_last,
			_hits(hp_last, true), _hits(hp_last, false)])
	print("")
	print("연속 = 콤보 유지(120·180·240…) · 끊김 = 매번 단발 120")
	print("DONE")
	quit()

# 단발 줄삭제를 n번 이어쳤을 때 hp가 0 이하가 되는 최소 n
func _hits(hp: int, streak: bool) -> String:
	var left: float = float(hp)
	for n in range(1, 9):
		var mult: float = (1.0 + STREAK_STEP * float(n - 1)) if streak else 1.0
		left -= float(LINE_BASE) * mult
		if left <= 0.0:
			return "%d번" % n
	return "9번+"
