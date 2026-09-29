"""Mixamo 캐릭터 + 애니메이션 FBX 를 TECH_SPEC 5.2-5.4 규격의 glb 하나로 만든다.

사용:
  blender -b --factory-startup --python art/blender/import_mixamo.py -- \
      --character "art/source/mixamo/scary_zombie_pack/X Bot.fbx" \
      --anim idle="art/source/mixamo/scary_zombie_pack/zombie idle.fbx" \
      --anim walk="art/source/mixamo/scary_zombie_pack/zombie walk.fbx" \
      --out godot/assets/models/zombie_walker.glb

하는 일 (규격 번호는 TECH_SPEC):
  - 애니메이션 이름을 --anim 에 준 이름으로 바꾼다            (5.4)
  - walk / run 은 제자리 동작(In Place)으로 만든다            (5.4 "이동 모션은 반드시 In Place")
    --in-place 로 hit 처럼 살아 있는 동안 쓰는 동작도 제자리로 만들 수 있다
  - 삼각형을 --max-tris 이하로 줄인다 (좀비 기본 10,000)       (5.3)
  - 정면이 Godot 기준 -Z 를 보게 돌린다                        (5.2 "캐릭터 정면은 -Z")
  - 원점은 발밑 중앙, 1 unit = 1 m 을 유지한다                 (5.2)
  - --height 로 기본 자세의 키를 맞춘다 (탱커 2.0 - 2.4 m 예외)  (5.2)
  - 그림을 한 변 --max-texture(기본 1024) 픽셀 이하로 줄인다     (5.2)
원본 FBX(art/source/)는 읽기만 하고 고치지 않는다.
"""
import argparse
import math
import sys

import bpy
from mathutils import Vector

IN_PLACE_DEFAULT = "walk,run"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--character", required=True)
    p.add_argument("--anim", action="append", default=[], help="이름=파일.fbx")
    p.add_argument("--out", required=True)
    p.add_argument("--max-tris", type=int, default=10000)
    p.add_argument("--target-tris", type=int, default=9000, help="여유를 두고 줄일 목표")
    p.add_argument("--in-place", default=IN_PLACE_DEFAULT,
                   help="제자리로 만들 동작 이름들 (쉼표). 5.4 는 walk·run 필수, 살아 있는 동안 쓰는 hit 도 권장")
    p.add_argument("--height", type=float, default=0.0,
                   help="기본 자세의 키를 이 값(m)으로 맞춘다. 0 이면 그대로 (탱커 2.0 - 2.4 m 예외, 5.2)")
    p.add_argument("--max-texture", type=int, default=1024, help="그림 한 변 최대 픽셀 (5.2)")
    return p.parse_args(argv)


def rest_height(arm, meshes):
    """기본 자세(rest)에서 메시의 키. 동작 때문에 달라지지 않게 rest 로 잰다."""
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    zs = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        zs += [(ev.matrix_world @ v.co).z for v in m.vertices]
        ev.to_mesh_clear()
    arm.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    return max(zs) - min(zs)


def shrink_textures(limit):
    """그림을 한 변 limit 픽셀 이하로 줄이고, 줄인 그림을 파일 안에 넣는다(pack)."""
    done = []
    for img in bpy.data.images:
        w, h = img.size
        if max(w, h) <= limit or w == 0:
            continue
        k = limit / max(w, h)
        img.scale(max(1, int(w * k)), max(1, int(h * k)))
        img.pack()
        done.append("%s %dx%d -> %dx%d" % (img.name, w, h, img.size[0], img.size[1]))
    return done


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def armature_of(objs):
    return next(o for o in objs if o.type == "ARMATURE")


def count_tris(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for o in meshes:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        m.calc_loop_triangles()
        total += len(m.loop_triangles)
        ev.to_mesh_clear()
    return total


def decimate(meshes, target, limit):
    """상한(limit)을 넘을 때만 목표(target)까지 줄인다. 메시마다 같은 비율, 가중치(뼈대 연결)는 보간해 유지."""
    now = count_tris(meshes)
    if now <= limit:
        return now, now
    ratio = target / now
    for o in meshes:
        mod = o.modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
            bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
            bpy.ops.object.modifier_apply(modifier=mod.name)
    return now, count_tris(meshes)


def hips_bone(arm):
    return next(pb for pb in arm.pose.bones if pb.name.lower().endswith("hips"))


def assign(arm, action):
    """동작을 뼈대에 붙인다. Blender 4.4+ 는 동작 안의 슬롯도 지정해야 실제로 움직인다."""
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and ad.action_slot is None and getattr(action, "slots", None):
        ad.action_slot = action.slots[0]
    return ad


def make_in_place(arm, action):
    """Hips 의 수평 이동(월드 X·Y)을 매 프레임 지워 제자리 동작으로 만든다. 높이(Z)는 둔다."""
    assign(arm, action)
    scene = bpy.context.scene
    pb = hips_bone(arm)
    f0, f1 = (int(round(v)) for v in action.frame_range)
    scene.frame_set(f0)
    start = arm.matrix_world @ pb.head
    # 월드 이동량 → Hips 의 로컬 location 공간으로 바꾸는 행렬 (Hips 는 뼈대의 뿌리)
    to_local = (arm.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()).inverted()
    fixes = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        w = arm.matrix_world @ pb.head
        drift = Vector((w.x - start.x, w.y - start.y, 0.0))
        fixes.append((f, pb.location - to_local @ drift))
    for f, loc in fixes:
        pb.location = loc
        pb.keyframe_insert("location", frame=f)
    scene.frame_set(f0)


def horizontal_move(arm, action):
    assign(arm, action)
    scene = bpy.context.scene
    pb = hips_bone(arm)
    f0, f1 = (int(round(v)) for v in action.frame_range)
    pts = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        pts.append((arm.matrix_world @ pb.head).copy())
    return max(math.hypot(p.x - pts[0].x, p.y - pts[0].y) for p in pts)


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)

    char_objs = import_fbx(args.character)
    arm = armature_of(char_objs)
    meshes = [o for o in char_objs if o.type == "MESH"]
    # 캐릭터 파일에 들어 있던 동작(T자 2프레임 등)은 쓰지 않는다
    if arm.animation_data:
        arm.animation_data.action = None
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)

    # 키 맞추기: 뼈대 오브젝트의 크기만 바꾼다 (뼈 안의 이동값은 그대로 두어야 동작이 어긋나지 않는다)
    h0 = rest_height(arm, meshes)
    h1 = h0
    if args.height > 0:
        arm.scale *= args.height / h0
        bpy.context.view_layer.update()
        h1 = rest_height(arm, meshes)

    # 애니메이션 파일마다 동작만 꺼내 오고, 같이 딸려 온 뼈대·메시는 지운다
    named = []
    for spec in args.anim:
        name, path = spec.split("=", 1)
        objs = import_fbx(path)
        src = armature_of(objs)
        act = src.animation_data.action
        # 동작이 움직이는 뼈 중 이 캐릭터에 없는 뼈 (있으면 그 부분만 안 움직인다)
        missing = sorted({b.name for b in src.data.bones} - {b.name for b in arm.data.bones})
        if missing:
            print("IMPORT_MIXAMO warn %s: 캐릭터에 없는 뼈 %d개 %s" % (name, len(missing), missing[:5]))
        act.name = name
        act.use_fake_user = True
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        named.append((name, act))

    if arm.animation_data is None:
        arm.animation_data_create()

    in_place = {n.strip() for n in args.in_place.split(",") if n.strip()}
    report = {}
    for name, act in named:
        if name in in_place:
            before = horizontal_move(arm, act)
            make_in_place(arm, act)
            report[name] = (round(before, 3), round(horizontal_move(arm, act), 3))

    # 정면을 Godot -Z 로: Mixamo 캐릭터는 Blender -Y 를 보고, glTF 로 가면 +Z 가 된다 → 180° 돌린다
    arm.rotation_euler.z += math.pi
    bpy.context.view_layer.update()

    tris_before, tris_after = decimate(meshes, args.target_tris, args.max_tris)

    # 애니메이션마다 NLA 트랙 하나 → glTF 애니메이션 이름 = 트랙 이름
    arm.animation_data.action = None
    for name, act in named:
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, int(act.frame_range[0]), act)
        if hasattr(strip, "action_slot") and strip.action_slot is None and getattr(act, "slots", None):
            strip.action_slot = act.slots[0]

    shrunk = shrink_textures(args.max_texture)

    bpy.ops.export_scene.gltf(
        filepath=args.out,
        export_format="GLB",
        export_animation_mode="NLA_TRACKS",
        export_yup=True,
    )

    print("IMPORT_MIXAMO height %.3f m -> %.3f m" % (h0, h1))
    for s in shrunk:
        print("IMPORT_MIXAMO texture " + s)
    print("IMPORT_MIXAMO tris %d -> %d (max %d)" % (tris_before, tris_after, args.max_tris))
    for name, (b, a) in report.items():
        print("IMPORT_MIXAMO in_place %s: %.3f m -> %.3f m" % (name, b, a))
    print("IMPORT_MIXAMO anims " + ",".join(n for n, _ in named))
    print("IMPORT_MIXAMO out " + args.out)


main()
