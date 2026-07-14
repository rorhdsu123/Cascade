extends SceneTree
# 적 색 ↔ 조각 색 충돌 검증 — 4개 적 타입을 R/B/Y 블록과 빈 칸 위에 각각 세워 렌더한다.
# 원래 버그: C_RED과 C_E_BASIC이 헥스까지 같아(#e5484d) 빨간 블록 위 기본 적이 묻혔다.
# 실행: godot --path . --script tools/color_probe.gd   (창 모드 필수 — headless는 렌더 텍스처가 null)

const OUT: String = "/private/tmp/claude-501/-Users-im-yujin-Desktop-Cascade/98a1100f-49fc-42c1-9cb4-a221c1201840/scratchpad/color"

# 행 = 배경(조각 색), 열 = 적 타입
const BANDS: Array = ["R", "B", "Y", ""]
const TYPES: Array = ["basic", "tank", "fast", "swarm"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_start_stage", 0)
	await process_frame

	# 배경: 행 0~3 = R/B/Y/빈칸 밴드 (각 밴드는 8칸 통째로 채운다)
	var board: Array = main.get("board")
	for r in range(8):
		for c in range(8):
			board[r][c] = String(BANDS[r]) if r < BANDS.size() else ""
	main.set("board", board)

	# 적: 각 밴드 위에 4타입을 col 1/3/5/7에 배치. 전진·연출은 멈춘다(step_every 큼).
	# HP는 실제 스테이지 값에 가깝게 — 탱크는 3자리(256)라 게이지 안에서 하트와 부딪힐 수 있다.
	var hp_of: Dictionary = {"basic": 65, "tank": 256, "fast": 39, "swarm": 26}
	var enemies: Array = []
	var eid: int = 700
	for r in range(BANDS.size()):
		for t in range(TYPES.size()):
			eid += 1
			var ty0: String = String(TYPES[t])
			enemies.append({
				"id": eid, "col": 1 + t * 2, "row": r, "vis_row": float(r),
				"hp": int(hp_of[ty0]), "maxhp": int(hp_of[ty0]), "etype": ty0,
				"step_every": 9999, "flinch": 0.0,
			})
	# 반피 basic — 저HP 명암이 어두워질 때 빨강/탱크로 안 읽히는지 확인
	eid += 1
	enemies.append({"id": eid, "col": 0, "row": 5, "vis_row": 5.0,
			"hp": 3, "maxhp": 30, "etype": "basic", "step_every": 9999, "flinch": 0.0})
	main.set("enemies", enemies)

	main.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + "_grid.png")

	# 픽셀 실측.
	#  - 배경 표본 = 적이 없는 '옆 셀'(짝수 열)의 블록 채움. 탱크는 제 셀을 거의 다 덮어서
	#    같은 셀에선 깨끗한 배경 픽셀이 안 나온다(첫 시도에서 배경 표본이 탱크 위에 찍혔다).
	#  - 몸통 표본 = 타입별 실제 채움 좌표(중심에서 살짝 위 = HP 바·HP 숫자를 피함).
	#    스웜은 점 사이에 빈틈이 있어 점 중심을 직접 찍는다.
	# 거리가 작을수록 '묻힌다'. 원래 버그(빨강 블록 위 기본 적)는 여기서 0.00이 나와야 한다.
	var body: Dictionary = {
		"basic": Vector2(32, 20),   # 원 내부
		"tank": Vector2(32, 20),    # 사각 내부
		"fast": Vector2(32, 26),    # 삼각 내부
		"swarm": Vector2(22, 24),   # 왼쪽 위 점의 중심
	}
	print("행=배경(조각색) / 열=적타입.  sep = 적 몸통색 ↔ 블록 색 RGB 거리 (0=같은 색)")
	for r in range(BANDS.size()):
		var bg_name: String = String(BANDS[r]) if String(BANDS[r]) != "" else "빈칸"
		var line: String = "  %-4s |" % bg_name
		for t in range(TYPES.size()):
			var col: int = 1 + t * 2
			var ty: String = String(TYPES[t])
			# 왼쪽 옆 셀(col−1 = 짝수, 적 없음) 중심 = 순수 블록 색.
			# col+1을 쓰면 swarm(col 7)에서 보드 밖(x=688)을 찍는다.
			var bgp: Color = img.get_pixel(144 + (col - 1) * 64 + 32, 150 + r * 64 + 32)
			var bo: Vector2 = body[ty] as Vector2
			var ep: Color = img.get_pixel(144 + col * 64 + int(bo.x), 150 + r * 64 + int(bo.y))
			var d: float = Vector3(ep.r - bgp.r, ep.g - bgp.g, ep.b - bgp.b).length()
			line += " %s %.2f |" % [ty.substr(0, 5).rpad(5), d]
		print(line)
	print("DONE")
	quit()
