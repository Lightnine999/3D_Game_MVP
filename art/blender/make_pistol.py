"""1인칭 권총 + 총을 쥔 장갑 손 — weapon_pistol.glb (TECH_SPEC 13.3.1 ①-2, 주인 A)
사진 참고 없이 "긴 슬라이드 + 빨간 점 조준경 + 오돌토돌한 손잡이" 형태를 직접 만든다 (라이선스 걱정 없음).

사용:
  blender -b --factory-startup --python art/blender/make_pistol.py -- --out godot/assets/models/weapon_pistol.glb

좌표 (Blender): +Y = 총구 쪽(Godot -Z), +Z = 위, +X = 오른쪽, 1 = 1 m. 원점 = 손잡이 가운데(오른손이 쥐는 곳).

물체 (B 의 코드가 이름으로 찾아 움직인다):
  Frame       몸통·손잡이·방아쇠울 (움직이지 않음)
  Slide       슬라이드 — 쏠 때·장전할 때 뒤로 밀림. 자식 Optic(빨간 점 조준경)이 함께 움직인다
  Magazine    탄창 — 원점이 탄창 위쪽. 손잡이 축(아래·뒤로 18° 기울어짐)을 따라 빠진다
  Trigger     방아쇠
  HandRight   오른손 (손잡이를 쥠) + 소매
  HandLeft    왼손 (받쳐 쥠) + 소매 — 장전할 때 탄창을 가지러 내려간다
뼈대는 없다: 손은 총과 함께 움직이고, 왼손만 통째로 옮긴다 (TECH_SPEC D6 변경 제안).
"""
import argparse
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

GRIP_TILT = math.radians(-18)            # 손잡이 기울기 (아래쪽이 뒤로)
GRIP_ROT = Matrix.Rotation(GRIP_TILT, 4, "X")
GRIP_CENTER = Vector((0, -0.012, -0.014))
BORE_Z = 0.055                           # 총열 중심 높이
SLIDE_Y0, SLIDE_Y1 = -0.046, 0.160       # 슬라이드 뒤·앞 (길이 0.206 m)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def material(name, color, rough, metal=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal    # 어두운 맵에서 새까매지지 않게 낮게 (PR #3)
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 6.0
    return m


M = {}


def mats():
    M["slide"] = material("SlideBlack", (0.022, 0.023, 0.025), 0.38, 0.3)
    M["frame"] = material("FrameBlack", (0.014, 0.014, 0.015), 0.5, 0.2)
    M["grip"] = material("GripStipple", (0.009, 0.009, 0.010), 0.95)
    M["steel"] = material("Steel", (0.45, 0.45, 0.47), 0.3, 0.5)
    M["bore"] = material("Bore", (0.005, 0.005, 0.005), 0.9)
    M["glass"] = material("OpticGlass", (0.1, 0.18, 0.16), 0.05, 0.0)
    M["dot"] = material("RedDot", (1.0, 0.05, 0.03), 0.4, 0.0, emit=(1.0, 0.05, 0.02))
    M["glove"] = material("Glove", (0.15, 0.095, 0.05), 0.8)          # 코요테색(황갈색) 전술 장갑 — 검은 총과 구분되게
    M["knuckle"] = material("GloveKnuckle", (0.012, 0.012, 0.011), 0.6)      # 검은 마디 보호대
    M["sleeve"] = material("Sleeve", (0.03, 0.036, 0.018), 0.9)         # 짙은 올리브 소매       # 올리브색 겉옷 소매


def _obj(mesh_fn, mat):
    mesh_fn()
    o = bpy.context.object
    o.data.materials.append(M[mat])
    return o


def box(center, size, mat, rot=None, bevel=0.0):
    o = _obj(lambda: bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0)), mat)
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = o.modifiers.new("b", "BEVEL")
        mod.width = bevel
        mod.segments = 2 if bevel >= 0.004 else 1          # 손처럼 큰 모서리는 둥글게
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if rot is not None:
        o.data.transform(rot)
    o.data.transform(Matrix.Translation(center))
    return o


def cyl(p0, p1, r, mat, segs=8, caps=True):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = _obj(lambda: bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=d.length,
                                                         end_fill_type="NGON" if caps else "NOTHING"), mat)
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    o.data.transform(rot)
    o.data.transform(Matrix.Translation((p0 + p1) / 2))
    return o


def ball(c, r, mat, segs=8):
    o = _obj(lambda: bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=r), mat)
    o.data.transform(Matrix.Translation(Vector(c)))
    return o


def finger(p0, p1, r, mat="glove"):
    """손가락 한 마디: 원기둥 + 끝 공."""
    return [cyl(p0, p1, r, mat, segs=7), ball(p1, r * 0.98, mat, segs=7)]


def wrap(z_local, R, r, sx, y_off=0.0, mat="glove", cut=0.3):
    """손잡이를 감싸는 손가락 (도넛 일부). 손잡이 축 위 z_local 높이에서 앞쪽을 남긴다 (cut 클수록 뒤로 더 감쌈)."""
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=16, minor_segments=6)
    o = bpy.context.object
    o.data.materials.append(M[mat])
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -cut * R], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.transform(Matrix.Diagonal((sx, 1, 1, 1)))
    o.data.transform(Matrix.Translation((0, y_off, z_local)))
    o.data.transform(GRIP_ROT)
    o.data.transform(Matrix.Translation(GRIP_CENTER))
    return o


def grip_point(x, y, z):
    """손잡이 축 기준 좌표 → 실제 좌표."""
    return GRIP_CENTER + (GRIP_ROT @ Vector((x, y, z, 1))).to_3d()


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    o.data.name = name
    return o


def set_origin(o, point):
    """물체의 원점을 point 로 (메시는 제자리)."""
    p = Vector(point)
    o.data.transform(Matrix.Translation(-p))
    o.location = p


def build_slide():
    L = SLIDE_Y1 - SLIDE_Y0
    parts = [box((0, (SLIDE_Y0 + SLIDE_Y1) / 2, 0.058), (0.026, L, 0.030), "slide", bevel=0.0025)]
    for i in range(7):                                          # 뒤쪽 톱니(세레이션)
        y = SLIDE_Y0 + 0.008 + i * 0.0045
        parts.append(box((0, y, 0.057), (0.0275, 0.0018, 0.022), "frame"))
    for i in range(5):                                          # 앞쪽 톱니
        y = SLIDE_Y1 - 0.042 + i * 0.0045
        parts.append(box((0, y, 0.057), (0.0275, 0.0018, 0.018), "frame"))
    parts.append(box((0.0132, 0.030, 0.064), (0.001, 0.034, 0.010), "bore"))       # 탄피 배출구
    parts.append(box((0, SLIDE_Y1 - 0.008, 0.0765), (0.004, 0.006, 0.005), "steel"))  # 앞 가늠쇠
    parts.append(box((0, SLIDE_Y0 + 0.006, 0.0775), (0.020, 0.006, 0.007), "frame"))  # 뒤 가늠자
    parts.append(cyl((0, SLIDE_Y1 - 0.002, BORE_Z), (0, SLIDE_Y1 + 0.0012, BORE_Z), 0.0062, "steel", segs=12))
    parts.append(cyl((0, SLIDE_Y1 - 0.001, BORE_Z), (0, SLIDE_Y1 + 0.0014, BORE_Z), 0.0042, "bore", segs=12))
    slide = join(parts, "Slide")

    optic = join([
        box((0, 0.008, 0.083), (0.024, 0.040, 0.020), "frame", bevel=0.002),        # 조준경 몸통
        box((0, 0.012, 0.086), (0.018, 0.030, 0.012), "glass"),                     # 유리창 (앞뒤로 뚫린 느낌)
        ball((0, 0.026, 0.086), 0.0012, "dot", segs=6),                              # 빨간 점
        box((0.0125, 0.0, 0.086), (0.002, 0.012, 0.010), "steel"),                   # 옆 버튼
    ], "Optic")
    set_origin(slide, (0, 0, BORE_Z))
    set_origin(optic, (0, 0.008, 0.083))
    # 조준경을 슬라이드의 자식으로 (슬라이드와 함께 움직임). 위치는 슬라이드 기준으로 다시 적는다
    world = optic.location.copy()
    optic.parent = slide
    optic.matrix_parent_inverse.identity()
    optic.location = world - slide.location
    return slide


def build_frame():
    parts = [
        box((0, 0.050, 0.036), (0.022, 0.170, 0.018), "frame", bevel=0.002),        # 몸통 (슬라이드 아래)
        box((0, 0.118, 0.024), (0.018, 0.034, 0.006), "frame"),                      # 앞 레일
        box(grip_point(0, 0, 0), (0.030, 0.052, 0.108), "grip", rot=GRIP_ROT, bevel=0.006),  # 손잡이
        box((0, 0.038, 0.004), (0.010, 0.004, 0.026), "frame"),                      # 방아쇠울 앞
        box((0, 0.019, -0.009), (0.010, 0.040, 0.004), "frame"),                     # 방아쇠울 아래
        box((0, -0.042, 0.050), (0.018, 0.012, 0.012), "frame", bevel=0.002),        # 뒤 비버테일
        box((0, -0.050, 0.060), (0.008, 0.008, 0.010), "frame"),                     # 공이치기
        box((-0.0125, 0.012, 0.042), (0.004, 0.024, 0.004), "steel"),                # 슬라이드 멈치 (왼쪽)
    ]
    for gx in (0.0152, -0.0152):                                                     # 손잡이 나사 두 개씩
        for gz in (0.022, -0.040):
            parts.append(cyl(grip_point(gx * 0.98, 0.004, gz), grip_point(gx * 1.12, 0.004, gz), 0.0028, "steel", segs=8))
    return join(parts, "Frame")


def build_trigger():
    t = box((0, 0.026, 0.012), (0.005, 0.005, 0.020), "steel")
    t.data.transform(Matrix.Translation((0, -0.026, -0.012)) @ Matrix.Rotation(math.radians(12), 4, "X") @ Matrix.Translation((0, 0.026, 0.012)))
    t.name = "Trigger"
    return t


def build_magazine():
    top = grip_point(0, 0.002, 0.050)
    body = box(grip_point(0, 0.002, -0.004), (0.022, 0.034, 0.108), "frame", rot=GRIP_ROT)
    base = box(grip_point(0, 0.002, -0.061), (0.032, 0.054, 0.008), "frame", rot=GRIP_ROT, bevel=0.002)
    lip = box(grip_point(0, 0.006, 0.052), (0.010, 0.020, 0.004), "steel", rot=GRIP_ROT)    # 맨 위 탄 (황동색은 생략)
    mag = join([body, base, lip], "Magazine")
    set_origin(mag, top)
    return mag


def build_hand_right():
    """오른손: 손잡이를 쥔다. 1인칭 카메라(오른쪽 뒤 위)에서 손등·손가락 마디가 보이게."""
    p = [
        box(grip_point(0.004, -0.036, -0.018), (0.038, 0.022, 0.076), "glove", rot=GRIP_ROT, bevel=0.007),   # 손바닥 뒤꿈치
        box(grip_point(0.021, -0.012, -0.016), (0.016, 0.050, 0.070), "glove", rot=GRIP_ROT, bevel=0.007),   # 손등 (오른쪽)
        box(grip_point(0.0295, -0.008, -0.004), (0.004, 0.026, 0.040), "knuckle", rot=GRIP_ROT),             # 손등 보호대
    ]
    for z in (-0.002, -0.021, -0.040):                                                       # 가운데·약지·새끼 손가락
        p.append(wrap(z, 0.031, 0.0085, 0.68, y_off=0.004, cut=0.35))
        p.append(ball(grip_point(0.021, 0.012, z), 0.0092, "knuckle", segs=8))               # 손가락 마디 (검은 보호대)
    p += finger((0.0185, -0.006, 0.030), (0.0185, 0.040, 0.031), 0.0080)                     # 검지: 방아쇠울 위로 곧게
    p.append(ball((0.0185, 0.012, 0.031), 0.0086, "knuckle", segs=8))
    p += finger((-0.018, -0.034, 0.040), (-0.0195, 0.016, 0.043), 0.0086)                    # 엄지: 왼쪽 몸통을 따라
    p.append(cyl(grip_point(0.012, -0.040, -0.050), (0.068, -0.180, -0.098), 0.021, "glove", segs=10))    # 손목
    p.append(cyl((0.052, -0.125, -0.074), (0.092, -0.225, -0.122), 0.026, "sleeve", segs=10))            # 소매
    return join(p, "HandRight")


def build_hand_left():
    """왼손: 오른손 손가락을 아래·앞에서 감싸 받친다. 손가락 끝이 오른쪽까지 돌아와 카메라에 보인다."""
    p = [
        box(grip_point(-0.028, -0.004, -0.026), (0.016, 0.062, 0.072), "glove", rot=GRIP_ROT, bevel=0.007),  # 손바닥 (왼쪽 면)
        box(grip_point(-0.0365, -0.004, -0.018), (0.004, 0.030, 0.040), "knuckle", rot=GRIP_ROT),
    ]
    for z in (-0.013, -0.031, -0.049):                                                       # 오른손 손가락 위를 감싼다
        p.append(wrap(z, 0.041, 0.0088, 0.74, y_off=0.010, cut=0.62))
    p += finger((-0.021, -0.008, 0.029), (-0.0205, 0.034, 0.030), 0.0088)                    # 엄지: 앞쪽을 가리키며
    p.append(cyl(grip_point(-0.026, -0.028, -0.058), (-0.085, -0.185, -0.110), 0.021, "glove", segs=10))
    p.append(cyl((-0.064, -0.125, -0.084), (-0.102, -0.225, -0.132), 0.026, "sleeve", segs=10))
    hand = join(p, "HandLeft")
    set_origin(hand, grip_point(-0.028, -0.004, -0.026))
    return hand


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats()
    frame = build_frame()
    slide = build_slide()
    trig = build_trigger()
    mag = build_magazine()
    hr = build_hand_right()
    hl = build_hand_left()
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=a.out, export_format="GLB", export_yup=True, export_apply=True)
    print("MAKE_PISTOL tris %d, objects %s" % (tris, sorted(o.name for o in bpy.context.scene.objects)))
    print("MAKE_PISTOL muzzle (Godot) = (0, %.3f, %.3f)" % (BORE_Z, -SLIDE_Y1))
    print("MAKE_PISTOL magazine top (Godot) = (%.3f, %.3f, %.3f), grip axis down (Godot) = (0, %.3f, %.3f)" % (
        mag.location.x, mag.location.z, -mag.location.y,
        -math.cos(GRIP_TILT), -math.sin(GRIP_TILT)))
    print("MAKE_PISTOL out " + a.out)


main()
