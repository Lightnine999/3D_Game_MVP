"""HUD 아이콘 마무리 — render_icons.py 가 찍은 원본에 어두운 테두리를 두르고 크기를 맞춘다.
어두운 테두리가 있어야 안개 낀 들판(밝은 회색)과 밤 장면(어두운 색) 어디에서나 아이콘이 보인다.

사용 (시스템 파이썬 + Pillow):
  blender -b --factory-startup --python art/blender/render_icons.py   # 먼저 원본 촬영
  python art/ui/finish_icons.py

결과: art/ui/icons/
  icon_pistol.png  icon_ammo.png  icon_knife.png  icon_supply.png   256×256, 투명 배경
  icon_pistol_empty.png 탄약 0발일 때 흐린 권총 (PRD F-78 "탄약이 0발이면 권총 아이콘을 흐리게")
  칼은 1회 사용하면 아이콘이 없어지므로(F-78, F-35) 흐린 판을 따로 만들지 않는다
"""
import os

from PIL import Image, ImageFilter, ImageOps

RAW = "art/previews/icons_raw"
OUT = "art/ui/icons"
SIZE = 256
NAMES = ["icon_pistol", "icon_ammo", "icon_knife", "icon_supply"]

OUTLINE_PX = 12          # 원본(512) 기준 두께 → 256 에서 약 6px
OUTLINE_COLOR = (12, 12, 10)
HALO_PX = 5              # 어두운 테두리 바깥의 옅은 밝은 테 — 밤 장면·어두운 판 위에서 윤곽이 묻히지 않게
HALO_COLOR = (215, 215, 200, 110)
SHADOW_OFFSET = (6, 8)   # 오른쪽 아래로 살짝 그림자


def outline(im):
    a = im.getchannel("A")
    grown = a.filter(ImageFilter.MaxFilter(OUTLINE_PX * 2 + 1)).filter(ImageFilter.GaussianBlur(1.5))
    shadow = grown.filter(ImageFilter.GaussianBlur(6)).point(lambda v: v * 0.5)

    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 255))
    sh.putalpha(shadow)
    out.alpha_composite(sh, SHADOW_OFFSET)
    halo_a = a.filter(ImageFilter.MaxFilter((OUTLINE_PX + HALO_PX) * 2 + 1)).filter(ImageFilter.GaussianBlur(2))
    halo = Image.new("RGBA", im.size, HALO_COLOR[:3] + (255,))
    halo.putalpha(halo_a.point(lambda v: v * HALO_COLOR[3] / 255))
    out.alpha_composite(halo)
    ol = Image.new("RGBA", im.size, OUTLINE_COLOR + (255,))
    ol.putalpha(grown)
    out.alpha_composite(ol)
    out.alpha_composite(im)
    return out


def fit(im):
    # 테두리·그림자가 잘리지 않게 여백을 두고 줄인다
    pad = OUTLINE_PX + HALO_PX + max(SHADOW_OFFSET) + 8
    canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(im, (pad, pad))
    return canvas


def faded(im):
    """흐린 판 — 색을 빼고 반투명하게."""
    gray = ImageOps.grayscale(im.convert("RGB")).point(lambda v: 60 + v * 0.35)
    g = Image.merge("RGBA", (gray, gray, gray, im.getchannel("A").point(lambda v: v * 0.45)))
    return g


def main():
    os.makedirs(OUT, exist_ok=True)
    for n in NAMES:
        raw = Image.open(os.path.join(RAW, n + ".png")).convert("RGBA")
        done = outline(fit(raw)).resize((SIZE, SIZE), Image.LANCZOS)
        done.save(os.path.join(OUT, n + ".png"), optimize=True)
        print("ICON %-16s %dx%d %5.1f KB" % (n, SIZE, SIZE, os.path.getsize(os.path.join(OUT, n + ".png")) / 1024))
        if n == "icon_pistol":
            faded(done).save(os.path.join(OUT, "icon_pistol_empty.png"), optimize=True)
            print("ICON %-16s %dx%d" % ("icon_pistol_empty", SIZE, SIZE))


main()
