"""구해 온 무거운 GLB → 모바일용 가벼운 GLB (A 소유)

비유: 박물관급 조각상(수백만 면)을 게임용 모형(수천 면)으로 다시 깎고, 실제 크기 자에 맞춰 세우는 일.

한 파일마다: 조각 합치기 → 면 수 줄이기(Decimate) → 텍스처 줄이기 → 실제 크기로 배율 → 원점 = 바닥 가운데 → 내보내기 + 미리보기
실행: blender -b --factory-startup -P art/blender/optimize_glb.py -- <작업표.json>
작업표: [{"src": 원본, "out": 결과 GLB, "tris": 목표 삼각형, "tex": 최대 텍스처 px,
          "height": 목표 높이(m) 또는 "length": 목표 가로 길이(m), "preview": 미리보기 PNG}, ...]
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def process(job: dict) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=job["src"])
    # 부모 관계를 풀고(위치는 유지) 메시가 아닌 것(빈 노드·조명·카메라)은 지운다
    for o in list(bpy.context.scene.objects):
        if o.parent:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    me.calc_loop_triangles()
    before = len(me.loop_triangles)
    if job.get("merge"):                     # 3D 스캔: 텍스처 이음매마다 떨어진 점을 먼저 합쳐야 줄이기가 된다
        lo, hi = world_bbox([ob])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=max(hi - lo) * job["merge"])
        bpy.ops.object.mode_set(mode="OBJECT")
        me.calc_loop_triangles()
        before = len(me.loop_triangles)
    after = before
    for _ in range(5):                       # 3D 스캔은 한 번에 목표까지 안 줄어서 여러 번 반복
        if after <= job["tris"] * 1.15:
            break
        mod = ob.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.use_collapse_triangulate = True
        mod.ratio = max(job["tris"] / after, 0.02)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        me.calc_loop_triangles()
        after = len(me.loop_triangles)
    # 실제 크기로 배율 → 원점 = 바닥 가운데
    lo, hi = world_bbox([ob])
    size = hi - lo
    if "height" in job:
        s = job["height"] / max(size.z, 1e-6)
    else:
        s = job["length"] / max(size.x, size.y, 1e-6)
    ob.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    lo, hi = world_bbox([ob])
    ob.location = (-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)
    bpy.ops.object.transform_apply(location=True)
    # 텍스처 줄이기
    for img in bpy.data.images:
        w, h = img.size
        if max(w, h) > job["tex"]:
            k = job["tex"] / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))
    Path(job["out"]).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=job["out"], export_format="GLB", use_selection=False,
                              export_apply=True, export_image_format="AUTO")
    lo, hi = world_bbox([ob])
    result = {"out": Path(job["out"]).name, "tris_before": before, "tris_after": after,
              "size_m": [round(v, 2) for v in (hi - lo)]}
    if job.get("preview"):
        render_preview(ob, job["preview"], hi - lo)
    return result


def render_preview(ob, path: str, size: Vector) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 320
    scene.render.resolution_y = 320
    scene.render.film_transparent = True
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.6, 0.65, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    sun.data.energy = 3.0
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    r = max(size) * 1.6
    cam.location = (r * 0.8, -r * 0.9, size.z * 0.5 + r * 0.45)
    direction = Vector((0, 0, size.z * 0.45)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


jobs = json.load(open(sys.argv[sys.argv.index("--") + 1]))
for job in jobs:
    try:
        print("OPT " + json.dumps(process(job), ensure_ascii=False), flush=True)
    except Exception as e:
        print("OPT " + json.dumps({"out": job["out"], "error": str(e)}), flush=True)
