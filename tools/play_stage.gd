extends SceneTree
# 특정 스테이지로 바로 들어가 '직접 플레이'하는 개발용 런처(창 모드 필수).
#   선택 화면의 선형 잠금을 우회해 _start_stage를 직접 부른다 — 밸런스 변경을 손으로 확인할 때.
#   실행: STAGE=14 godot --path . --script tools/play_stage.gd     (STAGE = 화면에 보이는 번호, 1부터)
#   CARE=3 을 주면 그 판을 **세 번 연속 진 상태**로 들어간다 = 실패 케어가 처음부터 켜져 있다
#     (2=줄-완성 배급만 / 3=거기에 전진 완화·비행기 완화까지). 케어를 손으로 판정할 때 쓴다.
#   ⚠프로브가 아니다: quit하지 않고 그대로 사람이 조작한다. 창을 닫으면 끝.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# ⚠_ready가 persist_enabled를 켠다. 아래서 dev_unlock_all로 잠금을 우회하므로, 안 끄면
	#   이 개발용 플레이가 실유저 진행도에 각인된다([[campaign-save-reset-gotchas]]).
	main.set("persist_enabled", false)
	var env: String = OS.get_environment("STAGE")
	var shown: int = int(env) if env != "" else 1
	var idx: int = clampi(shown - 1, 0, int(main.STAGES.size()) - 1)
	main.dev_unlock_all = true      # 돌아가기·재도전 시에도 잠금에 안 걸리게
	# ⚠_start_stage보다 **먼저** 세운다 — 비행기 첫 픽업 완화는 _init_game에서 한 번만 계산된다.
	# ⚠0도 **명시적으로 박는다** — 안 그러면 세이브에 남은 연속 실패 횟수가 그대로 살아나
	#   "케어 아닌 시나리오"를 보려는데 조용히 케어가 켜진 판을 플레이하게 된다(화면엔 안 나온다).
	var care: int = int(OS.get_environment("CARE")) if OS.get_environment("CARE") != "" else 0
	main.fail_streak[idx] = care
	# BAND=0 = 밴드 완화만 끄고 나머지 케어는 그대로 = 그 레버 하나의 손맛을 가른다.
	if OS.get_environment("BAND") == "0":
		main.care_band_enabled = false
	main.call("_start_stage", idx)
	print("▶ 스테이지 %d 시작 (배열 idx %d, %s)" % [idx + 1, idx, str(main.STAGES[idx].get("name", "?"))])
	if care == 0:
		print("   케어 없음 (연속 실패 0으로 박음 — 세이브 값 무시)")
	else:
		print("   케어 %d패 상태 (줄-완성 배급 %s · 밴드 완화 %s · 비행기 완화 %s)" % [
			care,
			"ON" if care >= main.CARE_CLEAR_FAILS else "off",
			"ON" if main.call("_care_band_bonus") > 0 else "off",
			"ON" if main.plane_cd_left == main.CARE_PLANE_FIRST_CD else "off"])
