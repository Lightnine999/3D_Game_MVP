"""타이틀 이미지 "좀비탈출" — 주인: A (타이틀 화면 F-70 은 C 가 만든다. 이 파일은 그림만)
배경: godot 의 scenes/stage/title_art.tscn 으로 찍은 탈출 지점(요새 정문) 장면
글자: 굵은 한글 글꼴을 좀비답게 — 가장자리 갉아먹기 → 핏물 흘러내림 → 긁힌 자국 → 녹슨 핏빛 질감 → 어두운 테두리·붉은 빛

사용:
  godot --path godot --resolution 1920x1080 res://scenes/stage/title_art.tscn -- --out=art/previews/title_bg.png
  python art/title/make_title.py --bg art/previews/title_bg.png --out art/title/title_zombie_escape.png
글꼴: 윈도우 기본 맑은 고딕 Bold (사용자 결정 2026-09-30: 과제용 비상업이라 괜찮음. 상용 전환 때 OFL 글꼴로 바꿀 것)
"""
import argparse
import math

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

FONT = "C:/Windows/Fonts/malgunbd.ttf"
TITLE = "좀비탈출"
SUB = "ZOMBIE ESCAPE"


def rough_mask(size, text, font, seed):
    """글자 모양 → 가장자리를 불규칙하게 갉아먹은 모양."""
    rng = np.random.default_rng(seed)
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).text((size[0] // 2, size[1] // 2), text, font=font, fill=255, anchor="mm")
    # 잡음으로 가장자리 흔들기: 흐림 → 잡음 더하기 → 다시 자르기
    noise = Image.fromarray((rng.random((size[1] // 6, size[0] // 6)) * 255).astype("uint8")).resize(size, Image.BICUBIC)
    blur = m.filter(ImageFilter.GaussianBlur(3))
    a = np.asarray(blur, dtype=np.float32) + (np.asarray(noise, dtype=np.float32) - 128) * 0.45
    fine = rng.random((size[1], size[0])) * 50 - 25
    a = a + fine * (np.asarray(blur) > 30)
    out = Image.fromarray(np.clip((a - 128) * 6 + 128, 0, 255).astype("uint8"))
    # 군데군데 이빨 자국처럼 파인 구멍
    d = ImageDraw.Draw(out)
    bbox = m.getbbox()
    for _ in range(14):
        x = rng.uniform(bbox[0], bbox[2]); y = rng.uniform(bbox[1], bbox[3]); r = rng.uniform(3, 8)
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=0)
    return out.filter(ImageFilter.GaussianBlur(0.8)), bbox


def drips(mask, bbox, seed):
    """글자 아래쪽 가장자리에서 핏물이 흘러내린 줄기."""
    rng = np.random.default_rng(seed)
    w, h = mask.size
    a = np.asarray(mask)
    out = mask.copy()
    d = ImageDraw.Draw(out)
    xs = np.sort(rng.uniform(bbox[0] + 20, bbox[2] - 20, 14))
    for x in xs:
        col = a[:, int(x)]
        ys = np.nonzero(col > 128)[0]
        if len(ys) == 0:
            continue
        y0 = ys.max() - 3                                   # 이 세로줄의 글자 맨 아래
        length = rng.choice([rng.uniform(15, 45), rng.uniform(50, 130)], p=[0.6, 0.4])
        wid = rng.uniform(3, 8)
        for i in range(int(length)):
            t = i / length
            ww = wid * (1 - 0.55 * t) + math.sin(i * 0.3) * 0.4
            d.ellipse((x - ww, y0 + i - ww * 0.4, x + ww, y0 + i + ww * 0.4), fill=255)
        r = wid * 1.25                                      # 끝에 맺힌 방울
        d.ellipse((x - r, y0 + length - r, x + r, y0 + length + r * 1.2), fill=255)
    return out


def scratches(mask, bbox, seed):
    """비스듬히 할퀸 자국 (글자를 파고든다)."""
    rng = np.random.default_rng(seed)
    cut = Image.new("L", mask.size, 0)
    d = ImageDraw.Draw(cut)
    cx = rng.uniform(bbox[0] + (bbox[2] - bbox[0]) * 0.55, bbox[2] - 80)
    for k in range(3):                                      # 손톱 세 줄
        x0 = cx + k * 26; y0 = bbox[1] - 10
        x1 = x0 - 120; y1 = bbox[3] + 10
        for j in range(24):
            t = j / 23
            wid = 7 * math.sin(math.pi * t) + 1
            x = x0 + (x1 - x0) * t; y = y0 + (y1 - y0) * t
            d.ellipse((x - wid, y - wid, x + wid, y + wid), fill=255)
    return ImageChops.subtract(mask, cut.filter(ImageFilter.GaussianBlur(1)))


def blood_fill(size, seed):
    """녹슨 핏빛 질감: 짙은 검붉음 ~ 선홍, 얼룩·세로 줄무늬."""
    rng = np.random.default_rng(seed)
    w, h = size
    base = rng.random((h // 8, w // 8)).astype(np.float32)
    big = np.asarray(Image.fromarray((base * 255).astype("uint8")).resize(size, Image.BICUBIC), dtype=np.float32) / 255
    streak = np.asarray(Image.fromarray((rng.random((8, w // 3)) * 255).astype("uint8")).resize(size, Image.BICUBIC), dtype=np.float32) / 255
    grain = rng.random((h, w)).astype(np.float32)
    v = 0.55 * big + 0.3 * streak + 0.15 * grain
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    v = v * (0.75 + 0.45 * y)                               # 아래로 갈수록 핏물이 고여 진하다
    dark = np.array([45, 3, 4], np.float32); mid = np.array([125, 10, 10], np.float32); hi = np.array([200, 30, 22], np.float32)
    rgb = np.where(v[..., None] < 0.5, dark + (mid - dark) * (v[..., None] / 0.5), mid + (hi - mid) * ((v[..., None] - 0.5) / 0.5))
    return Image.fromarray(np.clip(rgb, 0, 255).astype("uint8"), "RGB")


def title_layer(size, text, font, seed):
    m, bbox = rough_mask(size, text, font, seed)
    m = drips(m, bbox, seed + 1)
    m = scratches(m, bbox, seed + 2)
    fill = blood_fill(size, seed + 3).convert("RGBA")
    fill.putalpha(m)
    # 안쪽 그림자(위에서 빛)로 입체감: 아래 가장자리를 어둡게
    shade = m.filter(ImageFilter.GaussianBlur(6))
    inner = ImageChops.subtract(m, ImageChops.offset(shade, 0, -5))
    dk = Image.new("RGBA", size, (10, 0, 0, 255)); dk.putalpha(inner.point(lambda v: v * 0.55))
    hl = ImageChops.subtract(m, ImageChops.offset(shade, 0, 4))
    lt = Image.new("RGBA", size, (255, 120, 90, 255)); lt.putalpha(hl.point(lambda v: v * 0.35))
    fill = Image.alpha_composite(Image.alpha_composite(fill, dk), lt)
    fill.putalpha(ImageChops.multiply(fill.getchannel("A"), m))
    # 바깥: 어두운 테두리 + 붉게 번지는 빛
    edge = m.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1.5))
    glow = m.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(26))
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    g = Image.new("RGBA", size, (200, 10, 0, 255)); g.putalpha(glow.point(lambda v: v * 0.55))
    e = Image.new("RGBA", size, (8, 2, 2, 255)); e.putalpha(edge)
    for layer in (g, e, fill):
        out = Image.alpha_composite(out, layer)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    bg = Image.open(a.bg).convert("RGBA")
    W, H = bg.size
    # 배경: 위쪽을 어둡게 눌러 글자가 뜨게, 가장자리 어둡게(비네팅), 붉은 기 살짝
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None]; x = np.linspace(-1, 1, W, dtype=np.float32)[None, :]
    vign = np.clip(1 - 0.55 * (x ** 2) - 0.35 * ((y - 0.55) * 2) ** 2, 0.25, 1)
    top = 0.55 + 0.45 * np.clip(y / 0.5, 0, 1)
    arr = np.asarray(bg, dtype=np.float32)
    arr[..., :3] *= (vign * top)[..., None]
    arr[..., 0] *= 1.06
    bg = Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA")

    font = ImageFont.truetype(FONT, 240)
    t = title_layer((W, 520), TITLE, font, seed=13)
    bg.alpha_composite(t, (0, 40))
    # 부제 (영문) — 작고 가는 흰 글씨, 살짝 긁힘
    sub = Image.new("RGBA", (W, 120), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sub)
    sfont = ImageFont.truetype(FONT, 50)
    sd.text((W // 2, 60), " ".join(SUB), font=sfont, fill=(225, 215, 205, 235), anchor="mm", stroke_width=3, stroke_fill=(10, 5, 5, 230))
    bg.alpha_composite(sub, (0, 480))
    # 아래: "화면을 눌러 시작" 자리 표시 (C 가 실제 버튼으로 바꾼다)
    hint = Image.new("RGBA", (W, 90), (0, 0, 0, 0))
    ImageDraw.Draw(hint).text((W // 2, 45), "화면을 눌러 시작", font=ImageFont.truetype(FONT, 42), fill=(235, 225, 215, 210),
                               anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0, 220))
    bg.alpha_composite(hint, (0, H - 150))
    bg.convert("RGB").save(a.out, optimize=True)
    t.save(a.out.replace(".png", "_logo.png"), optimize=True)          # 글자만 (투명 배경) — C 가 타이틀 화면에 올려 쓰도록
    print("TITLE saved", a.out, "+ _logo.png")


main()
