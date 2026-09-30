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
  - --brightness 로 몸 색 그림만 밝게 한다 (종류끼리 구분이 안 될 때, WU-20 "4종이 서로 구분된다")
원본 FBX(art/source/)는 읽기만 하고 고치지 않는다.
"""
import argparse
import math
import re
import sys

import bpy
from mathutils import Vector

IN_PLACE_DEFAULT = "walk,run"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--character", required=True)
    p.add_argument("--anim", action="append", default=[], help="이름=파일.fbx")
    p.add_argument("--clip", action="append", default=[],
                   help="이미 넣은 동작의 일부 구간을 새 이름으로: 새이름=원래이름:시작:끝 (0 - 1 비율). "
                        "예: crouch_rise=getup:0.50:0.66 (누웠다 일어나는 동작에서 쭈그린 자세부터 선 자세까지)")
    p.add_argument("--out", required=True)
    p.add_argument("--max-tris", type=int, default=10000)
    p.add_argument("--target-tris", type=int, default=9000, help="여유를 두고 줄일 목표")
    p.add_argument("--in-place", default=IN_PLACE_DEFAULT,
                   help="제자리로 만들 동작 이름들 (쉼표). 5.4 는 walk·run 필수, 살아 있는 동안 쓰는 hit 도 권장")
    p.add_argument("--height", type=float, default=0.0,
                   help="기본 자세의 키를 이 값(m)으로 맞춘다. 0 이면 그대로 (탱커 2.0 - 2.4 m 예외, 5.2)")
    p.add_argument("--max-texture", type=int, default=1024, help="그림 한 변 최대 픽셀 (5.2)")
    p.add_argument("--brightness", type=float, default=1.0,
                   help="몸 색 그림(Base Color)의 밝기 배율. 1.25 = 한 단계(25%%) 밝게. 다른 그림은 그대로")
    p.add_argument("--zombify", type=float, default=0.0,
                   help="몸 색 그림을 썩은 피부색(회녹색)으로 바꾸고 얼룩·핏자국을 입힌다. 0 = 안 함, 1 = 최대")
    return p.parse_args(argv)


def brighten_base_color(factor):
    """재질의 Base Color 에 연결된 그림만 factor 배 밝게 한다 (1 을 넘는 값은 1 로)."""
    import numpy as np
    done = []
    seen = set()
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf or not bsdf.inputs["Base Color"].is_linked:
            continue
        img = getattr(bsdf.inputs["Base Color"].links[0].from_node, "image", None)
        if img is None or img.name in seen:
            continue
        seen.add(img.name)
        px = np.empty(len(img.pixels), dtype=np.float32)
        img.pixels.foreach_get(px)
        rgba = px.reshape(-1, 4)
        before = float(rgba[:, :3].mean())
        rgba[:, :3] = np.clip(rgba[:, :3] * factor, 0.0, 1.0)
        img.pixels.foreach_set(rgba.ravel())
        img.update()
        img.pack()
        done.append("%s 평균 밝기 %.3f -> %.3f" % (img.name, before, float(rgba[:, :3].mean())))
    return done


def smooth_noise(h, w, cells, rng):
    """부드러운 얼룩 무늬 (0 - 1). 작은 무작위 격자를 크게 늘린 뒤 흐리게 한다."""
    import numpy as np
    g = rng.random((cells + 1, cells + 1)).astype(np.float32)
    ys = np.linspace(0, cells, h, dtype=np.float32)
    xs = np.linspace(0, cells, w, dtype=np.float32)
    y0, x0 = np.minimum(ys.astype(int), cells - 1), np.minimum(xs.astype(int), cells - 1)
    fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)          # 부드럽게 이어지게
    a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy


def zombify_base_color(k):
    """몸 색 그림을 좀비답게: 색을 빼고(선명한 주황·파랑이 사라지게) 회녹색 썩은 살색을 입힌 뒤,
    때 얼룩으로 어둡게 하고 군데군데 마른 핏자국을 남긴다. 무작위 씨앗 고정이라 매번 같다."""
    import numpy as np
    rng = np.random.default_rng(13)
    done, seen = [], set()
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf or not bsdf.inputs["Base Color"].is_linked:
            continue
        img = getattr(bsdf.inputs["Base Color"].links[0].from_node, "image", None)
        if img is None or img.name in seen:
            continue
        seen.add(img.name)
        w, h = img.size
        px = np.empty(len(img.pixels), dtype=np.float32)
        img.pixels.foreach_get(px)
        rgb = px.reshape(h, w, 4)[:, :, :3]
        before = rgb.mean(axis=(0, 1))
        lum = (rgb @ np.array([0.3, 0.59, 0.11], dtype=np.float32))[:, :, None]
        rotten = lum * np.array([0.78, 0.86, 0.66], dtype=np.float32) * 1.15         # 회녹색 썩은 살
        out = rgb * (1 - k * 0.85) + rotten * (k * 0.85)                              # 원래 색은 15% 만 남김
        grime = smooth_noise(h, w, 24, rng)[:, :, None]
        out *= 1 - k * 0.35 * grime                                                   # 때 얼룩
        blood = np.clip((smooth_noise(h, w, 40, rng) - 0.68) / 0.12, 0, 1)[:, :, None] * k
        out = out * (1 - blood * 0.7) + np.array([0.22, 0.03, 0.02], dtype=np.float32) * blood * 0.7
        px.reshape(h, w, 4)[:, :, :3] = np.clip(out, 0, 1)
        img.pixels.foreach_set(px)
        img.update()
        img.pack()
        after = px.reshape(h, w, 4)[:, :, :3].mean(axis=(0, 1))
        done.append("%s 평균 색 (%.2f %.2f %.2f) -> (%.2f %.2f %.2f)" % (img.name, *before, *after))
    return done


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
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.type == "ARMATURE":
            normalize_bone_names(o)
    return objs


def normalize_bone_names(arm):
    """Mixamo 는 캐릭터마다 뼈 이름 앞에 숫자를 붙인다 (mixamorig5:Hips).
    동작 파일은 mixamorig:Hips 라서 이름이 다르면 동작이 몸에 입혀지지 않는다 → 숫자를 뗀다.
    Blender 는 뼈 이름을 바꾸면 메시의 가중치 그룹과 그 뼈대의 동작 경로도 함께 바꾼다."""
    renamed = 0
    for b in arm.data.bones:
        new = re.sub(r"^mixamorig\d+:", "mixamorig:", b.name)
        if new != b.name:
            b.name = new
            renamed += 1
    if renamed:
        print("IMPORT_MIXAMO bones: %s 뼈 이름 %d개를 mixamorig: 로 통일" % (arm.name, renamed))


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



def zero_metallic() -> int:
    """좀비는 금속이 아니다: Mixamo 재질의 Metallic 을 0 으로 (연결된 그림도 끊는다).
    그대로 두면 금속 값이 없는 재질은 glTF 기본값 1.0(완전 금속)이 되어, 어두운 맵에서 새까맣게 보였다 (2026-09-29)"""
    count = 0
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                sock = node.inputs["Metallic"]
                for link in list(sock.links):
                    mat.node_tree.links.remove(link)
                sock.default_value = 0.0
                count += 1
    return count

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
            if len(missing) > len(src.data.bones) // 2:
                raise SystemExit("IMPORT_MIXAMO 중단: %s 동작의 뼈 대부분이 캐릭터에 없다 (뼈대가 다름)" % name)
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
    acts = dict(named)
    for spec in args.clip:                                               # 구간 자르기 → 같은 동작의 일부만 재생하는 트랙
        new, rest = spec.split("=", 1)
        src, a, b = rest.split(":")
        act = acts[src]
        f0, f1 = act.frame_range
        s0, s1 = f0 + (f1 - f0) * float(a), f0 + (f1 - f0) * float(b)
        track = arm.animation_data.nla_tracks.new()
        track.name = new
        strip = track.strips.new(new, int(round(s0)), act)
        if hasattr(strip, "action_slot") and strip.action_slot is None and getattr(act, "slots", None):
            strip.action_slot = act.slots[0]
        strip.action_frame_start = s0
        strip.action_frame_end = s1
        strip.frame_end = strip.frame_start + (s1 - s0)
        named.append((new, act))
        print("IMPORT_MIXAMO clip %s = %s %.0f%% - %.0f%% (%.2f 초)" % (new, src, float(a) * 100, float(b) * 100,
                                                                   (s1 - s0) / bpy.context.scene.render.fps))

    shrunk = shrink_textures(args.max_texture)
    brightened = brighten_base_color(args.brightness) if args.brightness != 1.0 else []
    zombified = zombify_base_color(args.zombify) if args.zombify > 0 else []
    non_metal = zero_metallic()

    bpy.ops.export_scene.gltf(
        filepath=args.out,
        export_format="GLB",
        export_animation_mode="NLA_TRACKS",
        export_anim_slide_to_zero=True,        # 모든 동작을 0초부터 (잘라 넣은 구간이 원래 시각에서 시작하지 않게)
        export_yup=True,
    )

    print("IMPORT_MIXAMO height %.3f m -> %.3f m" % (h0, h1))
    for s in shrunk:
        print("IMPORT_MIXAMO texture " + s)
    for s in brightened:
        print("IMPORT_MIXAMO brightness " + s)
    print("IMPORT_MIXAMO metallic -> 0: %d materials" % non_metal)
    for s in zombified:
        print("IMPORT_MIXAMO zombify " + s)
    print("IMPORT_MIXAMO tris %d -> %d (max %d)" % (tris_before, tris_after, args.max_tris))
    for name, (b, a) in report.items():
        print("IMPORT_MIXAMO in_place %s: %.3f m -> %.3f m" % (name, b, a))
    print("IMPORT_MIXAMO anims " + ",".join(n for n, _ in named))
    print("IMPORT_MIXAMO out " + args.out)


main()
