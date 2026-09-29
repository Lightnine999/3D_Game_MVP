# 배경·장애물 소품 생성 (A 소유, TECH_SPEC 5.1 단계 2 · 13.3.1 ①-2)
# 실행: blender -b --factory-startup -P art/blender/make_env_props.py -- <출력 폴더>
#
# 비유: 레고 블록(상자·원기둥·덩어리)을 쌓아서 소품을 조립한다.
# 1,000m 맵 전체를 여기서 만들지 않는다. 작은 부품만 만들고, 배치는 Godot이 한다.
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import common as c  # noqa: E402

RUST = (0.32, 0.17, 0.09)
RUST_DARK = (0.18, 0.10, 0.06)
PAINT_FADED = (0.35, 0.33, 0.28)
TIRE = (0.05, 0.05, 0.05)
GLASS = (0.08, 0.10, 0.11)
CONCRETE = (0.30, 0.28, 0.25)
CONCRETE_DARK = (0.17, 0.16, 0.15)
BRICK = (0.28, 0.14, 0.10)
WOOD_DARK = (0.14, 0.10, 0.07)
BARK = (0.09, 0.07, 0.05)
PINE = (0.05, 0.07, 0.05)
TRASH = [(0.06, 0.06, 0.07), (0.20, 0.19, 0.15), (0.13, 0.15, 0.12), (0.25, 0.20, 0.12)]


def make_wreck_car(rng):
    """장애물: 폐차 (4.2 × 1.8 × 1.5m, TECH_SPEC 13.3.1)."""
    body_m, dark_m = c.material("car_body", PAINT_FADED), c.material("car_rust", RUST)
    parts = [
        c.box((4.2, 1.8, 0.75), (0, 0, 0.55), mat=body_m),
        c.box((2.2, 1.65, 0.6), (-0.2, 0, 1.2), mat=body_m),
        c.box((2.0, 1.7, 0.45), (-0.2, 0, 1.18), mat=c.material("car_glass", GLASS)),
        c.box((0.9, 1.82, 0.3), (1.6, 0, 0.72), mat=dark_m),
        c.box((0.6, 1.0, 0.1), (-1.2, 0.3, 1.52), rotation=(0.2, 0, 0.3), mat=dark_m),
    ]
    tire_m = c.material("car_tire", TIRE)
    for x, y in [(1.35, 0.85), (-1.35, 0.85), (1.35, -0.85), (-1.35, -0.85)]:
        if rng.random() < 0.25:
            continue  # 바퀴 하나쯤은 빠져 있다
        parts.append(c.cylinder(0.36, 0.28, (x, y, 0.36), (math.pi / 2, 0, 0), tire_m, vertices=10))
    car = c.join(parts, "obs_wreck_car")
    car.rotation_euler = (0.03, -0.04, 0)
    return car


def make_trash(rng):
    """장애물: 쓰레기 더미 (1.5 × 1.5 × 0.8m)."""
    parts = []
    for _ in range(11):
        col = c.material(f"trash_{rng.randrange(len(TRASH))}", rng.choice(TRASH))
        r = rng.uniform(0.18, 0.38)
        loc = (rng.uniform(-0.55, 0.55), rng.uniform(-0.55, 0.55), rng.uniform(0.1, 0.45))
        parts.append(c.blob(r, loc, (1.0, 1.0, rng.uniform(0.6, 0.9)), col, rng=rng))
    crate = c.material("trash_crate", WOOD_DARK)
    for _ in range(3):
        loc = (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0.2)
        parts.append(c.box((0.45, 0.35, 0.35), loc, (0, rng.uniform(0, 0.5), rng.uniform(0, 3)), crate))
    return c.join(parts, "obs_trash")


def make_drum(rng):
    """장애물: 폐드럼통 (지름 0.6m, 높이 0.9m)."""
    m = c.material("drum_rust", RUST if rng.random() < 0.6 else (0.12, 0.16, 0.20))
    parts = [c.cylinder(0.3, 0.9, (0, 0, 0.45), mat=m, vertices=14)]
    rim = c.material("drum_rim", RUST_DARK)
    for z in (0.28, 0.62):
        parts.append(c.cylinder(0.31, 0.04, (0, 0, z), mat=rim, vertices=14))
    return c.join(parts, "obs_drum")


def _ruin_wall(length, height, rng, mat, origin, angle):
    """부서진 벽 하나: 1m 블록을 쌓되 창문 구멍과 무너진 윗단을 만든다."""
    blocks = []
    cols = max(2, int(length))
    top = [max(1, height - rng.choice([0, 0, 1, 2, 3])) for _ in range(cols)]
    for i in range(cols):
        for z in range(top[i]):
            window = z in (1, 2) and i % 3 == 1 and rng.random() < 0.85
            if window:
                continue
            lx = i - cols / 2 + 0.5
            x = origin[0] + lx * math.cos(angle)
            y = origin[1] + lx * math.sin(angle)
            blocks.append(c.box((1.0, 0.35, 1.0), (x, y, z + 0.5), (0, 0, angle), mat))
    return blocks


def make_ruin(rng, name, w, d, h):
    """좌우 외곽 폐허: 벽 3-4면이 부서진 건물 껍데기 + 잔해."""
    wall_m = c.material("ruin_wall", rng.choice([CONCRETE, BRICK]))
    dark_m = c.material("ruin_rubble", CONCRETE_DARK)
    parts = []
    walls = [((0, -d / 2), 0, w), ((0, d / 2), 0, w), ((-w / 2, 0), math.pi / 2, d), ((w / 2, 0), math.pi / 2, d)]
    for idx, (origin, angle, length) in enumerate(walls):
        if idx == 1 and rng.random() < 0.5:
            continue  # 뒷벽 한 면은 무너져 없다
        parts += _ruin_wall(length, h, rng, wall_m, origin, angle)
    for _ in range(8):
        loc = (rng.uniform(-w / 2, w / 2), rng.uniform(-d / 2 - 1.5, d / 2 + 1.5), 0.25)
        parts.append(c.blob(rng.uniform(0.3, 0.7), loc, (1.3, 1.0, 0.6), dark_m, rng=rng))
    return c.join(parts, name)


def make_dead_tree(rng):
    """마른 나무 (키 7m 안팎, 실루엣용)."""
    m = c.material("bark", BARK)
    parts = [c.cylinder(0.28, 6.5, (0, 0, 3.25), mat=m, vertices=7, radius_top=0.06)]
    for _ in range(6):
        z = rng.uniform(2.8, 5.8)
        yaw, pitch = rng.uniform(0, math.tau), rng.uniform(0.6, 1.1)
        length = rng.uniform(1.4, 2.6)
        dx = math.sin(pitch) * math.cos(yaw) * length / 2
        dy = math.sin(pitch) * math.sin(yaw) * length / 2
        parts.append(c.cylinder(0.08, length, (dx, dy, z + math.cos(pitch) * length / 2),
                                (pitch * math.sin(yaw) * -1, pitch * math.cos(yaw), 0), m, vertices=5, radius_top=0.02))
    return c.join(parts, "prop_tree_dead")


def make_pine(rng):
    """침엽수 실루엣 (키 12m 안팎). 먼 거리 숲 줄에 쓴다."""
    parts = [c.cylinder(0.25, 3.0, (0, 0, 1.5), mat=c.material("bark", BARK), vertices=6)]
    m = c.material("pine", PINE)
    for i, (r, z) in enumerate([(2.6, 4.0), (2.1, 6.2), (1.5, 8.3), (0.9, 10.2)]):
        parts.append(c.cylinder(r, 3.2 - i * 0.3, (0, 0, z), mat=m, vertices=7, radius_top=0.1))
    return c.join(parts, "prop_tree_pine")


def make_power_pole(rng):
    """전봇대 (8m). 전선은 Godot에서 기둥 사이에 잇는다 (꼭대기 가로대 높이 7.6m)."""
    m = c.material("pole_wood", WOOD_DARK)
    parts = [c.cylinder(0.14, 8.0, (0, 0, 4.0), mat=m, vertices=8),
             c.box((2.2, 0.14, 0.14), (0, 0, 7.6), mat=m),
             c.box((0.12, 0.3, 0.12), (0.9, 0, 7.75), mat=c.material("insulator", (0.25, 0.25, 0.25))),
             c.box((0.12, 0.3, 0.12), (-0.9, 0, 7.75), mat=c.material("insulator", (0.25, 0.25, 0.25)))]
    return c.join(parts, "prop_power_pole")


def make_fence(rng):
    """부서진 나무 울타리 한 칸 (길이 3m)."""
    m = c.material("fence_wood", (0.20, 0.15, 0.10))
    parts = [c.box((0.12, 0.12, 1.2), (x, 0, 0.6), (0, rng.uniform(-0.12, 0.12), 0), m) for x in (-1.5, 0, 1.5)]
    for z in (0.45, 0.95):
        if rng.random() < 0.8:
            parts.append(c.box((3.0, 0.05, 0.14), (0, 0.07, z), (0, rng.uniform(-0.06, 0.06), 0), m))
    return c.join(parts, "prop_fence")


def make_rock(rng):
    return c.join([c.blob(0.7, (0, 0, 0.3), (1.4, 1.0, 0.7), c.material("rock", CONCRETE_DARK), subdivisions=2, rng=rng)], "prop_rock")


def main():
    out_dir = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    builders = [
        ("obs_wreck_car", make_wreck_car), ("obs_trash", make_trash), ("obs_drum", make_drum),
        ("prop_ruin_a", lambda r: make_ruin(r, "prop_ruin_a", 8, 6, 5)),
        ("prop_ruin_b", lambda r: make_ruin(r, "prop_ruin_b", 12, 8, 7)),
        ("prop_ruin_c", lambda r: make_ruin(r, "prop_ruin_c", 6, 5, 4)),
        ("prop_tree_dead", make_dead_tree), ("prop_tree_pine", make_pine),
        ("prop_power_pole", make_power_pole), ("prop_fence", make_fence), ("prop_rock", make_rock),
    ]
    for seed, (name, build) in enumerate(builders):
        c.reset_scene()
        obj = build(random.Random(1000 + seed))
        path = c.export_glb(obj, out_dir, name)
        dims = tuple(round(v, 2) for v in obj.dimensions)
        print(f"[props] {name}: tris={c.triangle_count(obj)} size={dims} -> {path.name}")


if __name__ == "__main__":
    main()
