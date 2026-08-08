extends SceneTree
# 무한 연출 **동영상** 캡처 — 프레임을 한 장씩 뽑아 두면 밖에서 GIF로 엮는다.
#   godot --path . --script tools/endless_juice_movie.gd -- <출력디렉터리>
#   ⚠창 모드 필수([[godot-pixel-verify-needs-window]]).
#
# 스틸(endless_juice_shots.gd)과 다른 점 = **상태를 직접 안 박는다.**
#   타이머만 꽂고 `_process`를 고정 delta로 돌려, 실제 재생과 같은 경로로 프레임을 만든다.
#   그래야 "이 값에서 이렇게 보인다"가 아니라 "실제로 이렇게 흐른다"를 볼 수 있다.
#   ⚠process_mode는 내내 DISABLED로 두고 `_process`를 손으로 부른다 —
#     엔진이 자기 delta로 또 돌면 프레임 간격이 들쭉날쭉해져 GIF 속도가 어긋난다.

const FPS: float = 30.0

var g: Node = null
var out_dir: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _frame(tag: String, i: int) -> void:
	g.call("queue_redraw")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s%s_%03d.png" % [out_dir, tag, i])

# ⚠프레임 번호는 태그별 **누적**이어야 한다 — 매번 0부터 쓰면 두 번째 _roll이 첫 번째를 덮는다
#   (전이 '직전' 비교 프레임이 통째로 사라졌다).
var _seq: Dictionary = {}

func _roll(tag: String, frames: int) -> void:
	var start: int = int(_seq.get(tag, 0))
	for i in range(frames):
		g.call("_process", 1.0 / FPS)
		await _frame(tag, start + i)
	_seq[tag] = start + frames
	print("%s: %d..%d" % [tag, start, start + frames - 1])

func _base() -> void:
	g.call("seed_game", 771)
	g.call("_start_endless")
	g.set("persist_enabled", false)
	g.set("dda_enabled", false)
	await process_frame
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.set("mode", "play")

func _run() -> void:
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = uargs[0] if uargs.size() > 0 else "/tmp/"
	if not out_dir.ends_with("/"):
		out_dir += "/"
	g = load("res://Main.tscn").instantiate()
	root.add_child(g)
	await process_frame

	# ── ① 존 전이(파문) ── 존 1→2를 넘는 순간. 점수를 직접 올려 `_add_endless_score`가
	#   엣지에서 zone_trans_t를 켜게 둔다(타이머를 손으로 안 박는다 = 실제 경로).
	await _base()
	g.set("endless_score", 11800)
	g.set("endless_score_shown", 11800.0)
	g.set("zone_index", 1)
	g.set("zone_mix", 1.0)
	g.set("zone_col", Color("#2a2470"))
	await _roll("zone", 10)                 # 전이 직전 몇 프레임(비교 기준)
	g.call("_add_endless_score", 400)      # 12,000 돌파 → 존 2 진입 비트 발화
	await _roll("zone", 54)                # 1.3초 전이 + 여유

	# ── ② PB 돌파 ── 표시 점수가 최고를 넘게 두면 _process가 pb_pop_t를 켠다.
	await _base()
	g.set("endless_best", 12000)
	g.set("endless_prev_best", 12000)
	g.set("zone_index", 2)
	g.set("zone_mix", 1.0)
	g.set("zone_col", Color("#382178"))
	g.set("endless_score", 18400)
	g.set("endless_score_shown", 11700.0)  # 롤업이 12,000을 넘어가며 발화
	await _roll("pb", 62)

	print("DONE")
	quit()
