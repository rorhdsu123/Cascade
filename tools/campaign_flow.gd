extends SceneTree
# 캠페인 플로우 폴리싱 probe — 메뉴·선택·8스테이지 대표 플레이 프레임·클리어·전체클리어를 창 캡처.
# [[godot-pixel-verify-needs-window]] 창 필수(헤드리스=렌더텍스처 null). [[zoom-renders-to-judge-ui]] 확대 판단은 후처리(PIL).
#   godot --path . --script tools/campaign_flow.gd
#
# 목적: "스테이지 사이 연결 조직 + 새 위협 첫 등장 가독성"의 폴리싱 결함을 프레임으로 드러냄.
# 플레이 진행이 배치(place_count) 기반이라 자동 플레이 대신 result_shot.gd처럼 대표 보드/적 상태를 주입한다.

const ShotDir = preload("res://tools/shot_dir.gd")
# 출력 경로 = SHOT_DIR 환경변수, 없으면 build/shots/ (tools/shot_dir.gd 참조).
var DIR: String = ShotDir.resolve("cf_")
var g: Node

func _initialize() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _shot(name: String) -> void:
	if _headless():
		print("[headless] skip ", name)
		return
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR + name)
	print("shot ", name)

# 대표 적 1마리 주입 — 감독 HP 램프를 그대로 써서 프레임의 HP바가 실제 스테이지 값과 일치.
func _put(col: int, etype: String, row: int, spawn_idx: int, gen: int = 0, split_done: bool = false) -> void:
	var director = g.get("director")
	var hp: int = director.call("enemy_hp", etype, spawn_idx)
	var step: int = director.call("enemy_step", etype)
	var e: Dictionary = {
		"col": col, "row": row, "vis_row": float(row), "hp": hp, "maxhp": hp,
		"etype": etype, "id": 9000 + col + row * 8, "step_every": step,
	}
	if etype == "split":
		e["gen"] = gen
		e["split_done"] = split_done
	var arr: Array = g.get("enemies")
	arr.append(e)
	g.set("enemies", arr)

# 하단 몇 줄을 부분 충전 — 막힘 아닌 '한창 플레이 중' 보드. (gaps 남겨 stuck 아님)
func _fill_board() -> void:
	var board: Array = g.get("board")
	var cols: Array = ["R", "B", "Y"]
	# rows 5,6,7 을 듬성듬성. 결정적 패턴(randf 없음 — probe 재현성).
	var pattern: Array = [
		[7, [0,1,2,4,5,7]],
		[6, [1,2,5,6]],
		[5, [3,4]],
	]
	for pr in pattern:
		var r: int = pr[0]
		for c in pr[1]:
			board[r][c] = cols[(r + c) % 3]
	g.set("board", board)

# 스테이지 대표 프레임 구성: 시작 → 적 주입(중반 램프) → 부분 보드 → 시그니처 콜아웃.
func _stage_frame(idx: int, layout: Array, callout_key: String) -> void:
	g.call("_start_stage", idx)
	g.set("intro_t", -1.0)   # 인트로 카드 억제 — 이 probe는 중반 플레이 프레임을 잡는다(진입 아님)
	await process_frame
	var st: Dictionary = g.get("st")
	var total: int = int(st["total"])
	var mid: int = int(total * 0.45)
	# _start_stage가 심은 시작 basic 1마리는 그대로 두고 위에 얹는다(진입 직후 아님을 표현).
	g.set("spawned", mid)
	g.set("killed", int(total * 0.30))
	g.set("place_count", mid)
	var si: int = mid
	for spec in layout:
		# spec = [col, etype, row] 또는 [col, etype, row, gen, split_done]
		if spec.size() >= 5:
			_put(spec[0], spec[1], spec[2], si, spec[3], spec[4])
		else:
			_put(spec[0], spec[1], spec[2], si)
		si += 1
	_fill_board()
	if callout_key != "":
		g.set("callout_text", g.call("_t", callout_key))
		g.set("callout_timer", g.get("CALLOUT_DUR"))
	await _shot("stage%d.png" % (idx + 1))

func _run() -> void:
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await process_frame
	# ⚠이 probe는 Main.tscn을 띄우므로 _ready가 돌아 persist_enabled=true가 된다(헤드리스 하네스와 달리).
	#   아래 5)에서 cleared[0..7]을 주입하는데, 그 상태로 _check_win이 한 번이라도 타면 실제 유저
	#   campaign.save에 8스테이지 클리어가 각인된다 → 명시적으로 끈다(캡처만 하고 디스크는 안 건드림).
	g.set("persist_enabled", false)
	DisplayServer.window_set_size(Vector2i(800, 1000))
	await process_frame

	# ── 1) 메인 허브
	g.set("mode", "menu")
	await _shot("menu.png")

	# ── 2) 스테이지 선택(전 스테이지 해금해 8개 다 보이게)
	g.set("dev_unlock_all", true)
	g.set("mode", "select")
	await _shot("select.png")

	# ── 3) 8스테이지 대표 플레이 프레임 (각 스테이지 시그니처 위협 + 첫등장 콜아웃)
	# S1 첫 방어선: basic만
	await _stage_frame(0, [[1,"basic",2],[4,"basic",3],[6,"basic",1]], "")
	# S2 무리: swarm 클러스터
	await _stage_frame(1, [[2,"swarm",2],[3,"swarm",2],[4,"swarm",3],[5,"swarm",2],[1,"basic",4]], "callout_swarm")
	# S3 속공: fast
	await _stage_frame(2, [[1,"fast",3],[5,"fast",2],[3,"fast",4],[6,"basic",1]], "callout_fast")
	# S4 줄 굶김: basic+swarm (lean 풀)
	await _stage_frame(3, [[2,"basic",3],[5,"swarm",2],[6,"swarm",2],[1,"basic",4]], "")
	# S5 장갑: tank(4.5배 HP) — 두꺼운 HP바
	await _stage_frame(4, [[2,"tank",2],[5,"tank",3],[6,"basic",1],[3,"swarm",4]], "callout_tank")
	# S6 총력전: 전 타입 혼합
	await _stage_frame(5, [[1,"tank",2],[3,"fast",3],[4,"swarm",4],[5,"swarm",4],[6,"basic",1]], "")
	# S7 분열: split gen0(크랙선) + gen1 쌍둥이
	await _stage_frame(6, [[2,"split",2,0,false],[3,"split",2,1,true],[5,"split",3,0,false],[1,"basic",4]], "callout_split")
	# S8 최종: 전 타입 + split
	await _stage_frame(7, [[1,"tank",2],[2,"fast",3],[4,"split",2,0,false],[5,"swarm",4],[6,"basic",1]], "")

	# ── 4) 클리어 팝업 (중간 스테이지 — '다음 스테이지' 버튼 상태)
	g.call("_start_stage", 3)
	await process_frame
	var st4: Dictionary = g.get("st")
	g.set("killed", int(st4["total"]))
	g.set("leaked", 0)
	g.set("game_over", false)
	g.set("game_clear", true)
	await _shot("clear_mid.png")

	# ── 5) 전체 클리어 (마지막 스테이지 클리어 = '홈으로', all_cleared 배너)
	for i in range(8):
		var cl: Dictionary = g.get("cleared")
		cl[i] = true
		g.set("cleared", cl)
	g.call("_start_stage", 7)
	await process_frame
	var st8: Dictionary = g.get("st")
	g.set("killed", int(st8["total"]))
	g.set("leaked", 0)
	g.set("game_over", false)
	g.set("game_clear", true)
	await _shot("gameclear.png")

	# 전체클리어 선택화면(하단 버튼 = all_cleared 문구)도 한 장
	g.set("mode", "select")
	await _shot("select_allclear.png")

	print("DONE")
	quit()
