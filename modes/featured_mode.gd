extends "res://modes/endless_mode.gd"
# featured 결정적 트랙 감독 = EndlessMode 램프(깊이 스케줄·HP·서지·pick_etype) 그대로.
#   단 하나: 밀도 하한(floor) 훅을 끈다. floor는 enemy_count(=보드·처치수)에 반응하는
#   유일한 스폰 경로라, 켜두면 플레이어마다 스폰 시퀀스가 갈려 '전원 동일 판'이 깨진다.
#   throttle·surge·pick_etype·enemy_hp는 place_count(깊이)·spawned(인덱스)만의 함수라
#   그대로 결정적(코어가 스텝마다 (시드,깊이) 고유 rng를 ctx["rng"]에 주입).
# [[gamemode-director-seam]] 형제 슬롯 — EndlessMode를 오염 없이 상속만.
func plan_floor_spawn(_ctx: Dictionary) -> Array:
	return []
