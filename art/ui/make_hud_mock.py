"""HUD 배치 시안 그림 — 팀(특히 C)이 위치를 정할 때 보는 참고 그림. 게임에 들어가는 파일이 아니다.
HUD 구현은 C 의 일(WU-31). 여기 적힌 위치·크기는 제안일 뿐이다.

사용 (시스템 파이썬 + Pillow):
  blender -b --factory-startup --python art/blender/render_icons.py
  python art/ui/finish_icons.py
  python art/ui/make_hud_mock.py
  → art/ui/hud_mock_full.png   게임 화면 전체 (1920×1080, TECH_SPEC 6.1 기준 해상도)
    art/ui/hud_mock_states.png 무기 표시 세 상태 (PRD F-78): 탄약 있음 / 0발 / 칼 사용 뒤

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
    """남은 거리와 진행 막대 (PRD F-54 "남은 거리(1,000m → 0m)와 진행 막대", B 의 WU-15 가 값 제공).
    예시: 320m 달림 → 남은 거리 680m, 막대는 달린 만큼(32%) 채움."""
    x0, x1 = cx - width // 2, cx + width // 2
    panel(img, (x0 - 24, y - 26, x1 + 24, y + 62), alpha=120)
    d.rounded_rectangle((x0, y + 22, x1, y + 44), 11, fill=(40, 40, 36), outline=(10, 10, 10), width=3)
    d.rounded_rectangle((x0, y + 22, x0 + int(width * 0.32), y + 44), 11, fill=(196, 58, 44))
    text(d, (cx, y + 2), "680m", 30, anchor="mm")


def weapon_group(img, d, cx, y, ammo, knife):
    """무기 표시 (PRD F-78) — 화면 최상단 중앙, 진행 막대보다 위.
    권총 + 남은 탄약 수. 0발이면 권총을 흐리게, 숫자는 0 (빨갛게). 칼은 있으면 보이고 쓰면 없어진다.
    아이콘 60px (처음 시안 120px 의 절반 — 화면 가운데를 덜 가리게)."""
    w = 150 + (70 if knife else 0)
    x = cx - w // 2
    panel(img, (x, y, x + w, y + 64), radius=12)
    img.alpha_composite(icon("icon_pistol" if ammo > 0 else "icon_pistol_empty", 60), (x + 6, y + 2))
    text(d, (x + 76, y + 32), str(ammo), 38, fill=(240, 238, 228) if ammo > 0 else (225, 70, 60), anchor="lm", stroke=2)
    if knife:
        d.line([(x + 146, y + 12), (x + 146, y + 52)], fill=(200, 200, 190, 120), width=2)
        img.alpha_composite(icon("icon_knife", 55), (x + 156, y + 4))
    return (x, y, x + w, y + 64)


def pause_button(img, d):
    """일시정지 (PRD F-72) — 오른쪽 위."""
    cx, cy, r = W - SAFE - 56, SAFE + 56, 44
    panel(img, (cx - r, cy - r, cx + r, cy + r), radius=r, alpha=150)
    d.rounded_rectangle((cx - 16, cy - 20, cx - 6, cy + 20), 3, fill=(240, 238, 228))
    d.rounded_rectangle((cx + 6, cy - 20, cx + 16, cy + 20), 3, fill=(240, 238, 228))
    return (cx - r, cy - r, cx + r, cy + r)


def fire_button(img, d, ammo):
    """사격 버튼 (PRD F-11 "화면 오른쪽") — 오른손 엄지 자리. 0발이면 비활성으로 흐리게 (F-13)."""
    cx, cy, r = W - SAFE - 170, H - SAFE - 170, 130
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    on = ammo > 0
    ld.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(150, 36, 28, 170) if on else (60, 60, 58, 120),
               outline=(250, 240, 230, 200 if on else 90), width=6)
    img.alpha_composite(layer)
    img.alpha_composite(icon("icon_pistol" if on else "icon_pistol_empty", 170), (cx - 85, cy - 95))
    text(d, (cx, cy + 78), "사격", 30, fill=(240, 238, 228) if on else (150, 150, 145), anchor="mm")
    return (cx - r, cy - r, cx + r, cy + r)


def screen(ammo, knife):
    """설명 딱지 없는 실제 게임 화면 모습."""
    img = background()
    d = ImageDraw.Draw(img, "RGBA")
    weapon_group(img, d, W // 2, SAFE, ammo, knife)          # 최상단 중앙 (F-78)
    progress_bar(img, d, W // 2, SAFE + 110)                   # 그 아래 남은 거리·진행 막대 (F-54)
    pause_button(img, d)
    fire_button(img, d, ammo)
    return img


# 상태 세 가지 (F-78): (탄약, 칼, 설명)
STATES = [(8, True, "① 탄약 8발 · 칼 있음"),
          (0, True, "② 탄약 0발 — 권총이 흐려지고 0 (사격 버튼도 흐림, F-13)"),
          (5, False, "③ 칼을 한 번 쓴 뒤 — 칼 아이콘이 없어짐")]


def main():
    full = screen(8, True)
    full.convert("RGB").save(os.path.join(OUT, "hud_mock_full.png"), optimize=True)

    # 세 상태를 위아래로: 각 줄은 화면 윗부분(진행 막대 + 무기 표시)만 잘라 붙인다
    crop = (W // 2 - 520, 0, W // 2 + 520, 230)
    cw, ch, cap = crop[2] - crop[0], crop[3] - crop[1], 48
    sheet = Image.new("RGB", (cw, (ch + cap) * len(STATES)), (20, 20, 20))
    sd = ImageDraw.Draw(sheet)
    for i, (ammo, knife, label) in enumerate(STATES):
        y = i * (ch + cap)
        sd.text((16, y + 8), label, font=font(26, True), fill=(255, 220, 60))
        sheet.paste(screen(ammo, knife).crop(crop).convert("RGB"), (0, y + cap))
    sheet.save(os.path.join(OUT, "hud_mock_states.png"), optimize=True)
    for n in ("hud_mock_full.png", "hud_mock_states.png"):
        print("MOCK", n, "%.0f KB" % (os.path.getsize(os.path.join(OUT, n)) / 1024))


main()
