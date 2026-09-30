"""HUD 아이콘 원본 렌더 — A 가 만든 3D 모델을 그대로 찍어 게임 속 모습과 같은 아이콘을 만든다.
HUD 자체는 C 의 일(WU-31, TECH_SPEC `godot/assets/ui/` (C)). 여기서는 그림만 만들어 넘긴다.

사용:
  blender -b --factory-startup --python art/blender/render_icons.py
  → art/previews/icons_raw/icon_*.png (512×512, 투명 배경, 테두리 없음)
  이어서 python art/ui/finish_icons.py 가 테두리를 두르고 256×256 으로 줄인다.

찍는 것:
  icon_pistol  weapon_pistol.glb      옆모습 (총구가 오른쪽)
  icon_knife   weapon_knife.glb       옆모습, 칼날이 오른쪽 위로 비스듬히
  icon_supply  prop_supply_crate.glb  비스듬히 위에서 (낙하산은 빼고 상자만)
  icon_ammo    (여기서 만든 탄약 한 발) 비스듬히 세운 모습 — 탄약 모델은 게임에 없어서 아이콘용으로만 만든다
"""
import math
import os

import bpy
from mathutils import Quaternion, Vector

MODELS = "godot/assets/models"
OUT = "art/previews/icons_raw"
RES = 512

# 이름: 모델, 카메라 방향(상자 중심에서 카메라 쪽), 화면 회전(도), 뺄 물체 이름
SHOTS = {
    "icon_pistol": {"glb": "weapon_pistol.glb", "view": (1, 0, 0), "roll": 0, "drop": ["Hand"]},   # 아이콘에는 손을 뺀다
    "icon_knife":  {"glb": "weapon_knife.glb",  "view": (1, 0, 0), "roll": 35},
    "icon_supply": {"glb": "prop_supply_crate.glb", "view": (0.8, -1.3, 0.9), "roll": 0, "drop": ["Parachute"]},  # 빨간 표식이 있는 -Y 면이 보이게
    "icon_ammo":   {"make": "cartridge", "view": (1, 0.25, 0.1), "roll": -30},
    # HUD 배치 시안(art/ui/make_hud_mock.py) 배경에 넣을 좀비 — 아이콘 아님, 앞모습 걷는 자세
    "mock_walker": {"glb": "zombie_walker.glb", "view": (0.25, 1, 0.08), "roll": 0, "anim": "walk", "frame": 12},
    "mock_runner": {"glb": "zombie_runner.glb", "view": (-0.3, 1, 0.08), "roll": 0, "anim": "run", "frame": 6},
    "mock_tank":   {"glb": "zombie_tank.glb",   "view": (0.1, 1, 0.08), "roll": 0, "anim": "walk", "frame": 20},
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"      # 색을 모델 그대로 (Filmic/AgX 는 색이 바랜다)
    sc.eevee.taa_render_samples = 64
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.55, 0.6, 1)   # 금속이 비칠 은은한 주변광
    bg.inputs["Strength"].default_value = 0.6
    sc.world = w
    return sc


def material(name, color, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    return m


def make_cartridge():
    """권총 탄 한 발 (탄피 + 탄두). 실제 9mm 보다 조금 길게 — 작은 아이콘에서 '총알'로 읽히게."""
    brass = material("Brass", (0.85, 0.6, 0.22), 1.0, 0.3)
    copper = material("Copper", (0.75, 0.38, 0.22), 0.7, 0.45)   # 덜 반짝이게 — 반사가 움푹 팬 자국처럼 보였다
    r, case_h = 0.005, 0.022
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r, depth=case_h, location=(0, 0, case_h / 2))
    case = bpy.context.object
    case.data.materials.append(brass)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r * 1.08, depth=0.0015, location=(0, 0, 0.00075))
    bpy.context.object.data.materials.append(brass)                     # 바닥 테두리(림)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r * 0.97, location=(0, 0, case_h))
    tip = bpy.context.object
    tip.scale.z = 2.0                                                    # 둥근 머리를 길쭉하게
    tip.data.materials.append(copper)
    for o in bpy.context.scene.objects:
        o.select_set(o.type == "MESH")
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))   # 옆면만 매끈하게 — 뚜껑까지 매끈하면 얼룩이 진다


def pose(anim, frame):
    """좀비를 T 자세 대신 걷는 자세로 — 해당 동작을 붙이고 그 프레임으로 옮긴다."""
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    act = bpy.data.actions[anim]
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    ad.action = act
    if getattr(act, "slots", None):
        ad.action_slot = act.slots[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Icosphere")]   # 뼈 모양 표시용 구는 뺀다


def bbox_world(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi, pts


def add_light(name, kind, direction, energy, color=(1, 1, 1)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    o = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = (-Vector(direction)).to_track_quat("-Z", "Y")
    return o


def shoot(name, s):
    sc = reset()
    if "glb" in s:
        bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, s["glb"]))
        for o in list(bpy.context.scene.objects):
            if any(d.lower() in o.name.lower() for d in s.get("drop", [])):
                bpy.data.objects.remove(o, do_unlink=True)
    else:
        make_cartridge()
    if "anim" in s:
        pose(s["anim"], s["frame"])
    objs = meshes()
    lo, hi, pts = bbox_world(objs)
    center = (lo + hi) / 2

    view = Vector(s["view"]).normalized()
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    dist = (hi - lo).length * 3
    cam.location = center + view * dist
    cam.rotation_mode = "QUATERNION"
    q = (-view).to_track_quat("-Z", "Y")          # 카메라 위쪽 = 세상 위쪽(Z)
    roll = math.radians(s["roll"])
    cam.rotation_quaternion = q @ Quaternion((0, 0, 1), -roll)   # 화면 안에서 돌리기 (+ = 반시계)
    cam_d.clip_end = dist * 3

    # 화면에 꽉 차게 (가장 긴 쪽 기준, 테두리 여백 12%)
    bpy.context.view_layer.update()
    m = cam.matrix_world.inverted()
    local = [m @ p for p in pts]
    w = max(p.x for p in local) - min(p.x for p in local)
    h = max(p.y for p in local) - min(p.y for p in local)
    cx = (max(p.x for p in local) + min(p.x for p in local)) / 2
    cy = (max(p.y for p in local) + min(p.y for p in local)) / 2
    cam_d.ortho_scale = max(w, h) * 1.12
    cam_d.shift_x = cx / cam_d.ortho_scale
    cam_d.shift_y = cy / cam_d.ortho_scale

    # 빛: 위 앞쪽 주광 + 반대편 테두리광 (어두운 게임 화면에서 윤곽이 서도록)
    add_light("Key", "SUN", view + Vector((0, 0, 1.2)), 3.5)
    add_light("Rim", "SUN", -view + Vector((0, 0, 0.6)), 2.5, (0.85, 0.9, 1.0))
    add_light("Fill", "SUN", Vector((0, 0, -1)) + view * 0.5, 0.6)

    sc.render.filepath = os.path.abspath(os.path.join(OUT, name + ".png"))
    bpy.ops.render.render(write_still=True)
    print("ICON %-12s 물체 %d개, 크기 %.3f×%.3f×%.3f m -> %s" % (
        name, len(objs), *(hi - lo), sc.render.filepath))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, s in SHOTS.items():
        shoot(name, s)


main()
