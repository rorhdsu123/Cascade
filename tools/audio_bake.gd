extends SceneTree
# 음색 청취용 굽기 (정본: AUDIO_PLAN.md §5)
#   실행: godot --headless --path . --script tools/audio_bake.gd
#   결과: build/audio_preview/*.wav  (파인더에서 더블클릭해서 듣는다)
#
# 왜 필요한가: 소리는 코드 리뷰로 판정할 수 없다. 합성음이 값싸게 들리는지, place가 거슬리는지,
#   연쇄 사다리가 음악으로 들리는지는 **사람 귀로만** 답이 나온다. 그래서 게임을 켜지 않고도
#   어휘를 듣고 상수를 고칠 수 있게 파일로 뽑아 둔다(튜닝 왕복을 짧게).
#
# 단어 파일 넷 + 조립 파일 둘:
#   ladder.wav  = chain 사다리 8단을 순서대로(연쇄가 음악으로 들리는지 판정)
#   fanfare.wav = clear 0/+4/+7/+12 아르페지오(판 닫는 소리)
# ⚠ .wav는 커밋하지 않는다 — build/는 .gitignore. 산출물이 아니라 청취용 스크래치다.

const OUT_DIR: String = "res://build/audio_preview"

func _init() -> void:
	var m: Node = load("res://Main.gd").new()
	m._sfx_build_bank()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rate: int = m.SFX_RATE

	var n_ok: int = 0
	for kind in ["place", "clear", "chain", "tap"]:
		var w: AudioStreamWAV = m._sfx_bank[kind]
		var path: String = "%s/%s.wav" % [OUT_DIR, kind]
		if w.save_to_wav(path) == OK:
			n_ok += 1
			print("  %-8s %5d 샘플 (%.3fs, %d bytes)" % [kind, w.data.size() / 2,
					float(w.data.size() / 2) / float(rate), w.data.size()])
		else:
			print("  %-8s SAVE FAILED" % kind)

	# 조립 둘 — 게임 안에서만 들리던 '시퀀스'를 파일 하나로 만들어 듣는다.
	_seq(m, "%s/ladder.wav" % OUT_DIR, "chain",
			[0, 2, 4, 7, 9, 12, 14, 16], 0.11, rate)
	_seq(m, "%s/fanfare.wav" % OUT_DIR, "clear", [0, 4, 7, 12], 0.10, rate)

	var total: int = 0
	for kind in m._sfx_bank:
		total += (m._sfx_bank[kind] as AudioStreamWAV).data.size()
	print("── 단어 %d개 저장, 뱅크 총 %d bytes (%.1f KB)" % [n_ok, total, float(total) / 1024.0])
	print("── 들어보기: open %s" % ProjectSettings.globalize_path(OUT_DIR))
	m.free()
	quit()

# 한 단어를 여러 음정으로 이어 붙여 한 파일로 굽는다(게임의 pitch_scale을 리샘플로 흉내).
#   선형 보간 리샘플 — 청취용이라 품질보다 '순서·간격이 맞나'가 중요하다.
func _seq(m: Node, path: String, kind: String, semis: Array, step: float, rate: int) -> void:
	var src: AudioStreamWAV = m._sfx_bank[kind]
	var n_src: int = src.data.size() / 2
	var step_n: int = int(step * float(rate))
	var out_n: int = step_n * semis.size() + n_src + rate / 4
	var acc: PackedFloat32Array = PackedFloat32Array()
	acc.resize(out_n)
	for k in range(semis.size()):
		var ratio: float = pow(2.0, float(semis[k]) / 12.0)
		var at: int = k * step_n
		var i: int = 0
		while true:
			var sp: float = float(i) * ratio      # 피치 업 = 원본을 빨리 읽는다
			var si: int = int(sp)
			if si + 1 >= n_src or at + i >= out_n:
				break
			var a: float = float(_s16(src.data, si)) / 32768.0
			var b: float = float(_s16(src.data, si + 1)) / 32768.0
			acc[at + i] += lerpf(a, b, sp - float(si))
			i += 1

	var data := PackedByteArray()
	data.resize(out_n * 2)
	for i in range(out_n):
		var v: int = clampi(int(round(clampf(acc[i], -1.0, 1.0) * 32767.0)), -32768, 32767)
		if v < 0:
			v += 65536
		data[i * 2] = v & 0xff
		data[i * 2 + 1] = (v >> 8) & 0xff
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	w.data = data
	if w.save_to_wav(path) == OK:
		print("  %-8s %5d 샘플 (%.3fs) — %s" % [path.get_file().get_basename(), out_n,
				float(out_n) / float(rate), str(semis)])
	else:
		print("  %s SAVE FAILED" % path)

func _s16(d: PackedByteArray, i: int) -> int:
	var v: int = d[i * 2] | (d[i * 2 + 1] << 8)
	return v - 65536 if v >= 32768 else v
