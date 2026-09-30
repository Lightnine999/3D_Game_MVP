# Scary Zombie Pack(Mixamo) 동작 FBX → 동작만 담은 GLB 하나 (godot/assets/models/zombie_anims.glb)
# 실행: blender -b -P tools/assets/pack_zombie_anims.py
# 원본 FBX 는 art/source/scary_zombie_pack/ (커밋 금지 — Mixamo 원본 재배포 금지). 캐릭터(Ch28)는 쓰지 않는다
# 모든 좀비가 같은 Mixamo 뼈대(mixamorig)라서 게임에서 4종 모두에 이 동작을 입힌다 (showcase.gd _anim_lib)
import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art", "source", "scary_zombie_pack")
OUT = os.path.join(ROOT, "godot", "assets", "models", "zombie_anims.glb")
NAMES = {                                   # 파일 → 게임 안 동작 이름
    "zombie walk.fbx": "p_walk", "zombie run.fbx": "p_run", "running crawl.fbx": "p_crawl_run",
    "zombie crawl.fbx": "p_crawl", "zombie attack.fbx": "p_attack", "zombie biting.fbx": "p_bite",
    "zombie biting (2).fbx": "p_bite2", "zombie neck bite.fbx": "p_neck_bite", "zombie death.fbx": "p_death",
    "zombie dying.fbx": "p_dying", "zombie idle.fbx": "p_idle", "zombie scream.fbx": "p_scream",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
keep = None
for fname, name in NAMES.items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, fname), automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    act = arm.animation_data.action
    act.name = name
    act.use_fake_user = True
    if keep is None:
        keep = arm
        keep.name = "Armature"
        for o in new:
            if o is not keep:
                bpy.data.objects.remove(o, do_unlink=True)
    else:
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
    print("[anim] %s ← %s  %d프레임" % (name, fname, int(act.frame_range[1] - act.frame_range[0])))

# 모든 동작을 NLA 트랙에 올려 한꺼번에 내보낸다
keep.animation_data.action = None
for act in bpy.data.actions:
    tr = keep.animation_data.nla_tracks.new()
    tr.name = act.name
    st = tr.strips.new(act.name, int(act.frame_range[0]), act)
    tr.mute = True
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_skins=True, export_morph=False, export_materials="NONE", export_apply=False)
print("[anim] 저장:", OUT, os.path.getsize(OUT) // 1024, "KB")
