extends SceneTree
# 음색 청취용 굽기 (정본: AUDIO_PLAN.md §5·§13)
#   실행: godot --headless --path . --script tools/audio_bake.gd
#   결과: build/audio_preview/*.wav  (파인더에서 더블클릭해서 듣는다)
#
# R7부터 음원은 합성이 아니라 `res://sfx/`의 CC0 파형 둘이다. 그래도 이 도구가 필요한 이유:
#   게임 안에서만 들리던 **조립 결과**(사다리·아르페지오·2단 삭제음)를 파일 하나로 만들어
#   귀로 확인해야 하기 때문이다. 낱개 파형은 그냥 sfx/ 폴더에서 들으면 된다.
#
# ⚠ .wav는 커밋하지 않는다 — build/는 .gitignore.

const OUT_DIR: String = "res://build/audio_preview"

func _init() -> void:
	var m: Node = load("res://Main.gd").new()
	m._sfx_build_bank()
	if (m._sfx_bank as Dictionary).is_empty():
		print("뱅크가 비었다 — `godot --headless --path . --import` 먼저 돌릴 것")
		m.free(); quit(1); return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 낱개 원본 둘(이름을 어휘로 바꿔 저장 — 어느 파형이 어디 쓰이는지 귀로 확인)
	for pair in [["pop_low__place_fail", "place"], ["pop_high__grab_score_tap", "grab"],
			["hit__clear", "clear"], ["shine__clear2", "clear2"]]:
		var w: AudioStreamWAV = m._sfx_bank[pair[1]]
		var path: String = "%s/%s.wav" % [OUT_DIR, pair[0]]
		if w.save_to_wav(path) == OK:
			print("  %-28s %5d 샘플 · %dHz · %d bytes" % [pair[0], w.data.size() / 2, w.mix_rate, w.data.size()])

	var lo: AudioStreamWAV = m._sfx_bank["clear"]      # 터지는 층
	var hi: AudioStreamWAV = m._sfx_bank["chain"]      # 반짝이는 층
	# ① 연쇄 사다리 — chain 파형을 5음계로 훑는다(연쇄가 음악으로 들리는지)
	_seq("%s/ladder.wav" % OUT_DIR, [[hi, 0], [hi, 2], [hi, 4], [hi, 7], [hi, 9], [hi, 12], [hi, 14], [hi, 16]], 0.11)
	# ② 판 닫는 아르페지오
	_seq("%s/fanfare.wav" % OUT_DIR, [[lo, 0], [lo, 4], [lo, 7], [lo, 12]], 0.10)
	# ③ 2단 삭제음 — 낮은 파형 타격 + 40ms 뒤 높은 파형(+9반음). 게임에선 이게 한 사건으로 들린다.
	_seq("%s/clear_2layer.wav" % OUT_DIR, [[lo, 0], [m._sfx_bank["clear2"], 0]], 0.040)
	# ④ 집기→착지 한 쌍(동작 계열)
	var g: AudioStreamWAV = m._sfx_bank["grab"]
	var pl: AudioStreamWAV = m._sfx_bank["place"]
	_seq("%s/grab_then_place.wav" % OUT_DIR, [[g, -2], [pl, 7]], 0.35)
	m.free()
	quit()

# 파형·음정 목록을 이어 붙여 한 파일로. 게임의 pitch_scale을 선형보간 리샘플로 흉내낸다.
func _seq(path: String, notes: Array, step: float) -> void:
	var rate: int = (notes[0][0] as AudioStreamWAV).mix_rate
	var step_n: int = int(step * float(rate))
	var longest: int = 0
	for nt in notes:
		longest = maxi(longest, (nt[0] as AudioStreamWAV).data.size() / 2)
	var out_n: int = step_n * notes.size() + longest + rate / 4
	var acc := PackedFloat32Array()
	acc.resize(out_n)
	for k in range(notes.size()):
		var src: AudioStreamWAV = notes[k][0]
		var n_src: int = src.data.size() / 2
		var ratio: float = pow(2.0, float(notes[k][1]) / 12.0)
		var at: int = k * step_n
		var i: int = 0
		while true:
			var sp: float = float(i) * ratio
			var si: int = int(sp)
			if si + 1 >= n_src or at + i >= out_n:
				break
			var a: float = float(_s16(src.data, si)) / 32768.0
			var b: float = float(_s16(src.data, si + 1)) / 32768.0
			acc[at + i] += lerpf(a, b, sp - float(si))
			i += 1
	# ⚠합친 뒤 피크 정규화 — 안 하면 겹친 음이 프리뷰 파일 자체를 클립시켜 음색 판정이 왜곡된다.
	var pk: float = 0.0
	for i2 in range(out_n):
		pk = maxf(pk, absf(acc[i2]))
	var g: float = (0.85 / pk) if pk > 0.0001 else 1.0
	var data := PackedByteArray()
	data.resize(out_n * 2)
	for i3 in range(out_n):
		var v: int = clampi(int(round(clampf(acc[i3] * g, -1.0, 1.0) * 32767.0)), -32768, 32767)
		if v < 0:
			v += 65536
		data[i3 * 2] = v & 0xff
		data[i3 * 2 + 1] = (v >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	w.data = data
	if w.save_to_wav(path) == OK:
		print("  %-28s %5d 샘플 (%.2fs)" % [path.get_file().get_basename(), out_n, float(out_n) / float(rate)])

func _s16(d: PackedByteArray, i: int) -> int:
	var v: int = d[i * 2] | (d[i * 2 + 1] << 8)
	return v - 65536 if v >= 32768 else v
