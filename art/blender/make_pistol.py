"""1인칭 권총 + 총을 쥔 장갑 손 — weapon_pistol.glb (TECH_SPEC 13.3.1 ①-2, 주인 A)
사진 참고 없이 "긴 슬라이드 + 빨간 점 조준경 + 오돌토돌한 손잡이" 형태를 직접 만든다 (라이선스 걱정 없음).

사용 (게임용 — Mixamo 손):
  blender -b --factory-startup --python art/blender/make_pistol.py --       --arms-fbx art/source/mixamo/swat_pistol/Swat.fbx       --arms-anim "art/source/mixamo/swat_pistol/pistol idle.fbx"       --out godot/assets/models/weapon_pistol.glb
  (--arms-fbx 를 빼면 도형으로 만든 간단한 손 — Mixamo 원본이 없는 PC 용)

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
    p.add_argument("--arms-fbx", default="", help="Mixamo 캐릭터 FBX — 주면 스크립트 손 대신 이 캐릭터의 팔(팔꿈치 아래)을 쓴다")
    p.add_argument("--arms-anim", default="", help="두 손으로 권총을 쥔 Mixamo 동작 FBX (예: pistol idle)")
    p.add_argument("--arms-frame", type=int, default=10, help="그 동작에서 손 모양을 가져올 프레임")
    p.add_argument("--grip", default="0.035,0.020,0.004,6",
                   help="오른손 손목에서 손잡이까지: 손끝 방향 m, 위 m, 오른쪽 m, 총구 좌우 각도(도)")
    p.add_argument("--max-texture", type=int, default=1024)
    p.add_argument("--sleeve", default="0.30,0.32,0.22",
                   help="소매(원래 SWAT 파란색) 를 바꿀 색 (선형 RGB). 기본 짙은 올리브. 빈 값이면 그대로")
    p.add_argument("--max-tris", type=int, default=4900, help="TECH_SPEC 5.3 weapon_ 5000 안쪽")
    return p.parse_args(argv)


def material(name, color, rough, metal=0.0, emit=None, strength=6.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal    # 어두운 맵에서 새까매지지 않게 낮게 (PR #3)
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


M = {}


def mats():
    M["slide"] = material("SlideBlack", (0.022, 0.023, 0.025), 0.38, 0.3)
    M["frame"] = material("FrameBlack", (0.014, 0.014, 0.015), 0.5, 0.2)
    M["grip"] = material("GripStipple", (0.009, 0.009, 0.010), 0.95)
    M["steel"] = material("Steel", (0.45, 0.45, 0.47), 0.3, 0.5)
    M["bore"] = material("Bore", (0.005, 0.005, 0.005), 0.9)
    M["glass"] = material("OpticGlass", (0.12, 0.2, 0.14), 0.05, 0.0, emit=(0.35, 0.18, 0.05), strength=0.5)   # 무지갯빛 코팅 렌즈 느낌 (초록 + 주황 빛)
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
    """사진 속 긴 슬라이드: 위 모서리를 깎은 긴 몸통, 뒤쪽 세로 톱니, 앞쪽 아래 비스듬한 톱니, 뒤 가늠자."""
    L = SLIDE_Y1 - SLIDE_Y0
    cy = (SLIDE_Y0 + SLIDE_Y1) / 2
    parts = [
        box((0, cy, 0.056), (0.025, L, 0.026), "slide", bevel=0.0035),              # 슬라이드 몸통 (위 모서리 둥글게)
        box((0, cy + 0.004, 0.0705), (0.017, L - 0.010, 0.004), "slide", bevel=0.0015),  # 윗면 (좁게 → 깎인 느낌)
    ]
    for i in range(8):                                          # 뒤쪽 세로 톱니 (양옆 홈)
        y = SLIDE_Y0 + 0.010 + i * 0.0042
        parts.append(box((0, y, 0.058), (0.0262, 0.0016, 0.020), "bore"))
    slant = Matrix.Rotation(math.radians(-28), 4, "X")         # 앞쪽 아래 비스듬한 톱니
    for i in range(5):
        y = SLIDE_Y1 - 0.050 + i * 0.0048
        parts.append(box((0, y, 0.049), (0.0262, 0.0016, 0.012), "bore", rot=slant))
    parts.append(box((0.0127, 0.028, 0.063), (0.001, 0.032, 0.009), "bore"))       # 탄피 배출구
    parts.append(box((0, SLIDE_Y1 - 0.007, 0.0745), (0.0035, 0.006, 0.005), "steel"))  # 앞 가늠쇠
    parts.append(box((0, SLIDE_Y0 + 0.006, 0.0745), (0.021, 0.008, 0.009), "frame", bevel=0.001))  # 뒤 가늠자 (조준경 뒤)
    parts.append(box((0, SLIDE_Y0 + 0.006, 0.0795), (0.004, 0.008, 0.002), "bore"))  # 가늠자 홈
    parts.append(cyl((0, SLIDE_Y1 - 0.002, BORE_Z), (0, SLIDE_Y1 + 0.0012, BORE_Z), 0.0062, "steel", segs=12))
    parts.append(cyl((0, SLIDE_Y1 - 0.001, BORE_Z), (0, SLIDE_Y1 + 0.0014, BORE_Z), 0.0042, "bore", segs=12))
    slide = join(parts, "Slide")

    hood = Matrix.Rotation(math.radians(24), 4, "X")            # 앞이 비스듬히 솟은 조준경 덮개
    optic = join([
        box((0, 0.002, 0.0765), (0.024, 0.036, 0.006), "frame", bevel=0.001),       # 받침
        box((-0.0105, 0.004, 0.086), (0.003, 0.030, 0.016), "frame", bevel=0.001),  # 왼쪽 벽
        box((0.0105, 0.004, 0.086), (0.003, 0.030, 0.016), "frame", bevel=0.001),   # 오른쪽 벽
        box((0, 0.012, 0.0945), (0.024, 0.020, 0.003), "frame", rot=hood),          # 덮개 (비스듬)
        box((0, -0.010, 0.0835), (0.018, 0.010, 0.010), "frame", bevel=0.001),      # 뒤 몸통 (전지)
        box((0, 0.016, 0.0865), (0.018, 0.002, 0.014), "glass"),                    # 렌즈 (무지갯빛)
        ball((0, 0.0165, 0.0865), 0.0011, "dot", segs=6),                            # 빨간 점
        box((0.0125, -0.008, 0.083), (0.002, 0.008, 0.006), "steel"),                # 옆 버튼
    ], "Optic")
    set_origin(slide, (0, 0, BORE_Z))
    set_origin(optic, (0, 0.002, 0.0765))
    # 조준경을 슬라이드의 자식으로 (슬라이드와 함께 움직임). 위치는 슬라이드 기준으로 다시 적는다
    world = optic.location.copy()
    optic.parent = slide
    optic.matrix_parent_inverse.identity()
    optic.location = world - slide.location
    return slide


def build_frame():
    """사진 속 몸통: 슬라이드 끝까지 이어진 몸통 + 아래 레일(홈 3개), 각진 방아쇠울, 비버테일·공이치기,
    긴 슬라이드 멈치와 디코커, 손잡이 판(오돌토돌) 양쪽 + 나사 두 개씩."""
    parts = [
        box((0, 0.055, 0.035), (0.022, 0.180, 0.018), "frame", bevel=0.0025),       # 몸통 (앞 끝까지)
        box((0, 0.112, 0.0235), (0.019, 0.050, 0.007), "frame", bevel=0.001),       # 아래 레일
        box(grip_point(0, 0, 0), (0.028, 0.050, 0.108), "frame", rot=GRIP_ROT, bevel=0.006),  # 손잡이 뼈대
        box((0, 0.043, 0.006), (0.010, 0.005, 0.030), "frame"),                     # 방아쇠울 앞 (각지게)
        box((0, 0.020, -0.0085), (0.010, 0.050, 0.005), "frame"),                   # 방아쇠울 아래
        box((0, -0.040, 0.049), (0.020, 0.018, 0.012), "frame", bevel=0.003),       # 비버테일
        box((0, -0.047, 0.062), (0.008, 0.008, 0.012), "frame", bevel=0.001),       # 공이치기
        box((-0.0125, 0.016, 0.043), (0.004, 0.032, 0.004), "steel"),               # 슬라이드 멈치 (왼쪽, 길게)
        box((-0.0125, -0.006, 0.030), (0.004, 0.014, 0.005), "frame"),              # 디코커
    ]
    for i in range(3):                                                              # 레일 홈
        parts.append(box((0, 0.096 + i * 0.012, 0.0195), (0.0195, 0.004, 0.002), "bore"))
    for side in (1, -1):                                                            # 손잡이 판 양쪽 (오돌토돌)
        parts.append(box(grip_point(side * 0.0152, 0.004, -0.010), (0.0026, 0.040, 0.090), "grip", rot=GRIP_ROT, bevel=0.001))
        for gz in (0.024, -0.042):                                                  # 나사 위·아래
            parts.append(cyl(grip_point(side * 0.0160, 0.004, gz), grip_point(side * 0.0172, 0.004, gz), 0.0026, "steel", segs=8))
    return join(parts, "Frame")


def build_trigger():
    t = box((0, 0.026, 0.012), (0.005, 0.005, 0.020), "steel")
    t.data.transform(Matrix.Translation((0, -0.026, -0.012)) @ Matrix.Rotation(math.radians(12), 4, "X") @ Matrix.Translation((0, 0.026, 0.012)))
    t.name = "Trigger"
    return t


def build_magazine():
    top = grip_point(0, 0.002, 0.050)
    body = box(grip_point(0, 0.002, -0.004), (0.022, 0.034, 0.108), "frame", rot=GRIP_ROT)
    base = box(grip_point(0, 0.004, -0.062), (0.034, 0.052, 0.010), "frame", rot=GRIP_ROT, bevel=0.0025)   # 넓은 바닥판
    lip = box(grip_point(0, 0.006, 0.052), (0.010, 0.020, 0.004), "steel", rot=GRIP_ROT)
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


def build_mixamo_hands(a):
    """Mixamo 캐릭터를 권총 쥔 자세로 굳히고, 팔꿈치 아래(ForeArm·Hand 뼈에 붙은 부분)만 남겨
    권총 좌표(원점 = 손잡이)로 옮긴다. 뼈대는 버린다 (TECH_SPEC D6 — 손은 총과 함께 움직인다).
    원본 FBX 는 art/source/ (git 제외, 재배포 금지). glb 에는 잘라 낸 팔만 들어간다."""
    before = set(bpy.context.scene.objects)                             # 총 부품은 건드리지 않는다
    bpy.ops.import_scene.fbx(filepath=a.arms_fbx)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in before]
    bpy.ops.import_scene.fbx(filepath=a.arms_anim)
    arm2 = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE" and o != arm)
    act = arm2.animation_data.action
    for o in list(bpy.context.scene.objects):
        if o == arm2 or o.parent == arm2:
            bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data_create()
    arm.animation_data.action = act
    if getattr(act, "slots", None):
        arm.animation_data.action_slot = act.slots[0]
    bpy.context.scene.frame_set(a.arms_frame)

    def bone(n):
        return next(b for b in arm.pose.bones if b.name.endswith(n))
    rhb = bone("RightHand")
    rh = arm.matrix_world @ rhb.head
    d = (arm.matrix_world.to_3x3() @ (rhb.tail - rhb.head)).normalized()
    f, u, x, yaw = [float(v) for v in a.grip.split(",")]
    F = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0)).normalized()   # 캐릭터는 -Y 를 본다
    U = Vector((0, 0, 1))
    R = F.cross(U)
    gun = Matrix((R, F, U)).transposed().to_4x4()
    gun.translation = rh + d * f + U * u + R * x
    to_gun = gun.inverted()

    parts = {"Right": [], "Left": []}
    for m in meshes:
        bpy.context.view_layer.objects.active = m
        for mod in list(m.modifiers):
            if mod.type == "ARMATURE":
                bpy.ops.object.modifier_apply(modifier=mod.name)          # 자세를 메시에 굳힘
        world = m.matrix_world.copy()
        m.parent = None
        m.matrix_world = world
        for side in ("Right", "Left"):
            c = m.copy()
            c.data = m.data.copy()
            bpy.context.scene.collection.objects.link(c)
            keep = {g.index for g in c.vertex_groups if g.name.split(":")[-1].startswith(side) and
                    any(k in g.name for k in ("ForeArm", "Hand"))}
            bm = bmesh.new()
            bm.from_mesh(c.data)
            dl = bm.verts.layers.deform.active
            kill = [v for v in bm.verts if not dl or sum(w for gi, w in v[dl].items() if gi in keep) < 0.5]
            bmesh.ops.delete(bm, geom=kill, context="VERTS")
            bm.to_mesh(c.data)
            bm.free()
            if len(c.data.polygons):
                c.vertex_groups.clear()
                c.matrix_world = to_gun @ c.matrix_world
                parts[side].append(c)
            else:
                bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.objects.remove(m, do_unlink=True)
    bpy.data.objects.remove(arm, do_unlink=True)
    for o in list(bpy.context.scene.objects):                            # FBX 에서 따라온 빈 물체(Geo 등) 정리
        if o.type == "EMPTY" and o not in before:
            bpy.data.objects.remove(o, do_unlink=True)
    hands = []
    for side, objs in parts.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        h = join(objs, "Hand" + side)
        hands.append(h)
    if a.sleeve:
        recolor_blue(a.sleeve)
    hl = next(h for h in hands if h.name == "HandLeft")
    c = sum((Vector(v.co) for v in hl.data.vertices), Vector()) / len(hl.data.vertices)
    set_origin(hl, c)                                                    # 왼손만 통째로 옮기므로 원점을 손 가운데로
    for img in bpy.data.images:                                          # TECH_SPEC 5.2 그림 1024 이하
        if img.size[0] > a.max_texture or img.size[1] > a.max_texture:
            k = a.max_texture / max(img.size)
            img.scale(int(img.size[0] * k), int(img.size[1] * k))
            img.pack()
    return hands


def recolor_blue(color):
    """몸 색 그림에서 파란 부분(SWAT 제복)만 골라 같은 밝기의 다른 색으로 칠한다. 검은 장갑·금속은 그대로."""
    import numpy as np
    tint = np.array([float(v) for v in color.split(",")], dtype=np.float32)
    tint = tint / tint.max()
    imgs = set()
    for o in bpy.context.scene.objects:                                  # 손 재질의 몸 색(Base Color) 그림만
        if o.type != "MESH" or not o.name.startswith("Hand"):
            continue
        for m in o.data.materials:
            b = m and m.use_nodes and next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if b and b.inputs["Base Color"].is_linked:
                img = getattr(b.inputs["Base Color"].links[0].from_node, "image", None)
                if img:
                    imgs.add(img)
    for img in imgs:
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        rgb = px.reshape(-1, 4)[:, :3]
        r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
        mx, mn = rgb.max(axis=1), rgb.min(axis=1)
        blue = (b >= mx - 1e-6) & (b > r + 0.03) & ((mx - mn) > 0.04)                 # 파랗고 색이 있는 곳
        k = np.clip(((b - r) - 0.03) / 0.08, 0, 1) * blue                              # 경계는 부드럽게 섞음
        lum = rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32)
        new = (lum * 0.55)[:, None] * tint[None, :]                                    # 어둡고 탁하게 (올리브·검정 느낌)
        rgb[:] = rgb * (1 - k[:, None]) + new * k[:, None]
        px.reshape(-1, 4)[:, :3] = np.clip(rgb, 0, 1)
        img.pixels.foreach_set(px)
        img.update()
        img.pack()
        print("MAKE_PISTOL sleeve recolor %s: %.0f%% 픽셀" % (img.name, 100 * float(blue.mean())))


def limit_tris(limit, keep_names):
    """삼각형이 상한을 넘으면 손(팔)만 줄인다 — 총 모양은 그대로 둔다."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    count = lambda: sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    total = count()
    hands = [o for o in objs if o.name in keep_names]
    hand_tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in hands)
    if total <= limit or not hand_tris:
        return total
    ratio = max(0.3, 1 - (total - limit) / hand_tris)
    for h in hands:
        bpy.context.view_layer.objects.active = h
        mod = h.modifiers.new("dec", "DECIMATE")
        mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return count()


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats()
    frame = build_frame()
    slide = build_slide()
    trig = build_trigger()
    mag = build_magazine()
    if a.arms_fbx:
        build_mixamo_hands(a)
    else:
        build_hand_right()
        build_hand_left()
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and not (a.arms_fbx and o.name.startswith("Hand")):   # Mixamo 팔은 원래 매끈함 그대로
            o.select_set(True)
    bpy.context.view_layer.objects.active = frame
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    tris = limit_tris(a.max_tris, {"HandRight", "HandLeft"})
    bpy.ops.export_scene.gltf(filepath=a.out, export_format="GLB", export_yup=True, export_apply=True)
    print("MAKE_PISTOL tris %d, objects %s" % (tris, sorted(o.name for o in bpy.context.scene.objects)))
    print("MAKE_PISTOL muzzle (Godot) = (0, %.3f, %.3f)" % (BORE_Z, -SLIDE_Y1))
    print("MAKE_PISTOL magazine top (Godot) = (%.3f, %.3f, %.3f), grip axis down (Godot) = (0, %.3f, %.3f)" % (
        mag.location.x, mag.location.z, -mag.location.y,
        -math.cos(GRIP_TILT), -math.sin(GRIP_TILT)))
    print("MAKE_PISTOL out " + a.out)


main()
