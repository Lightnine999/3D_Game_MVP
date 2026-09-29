"""무기 모델(glb/fbx)을 TECH_SPEC 13.3.1 ①-2 약속대로 정리해 glb 로 내보낸다.

사용:
  blender -b --factory-startup --python art/blender/prep_weapon.py -- \
      --src art/source/cc0/quaternius_pistol_3b53f0fe.glb --length 0.2 \
      --out godot/assets/models/weapon_pistol.glb

하는 일:
  - 가장 긴 방향을 총신(앞뒤)으로 보고, 길이를 --length(m)로 맞춘다      (13.3.1 "길이 0.2m")
  - 총구가 Godot -Z 를 보게 돌린다                                      (13.3.1 ①-1 "정면 -Z")
    총구 쪽 판단: 앞뒤 절반 중 아래로 늘어진 부분(손잡이)이 많은 쪽이 뒤쪽이다
  - 원점을 손잡이 가운데로 옮긴다                                        (13.3.1 "원점 = 손잡이")
  - 애니메이션·충돌은 넣지 않는다 (반동은 B 가 코드로, 충돌은 B 의 장면이 붙인다)
원본(art/source/)은 읽기만 한다.
"""
import argparse
import sys

import bpy
from mathutils import Matrix, Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--src", required=True)
    p.add_argument("--length", type=float, required=True, help="총신 방향 길이 (m)")
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def world_points(meshes):
    return [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if args.src.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=args.src)
    else:
        bpy.ops.import_scene.gltf(filepath=args.src)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    # 모두 하나로 합쳐 변형을 적용한다 (부모·크기가 섞여 있어도 한 물체로 다룬다)
    with bpy.context.temp_override(active_object=meshes[0], selected_editable_objects=meshes,
                                   selected_objects=meshes, object=meshes[0]):
        if len(meshes) > 1:
            bpy.ops.object.join()
    gun = meshes[0]
    for o in list(bpy.context.scene.objects):
        if o is not gun:
            bpy.data.objects.remove(o, do_unlink=True)
    gun.data.transform(gun.matrix_world)
    gun.parent = None
    gun.matrix_world = Matrix.Identity(4)

    pts = world_points([gun])
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = hi - lo
    # 총신 = 수평(X·Y) 중 긴 쪽
    axis = 0 if size.x >= size.y else 1

    # 앞뒤 절반 중 아래쪽(손잡이) 정점이 많은 쪽 = 뒤
    mid_a = (lo[axis] + hi[axis]) / 2
    mid_z = (lo.z + hi.z) / 2
    low_a = sum(1 for p in pts if p.z < mid_z and p[axis] < mid_a)
    low_b = sum(1 for p in pts if p.z < mid_z and p[axis] >= mid_a)
    muzzle_sign = 1 if low_a > low_b else -1   # 손잡이가 - 쪽이면 총구는 + 쪽

    # 총구 방향을 Blender +Y 로 (glTF 로 나가면 -Z = Godot 정면)
    muzzle_dir = Vector((0, 0, 0))
    muzzle_dir[axis] = muzzle_sign
    # to_track_quat 는 +Y 를 muzzle_dir 로 돌리는 회전 → 그 반대(역행렬)를 적용하면 muzzle_dir 이 +Y 가 된다
    rot = muzzle_dir.to_track_quat("Y", "Z").to_matrix().to_4x4()
    gun.data.transform(rot.inverted())

    # 길이 맞추기
    pts = world_points([gun])
    length = max(p.y for p in pts) - min(p.y for p in pts)
    k = args.length / length
    gun.data.transform(Matrix.Scale(k, 4))

    # 원점 = 손잡이 가운데: 뒤쪽 절반 + 아래쪽 절반에 있는 정점들의 가운데
    pts = world_points([gun])
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    mid_y, mid_z = (lo.y + hi.y) / 2, (lo.z + hi.z) / 2
    grip = [p for p in pts if p.y < mid_y and p.z < mid_z] or pts
    c = sum(grip, Vector()) / len(grip)
    gun.data.transform(Matrix.Translation(-c))
    gun.name = gun.data.name = args.out.replace("\\", "/").split("/")[-1].rsplit(".", 1)[0]

    tris = sum(len(p.vertices) - 2 for p in gun.data.polygons)
    bpy.ops.export_scene.gltf(filepath=args.out, export_format="GLB", export_animations=False)
    pts = world_points([gun])
    print("PREP_WEAPON 길이 %.3f m (총구 +Y = Godot -Z), 폭 %.3f, 높이 %.3f, 삼각형 %d, 원점 = 손잡이" % (
        max(p.y for p in pts) - min(p.y for p in pts), max(p.x for p in pts) - min(p.x for p in pts),
        max(p.z for p in pts) - min(p.z for p in pts), tris))
    print("PREP_WEAPON out " + args.out)


main()
