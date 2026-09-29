# Blender 공통 함수: 빈 장면, 재질, 도형 추가, 합치기, glb 내보내기
# 모든 모델 생성 스크립트가 이 파일을 불러 쓴다 (TECH_SPEC 5.1 단계 2).
import math
import random
from pathlib import Path

import bpy


def reset_scene():
    """빈 장면에서 시작한다."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, roughness=0.9):
    """이름이 같은 재질이 있으면 다시 쓰고, 없으면 만든다."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def _finish(obj, mat, location, rotation, scale):
    obj.location = location
    obj.rotation_euler = rotation
    obj.scale = scale
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def box(size, location=(0, 0, 0), rotation=(0, 0, 0), mat=None):
    """size = (가로 x, 깊이 y, 높이 z) 미터."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    return _finish(bpy.context.active_object, mat, location, rotation, size)


def cylinder(radius, depth, location=(0, 0, 0), rotation=(0, 0, 0), mat=None, vertices=10, radius_top=None):
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius_top, depth=depth)
    return _finish(bpy.context.active_object, mat, location, rotation, (1, 1, 1))


def blob(radius, location, scale=(1, 1, 1), mat=None, subdivisions=1, jitter=0.25, rng=None):
    """울퉁불퉁한 덩어리 (쓰레기 봉투, 바위)."""
    rng = rng or random
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius)
    obj = bpy.context.active_object
    for v in obj.data.vertices:
        v.co *= 1.0 + rng.uniform(-jitter, jitter)
    return _finish(obj, mat, location, (0, 0, rng.uniform(0, math.tau)), scale)


def join(objects, name):
    """여러 도형을 하나의 모델로 합치고, 변형을 적용하고, 원점을 발밑 중앙으로 맞춘다."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    _origin_to_feet(obj)
    return obj


def _origin_to_feet(obj):
    """원점 = 바닥면 중앙 (TECH_SPEC 5.2). 가장 낮은 점이 z=0이 되게 옮긴다."""
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    cx, cy, minz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)
    for v in obj.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= minz
    obj.location = (0, 0, 0)


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_glb(obj, out_dir, name):
    """선택한 모델 하나만 .glb로 내보낸다 (Blender Z-up → glTF Y-up 자동 변환)."""
    out = Path(out_dir) / f"{name}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_yup=True, use_selection=True)
    return out
