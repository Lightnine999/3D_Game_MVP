# 스테이지 소품·장애물 로우폴리 생성 (A 소유, TECH_SPEC 5장 · 13.3.1)
# 실행: blender -b --factory-startup -P art/blender/make_stage_props.py -- <출력 폴더>
#
# 모든 모델은 원점 = 발밑 중앙, 1 unit = 1 m. 충돌은 넣지 않는다 (B가 장면에서 붙임).
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

# 팔레트 (안개·달빛 아래에서 너무 어둡지 않게 채도 낮은 중간 톤)
C_RUST = (0.36, 0.20, 0.12)
C_RUST_DARK = (0.20, 0.12, 0.08)
C_CAR_PAINT = [(0.30, 0.34, 0.30), (0.42, 0.36, 0.26), (0.26, 0.28, 0.34)]
C_GLASS = (0.08, 0.10, 0.12)
C_TIRE = (0.05, 0.05, 0.05)
C_CONCRETE = (0.40, 0.39, 0.37)
C_CONCRETE_DARK = (0.27, 0.26, 0.25)
C_BRICK = (0.34, 0.22, 0.18)
C_WOOD = (0.25, 0.19, 0.14)
C_TRASH = [(0.12, 0.12, 0.13), (0.22, 0.24, 0.20), (0.30, 0.27, 0.22), (0.18, 0.20, 0.24)]
C_DRUM = [(0.30, 0.16, 0.10), (0.18, 0.24, 0.22)]
C_TREE = (0.16, 0.13, 0.11)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


_mats = {}


def mat(rgb):
    key = tuple(round(c, 3) for c in rgb)
    if key not in _mats:
        m = bpy.data.materials.new(f"m_{len(_mats)}")
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*rgb, 1.0)
        b.inputs["Roughness"].default_value = 0.9
        _mats[key] = m
    return _mats[key]


def box(size, loc, rgb, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    o.data.materials.append(mat(rgb))
    return o


def cyl(r, depth, loc, rgb, verts=8, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(mat(rgb))
    return o


def jitter(obj, amount, seed):
    rnd = random.Random(seed)
    for v in obj.data.vertices:
        v.co += Vector((rnd.uniform(-amount, amount), rnd.uniform(-amount, amount), rnd.uniform(-amount, amount)))


def finish(name, parts):
    """부품을 합치고 변형을 적용한 뒤 .glb로 내보낸다."""
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.shade_flat()
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    path = OUT / f"{name}.glb"
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True, use_selection=True)
    print(f"[props] {name}: tris={tris} size={o.dimensions[:]}")
    bpy.ops.object.delete()


# ── 장애물: 폐차 (4.2 × 1.8 × 1.5m) ──────────────────────────────
def wreck_car(seed):
    rnd = random.Random(seed)
    paint = C_CAR_PAINT[seed % len(C_CAR_PAINT)]
    p = [box((4.2, 1.8, 0.7), (0, 0, 0.55), paint)]
    jitter(p[0], 0.05, seed)
    cab = box((2.0, 1.6, 0.6), (-0.2, 0, 1.2), paint)
    jitter(cab, 0.06, seed + 1)
    p.append(cab)
    p.append(box((1.9, 1.62, 0.45), (-0.2, 0, 1.18), C_GLASS))  # 깨진 유리
    p.append(box((0.9, 1.7, 0.08), (1.6, 0, 0.92), C_RUST, rot=(0, math.radians(-12), 0)))  # 들린 보닛
    for i, (x, y) in enumerate([(1.4, 0.85), (1.4, -0.85), (-1.4, 0.85), (-1.4, -0.85)]):
        if rnd.random() < 0.25:
            continue  # 바퀴 빠짐
        p.append(cyl(0.35, 0.25, (x, y, 0.3), C_TIRE, verts=8, rot=(math.radians(90), 0, 0)))
    p.append(box((4.25, 1.85, 0.12), (0, 0, 0.18), C_RUST_DARK))
    return p


# ── 장애물: 쓰레기 더미 (1.5 × 1.5 × 0.8m) ──────────────────────
def trash_pile(seed):
    rnd = random.Random(seed)
    p = []
    for i in range(9):
        s = rnd.uniform(0.35, 0.7)
        x, y = rnd.uniform(-0.55, 0.55), rnd.uniform(-0.55, 0.55)
        z = s * 0.4 + (0.25 if i > 5 else 0)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=s * 0.6, location=(x, y, z))
        o = bpy.context.active_object
        o.scale = (1, rnd.uniform(0.7, 1.2), rnd.uniform(0.5, 0.8))
        jitter(o, 0.06, seed * 13 + i)
        o.data.materials.append(mat(C_TRASH[rnd.randrange(len(C_TRASH))]))
        p.append(o)
    p.append(box((0.6, 0.4, 0.35), (0.4, -0.3, 0.2), C_WOOD, rot=(0, 0, 0.5)))  # 나무 상자
    return p


# ── 장애물: 폐드럼통 (지름 0.6m, 높이 0.9m) ──────────────────────
def drum(seed):
    c = C_DRUM[seed % len(C_DRUM)]
    p = [cyl(0.3, 0.9, (0, 0, 0.45), c, verts=10)]
    p.append(cyl(0.31, 0.05, (0, 0, 0.3), C_RUST_DARK, verts=10))
    p.append(cyl(0.31, 0.05, (0, 0, 0.62), C_RUST_DARK, verts=10))
    return p


# ── 외곽 폐허: 무너진 건물 벽 ─────────────────────────────────────
def ruin(seed, width, height, depth, rgb):
    rnd = random.Random(seed)
    p = []
    t = 0.35  # 벽 두께
    # 앞벽·뒷벽·옆벽 1개 (한쪽은 무너짐)
    walls = [((width, t, height), (0, -depth / 2, height / 2)),
             ((width * rnd.uniform(0.4, 0.8), t, height * rnd.uniform(0.5, 0.9)), (-width * 0.2, depth / 2, height * 0.35)),
             ((t, depth, height * rnd.uniform(0.6, 1.0)), (-width / 2, 0, height * 0.4))]
    for size, loc in walls:
        w = box(size, loc, rgb)
        # 윗면을 들쭉날쭉하게 (무너진 느낌)
        for v in w.data.vertices:
            if v.co.z > 0.2:
                v.co.z += rnd.uniform(-0.35, 0.1)
        p.append(w)
    # 창문 구멍 대신 어두운 판 (뚫린 창처럼 보이게)
    floors = max(1, int(height // 3.2))
    for f in range(floors):
        for k in range(max(1, int(width // 3))):
            x = -width / 2 + 1.5 + k * 3.0
            if x > width / 2 - 1:
                break
            if rnd.random() < 0.8:
                p.append(box((1.1, 0.05, 1.3), (x, -depth / 2 - t / 2 - 0.02, 1.6 + f * 3.2), C_GLASS))
    # 잔해 더미
    for i in range(6):
        s = rnd.uniform(0.4, 1.1)
        p.append(box((s, s * 0.8, s * 0.5), (rnd.uniform(-width / 2, width / 2), rnd.uniform(-depth / 2 - 1.5, depth / 2), s * 0.2), C_CONCRETE_DARK,
                     rot=(rnd.uniform(0, 0.4), rnd.uniform(0, 0.4), rnd.uniform(0, 3))))
    # 삐져나온 철근 기둥
    for i in range(3):
        p.append(box((0.08, 0.08, rnd.uniform(0.8, 1.8)), (rnd.uniform(-width / 2, width / 2), -depth / 2, height * 0.9), C_RUST))
    return p


# ── 죽은 나무 ─────────────────────────────────────────────────────
def dead_tree(seed):
    rnd = random.Random(seed)
    h = rnd.uniform(5, 8)
    p = [cyl(0.22, h, (0, 0, h / 2), C_TREE, verts=6)]
    jitter(p[0], 0.05, seed)
    for i in range(5):
        z = rnd.uniform(h * 0.45, h * 0.9)
        ln = rnd.uniform(1.2, 2.6)
        a = rnd.uniform(0, math.tau)
        tilt = rnd.uniform(0.6, 1.1)
        cx, cy = math.cos(a) * ln * 0.45, math.sin(a) * ln * 0.45
        p.append(cyl(0.07, ln, (cx, cy, z + ln * 0.25), C_TREE, verts=5, rot=(tilt * math.sin(a), -tilt * math.cos(a) * -1, 0)))
    return p


# ── 전봇대 ─────────────────────────────────────────────────────────
def power_pole(seed):
    p = [cyl(0.14, 9.0, (0, 0, 4.5), C_WOOD, verts=6)]
    p.append(box((2.2, 0.14, 0.14), (0, 0, 8.3), C_WOOD))
    p.append(box((1.4, 0.12, 0.12), (0, 0, 7.6), C_WOOD))
    for x in (-0.9, 0.9, -0.5, 0.5):
        p.append(cyl(0.05, 0.18, (x, 0, 8.45), C_CONCRETE, verts=5))
    return p


# ── 부서진 나무 울타리 한 칸 (길이 3m) ─────────────────────────────
def fence(seed):
    rnd = random.Random(seed)
    p = []
    for x in (-1.5, 0, 1.5):
        h = rnd.uniform(0.9, 1.3)
        p.append(box((0.12, 0.12, h), (x, 0, h / 2), C_WOOD, rot=(rnd.uniform(-0.1, 0.1), rnd.uniform(-0.15, 0.15), 0)))
    for z in (0.45, 0.9):
        if rnd.random() < 0.8:
            p.append(box((3.0, 0.05, 0.14), (0, 0.07, z), C_WOOD, rot=(0, rnd.uniform(-0.12, 0.12), 0)))
    return p


BUILDS = {
    "obs_wreck_car": lambda: wreck_car(1),
    "obs_wreck_car_b": lambda: wreck_car(2),
    "obs_trash": lambda: trash_pile(3),
    "obs_trash_b": lambda: trash_pile(4),
    "obs_drum": lambda: drum(0),
    "prop_ruin_a": lambda: ruin(11, 9.0, 7.0, 6.0, C_CONCRETE),
    "prop_ruin_b": lambda: ruin(12, 6.0, 10.0, 5.0, C_BRICK),
    "prop_ruin_c": lambda: ruin(13, 12.0, 4.5, 7.0, C_CONCRETE_DARK),
    "prop_tree_dead": lambda: dead_tree(21),
    "prop_tree_dead_b": lambda: dead_tree(22),
    "prop_power_pole": lambda: power_pole(31),
    "prop_fence": lambda: fence(41),
}

for name, fn in BUILDS.items():
    reset()
    _mats.clear()
    finish(name, fn())
