"""glb 파일이 TECH_SPEC 5.2(단위·원점·이름·정면), 5.3(폴리곤 예산), 5.4(좀비 애니메이션)를 지키는지 검사한다.

사용:
  blender -b --factory-startup --python art/blender/validate.py -- godot/assets/models/zombie_walker.glb [...]
위반이 하나라도 있으면 종료 코드 1 (파이프라인에서 실패로 처리).
"""
import math
import re
import sys

import bpy
from mathutils import Vector

# TECH_SPEC 5.3
BUDGET = {"zombie_": 10000, "weapon_": 5000, "prop_": 2000, "env_": 5000}
PREFIXES = ("zombie_", "prop_", "env_", "weapon_", "fx_")
ZOMBIE_HEIGHT = (1.7, 1.9)          # 5.2 좀비 키
TANK_HEIGHT = (2.0, 2.4)            # 5.2 예외: 탱커(zombie_tank)만
ORIGIN_TOL = 0.02                    # 발밑이 지면(0)에서 2cm 이내
IN_PLACE_TOL = 0.05                  # 5.4 walk/run 수평 이동 5cm 이내
REQUIRED = ["idle", "attack", "hit", "death"]   # WU-20: idle, walk 또는 run, attack, hit, death


MAX_TEXTURE = 1024                  # 5.2 텍스처 최대 1024×1024


def glb_texture_sizes(path):
    """glb 안에 들어 있는 그림(PNG·JPEG)의 가로·세로를 파일에서 직접 읽는다."""
    import json
    import struct
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    sizes = []
    for img in gltf.get("images", []):
        if "bufferView" not in img:
            continue
        bv = gltf["bufferViews"][img["bufferView"]]
        raw = data[bin_start + bv.get("byteOffset", 0): bin_start + bv.get("byteOffset", 0) + bv["byteLength"]]
        if raw[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", raw[16:24])
        elif raw[:2] == b"\xff\xd8":
            i, w, h = 2, 0, 0
            while i < len(raw) - 9:
                if raw[i] != 0xFF:
                    i += 1
                    continue
                marker, seg = raw[i + 1], struct.unpack(">H", raw[i + 2:i + 4])[0]
                if marker in (0xC0, 0xC1, 0xC2):
                    h, w = struct.unpack(">HH", raw[i + 5:i + 9])
                    break
                i += 2 + seg
        else:
            continue
        sizes.append((img.get("name", "?"), w, h))
    return sizes


def check(path):
    fails, notes = [], []
    name = path.replace("\\", "/").split("/")[-1]
    stem = name.rsplit(".", 1)[0]

    # 5.2 이름: 소문자 스네이크케이스 + 접두사
    if not re.fullmatch(r"[a-z0-9]+(_[a-z0-9]+)*", stem):
        fails.append("이름이 소문자_스네이크케이스가 아님: " + stem)
    prefix = next((p for p in PREFIXES if stem.startswith(p)), None)
    if not prefix:
        fails.append("접두사 없음 (zombie_/prop_/env_/weapon_/fx_): " + stem)

    # 5.2 텍스처 크기
    for tname, w, h in glb_texture_sizes(path):
        notes.append("그림 %s %dx%d" % (tname, w, h))
        if max(w, h) > MAX_TEXTURE:
            fails.append("그림 %s %dx%d > %d" % (tname, w, h, MAX_TEXTURE))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    scene = bpy.context.scene
    arms = [o for o in scene.objects if o.type == "ARMATURE"]
    # glTF 를 불러오면 Blender 가 뼈 표시용 도형(Icosphere)을 만든다. 파일 안의 메시가 아니므로 뺀다
    bone_shapes = {pb.custom_shape for a in arms for pb in a.pose.bones if pb.custom_shape}
    meshes = [o for o in scene.objects if o.type == "MESH" and o not in bone_shapes]

    # 5.3 삼각형
    tris = sum(len(o.data.polygons) and sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    limit = BUDGET.get(prefix)
    notes.append("삼각형 %d%s" % (tris, " / 상한 %d" % limit if limit else ""))
    if limit and tris > limit:
        fails.append("삼각형 %d 개 > 상한 %d" % (tris, limit))

    # 5.2 크기·원점: 기본 자세(rest)에서 잰다
    for a in arms:
        a.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in m.vertices]
        ev.to_mesh_clear()
    if pts:
        lo_z = min(p.z for p in pts)
        height = max(p.z for p in pts) - lo_z
        cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
        cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
        notes.append("키 %.3f m, 발밑 z %.3f, 중심 (%.2f, %.2f)" % (height, lo_z, cx, cy))
        if abs(lo_z) > ORIGIN_TOL:
            fails.append("원점이 발밑이 아님 (최저점 z = %.3f)" % lo_z)
        if prefix == "zombie_":
            lo, hi = TANK_HEIGHT if stem.startswith("zombie_tank") else ZOMBIE_HEIGHT
            if not (lo <= height <= hi):
                fails.append("좀비 키 %.3f m 가 %.1f - %.1f m 범위 밖" % (height, lo, hi))

    if prefix != "zombie_" or not arms:
        return name, fails, notes

    arm = arms[0]
    # 5.2 정면 -Z (Godot) = Blender 로 다시 가져오면 +Y. 발끝이 발목보다 +Y 쪽이어야 한다
    bones = {b.name.split(":")[-1].lower(): b for b in arm.data.bones}
    foot, toe = bones.get("leftfoot"), bones.get("lefttoebase")
    if foot and toe:
        dy = (arm.matrix_world @ toe.head_local).y - (arm.matrix_world @ foot.head_local).y
        notes.append("발끝 방향 %s" % ("+Y (Godot -Z)" if dy > 0 else "-Y (Godot +Z)"))
        if dy <= 0:
            fails.append("정면이 Godot -Z 가 아님")

    # 5.4 애니메이션 이름과 제자리 동작
    for a in arms:
        a.data.pose_position = "POSE"
    acts = {a.name.split("|")[0]: a for a in bpy.data.actions}
    notes.append("애니메이션: " + ", ".join(sorted(acts)))
    missing = [n for n in REQUIRED if n not in acts]
    if "walk" not in acts and "run" not in acts:
        missing.append("walk 또는 run")
    if missing:
        fails.append("애니메이션 없음: " + ", ".join(missing))

    hips = next((pb for pb in arm.pose.bones if pb.name.lower().endswith("hips")), None)
    ad = arm.animation_data or arm.animation_data_create()

    # 애니메이션이 실제로 뼈를 움직이는지: 이름만 있고 몸이 안 움직이는 파일을 막는다
    # (뼈 이름이 달라 동작이 입혀지지 않은 경우 — 예: mixamorig5: 와 mixamorig:)
    for n, act in sorted(acts.items()):
        ad.action = act
        if hasattr(ad, "action_slot") and ad.action_slot is None and getattr(act, "slots", None):
            ad.action_slot = act.slots[0]
        f0, f1 = (int(round(v)) for v in act.frame_range)
        poses = []
        for f in (f0, (f0 + f1) // 2, f1):
            scene.frame_set(f)
            poses.append([pb.matrix.copy() for pb in arm.pose.bones])
        moved = max(
            (a.to_quaternion().rotation_difference(b.to_quaternion()).angle
             for i in range(1, len(poses)) for a, b in zip(poses[0], poses[i])),
            default=0.0,
        )
        if moved < math.radians(1):
            fails.append("%s 애니메이션이 뼈를 움직이지 않음 (최대 회전 %.2f°)" % (n, math.degrees(moved)))

    for n in ("walk", "run"):
        if n not in acts or not hips:
            continue
        act = acts[n]
        ad.action = act
        if hasattr(ad, "action_slot") and ad.action_slot is None and getattr(act, "slots", None):
            ad.action_slot = act.slots[0]
        f0, f1 = (int(round(v)) for v in act.frame_range)
        ps = []
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            ps.append((arm.matrix_world @ hips.head).copy())
        move = max(math.hypot(p.x - ps[0].x, p.y - ps[0].y) for p in ps)
        notes.append("%s 수평 이동 %.3f m" % (n, move))
        if move > IN_PLACE_TOL:
            fails.append("%s 가 제자리 동작이 아님 (%.3f m 이동)" % (n, move))

    return name, fails, notes


def main():
    files = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bad = 0
    for f in files:
        name, fails, notes = check(f)
        print("VALIDATE %s: %s" % (name, "통과" if not fails else "실패"))
        for n in notes:
            print("VALIDATE   - " + n)
        for x in fails:
            print("VALIDATE   ✗ " + x)
        bad += bool(fails)
    sys.exit(1 if bad else 0)


main()
