# 상점 팩 카드 3장 (2026-09-30): 상자에 무기·소품이 담긴 2D 일러스트 카드 → PNG
# 실행: python3 art/shop/make_packs.py  (Chrome 헤드리스로 찍는다. 외부 그림·글꼴 없음 — 모두 SVG 로 직접 그림)
import os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1080, 1350

DEFS = r"""
<defs>
  <linearGradient id="steel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e9e6e0"/><stop offset=".45" stop-color="#9c9a96"/><stop offset="1" stop-color="#55544f"/></linearGradient>
  <linearGradient id="dark" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3a3c"/><stop offset="1" stop-color="#141415"/></linearGradient>
  <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff1b8"/><stop offset=".35" stop-color="#e2b24a"/><stop offset=".7" stop-color="#a8761f"/><stop offset="1" stop-color="#5e3e0c"/></linearGradient>
  <linearGradient id="brass" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#7a5418"/><stop offset=".45" stop-color="#e8c06a"/><stop offset="1" stop-color="#8a611f"/></linearGradient>
  <linearGradient id="olive" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5d6340"/><stop offset="1" stop-color="#2c301d"/></linearGradient>
  <linearGradient id="wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8a5d34"/><stop offset="1" stop-color="#4a2f18"/></linearGradient>
  <linearGradient id="case" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#26262a"/><stop offset="1" stop-color="#0d0d0f"/></linearGradient>
  <linearGradient id="foam" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b1b1e"/><stop offset="1" stop-color="#101012"/></linearGradient>
  <radialGradient id="redglow"><stop offset="0" stop-color="#ff5a3c" stop-opacity=".95"/><stop offset=".4" stop-color="#c8141a" stop-opacity=".45"/><stop offset="1" stop-color="#c8141a" stop-opacity="0"/></radialGradient>
  <radialGradient id="goldglow"><stop offset="0" stop-color="#ffd978" stop-opacity=".75"/><stop offset=".5" stop-color="#d9962a" stop-opacity=".25"/><stop offset="1" stop-color="#d9962a" stop-opacity="0"/></radialGradient>
  <radialGradient id="fireglow"><stop offset="0" stop-color="#ffc766" stop-opacity=".9"/><stop offset=".5" stop-color="#ff6a1a" stop-opacity=".35"/><stop offset="1" stop-color="#ff6a1a" stop-opacity="0"/></radialGradient>
  <radialGradient id="bg" cx=".5" cy=".32" r=".8"><stop offset="0" stop-color="#5a2a2c"/><stop offset=".45" stop-color="#2a1a1e"/><stop offset="1" stop-color="#0c0a0c"/></radialGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#000" flood-opacity=".6"/></filter>
  <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 .08 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>

  <!-- 칼 (가로, 날이 오른쪽) 길이 300 -->
  <g id="knife">
    <path d="M110 18 L292 30 Q300 34 292 40 L110 50 Z" fill="url(#steel)"/>
    <path d="M110 18 L292 30 L200 30 L110 28 Z" fill="#fff" opacity=".55"/>
    <path d="M150 44 L270 38" stroke="#6b6a66" stroke-width="2"/>
    <rect x="96" y="8" width="14" height="52" rx="3" fill="url(#dark)"/>
    <rect x="8" y="20" width="90" height="28" rx="10" fill="#1c1c1e"/>
    <g stroke="#333336" stroke-width="3">
      <line x1="22" y1="22" x2="22" y2="46"/><line x1="38" y1="22" x2="38" y2="46"/><line x1="54" y1="22" x2="54" y2="46"/><line x1="70" y1="22" x2="70" y2="46"/><line x1="86" y1="22" x2="86" y2="46"/>
    </g>
    <circle cx="8" cy="34" r="6" fill="#55544f"/>
  </g>

  <!-- 권총 (가로, 총구 오른쪽) 폭 300 — fill 로 색 바꿈 -->
  <g id="pistol-shape">
    <path d="M40 20 H292 Q300 20 300 28 V64 H40 Z"/>
    <path d="M60 64 H250 V84 Q246 92 236 92 H150 Q132 92 126 110 L108 196 Q104 206 94 206 H56 Q44 206 46 194 L66 90 Q68 70 60 64 Z"/>
    <path d="M150 92 Q150 128 184 128 H214 Q226 128 226 116 V92 H212 V112 Q212 116 208 116 H186 Q166 116 166 92 Z"/>
  </g>
  <g id="pistol-lines" fill="none" stroke="#000" stroke-opacity=".45" stroke-width="3">
    <line x1="58" y1="26" x2="58" y2="58"/><line x1="68" y1="26" x2="68" y2="58"/><line x1="78" y1="26" x2="78" y2="58"/><line x1="88" y1="26" x2="88" y2="58"/>
    <rect x="160" y="30" width="60" height="16" rx="2"/>
    <line x1="40" y1="64" x2="300" y2="64"/>
    <path d="M70 110 L60 190" stroke-opacity=".25" stroke-width="10"/>
  </g>
  <g id="pistol"><use href="#pistol-shape" fill="url(#dark)"/><use href="#pistol-lines"/><path d="M44 22 H296" stroke="#8b8b90" stroke-width="3"/></g>
  <g id="pistol-gold"><use href="#pistol-shape" fill="url(#gold)"/><use href="#pistol-lines"/><path d="M44 22 H296" stroke="#fff4c4" stroke-width="4"/></g>

  <!-- 탄창 (세로) 높이 190 -->
  <g id="mag">
    <path d="M14 30 L60 30 L70 190 L26 190 Z" fill="url(#dark)"/>
    <rect x="22" y="180" width="52" height="16" rx="3" fill="#2a2a2d"/>
    <path d="M26 42 L58 42" stroke="#5a5a5e" stroke-width="3"/>
    <rect x="22" y="14" width="30" height="20" rx="6" fill="url(#brass)"/>
    <ellipse cx="37" cy="12" rx="11" ry="8" fill="#b36a2a"/>
  </g>
  <g id="mag-hot"><use href="#mag"/><circle cx="42" cy="100" r="80" fill="url(#redglow)" opacity=".55"/><path d="M26 60 L64 60 M28 90 L66 90 M30 120 L68 120" stroke="#ff4a2a" stroke-width="3" opacity=".8"/></g>

  <!-- 총알 하나 (세로) -->
  <g id="round"><rect x="0" y="16" width="16" height="34" rx="2" fill="url(#brass)"/><path d="M0 16 Q8 -4 16 16 Z" fill="#b8702e"/></g>

  <!-- 탄약 상자 (시작 탄약 팩) 폭 150 -->
  <g id="ammobox">
    <rect x="0" y="0" width="150" height="96" rx="6" fill="#6e5a3a"/>
    <rect x="0" y="0" width="150" height="26" rx="6" fill="#8a7248"/>
    <text x="75" y="70" text-anchor="middle" font-family="Impact, Arial Black, sans-serif" font-size="32" fill="#e8dcc0" letter-spacing="3">9MM</text>
    <g transform="translate(22,-34)"><use href="#round"/></g><g transform="translate(44,-38)"><use href="#round"/></g><g transform="translate(66,-34)"><use href="#round"/></g><g transform="translate(88,-40)"><use href="#round"/></g><g transform="translate(110,-34)"><use href="#round"/></g>
  </g>

  <!-- 신호탄 (세로) 높이 200 -->
  <g id="flare">
    <circle cx="22" cy="0" r="70" fill="url(#redglow)"/>
    <rect x="6" y="20" width="32" height="180" rx="6" fill="#b3161a"/>
    <rect x="6" y="120" width="32" height="18" fill="#e8dcc0"/>
    <rect x="2" y="10" width="40" height="22" rx="4" fill="#2a2a2d"/>
    <path d="M22 8 L14 -18 L22 -6 L28 -26 L30 -4" fill="#ffd27a"/>
  </g>

  <!-- 주사기 (가로) 길이 260 — 부활 -->
  <g id="syringe">
    <ellipse cx="130" cy="30" rx="150" ry="55" fill="url(#redglow)" opacity=".8"/>
    <rect x="0" y="22" width="16" height="16" rx="3" fill="#cfcac0"/>
    <rect x="14" y="27" width="40" height="6" fill="#bdb8ae"/>
    <rect x="52" y="12" width="140" height="36" rx="8" fill="#e8eef0" fill-opacity=".35" stroke="#f2f6f7" stroke-width="3"/>
    <rect x="60" y="18" width="126" height="24" rx="5" fill="#d8101a"/>
    <rect x="60" y="18" width="126" height="7" rx="3" fill="#ff7a6a" opacity=".7"/>
    <g stroke="#f2f6f7" stroke-width="2"><line x1="90" y1="12" x2="90" y2="22"/><line x1="120" y1="12" x2="120" y2="22"/><line x1="150" y1="12" x2="150" y2="22"/></g>
    <path d="M192 22 L210 26 L210 34 L192 38 Z" fill="#bdb8ae"/>
    <line x1="210" y1="30" x2="262" y2="30" stroke="#dcdcdc" stroke-width="3"/>
  </g>
  <!-- 아드레날린 주사기 (호박색 — 붉은 부활 주사기와 구분) -->
  <g id="syringe-adren">
    <ellipse cx="130" cy="30" rx="150" ry="55" fill="url(#fireglow)" opacity=".8"/>
    <rect x="0" y="22" width="16" height="16" rx="3" fill="#cfcac0"/>
    <rect x="14" y="27" width="40" height="6" fill="#bdb8ae"/>
    <rect x="52" y="12" width="140" height="36" rx="8" fill="#e8eef0" fill-opacity=".35" stroke="#f2f6f7" stroke-width="3"/>
    <rect x="60" y="18" width="126" height="24" rx="5" fill="#f2b01e"/>
    <rect x="60" y="18" width="126" height="7" rx="3" fill="#ffe08a" opacity=".7"/>
    <g stroke="#f2f6f7" stroke-width="2"><line x1="90" y1="12" x2="90" y2="22"/><line x1="120" y1="12" x2="120" y2="22"/><line x1="150" y1="12" x2="150" y2="22"/></g>
    <path d="M192 22 L210 26 L210 34 L192 38 Z" fill="#bdb8ae"/>
    <line x1="210" y1="30" x2="262" y2="30" stroke="#dcdcdc" stroke-width="3"/>
  </g>

  <!-- 모닥불 폭 170 -->
  <g id="bonfire">
    <circle cx="85" cy="40" r="120" fill="url(#fireglow)"/>
    <path d="M85 -40 Q120 10 108 50 Q130 20 124 -6 Q150 40 118 84 H52 Q20 44 46 0 Q48 30 64 44 Q52 0 85 -40 Z" fill="#ff7a1c"/>
    <path d="M86 0 Q106 34 96 70 H74 Q62 40 86 0 Z" fill="#ffd66a"/>
    <rect x="10" y="80" width="150" height="20" rx="10" fill="#4a2f18" transform="rotate(-10 85 90)"/>
    <rect x="10" y="80" width="150" height="20" rx="10" fill="#5e3b1e" transform="rotate(10 85 90)"/>
  </g>

  <!-- 고글 (위험 감지) 폭 220 -->
  <g id="goggles">
    <path d="M0 50 Q110 20 220 50" stroke="#2a2a2d" stroke-width="12" fill="none"/>
    <circle cx="70" cy="56" r="44" fill="#1c1c1e"/><circle cx="150" cy="56" r="44" fill="#1c1c1e"/>
    <circle cx="70" cy="56" r="32" fill="#b3161a"/><circle cx="150" cy="56" r="32" fill="#b3161a"/>
    <circle cx="70" cy="56" r="60" fill="url(#redglow)" opacity=".6"/><circle cx="150" cy="56" r="60" fill="url(#redglow)" opacity=".6"/>
    <ellipse cx="60" cy="44" rx="10" ry="6" fill="#ffb0a0" opacity=".8"/><ellipse cx="140" cy="44" rx="10" ry="6" fill="#ffb0a0" opacity=".8"/>
    <rect x="104" y="46" width="12" height="18" fill="#2a2a2d"/>
  </g>

  <!-- 서포터 배지 -->
  <g id="badge">
    <path d="M-20 -10 L-40 70 L-14 58 L0 84 L10 -10 Z M20 -10 L40 70 L14 58 L0 84 L-10 -10 Z" fill="#8f1418"/>
    <circle cx="0" cy="0" r="46" fill="url(#gold)" stroke="#5e3e0c" stroke-width="4"/>
    <path d="M0 -28 L8 -9 L28 -8 L12 5 L18 25 L0 14 L-18 25 L-12 5 L-28 -8 L-8 -9 Z" fill="#fff1b8"/>
  </g>
</defs>
"""

CSS = """
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:%dpx;height:%dpx;background:#0c0a0c;overflow:hidden}
.card{position:relative;width:100%%;height:100%%;font-family:Palatino,'Palatino Linotype',Baskerville,'Times New Roman',serif;color:#e9e2d4}
svg.art{position:absolute;left:0;top:0}
.tag{position:absolute;top:44px;left:50%%;transform:translateX(-50%%);font:600 30px/1 'Apple SD Gothic Neo',sans-serif;letter-spacing:6px;padding:12px 26px;border:2px solid currentColor}
.body{position:absolute;left:70px;right:70px;bottom:64px}
h1{font-weight:400;font-size:84px;letter-spacing:6px;line-height:1;margin-bottom:10px}
.sub{font:500 30px/1.3 'Apple SD Gothic Neo',sans-serif;color:#b8ab96;margin-bottom:28px}
ul{list-style:none;display:flex;flex-wrap:wrap;gap:12px;margin-bottom:36px}
li{font:600 28px/1 'Apple SD Gothic Neo',sans-serif;padding:14px 18px;background:rgba(255,255,255,.06);border-left:4px solid var(--accent)}
li b{color:var(--accent);margin-right:6px}
.buy{display:flex;align-items:center;justify-content:space-between;height:120px;padding:0 44px;background:var(--btn);color:#fff}
.buy .price{font:700 58px/1 'Apple SD Gothic Neo',sans-serif;letter-spacing:1px}
.buy .go{font:600 34px/1 'Apple SD Gothic Neo',sans-serif;letter-spacing:4px}
.note{margin-top:16px;font:500 22px/1 'Apple SD Gothic Neo',sans-serif;color:#8a8074;text-align:center}
"""

def card(key, title, sub, items, price, accent, btn, tag, tagcolor, scene):
    lis = "".join("<li><b>%s</b>%s</li>" % (n, t) for n, t in items)
    tag_html = ('<div class="tag" style="color:%s">%s</div>' % (tagcolor, tag)) if tag else ""
    return """<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>
<div class="card" style="--accent:%s;--btn:%s">
<svg class="art" width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">%s
<rect width="100%%" height="100%%" fill="url(#bg)"/>
%s
<rect width="100%%" height="100%%" filter="url(#grain)" fill="#fff"/>
<rect y="760" width="100%%" height="590" fill="url(#fadeb)"/>
<defs><linearGradient id="fadeb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0c0a0c" stop-opacity="0"/><stop offset=".35" stop-color="#0c0a0c" stop-opacity=".92"/><stop offset="1" stop-color="#0c0a0c"/></linearGradient></defs>
</svg>
%s
<div class="body"><h1>%s</h1><div class="sub">%s</div><ul>%s</ul>
<div class="buy"><span class="price">%s</span><span class="go">구매하기</span></div>
<div class="note">테스트 결제입니다 · 실제 돈이 나가지 않습니다</div></div>
</div></body></html>""" % (CSS % (W, H), accent, btn, W, H, W, H, DEFS, scene, tag_html, title, sub, lis, price)


# ── 장면 (상자 + 소품). 상자는 정면에서 살짝 내려다본 모습: 안쪽 벽 → 소품 → 앞면 순서로 그려 "담긴" 느낌
AMMO_TIN = """
<g transform="translate(540,520)">
  <ellipse cx="0" cy="250" rx="380" ry="40" fill="#000" opacity=".5"/>
  <!-- 뒤로 젖힌 뚜껑 -->
  <path d="M-300 -120 L300 -120 L270 -300 L-270 -300 Z" fill="url(#olive)"/>
  <path d="M-270 -300 L270 -300" stroke="#7b8254" stroke-width="6"/>
  <text x="0" y="-195" text-anchor="middle" font-family="Impact, Arial Black, sans-serif" font-size="54" fill="#d9cfa8" opacity=".75" letter-spacing="8">SURVIVAL</text>
  <!-- 안쪽 -->
  <path d="M-300 -120 L300 -120 L300 40 L-300 40 Z" fill="#1b1d12"/>
  <!-- 소품 -->
  <g transform="translate(-250,-60) rotate(-8)" filter="url(#shadow)"><use href="#knife" transform="scale(1.6)"/></g>
  <g transform="translate(90,-150) rotate(12)" filter="url(#shadow)"><use href="#flare" transform="scale(1.05)"/></g>
  <g transform="translate(-120,-30)" filter="url(#shadow)"><use href="#ammobox" transform="scale(1.3)"/></g>
  <g transform="translate(-255,-125) rotate(-3)" filter="url(#shadow)"><use href="#syringe-adren" transform="scale(.8)"/></g>
  <!-- 앞면 -->
  <path d="M-320 20 L320 20 L300 220 L-300 220 Z" fill="url(#olive)"/>
  <path d="M-320 20 L320 20" stroke="#8a915e" stroke-width="8"/>
  <rect x="-60" y="60" width="120" height="44" rx="6" fill="#23261a"/>
  <rect x="-40" y="72" width="80" height="20" rx="4" fill="#6e7449"/>
  <text x="0" y="176" text-anchor="middle" font-family="Impact, Arial Black, sans-serif" font-size="40" fill="#d9cfa8" opacity=".7" letter-spacing="10">KIT · 01</text>
</g>"""

SUPPLY_CRATE = """
<g transform="translate(540,520)">
  <circle cx="0" cy="-60" r="380" fill="url(#redglow)" opacity=".35"/>
  <ellipse cx="0" cy="260" rx="420" ry="44" fill="#000" opacity=".55"/>
  <!-- 비스듬히 기댄 뚜껑 -->
  <g transform="translate(250,-120) rotate(18)"><rect x="-120" y="-230" width="240" height="330" fill="url(#wood)"/><g stroke="#2e1c0e" stroke-width="5"><line x1="-120" y1="-120" x2="120" y2="-120"/><line x1="-120" y1="-10" x2="120" y2="-10"/></g>
    <path d="M-20 -100 h40 v-40 h40 v40 h40 v40 h-40 v40 h-40 v-40 h-40 z" transform="translate(-40,-10) scale(.8)" fill="#b3161a" opacity=".85"/></g>
  <!-- 안쪽 -->
  <path d="M-330 -130 L330 -130 L330 40 L-330 40 Z" fill="#1d120a"/>
  <!-- 소품 -->
  <g transform="translate(-40,-150)"><use href="#bonfire" transform="scale(1.05)"/></g>
  <g transform="translate(-310,-90) rotate(-4)" filter="url(#shadow)"><use href="#syringe" transform="scale(1.25)"/></g>
  <g transform="translate(150,-150) rotate(14)" filter="url(#shadow)"><use href="#mag-hot" transform="scale(1.1)"/></g>
  <!-- 앞면 (판자) -->
  <path d="M-350 20 L350 20 L330 230 L-330 230 Z" fill="url(#wood)"/>
  <g stroke="#2e1c0e" stroke-width="6"><line x1="-345" y1="90" x2="345" y2="90"/><line x1="-338" y1="160" x2="338" y2="160"/></g>
  <path d="M-350 20 L350 20" stroke="#a9774a" stroke-width="8"/>
  <path d="M-20 -30 h40 v-40 h40 v40 h40 v40 h-40 v40 h-40 v-40 h-40 z" transform="translate(-20,150)" fill="#b3161a" opacity=".9"/>
  <g fill="#6b6b6e"><circle cx="-320" cy="44" r="7"/><circle cx="320" cy="44" r="7"/><circle cx="-310" cy="206" r="7"/><circle cx="310" cy="206" r="7"/></g>
</g>"""

LEGEND_CASE = """
<g transform="translate(540,440) scale(.9)">
  <circle cx="0" cy="-40" r="440" fill="url(#goldglow)"/>
  <ellipse cx="0" cy="280" rx="440" ry="46" fill="#000" opacity=".6"/>
  <!-- 열린 뚜껑 (뒤) -->
  <path d="M-380 -170 L380 -170 L350 -330 L-350 -330 Z" fill="url(#case)" stroke="url(#gold)" stroke-width="6"/>
  <text x="0" y="-232" text-anchor="middle" font-family="Palatino, serif" font-size="46" fill="url(#gold)" letter-spacing="14">LEGEND</text>
  <!-- 스펀지 판 -->
  <path d="M-380 -170 L380 -170 L380 250 L-380 250 Z" fill="url(#foam)" stroke="url(#gold)" stroke-width="8"/>
  <g fill="#070708">
    <rect x="-300" y="-150" width="420" height="220" rx="16"/>
    <rect x="160" y="-150" width="190" height="140" rx="16"/>
    <rect x="-350" y="90" width="330" height="60" rx="14"/><rect x="-350" y="165" width="330" height="60" rx="14"/>
    <rect x="10" y="90" width="120" height="140" rx="14"/><rect x="145" y="0" width="210" height="110" rx="14"/>
    <rect x="160" y="125" width="190" height="105" rx="14"/>
  </g>
  <!-- 소품 -->
  <g transform="translate(-280,-150)" filter="url(#shadow)"><circle cx="190" cy="100" r="190" fill="url(#goldglow)"/><use href="#pistol-gold" transform="scale(1.3)"/></g>
  <g transform="translate(168,-150)" filter="url(#shadow)"><use href="#goggles" transform="scale(.8)"/></g>
  <g transform="translate(-352,95)" filter="url(#shadow)"><use href="#knife" transform="scale(1.07)"/></g>
  <g transform="translate(-352,170)" filter="url(#shadow)"><use href="#knife" transform="scale(1.07)"/></g>
  <g transform="translate(22,92)" filter="url(#shadow)"><use href="#mag" transform="scale(.7)"/></g><g transform="translate(66,92)" filter="url(#shadow)"><use href="#mag" transform="scale(.7)"/></g>
  <g transform="translate(150,10)" filter="url(#shadow)"><use href="#syringe" transform="scale(.75)"/></g>
  <g transform="translate(150,45)" filter="url(#shadow)"><use href="#syringe" transform="scale(.75)"/></g>
  <g transform="translate(255,172)" filter="url(#shadow)"><use href="#badge" transform="scale(.9)"/></g>
  <!-- 금 모서리 -->
  <g fill="url(#gold)"><path d="M-380 -170 h60 v14 h-46 v46 h-14 z"/><path d="M380 -170 h-60 v14 h46 v46 h14 z"/><path d="M-380 250 h60 v-14 h-46 v-46 h-14 z"/><path d="M380 250 h-60 v-14 h46 v-46 h14 z"/></g>
</g>"""

CARDS = [
    ("pack_survival_kit", "생존 키트", "처음 몇 번 쓰러진 당신에게", [("예비 칼", "×1"), ("시작 탄약 팩", "×1"), ("보급 신호탄", "×1"), ("아드레날린", "×1")],
     "₩1,500", "#b9ad7a", "#5d6340", "", "", AMMO_TIN),
    ("pack_one_more", "한 번 더", "끝을 보기 위한 한 번의 기회", [("부활", "×1"), ("광란의 15초", "×1"), ("모닥불", "×1")],
     "₩3,300", "#e0473a", "#a3121a", "가장 인기", "#ff6a55", SUPPLY_CRATE),
    ("pack_legend", "전설의 생존자", "끝까지 살아남는 자의 상자", [("부활", "×2"), ("예비 칼", "×2"), ("광란의 15초", "×2"), ("위험 감지", "×2"), ("황금 권총", "영구"), ("서포터 배지", "영구")],
     "₩5,500", "#e2b24a", "#8a5f14", "최고 가치", "#ffd978", LEGEND_CASE),
]

for key, *args in CARDS:
    html = os.path.join(HERE, "_%s.html" % key)
    open(html, "w").write(card(key, *args))
    out = os.path.join(HERE, "%s.png" % key)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=%d,%d" % (W, H),
                    "--screenshot=%s" % out, "file://" + html], check=True, capture_output=True)
    os.remove(html)
    print("[pack]", out, os.path.getsize(out) // 1024, "KB")
