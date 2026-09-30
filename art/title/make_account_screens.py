"""로그인(sign in)·회원가입(sign up) 화면 시안 — 주인: A (화면 구현은 C, PRD 4.11 F-100 - F-108). 그림만 만든다.
타이틀과 같은 느낌(노을·안개·좀비, 핏빛 글자)으로, 두 화면은 배경과 판 모양을 다르게:
  로그인  = 폐허 마을 배경 · 오른쪽에 녹슨 철판(볼트) "생존자 확인"
  회원가입 = 부서진 다리 배경 · 왼쪽에 피 묻은 종이 등록증(테이프) "생존자 등록"

사용:
  godot --path godot --resolution 1920x1080 res://scenes/stage/title_art.tscn -- --out=art/previews/bg_in.png --dist=440 --yaw=20 --zombies=2
  godot --path godot --resolution 1920x1080 res://scenes/stage/title_art.tscn -- --out=art/previews/bg_up.png --dist=665 --yaw=-15 --zombies=3
  python art/title/make_account_screens.py --bg-in art/previews/bg_in.png --bg-up art/previews/bg_up.png --out-dir art/title
글꼴: 맑은 고딕 (과제용 비상업 — 상용 전 OFL 글꼴로 교체, README)
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_title import FONT, title_layer  # noqa: E402

FONT_R = "C:/Windows/Fonts/malgun.ttf"
W, H = 1920, 1080


def f(size, bold=False):
    return ImageFont.truetype(FONT if bold else FONT_R, size)


def darken(bg, side):
    """배경을 어둡게 누르고, 판이 놓일 쪽을 더 어둡게."""
    a = np.asarray(bg.convert("RGBA"), dtype=np.float32).copy()
    x = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    y = np.linspace(-1, 1, H, dtype=np.float32)[:, None]
    k = x if side == "right" else 1 - x
    shade = np.clip(0.8 - 0.45 * k ** 1.5 - 0.2 * y ** 2, 0.25, 1)
    a[..., :3] *= shade[..., None]
    a[..., 0] *= 1.05
    return Image.fromarray(np.clip(a, 0, 255).astype("uint8"), "RGBA")


def noise(size, seed, scale=6):
    rng = np.random.default_rng(seed)
    n = rng.random((size[1] // scale + 1, size[0] // scale + 1))
    return np.asarray(Image.fromarray((n * 255).astype("uint8")).resize(size, Image.BICUBIC), dtype=np.float32) / 255


def metal_panel(size, seed):
    """녹슨 철판: 짙은 쇠색 + 녹 얼룩 + 긁힘 + 모서리 볼트."""
    w, h = size
    n1, n2 = noise(size, seed, 40), noise(size, seed + 1, 8)
    base = np.array([38, 38, 40], np.float32) + (n2[..., None] - 0.5) * 18
    rust = np.array([70, 32, 18], np.float32)
    r = np.clip((n1 - 0.62) * 2.2, 0, 0.7)[..., None]          # 녹은 군데군데만, 글자가 묻히지 않게
    rgb = base * (1 - r) + rust * r
    img = Image.fromarray(np.clip(rgb, 0, 255).astype("uint8")).convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(40):                                    # 긁힘
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        L, ang = rng.uniform(20, 90), rng.uniform(-0.4, 0.4)
        d.line((x, y, x + L, y + L * ang), fill=(120, 118, 115, 90), width=1)
    for bx, by in ((22, 22), (w - 22, 22), (22, h - 22), (w - 22, h - 22)):   # 볼트
        d.ellipse((bx - 9, by - 9, bx + 9, by + 9), fill=(70, 66, 62), outline=(20, 18, 16), width=2)
        d.line((bx - 5, by, bx + 5, by), fill=(25, 22, 20), width=2)
    d.rectangle((0, 0, w - 1, h - 1), outline=(15, 12, 12), width=6)
    d.rectangle((6, 6, w - 7, h - 7), outline=(90, 30, 25), width=2)
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), 10, fill=235)
    img.putalpha(m)
    return img


def paper_panel(size, seed):
    """피 묻은 종이 등록증: 누렇게 바랜 종이 + 핏자국 + 찢긴 가장자리 + 테이프."""
    w, h = size
    n1, n2 = noise(size, seed, 30), noise(size, seed + 1, 4)
    base = np.array([196, 184, 158], np.float32) * (0.82 + 0.18 * n2[..., None]) - n1[..., None] * 35
    img = Image.fromarray(np.clip(base, 0, 255).astype("uint8")).convert("RGBA")
    blood = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(blood)
    rng = np.random.default_rng(seed)
    for _ in range(9):                                     # 핏자국
        x, y, r = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(8, 40)
        d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=(110, 12, 10, int(rng.uniform(60, 140))))
    x, y = w * 0.82, h * 0.12                              # 손가락 자국
    for k in range(4):
        d.ellipse((x + k * 16 - 8, y - 34 + abs(k - 1.5) * 6, x + k * 16 + 8, y + 12), fill=(95, 10, 8, 120))
    img.alpha_composite(blood.filter(ImageFilter.GaussianBlur(1.2)))
    m = Image.new("L", size, 0)                            # 찢긴 가장자리
    pts = [(w * i / 40, rng.uniform(0, 10)) for i in range(41)]
    pts += [(w - rng.uniform(0, 10), h * i / 40) for i in range(41)]
    pts += [(w - w * i / 40, h - rng.uniform(0, 12)) for i in range(41)]
    pts += [(rng.uniform(0, 10), h - h * i / 40) for i in range(41)]
    ImageDraw.Draw(m).polygon(pts, fill=255)
    img.putalpha(m)
    t = ImageDraw.Draw(img)                                # 테이프
    t.rectangle((w * 0.5 - 70, 0, w * 0.5 + 70, 30), fill=(215, 210, 190, 170))
    return img


def field(d, x, y, w, label, value, dark, error=None, password=False):
    lab = (230, 220, 210) if dark else (40, 20, 15)
    box_bg = (18, 16, 16, 220) if dark else (245, 238, 222, 230)
    box_line = (120, 35, 28) if dark else (70, 40, 30)
    txt = (235, 228, 220) if dark else (30, 20, 15)
    d.text((x, y), label, font=f(28, True), fill=lab)
    d.rounded_rectangle((x, y + 42, x + w, y + 110), 8, fill=box_bg, outline=(200, 40, 30) if error else box_line, width=3)
    d.text((x + 20, y + 76), "●" * len(value) if password else value, font=f(28), fill=txt, anchor="lm")
    if error:
        d.text((x, y + 118), "※ " + error, font=f(24, True), fill=(190, 25, 18))
        return y + 160
    return y + 135


def button(d, x, y, w, text, primary=True, dark=True):
    if primary:
        d.rounded_rectangle((x, y, x + w, y + 84), 10, fill=(140, 18, 14), outline=(30, 5, 5), width=4)
        d.rounded_rectangle((x + 6, y + 6, x + w - 6, y + 30), 8, fill=(170, 36, 28))
        d.text((x + w // 2, y + 44), text, font=f(36, True), fill=(250, 235, 225), anchor="mm", stroke_width=2, stroke_fill=(40, 5, 5))
        return y + 106
    col = (225, 215, 205) if dark else (50, 25, 20)
    d.rounded_rectangle((x, y, x + w, y + 70), 10, outline=col, width=2)
    d.text((x + w // 2, y + 35), text, font=f(28, True), fill=col, anchor="mm")
    return y + 92


def logo(scale):
    t = title_layer((1920, 520), "좀비탈출", ImageFont.truetype(FONT, 240), seed=13)
    t = t.crop(t.getbbox())
    return t.resize((int(t.width * scale), int(t.height * scale)), Image.LANCZOS)


def shadow(img, box, r=30):
    s = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle(box, 14, fill=(0, 0, 0, 170))
    img.alpha_composite(s.filter(ImageFilter.GaussianBlur(r)))


def sign_in(bg):
    img = darken(bg, "right")
    pw, ph = 720, 900
    px, py = W - pw - 110, (H - ph) // 2
    shadow(img, (px + 10, py + 20, px + pw + 10, py + ph + 20))
    img.alpha_composite(metal_panel((pw, ph), 3), (px, py))
    lg = logo(0.34)
    img.alpha_composite(lg, (px + (pw - lg.width) // 2, py + 26))
    d = ImageDraw.Draw(img)
    y = py + 34 + lg.height
    d.text((px + pw // 2, y), "생존자 확인", font=f(40, True), fill=(235, 220, 205), anchor="mt", stroke_width=2, stroke_fill=(0, 0, 0))
    y += 70
    x, w = px + 60, pw - 120
    y = field(d, x, y, w, "이메일", "survivor@mail.com", True)
    y = field(d, x, y, w, "비밀번호", "safehouse", True, password=True)
    d.text((x + w, y - 14), "비밀번호를 잊으셨나요?", font=f(24), fill=(215, 150, 130), anchor="rt")
    y += 28
    y = button(d, x, y, w, "로그인")
    y = button(d, x, y, w, "새 생존자 등록 (회원가입)", primary=False)
    d.text((px + pw // 2, y + 4), "게스트로 계속하기  ›", font=f(26, True), fill=(200, 190, 180), anchor="mt")
    return img


def sign_up(bg):
    img = darken(bg, "left")
    pw, ph = 720, 960
    px, py = 110, (H - ph) // 2
    shadow(img, (px + 10, py + 20, px + pw + 10, py + ph + 20))
    paper = paper_panel((pw, ph), 7).rotate(-1.2, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(paper, (px - 10, py - 8))
    d = ImageDraw.Draw(img)
    lg = logo(0.27)
    img.alpha_composite(lg, (px + (pw - lg.width) // 2, py + 36))
    y = py + 42 + lg.height
    d.text((px + pw // 2, y), "생존자 등록", font=f(42, True), fill=(90, 10, 8), anchor="mt")
    d.text((px + pw // 2, y + 56), "지금까지의 게스트 기록이 그대로 이어집니다", font=f(22), fill=(70, 45, 35), anchor="mt")
    y += 98
    x, w = px + 60, pw - 120
    y = field(d, x, y, w, "닉네임", "마지막생존자", False)
    y = field(d, x, y, w, "이메일", "survivor@mail.com", False, error="이미 가입된 이메일입니다 (오류 안내 예)")
    y = field(d, x, y, w, "비밀번호 (8자 이상)", "safehouse", False, password=True)
    y = field(d, x, y, w, "비밀번호 확인", "safehouse", False, password=True)
    y = button(d, x, y, w, "등록하기")
    d.text((px + pw // 2, y - 4), "이미 등록했나요?  로그인  ›", font=f(26, True), fill=(60, 30, 22), anchor="mt")
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg-in", required=True)
    ap.add_argument("--bg-up", required=True)
    ap.add_argument("--out-dir", required=True)
    a = ap.parse_args()
    for name, fn, bgp in (("signin_mock.png", sign_in, a.bg_in), ("signup_mock.png", sign_up, a.bg_up)):
        out = os.path.join(a.out_dir, name)
        fn(Image.open(bgp)).convert("RGB").save(out, optimize=True)
        print("ACCOUNT saved", out)


if __name__ == "__main__":
    main()
