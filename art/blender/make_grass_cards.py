"""Blender로 풀 포기 5종을 만들고 정면에서 찍어 투명 PNG 카드로 굽는다 (A 소유)

비유: 풀 모형을 실제로 만들어 흰 벽 대신 투명 배경 앞에서 사진을 찍는 일.
수만 포기를 3D로 그리면 폰이 버티지 못하니, 3D로 만든 모양을 그림으로 구워 카드에 붙인다.

실행: blender -b --factory-startup -P art/blender/make_grass_cards.py -- godot/assets/textures/v2
출력: grass_wild.png, grass_seed.png, grass_reed.png, grass_weed.png, grass_thistle.png (512x512, RGBA)
- 색은 발광(Emission) 재질로 찍어 조명 없이 "순수한 색"만 담는다 → 빛·그림자는 Godot이 입힌다
- 카드 밑변 = 땅, 가운데 = 포기 뿌리
"""
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 512

# 풀 색 팔레트 (뿌리 쪽, 끝쪽) — 새 콘셉트의 차가운 회갈색·잿빛 올리브
PALETTE = [
    ((0.10, 0.11, 0.07), (0.33, 0.32, 0.22)),   # 짙은 올리브
    ((0.16, 0.13, 0.08), (0.46, 0.39, 0.26)),   # 마른 갈색
    ((0.14, 0.14, 0.11), (0.42, 0.41, 0.34)),   # 잿빛
    ((0.18, 0.15, 0.09), (0.55, 0.47, 0.31)),   # 밀짚
]
STEM = ((0.10, 0.09, 0.06), (0.30, 0.26, 0.18))   # 곧은 줄기는 30% 어둡게 (밝으면 막대처럼 튄다)


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"   # 색이 바뀌지 않게
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = 1.0                              # 카드 한 장 = 1m × 1m
    cam_ob = bpy.data.objects.new("cam", cam)
    cam_ob.location = (0, -5, 0.5)
    cam_ob.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam_ob)
    scene.camera = cam_ob


_mats: dict = {}


def mat(base, tip) -> bpy.types.Material:
    key = (base, tip)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("grass")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    ramp.color_ramp.elements[0].color = (*base, 1)
    ramp.color_ramp.elements[1].color = (*tip, 1)
    nt.links.new(coord.outputs["Object"], sep.inputs[0])     # 높이(z)에 따라 뿌리 → 끝 색
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    emit.inputs["Strength"].default_value = 0.55                # 기존 풀(grass_v2)과 밝기를 맞춘다
    _mats[key] = m
    return m


def blade(bm, root: Vector, height: float, width: float, lean: Vector, curl: float, steps: int = 8) -> None:
    """뿌리에서 끝으로 가늘어지며 휘는 풀잎 한 장 (앞에서 보이게 x-z 평면)"""
    prev = None
    for i in range(steps + 1):
        t = i / steps
        center = root + Vector((0, 0, height * t)) + lean * (t ** curl)
        w = width * (1 - t) ** 0.8 + 0.0015
        pair = (bm.verts.new(center + Vector((-w, 0, 0))), bm.verts.new(center + Vector((w, 0, 0))))
        if prev:
            bm.faces.new((prev[0], prev[1], pair[1], pair[0]))
        prev = pair


def stem(bm, root: Vector, top: Vector, width: float) -> None:
    blade(bm, root, top.z - root.z, width, Vector((top.x - root.x, 0, 0)), 1.0, steps=4)


def seed_head(bm, at: Vector, length: float, rnd: random.Random) -> None:
    """이삭: 줄기 끝에 작은 알갱이(마름모)를 줄줄이"""
    for k in range(10):
        t = k / 9
        c = at + Vector((rnd.uniform(-0.006, 0.006), 0, length * t))
        s = 0.012 * (1 - 0.6 * t)
        v = [bm.verts.new(c + Vector(o)) for o in ((0, 0, -s * 1.6), (s, 0, 0), (0, 0, s * 1.6), (-s, 0, 0))]
        bm.faces.new(v)


def leaf(bm, root: Vector, length: float, width: float, angle: float) -> None:
    """넓은 잎: 뿌리에서 비스듬히 뻗는 타원형"""
    d = Vector((math.sin(angle), 0, math.cos(angle)))
    side = Vector((d.z, 0, -d.x))
    prev = None
    for i in range(9):
        t = i / 8
        c = root + d * length * t + Vector((0, 0, -0.08 * t * t))   # 끝이 살짝 처진다
        w = width * math.sin(math.pi * t) + 0.002
        pair = (bm.verts.new(c - side * w), bm.verts.new(c + side * w))
        if prev:
            bm.faces.new((prev[0], prev[1], pair[1], pair[0]))
        prev = pair


def build(kind: str, seed: int) -> None:
    rnd = random.Random(seed)
    groups: dict = {}

    def bm_for(p):
        if p not in groups:
            groups[p] = bmesh.new()
        return groups[p]

    def pal():
        return PALETTE[rnd.randrange(len(PALETTE))]

    if kind == "grass_wild":
        for _ in range(70):
            x = rnd.gauss(0, 0.07)
            h = rnd.uniform(0.35, 0.95)
            blade(bm_for(pal()), Vector((x, rnd.uniform(-0.01, 0.01), 0)), h, rnd.uniform(0.006, 0.013),
                  Vector(((x * 2.2 + rnd.uniform(-0.28, 0.28)) * h, 0, -h * rnd.uniform(0.05, 0.35))), rnd.uniform(1.6, 2.6))
    elif kind == "grass_seed":
        for _ in range(40):
            x = rnd.gauss(0, 0.06)
            h = rnd.uniform(0.25, 0.6)
            blade(bm_for(pal()), Vector((x, 0, 0)), h, 0.009, Vector(((x * 2 + rnd.uniform(-0.2, 0.2)) * h, 0, -h * 0.2)), 2.0)
        for _ in range(9):                                 # 이삭 줄기
            x = rnd.gauss(0, 0.05)
            top = Vector((x * 2.5 + rnd.uniform(-0.12, 0.12), 0, rnd.uniform(0.62, 0.9)))
            p = STEM
            stem(bm_for(p), Vector((x, 0, 0)), top, 0.004)
            seed_head(bm_for(p), top, rnd.uniform(0.07, 0.11), rnd)
    elif kind == "grass_reed":
        for _ in range(28):
            x = rnd.gauss(0, 0.09)
            top = Vector((x + rnd.uniform(-0.05, 0.05), 0, rnd.uniform(0.6, 0.97)))
            stem(bm_for(STEM), Vector((x, 0, 0)), top, rnd.uniform(0.004, 0.007))
        for _ in range(26):                                # 줄기 사이 긴 잎
            x = rnd.gauss(0, 0.08)
            h = rnd.uniform(0.3, 0.7)
            blade(bm_for(pal()), Vector((x, 0, 0)), h, 0.01, Vector((rnd.uniform(-0.25, 0.25) * h, 0, -h * 0.25)), 2.2)
    elif kind == "grass_weed":
        for _ in range(16):
            a = rnd.uniform(-1.25, 1.25)
            leaf(bm_for(pal()), Vector((rnd.uniform(-0.03, 0.03), 0, 0.02)), rnd.uniform(0.22, 0.42), rnd.uniform(0.04, 0.07), a)
        for _ in range(5):
            x = rnd.uniform(-0.05, 0.05)
            stem(bm_for(PALETTE[1]), Vector((x, 0, 0)), Vector((x + rnd.uniform(-0.1, 0.1), 0, rnd.uniform(0.45, 0.7))), 0.004)
    elif kind == "grass_thistle":
        for _ in range(6):                                 # 가지 친 마른 대
            x = rnd.gauss(0, 0.05)
            top = Vector((x + rnd.uniform(-0.12, 0.12), 0, rnd.uniform(0.6, 0.92)))
            stem(bm_for(STEM), Vector((x, 0, 0)), top, 0.005)
            for b in range(3):
                t = rnd.uniform(0.45, 0.85)
                j = Vector((x, 0, 0)).lerp(top, t)
                tip = j + Vector((rnd.uniform(-0.16, 0.16), 0, rnd.uniform(0.06, 0.16)))
                stem(bm_for(STEM), j, tip, 0.003)
                seed_head(bm_for(PALETTE[1]), tip, 0.03, rnd)
            seed_head(bm_for(PALETTE[1]), top, 0.04, rnd)
        for _ in range(24):                                # 밑동 풀
            x = rnd.gauss(0, 0.07)
            h = rnd.uniform(0.15, 0.4)
            blade(bm_for(pal()), Vector((x, 0, 0)), h, 0.008, Vector((rnd.uniform(-0.25, 0.25) * h, 0, -h * 0.2)), 2.0)
    for p, bm in groups.items():
        me = bpy.data.meshes.new(kind)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(kind, me)
        ob.data.materials.append(mat(*p))
        bpy.context.scene.collection.objects.link(ob)


def main() -> None:
    for i, kind in enumerate(["grass_wild", "grass_seed", "grass_reed", "grass_weed", "grass_thistle"]):
        reset()
        _mats.clear()
        build(kind, 100 + i)
        bpy.context.scene.render.filepath = str(OUT / f"{kind}.png")
        bpy.ops.render.render(write_still=True)
        print("[grass]", kind)


main()
