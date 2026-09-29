"""GLB 에셋 점검: 삼각형 수·크기(m)·텍스처 해상도를 JSON 한 줄씩 출력 (A 소유)

실행: blender -b --factory-startup -P art/blender/inspect_glb.py -- <glb 파일들...>
"""
import json
import sys

import bpy
from mathutils import Vector


def inspect(path: str) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    tris = 0
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        me = o.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    images = sorted({f"{i.size[0]}x{i.size[1]}" for i in bpy.data.images if i.size[0] > 0})
    size = hi - lo
    return {
        "file": path.split("/")[-1], "objects": len(meshes), "tris": tris,
        "size_xyz_m": [round(v, 2) for v in size], "min_z": round(lo.z, 2),
        "materials": len(bpy.data.materials), "images": len(bpy.data.images), "image_sizes": images,
    }


for p in sys.argv[sys.argv.index("--") + 1:]:
    try:
        print("INSPECT " + json.dumps(inspect(p), ensure_ascii=False))
    except Exception as e:  # 한 파일이 실패해도 나머지는 계속
        print("INSPECT " + json.dumps({"file": p.split("/")[-1], "error": str(e)}))
