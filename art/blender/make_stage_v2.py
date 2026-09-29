# 스테이지 v2 소품 생성 — 새 콘셉트(분홍 노을 + 청회색 안개 + 앙상한 숲 + 폐허 마을) (A 소유)
# 실행: blender -b --factory-startup -P art/blender/make_stage_v2.py -- <출력 폴더>
#
# 비유: 레고 블록(상자·원기둥·원뿔)을 코드로 쌓아서 소품을 조립한다.
# 재질 이름 앞부분(wood_, rust_, concrete_, metal_, fabric_, dark_, glow_)을 보고
# Godot이 질감(나무판자·녹·콘크리트)을 씌운다 → scripts/stage/stage_materials.gd
#
# 규격: 1 unit = 1 m, 원점 = 발밑 중앙, 충돌 없음 (TECH_SPEC 13.3.1)
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

# 재질: (이름, 색) — 색은 질감이 없을 때의 기본색 겸 질감에 곱해지는 색
MATS = {
    "wood_siding": (0.30, 0.29, 0.27),
    "wood_dark": (0.12, 0.10, 0.09),
    "wood_crate": (0.33, 0.24, 0.15),
    "rust_body": (0.30, 0.15, 0.08),
    "rust_dark": (0.14, 0.07, 0.04),
    "rust_drum": (0.40, 0.17, 0.07),
    "paint_bus": (0.55, 0.40, 0.10),
    "metal_dark": (0.06, 0.06, 0.07),
    "concrete": (0.34, 0.34, 0.35),
    "concrete_dark": (0.18, 0.18, 0.19),
    "fabric_red": (0.40, 0.12, 0.10),
    "fabric_blue": (0.10, 0.15, 0.24),
    "fabric_brown": (0.28, 0.16, 0.10),
    "dark_void": (0.015, 0.015, 0.02),      # 창문·문 구멍 (안이 어둡게)
    "dark_tire": (0.03, 0.03, 0.03),
    "bark": (0.09, 0.085, 0.08),
    "sign_board": (0.62, 0.60, 0.55),
    "glow_lamp": (1.0, 0.95, 0.8),          # 투광등 (Godot에서 빛나게)
    "glow_window": (1.0, 0.62, 0.30),       # 불 켜진 창문 하나
}


class Builder:
    """bmesh 하나에 상자·관을 쌓고, 재질 번호를 면마다 붙인다."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _tag(self, before, mat):
        self.bm.faces.ensure_lookup_table()
        idx = self._mi(mat)
        for f in self.bm.faces[before:]:
            f.material_index = idx

    def box(self, center, size, mat, rot=(0, 0, 0)):
        before = len(self.bm.faces)
        m = Matrix.Translation(Vector(center)) @ _euler(rot) @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._tag(before, mat)

    def tube(self, p0, p1, r0, r1, mat, sides=6, caps=True):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        length = d.length
        if length < 1e-4:
            return
        rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        m = Matrix.Translation((p0 + p1) / 2) @ rot
        before = len(self.bm.faces)
        bmesh.ops.create_cone(self.bm, cap_ends=caps, segments=sides, radius1=r0, radius2=r1, depth=length, matrix=m)
        self._tag(before, mat)

    def blob(self, center, radius, scale, mat, subdiv=1):
        before = len(self.bm.faces)
        m = Matrix.Translation(Vector(center)) @ _euler((random.random() * 3, random.random() * 3, random.random() * 3)) @ Matrix.Diagonal((*scale, 1.0))
        bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius, matrix=m)
        self._tag(before, mat)

    def export(self, name, ground=True):
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for mname in self.mats:
            mesh.materials.append(_material(mname))
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if ground:   # 원점 = 발밑 중앙
            xs = [v.co.x for v in mesh.vertices]
            ys = [v.co.y for v in mesh.vertices]
            zmin = min(v.co.z for v in mesh.vertices)
            off = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, zmin))
            for v in mesh.vertices:
                v.co -= off
        for p in mesh.polygons:
            p.use_smooth = False
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = OUT / f"{name}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True, use_selection=True)
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        dims = [round(d, 2) for d in obj.dimensions]
        print(f"[v2] {name}: tris={tris} size={dims}")
        bpy.data.objects.remove(obj)


def _euler(rot):
    from mathutils import Euler
    return Euler(rot, "XYZ").to_matrix().to_4x4()


def _material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*MATS[name], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.92
    if name.startswith("glow_"):
        bsdf.inputs["Emission Color"].default_value = (*MATS[name], 1.0)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ══════════════════════════════════════════════════════════════════
# 앙상한 나무 — 가지를 재귀적으로 뻗는다 (콘셉트의 핵심 실루엣)
# ══════════════════════════════════════════════════════════════════
def bare_tree(name, seed, height, spread, depth=4):
    reset()
    random.seed(seed)
    b = Builder()

    def branch(p0, direction, length, radius, level):
        # 가지를 3토막으로 살짝 휘게
        pts = [Vector(p0)]
        d = Vector(direction).normalized()
        for k in range(3):
            d = (d + Vector((random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25), random.uniform(-0.05, 0.12)))).normalized()
            pts.append(pts[-1] + d * (length / 3))
        radii = [radius * (1 - 0.22 * k) for k in range(4)]
        sides = 6 if level == 0 else (4 if level < 3 else 3)
        for k in range(3):
            b.tube(pts[k], pts[k + 1], radii[k], radii[k + 1], "bark", sides=sides, caps=False)
        if level >= depth:
            return
        n = random.randint(2, 4) if level > 0 else random.randint(4, 6)
        for _ in range(n):
            t = random.uniform(0.35, 0.95) if level > 0 else random.uniform(0.35, 0.9)
            seg = min(int(t * 3), 2)
            origin = pts[seg].lerp(pts[seg + 1], t * 3 - seg)
            axis = Vector((random.uniform(-1, 1), random.uniform(-1, 1), 0)).normalized()
            pitch = random.uniform(0.45, 0.95) * spread
            nd = (Matrix.Rotation(pitch, 3, axis) @ d).normalized()
            nd.z = max(nd.z, 0.15)
            branch(origin, nd, length * random.uniform(0.55, 0.72), radius * random.uniform(0.45, 0.6), level + 1)

    lean = Vector((random.uniform(-0.08, 0.08), random.uniform(-0.08, 0.08), 1.0))
    branch((0, 0, 0), lean, height, height * 0.035, 0)
    # 뿌리 부분 두껍게
    b.tube((0, 0, -0.1), (0, 0, 0.6), height * 0.05, height * 0.035, "bark", sides=6)
    b.export(name)


# ══════════════════════════════════════════════════════════════════
# 목조 주택 — 벽·창문(어두운 구멍)·베란다·부서진 지붕
# ══════════════════════════════════════════════════════════════════
def _windows(b, face_y, xs, zs, w=1.0, h=1.4, sign=-1, lit=None):
    for x in xs:
        for z in zs:
            mat = "glow_window" if lit == (x, z) else "dark_void"
            b.box((x, face_y + sign * 0.06, z), (w, 0.1, h), mat)
            b.box((x, face_y + sign * 0.1, z + h / 2 + 0.06), (w + 0.25, 0.08, 0.12), "wood_dark")   # 창틀 위
            b.box((x, face_y + sign * 0.1, z - h / 2 - 0.06), (w + 0.25, 0.14, 0.1), "wood_dark")    # 창틀 아래


def _gable_roof(b, w, d, z0, pitch, broken, seed):
    random.seed(seed)
    half = w / 2 + 0.4
    rise = math.tan(pitch) * half
    slab = half / math.cos(pitch)
    n = 6
    for side in (-1, 1):
        for k in range(n):                                   # 지붕을 길이 방향으로 6조각 → 일부 빠뜨려 구멍
            if broken and random.random() < 0.28 and 0 < k < n - 1:
                for r in range(3):                           # 드러난 서까래
                    y = -d / 2 + (k + (r + 0.5) / 3) * d / n
                    b.box((side * half / 2, y, z0 + rise / 2), (0.08, 0.1, slab), "wood_dark", rot=(0, side * (math.pi / 2 - pitch), 0))
                continue
            y = -d / 2 - 0.3 + (k + 0.5) * (d + 0.6) / n
            b.box((side * half / 2, y, z0 + rise / 2), (slab + 0.2, (d + 0.6) / n + 0.02, 0.14), "wood_dark",
                  rot=(0, -side * pitch, 0))
    # 박공벽(삼각형)을 계단식 상자로
    for s in range(5):
        hh = rise * (1 - s / 5)
        ww = w * (1 - s / 5)
        for y in (-d / 2, d / 2):
            b.box((0, y, z0 + rise * s / 5 + rise / 10), (ww, 0.2, rise / 5), "wood_siding")
    return rise


def house(name, seed, w, d, floors, porch=True, broken=True, lit_window=False):
    reset()
    random.seed(seed)
    b = Builder()
    fh = 3.0
    H = floors * fh
    b.box((0, 0, 0.3), (w + 0.3, d + 0.3, 0.6), "concrete_dark")                 # 기초
    b.box((0, 0, 0.6 + H / 2), (w, d, H), "wood_siding")                           # 몸체
    for z in [0.6 + k * fh for k in range(1, floors)]:                               # 층 사이 띠
        b.box((0, 0, z), (w + 0.12, d + 0.12, 0.18), "wood_dark")
    for x in (-w / 2, w / 2):                                                        # 모서리 기둥
        for y in (-d / 2, d / 2):
            b.box((x, y, 0.6 + H / 2), (0.22, 0.22, H), "wood_dark")
    xs = [(-w / 2 + (i + 0.5) * w / 3) for i in range(3)]
    zs = [0.6 + k * fh + 1.6 for k in range(floors)]
    lit = (xs[2], zs[-1]) if lit_window else None
    _windows(b, -d / 2, xs, zs, lit=lit)
    _windows(b, d / 2, xs, zs, sign=1)
    b.box((xs[1], -d / 2 - 0.06, 0.6 + 1.1), (1.1, 0.12, 2.2), "dark_void")        # 현관문 구멍
    _gable_roof(b, w, d, 0.6 + H, math.radians(38), broken, seed)
    if porch:                                                                          # 앞 베란다
        pd = 2.2
        b.box((0, -d / 2 - pd / 2, 0.45), (w, pd, 0.18), "wood_dark")
        for x in [-w / 2 + 0.2 + i * (w - 0.4) / 3 for i in range(4)]:
            b.box((x, -d / 2 - pd + 0.15, 0.55 + 1.35), (0.16, 0.16, 2.7), "wood_dark")
        b.box((0, -d / 2 - pd / 2, 3.35), (w + 0.2, pd + 0.2, 0.14), "wood_dark", rot=(math.radians(-8), 0, 0))
        for i in range(10):                                                            # 난간 살 (일부 빠짐)
            if random.random() < 0.3:
                continue
            x = -w / 2 + 0.3 + i * (w - 0.6) / 9
            b.box((x, -d / 2 - pd + 0.15, 1.0), (0.06, 0.06, 0.9), "wood_dark")
        b.box((0, -d / 2 - pd + 0.15, 1.45), (w - 0.2, 0.08, 0.08), "wood_dark")
    if broken:                                                                         # 떨어져 나간 판자
        for _ in range(8):
            b.box((random.uniform(-w / 2, w / 2), random.uniform(-d / 2 - 3, -d / 2 - 0.5), 0.05),
                  (random.uniform(0.8, 2.0), 0.18, 0.04), "wood_siding", rot=(0, 0, random.random() * 3))
    b.export(name)


# ══════════════════════════════════════════════════════════════════
# 차량 — 세단·픽업·스쿨버스·박스트럭 (녹슨 차체 + 어두운 창 + 바퀴)
# ══════════════════════════════════════════════════════════════════
def _wheels(b, xs, y, r, missing=()):
    for i, x in enumerate(xs):
        for side in (-1, 1):
            if (i, side) in missing:
                continue
            b.tube((x, side * y - 0.12, r), (x, side * y + 0.12, r), r, r, "dark_tire", sides=10)


def car_sedan(name, seed):
    reset(); random.seed(seed); b = Builder()
    b.box((0, 0, 0.62), (4.5, 1.8, 0.62), "rust_body")                              # 차체
    b.box((-0.15, 0, 1.2), (2.3, 1.66, 0.55), "rust_body")                         # 실내
    b.box((0.95, 0, 1.18), (0.1, 1.5, 0.48), "dark_void", rot=(0, 0.55, 0))        # 앞유리 (깨져 어둡게)
    b.box((-1.35, 0, 1.18), (0.1, 1.5, 0.45), "dark_void", rot=(0, -0.45, 0))
    for x in (0.3, -0.7):
        for s in (-1, 1):
            b.box((x, s * 0.84, 1.2), (0.85, 0.05, 0.42), "dark_void")             # 옆창
    b.box((2.28, 0, 0.55), (0.12, 1.85, 0.25), "metal_dark")                       # 범퍼
    b.box((-2.28, 0, 0.55), (0.12, 1.85, 0.25), "metal_dark")
    b.box((1.55, 0, 0.98), (1.2, 1.7, 0.08), "rust_dark", rot=(0, -0.18, 0))       # 들린 보닛
    _wheels(b, (1.4, -1.4), 0.86, 0.34, missing={(1, -1)} if seed % 2 else set())
    b.export(name)


def car_pickup(name, seed):
    reset(); random.seed(seed); b = Builder()
    b.box((0, 0, 0.75), (5.2, 1.9, 0.6), "rust_body")
    b.box((1.2, 0, 1.45), (1.6, 1.8, 0.85), "rust_body")                           # 운전석
    b.box((2.05, 0, 1.5), (0.08, 1.6, 0.6), "dark_void", rot=(0, 0.3, 0))
    for s in (-1, 1):
        b.box((1.2, s * 0.91, 1.55), (1.0, 0.05, 0.5), "dark_void")
        b.box((-1.3, s * 0.93, 1.3), (2.4, 0.1, 0.5), "rust_dark")                # 짐칸 옆판
    b.box((-2.55, 0, 1.3), (0.1, 1.9, 0.5), "rust_dark")
    b.box((2.3, 0, 0.95), (0.9, 1.85, 0.5), "rust_body")                          # 보닛
    b.box((2.78, 0, 0.7), (0.1, 1.9, 0.3), "metal_dark")
    _wheels(b, (1.8, -1.6), 0.9, 0.42)
    b.export(name)


def school_bus(name):
    reset(); b = Builder()
    L, W, H = 10.5, 2.5, 2.6
    b.box((0, 0, 0.55 + H / 2), (L, W, H), "paint_bus")
    b.box((L / 2 + 0.7, 0, 1.2), (1.4, W - 0.1, 1.3), "paint_bus")               # 보닛
    b.box((0, 0, 0.55 + H + 0.08), (L - 0.2, W - 0.2, 0.16), "paint_bus")
    for s in (-1, 1):
        for i in range(9):                                                             # 창문 줄
            x = -L / 2 + 0.8 + i * (L - 1.6) / 8
            b.box((x, s * (W / 2 + 0.02), 0.55 + H - 0.75), (0.85, 0.06, 0.8), "dark_void")
        b.box((0, s * (W / 2 + 0.03), 0.55 + 1.05), (L, 0.05, 0.08), "metal_dark")
    b.box((L / 2 + 0.02, 0, 0.55 + H - 0.7), (0.06, W - 0.3, 0.9), "dark_void")
    for x in (3.2, -3.4):
        for s in (-1, 1):
            b.tube((x, s * 1.2 - 0.15, 0.5), (x, s * 1.2 + 0.15, 0.5), 0.5, 0.5, "dark_tire", sides=10)
    b.export(name)


def box_truck(name):
    reset(); b = Builder()
    b.box((-0.8, 0, 1.9), (5.0, 2.4, 2.5), "concrete")                             # 짐칸
    b.box((2.4, 0, 1.3), (1.6, 2.2, 1.7), "rust_body")
    b.box((3.22, 0, 1.6), (0.06, 1.9, 0.7), "dark_void")
    _wheels(b, (2.5, -2.3), 1.05, 0.45)
    b.export(name)


# ══════════════════════════════════════════════════════════════════
# 작은 소품 — 드럼통·나무상자·여행가방·타이어·잔해·간판
# ══════════════════════════════════════════════════════════════════
def drum(name):
    reset(); b = Builder()
    b.tube((0, 0, 0), (0, 0, 0.9), 0.3, 0.3, "rust_drum", sides=14, caps=False)
    b.tube((0, 0, 0), (0, 0, 0.02), 0.3, 0.3, "rust_dark", sides=14)
    for z in (0.02, 0.3, 0.6, 0.89):
        b.tube((0, 0, z - 0.02), (0, 0, z + 0.02), 0.312, 0.312, "rust_dark", sides=14, caps=False)
    b.tube((0, 0, 0.72), (0, 0, 0.74), 0.29, 0.29, "dark_void", sides=14)       # 안쪽 (불이 올라올 자리)
    b.export(name)


def crate(name, seed):
    reset(); random.seed(seed); b = Builder()
    s = 0.7
    for z in (0.12, 0.36, 0.6):
        for y in (-s / 2, s / 2):
            b.box((0, y, z), (s, 0.04, 0.2), "wood_crate")
        for x in (-s / 2, s / 2):
            b.box((x, 0, z), (0.04, s, 0.2), "wood_crate")
    b.box((0, 0, 0.02), (s, s, 0.04), "wood_crate")
    for x in (-s / 2, s / 2):
        for y in (-s / 2, s / 2):
            b.box((x, y, 0.35), (0.06, 0.06, 0.7), "wood_dark")
    b.export(name)


def suitcase(name, mat):
    reset(); b = Builder()
    b.box((0, 0, 0.12), (0.7, 0.45, 0.24), mat)
    b.box((0, 0, 0.245), (0.72, 0.47, 0.02), "metal_dark")
    b.box((0, -0.24, 0.12), (0.22, 0.04, 0.06), "metal_dark")
    b.export(name)


def tire(name):
    reset()
    bpy.ops.mesh.primitive_torus_add(major_radius=0.33, minor_radius=0.13, major_segments=14, minor_segments=6, location=(0, 0, 0.13))
    o = bpy.context.active_object
    o.data.materials.append(_material("dark_tire"))
    b = Builder()
    b.bm.from_mesh(o.data); b.mats = ["dark_tire"]
    bpy.data.objects.remove(o)
    b.export(name)


def rubble(name, seed, n, spread, mats):
    reset(); random.seed(seed); b = Builder()
    for _ in range(n):
        r = random.uniform(0.15, 0.5)
        b.blob((random.gauss(0, spread), random.gauss(0, spread), r * 0.3), r,
               (1.3, random.uniform(0.8, 1.4), random.uniform(0.35, 0.6)), random.choice(mats))
    for _ in range(n // 3):                                                           # 부러진 판자
        b.box((random.gauss(0, spread), random.gauss(0, spread), 0.1), (random.uniform(0.8, 1.8), 0.15, 0.05),
              random.choice(["wood_siding", "wood_dark"]), rot=(random.uniform(-0.3, 0.3), random.uniform(-0.3, 0.3), random.random() * 3))
    b.export(name)


def sign_post(name):
    reset(); b = Builder()
    b.box((0, 0, 0.9), (0.07, 0.07, 1.8), "metal_dark")
    b.box((0, -0.05, 1.55), (0.8, 0.04, 0.9), "sign_board")
    b.box((0, -0.03, 1.55), (0.84, 0.03, 0.94), "rust_dark")
    b.export(name)


def fence_wood(name, seed):
    reset(); random.seed(seed); b = Builder()
    for x in (-1.5, 1.5):
        b.box((x, 0, 0.6), (0.1, 0.1, 1.2), "wood_dark", rot=(0, random.uniform(-0.1, 0.1), 0))
    for i in range(9):                                                                 # 세로 판자, 일부 빠지고 기울어짐
        if random.random() < 0.3:
            continue
        x = -1.35 + i * 0.34
        b.box((x, 0.06, 0.55), (0.18, 0.03, random.uniform(0.7, 1.1)), "wood_siding",
              rot=(random.uniform(-0.15, 0.15), 0, random.uniform(-0.1, 0.1)))
    b.box((0, 0.04, 0.35), (3.0, 0.05, 0.1), "wood_dark")
    b.box((0, 0.04, 0.85), (3.0, 0.05, 0.1), "wood_dark", rot=(0, 0.05, 0))
    b.export(name)


def market_stall(name):
    reset(); b = Builder()
    for x in (-1.2, 1.2):
        for y in (-0.8, 0.8):
            b.box((x, y, 1.1), (0.08, 0.08, 2.2), "wood_dark")
    b.box((0, 0, 0.85), (2.4, 1.6, 0.08), "wood_crate")
    b.box((0, -0.3, 2.3), (2.8, 2.2, 0.04), "fabric_red", rot=(0.25, 0, 0))          # 천막 (한쪽이 처짐)
    b.box((0, 0.2, 0.45), (2.2, 0.06, 0.8), "wood_crate")
    b.export(name)


# ══════════════════════════════════════════════════════════════════
# 큰 구조물 — 급수탑·다리·철탑·요새 성벽·투광등
# ══════════════════════════════════════════════════════════════════
def water_tower(name):
    reset(); b = Builder()
    for x in (-1.8, 1.8):
        for y in (-1.8, 1.8):
            b.tube((x * 1.2, y * 1.2, 0), (x * 0.8, y * 0.8, 12), 0.14, 0.12, "wood_dark", sides=5)
    for z in (3, 6.5, 10):                                                             # X자 버팀대
        s = 1.8 * (1.2 - 0.4 * z / 12)
        for (a, c) in [((-s, -s), (s, -s)), ((s, -s), (s, s)), ((s, s), (-s, s)), ((-s, s), (-s, -s))]:
            b.tube((a[0], a[1], z), (c[0], c[1], z + 2), 0.05, 0.05, "wood_dark", sides=4)
    b.tube((0, 0, 12), (0, 0, 16), 2.6, 2.6, "wood_siding", sides=14)
    b.tube((0, 0, 16), (0, 0, 17.8), 2.8, 0.2, "wood_dark", sides=14)
    b.box((0, -2.8, 13.5), (0.1, 0.1, 5), "metal_dark")
    b.export(name)


def bridge_deck(name, broken=False):
    reset(); random.seed(5); b = Builder()
    L, W = 10.0, 8.0
    b.box((0, 0, -0.35), (W, L, 0.7), "concrete")                                     # 상판 (윗면이 y=0 → 길과 같은 높이)
    for s in (-1, 1):
        b.box((s * (W / 2 - 0.15), 0, 0.5), (0.3, L, 0.2), "concrete_dark")          # 난간 윗대
        for i in range(6):
            if broken and s > 0 and i > 2:
                continue
            b.box((s * (W / 2 - 0.15), -L / 2 + 0.8 + i * (L - 1.6) / 5, 0.2), (0.2, 0.2, 0.6), "concrete_dark")
    if broken:                                                                         # 부서진 가장자리 + 삐져나온 철근
        for _ in range(10):
            x = random.uniform(1.5, W / 2)
            y = random.uniform(-L / 2, L / 2)
            b.tube((x, y, -0.2), (x + random.uniform(-0.5, 0.8), y + random.uniform(-0.3, 0.3), random.uniform(0.3, 1.2)), 0.02, 0.02, "rust_dark", sides=3)
        b.box((W / 2 - 1.0, 1.0, -0.8), (2.0, 4.0, 0.6), "concrete_dark", rot=(0.3, -0.5, 0))
    b.export(name, ground=False)


def bridge_pillar(name):
    reset(); b = Builder()
    for x in (-2.5, 2.5):
        b.box((x, 0, -3.5), (1.1, 1.1, 6.0), "concrete")
    b.box((0, 0, -0.9), (7.5, 1.4, 0.8), "concrete_dark")
    b.export(name, ground=False)


def bridge_slab(name):
    reset(); random.seed(8); b = Builder()
    b.box((0, 0, 0), (7.0, 9.0, 0.7), "concrete", rot=(0.55, 0.1, 0))                 # 무너져 기울어진 상판
    for _ in range(12):
        x = random.uniform(-3.4, 3.4)
        b.tube((x, 4.2, 2.4), (x + random.uniform(-0.5, 0.5), 5.2, 3.0 + random.uniform(-0.5, 0.8)), 0.02, 0.02, "rust_dark", sides=3)
    b.export(name, ground=False)


def pylon(name):
    reset(); b = Builder()
    H = 22.0
    base, top = 3.0, 0.9
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for cx, cy in corners:
        b.tube((cx * base, cy * base, 0), (cx * top, cy * top, H), 0.12, 0.08, "metal_dark", sides=4)
    levels = 7
    for k in range(levels):                                                            # 격자 버팀대
        z0 = H * k / levels
        z1 = H * (k + 1) / levels
        s0 = base + (top - base) * k / levels
        s1 = base + (top - base) * (k + 1) / levels
        for i in range(4):
            a, c = corners[i], corners[(i + 1) % 4]
            b.tube((a[0] * s0, a[1] * s0, z0), (c[0] * s1, c[1] * s1, z1), 0.04, 0.04, "metal_dark", sides=3, caps=False)
            b.tube((c[0] * s0, c[1] * s0, z0), (a[0] * s1, a[1] * s1, z1), 0.04, 0.04, "metal_dark", sides=3, caps=False)
            b.tube((a[0] * s1, a[1] * s1, z1), (c[0] * s1, c[1] * s1, z1), 0.04, 0.04, "metal_dark", sides=3, caps=False)
    for z, w in ((H * 0.72, 5.5), (H * 0.88, 4.0)):                                  # 팔
        b.box((0, 0, z), (w * 2, 0.25, 0.3), "metal_dark")
        for s in (-1, 1):
            b.tube((s * w, 0, z), (s * w, 0, z - 1.4), 0.05, 0.05, "metal_dark", sides=3)
    b.export(name)


def fortress_wall(name):
    reset(); random.seed(21); b = Builder()
    W, H = 12.0, 9.0
    for i in range(4):                                                                 # 큰 콘크리트 패널
        x = -W / 2 + (i + 0.5) * W / 4
        b.box((x, 0, H / 2), (W / 4 - 0.12, 1.2, H), "concrete")
        b.box((x, -0.62, H * 0.35), (W / 4 - 0.6, 0.06, 0.12), "concrete_dark")
    b.box((0, 0, H + 0.4), (W, 1.6, 0.8), "concrete_dark")
    for i in range(12):                                                                # 윗부분 철조망 기둥
        x = -W / 2 + 0.5 + i * (W - 1) / 11
        b.tube((x, 0, H + 0.8), (x, -0.3, H + 2.0), 0.03, 0.03, "metal_dark", sides=3)
    b.export(name)


def fortress_gate(name):
    reset(); b = Builder()
    for s in (-1, 1):                                                                  # 양쪽 탑
        b.box((s * 7.0, 0, 7.0), (4.0, 4.0, 14.0), "concrete")
        b.box((s * 7.0, 0, 14.3), (4.6, 4.6, 0.6), "concrete_dark")
        b.box((s * 7.0, -2.05, 10.5), (1.6, 0.1, 0.5), "dark_void")                 # 총안
    b.box((0, 0, 11.0), (10.0, 3.0, 2.0), "concrete_dark")                              # 문 위 다리
    for s in (-1, 1):                                                                  # 철문 (살짝 열림)
        b.box((s * 2.4, -0.3 * s, 4.5), (4.6, 0.25, 9.0), "rust_dark", rot=(0, 0, s * 0.12))
        for k in range(6):
            b.box((s * (0.6 + k * 0.7), -0.45 * s, 4.5), (0.12, 0.12, 9.0), "metal_dark", rot=(0, 0, s * 0.12))
    b.export(name)


def floodlight(name):
    reset(); b = Builder()
    b.tube((0, 0, 0), (0, 0, 14), 0.18, 0.12, "metal_dark", sides=6)
    b.box((0, 0, 14.1), (2.2, 0.3, 0.15), "metal_dark")
    for x in (-0.7, 0.7):
        b.box((x, -0.25, 14.4), (0.9, 0.35, 0.6), "metal_dark", rot=(0.4, 0, 0))
        b.box((x, -0.45, 14.35), (0.75, 0.04, 0.45), "glow_lamp", rot=(0.4, 0, 0))
    b.export(name)


def barrier(name):
    reset(); b = Builder()                                                             # 콘크리트 차단벽 (다리 난간 대용)
    b.box((0, 0, 0.35), (2.0, 0.5, 0.7), "concrete")
    b.box((0, 0, 0.8), (2.0, 0.25, 0.3), "concrete")
    b.export(name)


# ── 실행 ─────────────────────────────────────────────────────────
bare_tree("v2_tree_a", 1, 9.0, 1.0)
bare_tree("v2_tree_b", 2, 11.0, 0.9)
bare_tree("v2_tree_c", 3, 7.0, 1.2)
bare_tree("v2_tree_d", 4, 13.0, 0.8, depth=4)
house("v2_house_a", 11, 8.0, 7.0, 2, porch=True, broken=True)
house("v2_house_b", 12, 6.0, 8.0, 3, porch=False, broken=True, lit_window=True)
house("v2_house_c", 13, 7.0, 6.0, 2, porch=True, broken=False)
house("v2_shack", 14, 5.0, 4.5, 1, porch=False, broken=True)
car_sedan("v2_car_sedan", 1)
car_sedan("v2_car_sedan_b", 2)
car_pickup("v2_car_pickup", 3)
school_bus("v2_bus")
box_truck("v2_truck")
drum("v2_drum")
crate("v2_crate", 1)
suitcase("v2_suitcase_red", "fabric_red")
suitcase("v2_suitcase_blue", "fabric_blue")
tire("v2_tire")
rubble("v2_rubble_wood", 31, 18, 0.9, ["wood_siding", "concrete_dark", "fabric_brown"])
rubble("v2_rubble_stone", 32, 22, 1.1, ["concrete", "concrete_dark"])
rubble("v2_trash", 33, 16, 0.6, ["fabric_blue", "fabric_brown", "dark_void", "metal_dark"])
sign_post("v2_sign")
fence_wood("v2_fence", 1)
market_stall("v2_stall")
water_tower("v2_water_tower")
bridge_deck("v2_bridge_deck")
bridge_deck("v2_bridge_deck_broken", broken=True)
bridge_pillar("v2_bridge_pillar")
bridge_slab("v2_bridge_slab")
pylon("v2_pylon")
fortress_wall("v2_wall")
fortress_gate("v2_gate")
floodlight("v2_floodlight")
barrier("v2_barrier")
print("[v2] done")
