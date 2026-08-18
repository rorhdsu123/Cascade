extends SceneTree
# 훅 클립 — "놓는다 → 줄이 찬다 → 그 줄에 서 있던 적이 같이 쓸린다" (C207)
#   godot --path . --write-movie build/clips/hook.avi --fixed-fps 60 --script tools/hook_movie.gd
#
# `clear_movie.gd`와 목적이 다르다. 저쪽은 **이긴 뒤의 축하**(스윕 → 로고 → 팝업)를 찍고,
# 이쪽은 **한 수**를 찍는다. 처음 보는 사람에게 필요한 건 결과 화면이 아니라
# "이 게임이 어떻게 도는가" 8초다 — 2026-08-17에 모집 글을 다시 짜면서 필요해졌다.
#
# ⚠**판정 경로를 우회하지 않는다.** 보드와 적만 원하는 모양으로 심고, 배치는 실제 `_place_piece()`가
#   한다. 그래서 여기 찍힌 그림은 "이 값이면 이렇게 보인다"가 아니라 **실제로 일어나는 일**이다.
#   (`campaign_flow.gd`가 대표 상태를 주입하는 것과 같은 방식이고, 연출을 손으로 켜는
#   `clear_movie.gd`와는 그 점이 다르다.)

const FPS: int = 60
const ROW: int = 5                 # 적이 내려앉은 줄. 아래쪽이라 거점과 가까워 긴장이 읽힌다
const GAP_COL: int = 3             # 비워 둘 자리(조각이 들어갈 곳) 시작 열
const PRE_S: float = 1.5           # 놓기 전 — 무엇이 걸려 있는지 읽는 시간
const POST_S: float = 2.6          # 놓은 뒤 — 줄이 차고, 쓸리고, 여운
#   ⚠POST를 늘리지 말 것. 4.4초까지 두면 새 적이 스폰되며 **첫 등장 안내 문구**가 뜨는데,
#   방금 일어난 일과 무관한 문장이라 8초짜리 광고에서 시선을 통째로 가져간다(1차 촬영에서 확인).
const COLORS: Array = ["R", "O", "Y", "G", "B", "P"]

var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 3)
	await process_frame

	# 🔴**녹화가 시작되기 전에 심는다.** 1차 촬영에서 워밍업 뒤에 심었더니 빈 판에 보드가
	#   한 프레임 만에 튀어나와, 광고로 보면 게임이 깨진 것처럼 읽혔다. 첫 프레임부터 완성된
	#   판이 서 있어야 "이 판에서 한 수를 둔다"로 읽힌다.
	_stage_the_move()
	for _w in range(20):
		main.call("_process", 1.0 / float(FPS))
		await process_frame

	for _i in range(int(PRE_S * float(FPS))):
		await process_frame

	main.call("_place_piece")

	for _i in range(int(POST_S * float(FPS))):
		await process_frame

	print("DONE")
	quit()


# 한 수가 성립하는 판을 만든다 — 줄 하나가 조각 하나 크기만큼 비어 있고, 그 줄에 적이 서 있다.
func _stage_the_move() -> void:
	var cols: int = main.get("COLS")
	var pieces: Dictionary = main.get("PIECES")

	# 트레이 첫 칸에 가로 3칸을 쥐어 준다. 가로여야 '줄을 채운다'가 한눈에 읽힌다.
	var offsets: Array = (pieces["I3h"] as Array).duplicate()
	var tray: Array = main.get("tray")
	tray[0] = {"type": "I3h", "color": "B", "offsets": offsets}
	main.set("tray", tray)
	main.set("sel", 0)

	# 놓을 자리를 겨눈다 — 이 값이 곧 화면의 미리보기(고스트)라 PRE 구간에서 의도가 보인다.
	main.set("hover_row", ROW)
	main.set("hover_col", GAP_COL)
	main.set("tut_lock", false)
	main.set("resolving", false)

	# 그 줄을 조각 자리만 남기고 채운다. 빈 칸은 정확히 고스트가 덮는 칸이어야 한다.
	var gap: Dictionary = {}
	for o in offsets:
		var ov: Vector2i = o as Vector2i
		gap[GAP_COL + ov.x] = true

	var board: Array = main.get("board")
	for c in range(cols):
		board[ROW][c] = "" if gap.has(c) else String(COLORS[(c * 3) % COLORS.size()])
	# 바로 윗줄에도 몇 칸 남겨 둔다 — 판이 '거의 다 찬' 상태로 보여야 한 수의 무게가 산다
	for c in range(cols):
		if (c % 3) != 1:
			board[ROW - 1][c] = String(COLORS[(c * 5 + 2) % COLORS.size()])
	main.set("board", board)

	# 그 줄에 적을 세운다. 조각이 들어갈 빈 칸은 피한다 — 거기 세우면 무엇이 죽는지가 안 읽힌다.
	var enemies: Array = main.get("enemies")
	var seq: int = int(main.get("enemy_seq"))
	for c in [0, 1, 6, 7]:
		if gap.has(c):
			continue
		enemies.append({
			"col": c, "row": ROW, "vis_row": float(ROW), "hp": 1, "maxhp": 1,
			"etype": "basic", "id": seq, "step_every": 3,
		})
		seq += 1
	main.set("enemies", enemies)
	main.set("enemy_seq", seq)
