"""HUD 배치 시안 그림 — 팀(특히 C)이 위치를 정할 때 보는 참고 그림. 게임에 들어가는 파일이 아니다.
HUD 구현은 C 의 일(WU-31). 여기 적힌 위치·크기는 제안일 뿐이다.

사용 (시스템 파이썬 + Pillow):
  blender -b --factory-startup --python art/blender/render_icons.py
  python art/ui/finish_icons.py
  python art/ui/make_hud_mock.py
  → art/ui/hud_mock_1_top_center.png, art/ui/hud_mock_2_top_left.png (1920×1080, TECH_SPEC 6.1 기준 해상도)

그림에 쓰는 글꼴은 윈도우 기본 '맑은 고딕' — 시안 그림에만 쓰고 게임에는 넣지 않는다.
"""
import os

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
ICONS = "art/ui/icons"
RAW = "art/previews/icons_raw"
OUT = "art/ui"
FONT = "C:/Windows/Fonts/malgun.ttf"
FONT_B = "C:/Windows/Fonts/malgunbd.ttf"
SAFE = 60                       # 안전 영역 여백 표시 (PRD F-69) — 실제 값은 기기에서 받는다 (TECH_SPEC 6.1)

FOG = (148, 156, 150)


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


def icon(name, size):
    return Image.open(os.path.join(ICONS, name + ".png")).resize((size, size), Image.LANCZOS)


def background():
    """안개 낀 들판 느낌 — 위는 안개 하늘, 아래는 어두운 풀밭, 가운데 흙길."""
    img = Image.new("RGBA", (W, H), FOG + (255,))
    d = ImageDraw.Draw(img)
    horizon = 470
    for y in range(horizon, H):                          # 멀수록 안개색, 가까울수록 어두운 풀
        t = (y - horizon) / (H - horizon)
        c = tuple(int(FOG[i] * (1 - t) + (48, 58, 42)[i] * t) for i in range(3))
        d.line([(0, y), (W, y)], fill=c + (255,))
    d.polygon([(W / 2 - 40, horizon), (W / 2 + 40, horizon), (W / 2 + 520, H), (W / 2 - 520, H)],
              fill=(92, 86, 72, 255))                    # 흙길
    fog = Image.new("RGBA", (W, H), (0, 0, 0, 0))        # 길 위에도 안개가 덮이게
    fd = ImageDraw.Draw(fog)
    for y in range(horizon, H):
        a = int(200 * (1 - (y - horizon) / (H - horizon)) ** 2)
        fd.line([(0, y), (W, y)], fill=FOG + (a,))
    img.alpha_composite(fog)

    # 좀비 셋: (그림, 화면 가로 위치, 발 높이, 키 px, 안개 정도)
    for name, x, foot, h, fogged in (("mock_tank", 1180, 560, 150, 0.6),
                                     ("mock_walker", 760, 640, 230, 0.35),
                                     ("mock_runner", 1020, 790, 360, 0.1)):
        z = Image.open(os.path.join(RAW, name + ".png"))
        z = z.crop(z.getbbox())
        z = z.resize((int(z.width * h / z.height), h), Image.LANCZOS)
        tint = Image.new("RGBA", z.size, FOG + (int(255 * fogged),))
        z2 = z.copy()
        z2.alpha_composite(tint)
        z2.putalpha(z.getchannel("A"))
        img.alpha_composite(z2, (x - z.width // 2, foot - h))
    return img


def panel(img, box, radius=18, alpha=150):
    """아이콘 뒤 반투명 어두운 판 — 밝은 안개 위에서도 숫자가 읽히게."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius, fill=(14, 16, 14, alpha))
    img.alpha_composite(layer)


def text(d, xy, s, size, fill=(240, 238, 228), bold=True, anchor="la", stroke=3):
    d.text(xy, s, font=font(size, bold), fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=(10, 10, 10))


def progress_bar(img, d, cx, y, width=720):
    """진행 막대 (PRD F-54, B 의 WU-15 가 값 제공) — 320m / 1,000m 예시."""
    x0, x1 = cx - width // 2, cx + width // 2
    panel(img, (x0 - 24, y - 26, x1 + 24, y + 62), alpha=120)
    d.rounded_rectangle((x0, y + 22, x1, y + 44), 11, fill=(40, 40, 36), outline=(10, 10, 10), width=3)
    d.rounded_rectangle((x0, y + 22, x0 + int(width * 0.32), y + 44), 11, fill=(196, 58, 44))
    text(d, (cx, y + 2), "320 m / 1,000 m", 26, anchor="mm")


def weapon_group(img, d, x, y):
    """권총 + 탄약 수 + 칼. 폭 약 440px, 높이 약 110px."""
    panel(img, (x, y, x + 440, y + 112))
    img.alpha_composite(icon("icon_pistol", 104), (x + 8, y + 4))
    img.alpha_composite(icon("icon_ammo", 72), (x + 110, y + 20))
    text(d, (x + 180, y + 56), "8", 60, anchor="lm")
    text(d, (x + 222, y + 64), "/ 12", 30, fill=(200, 198, 188), bold=False, anchor="lm", stroke=2)
    d.line([(x + 312, y + 18), (x + 312, y + 94)], fill=(200, 200, 190, 120), width=2)
    img.alpha_composite(icon("icon_knife", 104), (x + 326, y + 4))
    return (x, y, x + 440, y + 112)


def supply_toast(img, d, x, y):
    """보급 획득 알림 (+6발, PRD F-23). PRD HUD 목록(F-72)에는 없는 '제안' — 잠깐 떴다 사라지는 용도."""
    panel(img, (x, y, x + 250, y + 84), alpha=130)
    img.alpha_composite(icon("icon_supply", 80), (x + 6, y + 2))
    text(d, (x + 96, y + 42), "+6발", 40, fill=(255, 214, 120), anchor="lm")
    return (x, y, x + 250, y + 84)


def pause_button(img, d):
    """일시정지 (PRD F-72) — 오른쪽 위."""
    cx, cy, r = W - SAFE - 56, SAFE + 56, 44
    panel(img, (cx - r, cy - r, cx + r, cy + r), radius=r, alpha=150)
    d.rounded_rectangle((cx - 16, cy - 20, cx - 6, cy + 20), 3, fill=(240, 238, 228))
    d.rounded_rectangle((cx + 6, cy - 20, cx + 16, cy + 20), 3, fill=(240, 238, 228))
    return (cx - r, cy - r, cx + r, cy + r)


def fire_button(img, d):
    """사격 버튼 (PRD F-11 "화면 오른쪽") — 오른손 엄지 자리."""
    cx, cy, r = W - SAFE - 170, H - SAFE - 170, 130
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(150, 36, 28, 170), outline=(250, 240, 230, 200), width=6)
    img.alpha_composite(layer)
    img.alpha_composite(icon("icon_pistol", 170), (cx - 85, cy - 95))
    text(d, (cx, cy + 78), "사격", 30, anchor="mm")
    return (cx - r, cy - r, cx + r, cy + r)


def safe_guide(d):
    """안전 영역 점선 (F-69) — 이 안에 UI 를 둔다. 펀치홀 카메라가 왼쪽이나 오른쪽 가장자리에 온다."""
    x0, y0, x1, y1 = SAFE, SAFE, W - SAFE, H - SAFE
    for x in range(x0, x1, 28):
        d.line([(x, y0), (min(x + 14, x1), y0)], fill=(255, 255, 255, 160), width=2)
        d.line([(x, y1), (min(x + 14, x1), y1)], fill=(255, 255, 255, 160), width=2)
    for y in range(y0, y1, 28):
        d.line([(x0, y), (x0, min(y + 14, y1))], fill=(255, 255, 255, 160), width=2)
        d.line([(x1, y), (x1, min(y + 14, y1))], fill=(255, 255, 255, 160), width=2)


def note(d, box, label, where="below"):
    """노란 설명 딱지 — 시안 설명용. 실제 화면에는 없다."""
    x0, y0, x1, y1 = box
    d.rectangle(box, outline=(255, 220, 60), width=3)
    f = font(22, True)
    tw = d.textlength(label, font=f)
    tx = max(12, min(W - tw - 22, x0))
    ty = y1 + 10 if where == "below" else y0 - 44
    d.rectangle((tx, ty, tx + tw + 16, ty + 34), fill=(255, 220, 60))
    d.text((tx + 8, ty + 3), label, font=f, fill=(20, 20, 20))


def title(d, s):
    d.rectangle((0, H - 44, W, H), fill=(20, 20, 20))
    d.text((20, H - 38), s, font=font(24, True), fill=(255, 220, 60))


def mock(variant):
    img = background()
    d = ImageDraw.Draw(img, "RGBA")
    safe_guide(d)
    progress_bar(img, d, W // 2, SAFE + 16)
    notes = [((W // 2 - 384, SAFE - 10, W // 2 + 384, SAFE + 78), "진행 막대 F-54 (WU-15, 이미 상단 중앙)", "below")]
    if variant == 1:
        g = weapon_group(img, d, W // 2 - 220, SAFE + 140)
        t = supply_toast(img, d, W // 2 + 240, SAFE + 154)
        notes += [(g, "권총·탄약 수 8/12 (F-15)·칼 (F-35)", "below"),
                  (t, "보급 +6발 알림 — 제안 (F-72 목록에 없음)", "below")]
        cap = "시안 1  상단 중앙: 진행 막대 바로 아래에 권총·탄약·칼을 묶는다 — 한눈에 보이지만 화면 가운데(좀비가 오는 곳)를 조금 가린다"
    else:
        g = weapon_group(img, d, SAFE + 20, SAFE + 20)
        t = supply_toast(img, d, SAFE + 20, SAFE + 190)
        notes += [(g, "권총·탄약 수 8/12 (F-15)·칼 (F-35)", "below"),
                  (t, "보급 +6발 알림 — 제안 (F-72 목록에 없음)", "below")]
        cap = "시안 2  왼쪽 위: 가운데는 진행 막대만 — 앞이 트이지만 눈을 옆으로 돌려야 탄약 수가 보인다"
    notes += [(pause_button(img, d), "일시정지 F-72", "below"),
              (fire_button(img, d), "사격 버튼 F-11 (오른쪽)", "above")]
    for box, label, where in notes:
        note(d, box, label, where)
    title(d, cap)
    path = os.path.join(OUT, "hud_mock_%d_%s.png" % (variant, "top_center" if variant == 1 else "top_left"))
    img.convert("RGB").save(path, optimize=True)
    print("MOCK", path, "%.0f KB" % (os.path.getsize(path) / 1024))


def main():
    mock(1)
    mock(2)


main()
