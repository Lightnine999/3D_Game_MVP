"""낙하산 보급 상자를 Blender 스크립트로 만든다 (WU-29, 외부 에셋 없음).

사용:
  blender -b --factory-startup --python art/blender/make_supply_crate.py -- --out godot/assets/models/prop_supply_crate.glb

규격 (TECH_SPEC 13.3.1 ①-2 "0.6m 정육면체 + 낙하산", ①-1 공통):
  - 원점 = 상자 발밑 중앙, 1 unit = 1 m, 충돌 없음
  - 물체 두 개로 나눈다: `Crate`(상자), `Parachute`(낙하산 + 줄)
    → B 는 착지하면 `Parachute` 만 숨긴다 (예: $Parachute.visible = false)
  - 소품 삼각형 2,000 이하 (5.3)
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

CRATE = 0.6
CANOPY_R = 0.8
CANOPY_Z = 1.9          # 낙하산 아래 가장자리 높이


def material(name, color, metallic=0.0, roughness=0.7):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def new_object(name, mats):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for m in mats:
        mesh.materials.append(m)
    return obj


def box(bm, center, size, mat_index, bevel=0.0):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    for v in verts:
        v.co = Vector((center[0] + v.co.x * size[0], center[1] + v.co.y * size[1], center[2] + v.co.z * size[2]))
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.material_index = mat_index
    if bevel > 0:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES")


def rod(bm, a, b, radius, mat_index):
    """a 에서 b 까지 가는 가는 기둥 (낙하산 줄)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = Matrix.Translation((a + b) / 2) @ rot
    geom = bmesh.ops.create_cone(bm, cap_ends=False, segments=4, radius1=radius, radius2=radius,
                                 depth=d.length, matrix=m)
    for f in {f for v in geom["verts"] for f in v.link_faces}:
        f.material_index = mat_index


def make_crate(mats):
    obj = new_object("Crate", mats)
    bm = bmesh.new()
    box(bm, (0, 0, CRATE / 2), (CRATE, CRATE, CRATE), 0, bevel=0.015)          # 나무 상자
    for z in (0.14, 0.46):                                                     # 금속 띠 두 줄
        box(bm, (0, 0, z), (CRATE + 0.012, CRATE + 0.012, 0.05), 1)
    box(bm, (0, -CRATE / 2 - 0.004, 0.30), (0.26, 0.006, 0.10), 2)             # 앞면 빨간 표식
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def make_parachute(mats):
    obj = new_object("Parachute", mats)
    bm = bmesh.new()
    # 반구 모양 덮개 — 16 조각을 주황·흰색 번갈아 칠한다
    segs, rings = 16, 5
    top = bm.verts.new((0, 0, CANOPY_Z + CANOPY_R * 0.45))
    rows = []
    for r in range(1, rings + 1):
        t = r / rings * (math.pi / 2)
        rr, zz = CANOPY_R * math.sin(t), CANOPY_Z + CANOPY_R * 0.45 * math.cos(t)
        rows.append([bm.verts.new((rr * math.cos(2 * math.pi * i / segs), rr * math.sin(2 * math.pi * i / segs), zz))
                     for i in range(segs)])
    for i in range(segs):
        j = (i + 1) % segs
        f = bm.faces.new((top, rows[0][i], rows[0][j]))
        f.material_index = i % 2
        for r in range(rings - 1):
            f = bm.faces.new((rows[r][i], rows[r + 1][i], rows[r + 1][j], rows[r][j]))
            f.material_index = i % 2
    # 줄 4개: 상자 윗모서리 → 덮개 가장자리
    h = CRATE / 2 - 0.03
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        edge = Vector((sx, sy, 0)).normalized() * CANOPY_R * 0.98
        rod(bm, (sx * h, sy * h, CRATE), (edge.x, edge.y, CANOPY_Z), 0.006, 2)
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.materials[0].use_backface_culling = False
    return obj


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out = argv[argv.index("--out") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    crate = make_crate([material("Wood", (0.42, 0.28, 0.15)), material("Metal", (0.15, 0.15, 0.16), 1.0, 0.45),
                        material("RedMark", (0.7, 0.06, 0.05))])
    chute = make_parachute([material("CanopyOrange", (0.95, 0.38, 0.08), roughness=0.9),
                            material("CanopyWhite", (0.9, 0.9, 0.88), roughness=0.9),
                            material("Cord", (0.8, 0.78, 0.7), roughness=0.9)])
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=False)
    for o in (crate, chute):
        vs = [v.co for v in o.data.vertices]
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        print("MAKE_CRATE %s: 크기 x%.2f y%.2f z%.2f, 최저 z %.3f, 삼각형 %d" % (
            o.name, max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs),
            max(v.z for v in vs) - min(v.z for v in vs), min(v.z for v in vs), tris))
    print("MAKE_CRATE out " + out)


main()
