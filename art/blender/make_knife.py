"""칼 모델을 Blender 스크립트로 만든다 (WU-29 "없으면 Blender 스크립트로 제작").

사용:
  blender -b --factory-startup --python art/blender/make_knife.py -- --out godot/assets/models/weapon_knife.glb

규격 (TECH_SPEC 13.3.1 ①-2 에 weapon_knife 로 추가, 권총과 같은 규칙):
  - 전체 길이 0.25 m (칼날 0.14 m + 손잡이 약 0.10 m), 1 unit = 1 m
  - 원점 = 손잡이 가운데, 칼끝 = Godot -Z (Blender +Y)
  - 애니메이션·충돌 없음 (찌르는 동작은 B 의 WU-25 가 코드로)
외부 에셋을 쓰지 않으므로 라이선스 걱정이 없다.
"""
import sys

import bmesh
import bpy


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def add_box(bm, center, size, mat_index):
    """center·size (m) 인 상자를 bm 에 더한다."""
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = [e for e in geom["verts"]]
    for v in verts:
        v.co.x = center[0] + v.co.x * size[0]
        v.co.y = center[1] + v.co.y * size[1]
        v.co.z = center[2] + v.co.z * size[2]
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index


def add_blade(bm, y0, mat_index):
    """옆모습(Y·Z 평면) 윤곽을 두께 방향(X)으로 뽑아 칼날을 만든다. 칼끝이 +Y."""
    half_t = 0.002                                   # 칼날 두께 4 mm
    profile = [                                      # (y, z) — 등은 위, 날은 아래
        (y0, 0.013), (y0 + 0.105, 0.012), (y0 + 0.140, 0.000),
        (y0 + 0.095, -0.012), (y0, -0.013),
    ]
    front = [bm.verts.new((half_t, y, z)) for y, z in profile]
    back = [bm.verts.new((-half_t, y, z)) for y, z in profile]
    n = len(profile)
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((front[i], back[i], back[j], front[j])))
    for f in faces:
        f.material_index = mat_index


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out = argv[argv.index("--out") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mats = [
        material("Steel", (0.62, 0.63, 0.65), 1.0, 0.35),
        material("DarkMetal", (0.12, 0.12, 0.13), 1.0, 0.5),
        material("Grip", (0.06, 0.05, 0.045), 0.0, 0.8),
    ]
    mesh = bpy.data.meshes.new("weapon_knife")
    obj = bpy.data.objects.new("weapon_knife", mesh)
    bpy.context.scene.collection.objects.link(obj)
    for m in mats:
        mesh.materials.append(m)

    bm = bmesh.new()
    # 손잡이 가운데가 원점(0,0,0). 손잡이는 -Y 쪽, 칼날은 +Y 쪽
    add_box(bm, (0, 0.0, 0), (0.020, 0.095, 0.024), 2)        # 손잡이
    add_box(bm, (0, -0.050, 0), (0.024, 0.008, 0.028), 1)     # 손잡이 끝(폼멜)
    add_box(bm, (0, 0.052, 0), (0.026, 0.009, 0.046), 1)      # 가드
    add_blade(bm, 0.0565, 0)                                  # 칼날 (가드 앞에서 시작)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()

    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=False)
    ys = [v.co.y for v in mesh.vertices]
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print("MAKE_KNIFE 길이 %.3f m (칼끝 +Y = Godot -Z), 삼각형 %d, 원점 = 손잡이" % (max(ys) - min(ys), tris))
    print("MAKE_KNIFE out " + out)


main()
