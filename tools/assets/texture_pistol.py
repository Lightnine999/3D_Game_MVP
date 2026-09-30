# 권총 텍스처 디벨롭 (2026-09-30): weapon_pistol.glb(팀원 make_pistol.py 결과, 단색 재질)를 불러와
# 총몸·슬라이드·탄창에 절차적 질감(폴리머 스티플링·먼지, 금속 모서리 마모·잔 긁힘)을 만들고 텍스처로 구워
# weapon_pistol_hd.glb 로 내보낸다. 원본은 건드리지 않는다. 손·조준경·방아쇠는 그대로. 상표(로고)는 넣지 않는다.
# 실행: blender -b -P tools/assets/texture_pistol.py
import bpy, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "godot", "assets", "models", "weapon_pistol.glb")
OUT = os.path.join(ROOT, "godot", "assets", "models", "weapon_pistol_hd.glb")
PARTS = {"Slide": 1024, "Frame": 1024, "Magazine": 512}   # 구울 부품과 텍스처 크기

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 24
sc.render.bake.margin = 8


def node(nt, kind, x, y, **kw):
    n = nt.nodes.new(kind)
    n.location = (x * 220, y * 220)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def edge_mask(nt):
    """모서리일수록 1 (둥근 모서리 법선과 원래 법선의 차이)"""
    bev = node(nt, "ShaderNodeBevel", -6, 2, samples=8)
    bev.inputs["Radius"].default_value = 0.0006
    geo = node(nt, "ShaderNodeNewGeometry", -6, 1)
    dot = node(nt, "ShaderNodeVectorMath", -5, 2, operation="DOT_PRODUCT")
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    inv = node(nt, "ShaderNodeMath", -4, 2, operation="SUBTRACT")
    inv.inputs[0].default_value = 1.0
    nt.links.new(dot.outputs["Value"], inv.inputs[1])
    amp = node(nt, "ShaderNodeMath", -3, 2, operation="MULTIPLY")
    amp.inputs[1].default_value = 22.0
    amp.use_clamp = True
    nt.links.new(inv.outputs[0], amp.inputs[0])
    sq = node(nt, "ShaderNodeMath", -2, 2, operation="POWER")   # 날카로운 모서리만 남게
    sq.inputs[1].default_value = 2.0
    nt.links.new(amp.outputs[0], sq.inputs[0])
    return sq.outputs[0]


def cavity(nt):
    """틈·홈일수록 1 (주변에 가려진 정도 — 먼지가 끼는 곳)"""
    ao = node(nt, "ShaderNodeAmbientOcclusion", -6, 4, samples=16)
    ao.inputs["Distance"].default_value = 0.004
    inv = node(nt, "ShaderNodeMapRange", -5, 4)
    inv.inputs[1].default_value = 0.72
    inv.inputs[2].default_value = 1.0
    inv.inputs[3].default_value = 1.0
    inv.inputs[4].default_value = 0.0
    nt.links.new(ao.outputs["AO"], inv.inputs[0])
    return inv.outputs[0]


def smudge(nt, x, y):
    """손때·기름 얼룩 (큰 반점) — 거칠기를 낮춰 번들거리게"""
    n = noise(nt, 38.0, x, y, 3.0)
    r = node(nt, "ShaderNodeMapRange", x + 1, y)
    r.inputs[1].default_value = 0.55
    r.inputs[2].default_value = 0.72
    nt.links.new(n, r.inputs[0])
    return r.outputs[0]


def pins(nt, points, radius):
    """둥근 핀 자국 (오브젝트 좌표 YZ 평면의 점들) — 1 = 핀 테두리 홈"""
    tc = node(nt, "ShaderNodeTexCoord", -8, -5)
    acc = None
    for i, (py, pz) in enumerate(points):
        sep = node(nt, "ShaderNodeVectorMath", -7, -5 - i, operation="SUBTRACT")
        sep.inputs[1].default_value = (0.0, py, pz)
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        mul = node(nt, "ShaderNodeVectorMath", -6, -5 - i, operation="MULTIPLY")
        mul.inputs[1].default_value = (0.0, 1.0, 1.0)            # 두께 방향(X)은 무시
        nt.links.new(sep.outputs[0], mul.inputs[0])
        ln = node(nt, "ShaderNodeVectorMath", -5, -5 - i, operation="LENGTH")
        nt.links.new(mul.outputs[0], ln.inputs[0])
        ring = node(nt, "ShaderNodeMapRange", -4, -5 - i, interpolation_type="SMOOTHSTEP")   # 반지름 근처에 얇은 고리
        d = node(nt, "ShaderNodeMath", -4.5, -5 - i, operation="ABSOLUTE")
        sub = node(nt, "ShaderNodeMath", -5, -6 - i, operation="SUBTRACT")
        sub.inputs[1].default_value = radius
        nt.links.new(ln.outputs["Value"], sub.inputs[0])
        nt.links.new(sub.outputs[0], d.inputs[0])
        ring.inputs[1].default_value = 0.0003
        ring.inputs[2].default_value = 0.0
        ring.inputs[3].default_value = 0.0
        ring.inputs[4].default_value = 1.0
        nt.links.new(d.outputs[0], ring.inputs[0])
        if acc is None:
            acc = ring.outputs[0]
        else:
            mx = node(nt, "ShaderNodeMath", -3, -5 - i, operation="MAXIMUM")
            nt.links.new(acc, mx.inputs[0])
            nt.links.new(ring.outputs[0], mx.inputs[1])
            acc = mx.outputs[0]
    return acc


def noise(nt, scale, x, y, detail=6.0):
    tc = node(nt, "ShaderNodeTexCoord", x - 1, y)
    nz = node(nt, "ShaderNodeTexNoise", x, y)
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    return nz.outputs["Fac"]


def ramp(nt, fac, a, b, x, y, lo=0.0, hi=1.0):
    r = node(nt, "ShaderNodeValToRGB", x, y)
    r.color_ramp.elements[0].position = lo
    r.color_ramp.elements[0].color = (*a, 1)
    r.color_ramp.elements[1].position = hi
    r.color_ramp.elements[1].color = (*b, 1)
    nt.links.new(fac, r.inputs["Fac"])
    return r.outputs["Color"]


def mixc(nt, fac, c1, c2, x, y):
    m = node(nt, "ShaderNodeMix", x, y, data_type="RGBA")
    nt.links.new(fac, m.inputs["Factor"])
    nt.links.new(c1, m.inputs[6])
    nt.links.new(c2, m.inputs[7])
    return m.outputs[2]


def proc_material(name, kind):
    """재질 이름별 절차적 재질 (굽기 전용)"""
    m = bpy.data.materials.new("PROC_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = node(nt, "ShaderNodeOutputMaterial", 4, 0)
    bs = node(nt, "ShaderNodeBsdfPrincipled", 2, 0)
    nt.links.new(bs.outputs[0], out.inputs[0])
    n1 = noise(nt, 180.0, -3, -1)                      # 얼룩·먼지 (큰 결)
    n2 = noise(nt, 1800.0, -3, -2, 2.0)               # 잔 결 (거칠기 변화)
    bump = node(nt, "ShaderNodeBump", 1, -2)
    nt.links.new(bump.outputs[0], bs.inputs["Normal"])
    if kind == "slide":                                # 반광 검정 금속 + 모서리 마모(은색) + 잔 긁힘
        edge = edge_mask(nt)
        wave = node(nt, "ShaderNodeTexWave", -3, -3, wave_type="BANDS")
        wave.inputs["Scale"].default_value = 1400.0
        wave.inputs["Distortion"].default_value = 12.0
        wave.inputs["Detail"].default_value = 4.0
        tc = node(nt, "ShaderNodeTexCoord", -4, -3)
        nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
        scratch = node(nt, "ShaderNodeMath", -2, -3, operation="GREATER_THAN")
        scratch.inputs[1].default_value = 0.955
        nt.links.new(wave.outputs["Fac"], scratch.inputs[0])
        wear = node(nt, "ShaderNodeMath", -1, 1, operation="MAXIMUM")
        wear.use_clamp = True
        nt.links.new(edge, wear.inputs[0])
        s2 = node(nt, "ShaderNodeMath", -1, -3, operation="MULTIPLY")
        s2.inputs[1].default_value = 0.55
        nt.links.new(scratch.outputs[0], s2.inputs[0])
        nt.links.new(s2.outputs[0], wear.inputs[1])
        base = ramp(nt, n1, (0.018, 0.019, 0.021), (0.034, 0.035, 0.038), -1, 0)
        steel = node(nt, "ShaderNodeRGB", -1, -1)
        steel.outputs[0].default_value = (0.32, 0.32, 0.33, 1)
        nt.links.new(mixc(nt, wear.outputs[0], base, steel.outputs[0], 0, 0), bs.inputs["Base Color"])
        rough = node(nt, "ShaderNodeMapRange", 0, -1)
        rough.inputs[3].default_value = 0.30
        rough.inputs[4].default_value = 0.42
        nt.links.new(n2, rough.inputs[0])
        rw = node(nt, "ShaderNodeMix", 1, -1, data_type="FLOAT")
        nt.links.new(wear.outputs[0], rw.inputs["Factor"])
        nt.links.new(rough.outputs[0], rw.inputs[2])
        rw.inputs[3].default_value = 0.22
        nt.links.new(rw.outputs[0], bs.inputs["Roughness"])
        mw = node(nt, "ShaderNodeMapRange", 1, 1)
        mw.inputs[3].default_value = 0.35
        mw.inputs[4].default_value = 0.9
        nt.links.new(wear.outputs[0], mw.inputs[0])
        nt.links.new(mw.outputs[0], bs.inputs["Metallic"])
        bump.inputs["Strength"].default_value = 0.08
        nt.links.new(n2, bump.inputs["Height"])
    elif kind in ("frame", "grip", "mag"):             # 무광 폴리머 + 먼지 + (손잡이는) 오돌토돌 스티플링
        base = ramp(nt, n1, (0.009, 0.009, 0.010), (0.019, 0.018, 0.017), -1, 0, 0.35, 0.8)
        edge = edge_mask(nt)
        worn = node(nt, "ShaderNodeRGB", -1, -1)
        worn.outputs[0].default_value = (0.042, 0.042, 0.044, 1)
        nt.links.new(mixc(nt, edge, base, worn.outputs[0], 0, 0), bs.inputs["Base Color"])
        rough = node(nt, "ShaderNodeMapRange", 0, -1)
        rough.inputs[3].default_value = 0.55 if kind != "grip" else 0.78
        rough.inputs[4].default_value = 0.7 if kind != "grip" else 0.92
        nt.links.new(n2, rough.inputs[0])
        nt.links.new(rough.outputs[0], bs.inputs["Roughness"])
        bs.inputs["Metallic"].default_value = 0.0
        if kind == "grip":
            vor = node(nt, "ShaderNodeTexVoronoi", -2, -2)
            vor.inputs["Scale"].default_value = 700.0
            tc = node(nt, "ShaderNodeTexCoord", -3, -2)
            nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
            nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
            bump.inputs["Strength"].default_value = 0.55
        else:
            nt.links.new(n2, bump.inputs["Height"])
            bump.inputs["Strength"].default_value = 0.05
    elif kind == "steel":                               # 은색 금속 부품 (핀·레일)
        base = ramp(nt, n1, (0.30, 0.30, 0.31), (0.42, 0.42, 0.44), -1, 0)
        nt.links.new(base, bs.inputs["Base Color"])
        bs.inputs["Metallic"].default_value = 0.9
        rough = node(nt, "ShaderNodeMapRange", 0, -1)
        rough.inputs[3].default_value = 0.25
        rough.inputs[4].default_value = 0.4
        nt.links.new(n2, rough.inputs[0])
        nt.links.new(rough.outputs[0], bs.inputs["Roughness"])
    else:                                               # 총구 속 (검정)
        bs.inputs["Base Color"].default_value = (0.004, 0.004, 0.004, 1)
        bs.inputs["Roughness"].default_value = 0.9
        return m
    # 생활감 (2차, 2026-09-30 "무광이지만 생활감·디테일을"): ① 틈에 낀 회갈색 먼지 ② 손때(번들거리는 얼룩) ③ 핀 자국
    cav = cavity(nt)
    dust_amt = node(nt, "ShaderNodeMath", 0, 3, operation="MULTIPLY")
    dust_amt.inputs[1].default_value = 0.5
    nt.links.new(cav, dust_amt.inputs[0])
    dust = node(nt, "ShaderNodeRGB", 0, 4)
    dust.outputs[0].default_value = (0.05, 0.045, 0.037, 1)
    col_link = next(l for l in nt.links if l.to_socket == bs.inputs["Base Color"])
    nt.links.new(mixc(nt, dust_amt.outputs[0], col_link.from_socket, dust.outputs[0], 1, 3), bs.inputs["Base Color"])
    r_link = next((l for l in nt.links if l.to_socket == bs.inputs["Roughness"]), None)
    if r_link:
        sm = smudge(nt, -2, -6)
        oily = node(nt, "ShaderNodeMix", 1.5, -1.5, data_type="FLOAT")
        nt.links.new(sm, oily.inputs["Factor"])
        nt.links.new(r_link.from_socket, oily.inputs[2])
        oily.inputs[3].default_value = 0.28                 # 손때 자리는 번들
        dusty = node(nt, "ShaderNodeMix", 1.8, -1.8, data_type="FLOAT")
        nt.links.new(dust_amt.outputs[0], dusty.inputs["Factor"])
        nt.links.new(oily.outputs[0], dusty.inputs[2])
        dusty.inputs[3].default_value = 0.95                # 먼지 낀 곳은 푸석
        nt.links.new(dusty.outputs[0], bs.inputs["Roughness"])
    if PIN_POINTS.get(kind):
        ring = pins(nt, PIN_POINTS[kind], 0.0022)
        h_link = next((l for l in nt.links if l.to_socket == bump.inputs["Height"]), None)
        add = node(nt, "ShaderNodeMath", 0.5, -2.5, operation="SUBTRACT")   # 핀 테두리는 파인 홈
        if h_link:
            nt.links.new(h_link.from_socket, add.inputs[0])
        nt.links.new(ring, add.inputs[1])
        nt.links.new(add.outputs[0], bump.inputs["Height"])
        bump.inputs["Distance"].default_value = 0.0004
    return m


PIN_POINTS = {}                                          # kind → [(y, z)] 오브젝트 좌표 (bake 에서 채운다)
KIND = {"SlideBlack": "slide", "FrameBlack": "frame", "GripStipple": "grip", "Steel": "steel", "Bore": "bore"}


def bake(obj, size):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # 겹치지 않는 굽기용 UV
    uv = obj.data.uv_layers.new(name="bake")
    obj.data.uv_layers.active = uv
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    if obj.name == "Frame":                             # 총몸 옆면 핀 두 개 (방아쇠 위·뒤) — 모양 상자 비율로 자리 잡기
        ys = [v.co.y for v in obj.data.vertices]
        zs = [v.co.z for v in obj.data.vertices]
        y0, y1, z0, z1 = min(ys), max(ys), min(zs), max(zs)
        PIN_POINTS["frame"] = [(y0 + (y1 - y0) * 0.36, z0 + (z1 - z0) * 0.78), (y0 + (y1 - y0) * 0.5, z0 + (z1 - z0) * 0.8)]
    else:
        PIN_POINTS.pop("frame", None)
    for i, slot in enumerate(obj.material_slots):     # 슬롯마다 절차적 재질로 바꾼다 (같은 재질을 다른 부품이 써도 섞이지 않게 복사)
        k = KIND.get(slot.material.name.split(".")[0], "frame")
        if obj.name == "Magazine" and k == "frame":
            k = "mag"
        slot.material = proc_material(slot.material.name, k)
    imgs = {}
    for ch in ["color", "rough", "metal", "normal"]:
        img = bpy.data.images.new("%s_%s" % (obj.name.lower(), ch), size, size, alpha=False)
        if ch != "color":
            img.colorspace_settings.name = "Non-Color"
        imgs[ch] = img
    def target(img):
        for slot in obj.material_slots:
            nt = slot.material.node_tree
            for n in nt.nodes:
                n.select = False
            t = nt.nodes.get("BAKE_TARGET") or nt.nodes.new("ShaderNodeTexImage")
            t.name = "BAKE_TARGET"
            t.image = img
            t.select = True
            nt.nodes.active = t
    target(imgs["color"])
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE")
    target(imgs["rough"])
    bpy.ops.object.bake(type="ROUGHNESS")
    target(imgs["normal"])
    bpy.ops.object.bake(type="NORMAL")
    # 금속감: 방출(Emission)로 잠깐 바꿔 굽는다
    for slot in obj.material_slots:
        nt = slot.material.node_tree
        bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        link = next((l for l in nt.links if l.to_socket == bs.inputs["Metallic"]), None)
        em = nt.nodes.new("ShaderNodeEmission")
        if link:
            nt.links.new(link.from_socket, em.inputs["Color"])
        else:
            v = bs.inputs["Metallic"].default_value
            em.inputs["Color"].default_value = (v, v, v, 1)
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        nt.links.new(em.outputs[0], out.inputs[0])
    target(imgs["metal"])
    bpy.ops.object.bake(type="EMIT")
    # 최종 재질: 구운 텍스처 4장 하나로
    fm = bpy.data.materials.new(obj.name + "_HD")
    fm.use_nodes = True
    nt = fm.node_tree
    bs = nt.nodes["Principled BSDF"]
    def tex(img, x, y):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.location = (x, y)
        return t
    nt.links.new(tex(imgs["color"], -600, 300).outputs[0], bs.inputs["Base Color"])
    nt.links.new(tex(imgs["rough"], -600, 0).outputs[0], bs.inputs["Roughness"])
    nt.links.new(tex(imgs["metal"], -600, -300).outputs[0], bs.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex(imgs["normal"], -900, -600).outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], bs.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(fm)
    for p in obj.data.polygons:
        p.material_index = 0
    for u in list(obj.data.uv_layers):                  # 굽기용 UV 만 남긴다
        if u.name != "bake":
            obj.data.uv_layers.remove(u)
    for img in imgs.values():
        img.pack()
    print("[pistol] %s 구움 (%dpx)" % (obj.name, size))


for name, size in PARTS.items():
    bake(bpy.data.objects[name], size)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=90)
print("[pistol] 저장:", OUT, os.path.getsize(OUT) // 1024, "KB")
