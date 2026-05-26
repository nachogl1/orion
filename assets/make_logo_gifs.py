"""Generate animated 'orion' logo GIFs (several styles) into the user's Downloads.

Recreates the constellation + wordmark from assets/orion.svg on a deep-space
background and animates the stars. Pillow-only (no numpy). Supersampled for AA.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops, ImageOps

# ---- canvas / palette ------------------------------------------------------
W, H = 820, 260
SS = 3                      # supersample factor
CW, CH = W * SS, H * SS

CYAN = (92, 200, 255)       # #5cc8ff  stars / wordmark
SUB = (138, 160, 194)       # #8aa0c2  subtitle
BG = (7, 11, 26)            # deep navy space

OUT = os.path.expanduser(r"~\Downloads")

# ---- geometry (SVG coords + translate(40,20)) ------------------------------
# (x, y, radius)
STARS = [
    (80, 90, 5.5),   # 0  bright anchor (left)
    (230, 75, 4.0),  # 1
    (150, 38, 3.0),  # 2  top
    (112, 170, 3.6), # 3
    (148, 160, 3.6), # 4
    (188, 158, 3.6), # 5
    (102, 242, 3.6), # 6  bottom-left
    (236, 246, 5.5), # 7  bright anchor (bottom-right)
]
EDGES = [(0, 1), (0, 2), (2, 1), (0, 3), (3, 4), (4, 5), (1, 5), (3, 6), (5, 7)]

# per-star twinkle phase so they don't pulse in unison
PHASE = [0.0, 0.35, 0.7, 0.15, 0.55, 0.85, 0.45, 0.25]

# ---- fonts -----------------------------------------------------------------
FDIR = r"C:\Windows\Fonts"
font_word = ImageFont.truetype(os.path.join(FDIR, "segoeuil.ttf"), int(92 * SS))   # Segoe UI Light
font_sub = ImageFont.truetype(os.path.join(FDIR, "segoeui.ttf"), int(19 * SS))


def scol(color, b):
    """Scale an RGB tuple by brightness b, clamped."""
    return tuple(max(0, min(255, int(c * b))) for c in color)


def draw_tracked(d, pos, text, font, fill, tracking):
    """Draw text with manual letter-spacing (Pillow has none). pos = left baseline."""
    x, y = pos
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill, anchor="ls")
        x += font.getlength(ch) + tracking * SS


# ---- static background (vignette glow + faint starfield) -------------------
def build_bg():
    base = Image.new("RGB", (CW, CH), BG)
    # soft central depth-glow
    blob = ImageOps.invert(Image.radial_gradient("L")).resize((CW, CH))
    tint = ImageOps.colorize(blob, black=(0, 0, 0), white=(14, 30, 60))
    base = ImageChops.add(base, tint)
    # faint static starfield (deterministic)
    d = ImageDraw.Draw(base)
    rng = _lcg(20240526)
    for _ in range(90):
        x = next(rng) * CW
        y = next(rng) * CH
        b = 0.12 + next(rng) * 0.35
        r = (0.5 + next(rng) * 1.0) * SS
        c = scol((150, 175, 215), b)
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    return base


def _lcg(seed):
    """Tiny deterministic [0,1) generator (no numpy)."""
    s = seed
    while True:
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        yield s / 0x7FFFFFFF


BG_STATIC = build_bg()

# twinkling foreground starfield (animated): (x, y, base, phase, freq, r)
def build_twinkle_field():
    rng = _lcg(777)
    field = []
    for _ in range(45):
        field.append((
            next(rng) * CW, next(rng) * CH,
            0.2 + next(rng) * 0.4,            # base brightness
            next(rng),                        # phase
            1 + int(next(rng) * 2),           # freq
            (0.6 + next(rng) * 1.1) * SS,     # radius
        ))
    return field


TW_FIELD = build_twinkle_field()


def add_glow(base, glow, blur, gain):
    g = glow.filter(ImageFilter.GaussianBlur(blur))
    if gain != 1.0:
        g = g.point(lambda v: min(255, int(v * gain)))
    return ImageChops.add(base, g)


# ---- core frame renderer ---------------------------------------------------
def render(star_b, star_s, line_b, master=1.0, meteor=None, twk=0.0,
           word_glow=0.6):
    """star_b/star_s: per-star brightness & size mult. line_b: per-edge brightness."""
    base = BG_STATIC.copy()
    glow = Image.new("RGB", (CW, CH), 0)
    gd = ImageDraw.Draw(glow)
    sharp = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sharp)

    # animated twinkle starfield (sharp dots)
    if twk > 0:
        for (x, y, b0, ph, fq, r) in TW_FIELD:
            b = b0 * (0.5 + 0.5 * math.sin(2 * math.pi * (twk * fq + ph)))
            c = scol((170, 195, 235), b * master)
            sd.ellipse([x - r, y - r, x + r, y + r], fill=c + (255,))

    # constellation lines
    for k, (a, b) in enumerate(EDGES):
        lb = line_b[k] * master
        if lb <= 0.01:
            continue
        ax, ay = STARS[a][0] * SS, STARS[a][1] * SS
        bx, by = STARS[b][0] * SS, STARS[b][1] * SS
        gd.line([ax, ay, bx, by], fill=scol(CYAN, 0.55 * lb), width=int(3.4 * SS),
                joint="curve")
        sd.line([ax, ay, bx, by], fill=scol(CYAN, lb) + (255,), width=max(1, int(1.4 * SS)),
                joint="curve")

    # stars (halo on glow, crisp core on sharp)
    for i, (x, y, r) in enumerate(STARS):
        b = star_b[i] * master
        sc = star_s[i]
        cx, cy = x * SS, y * SS
        hr = r * SS * (2.4 + 0.6 * sc)
        gd.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=scol(CYAN, 0.7 * b))
        cr = r * SS * sc
        sd.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=scol((210, 240, 255), b) + (255,))

    # meteor / shooting star
    if meteor is not None:
        hx, hy, dx, dy, ml, mb = meteor
        for j in range(14):
            f = j / 13.0
            x1 = hx - dx * ml * f
            y1 = hy - dy * ml * f
            x2 = hx - dx * ml * (f + 1 / 13.0)
            y2 = hy - dy * ml * (f + 1 / 13.0)
            tb = mb * (1 - f) ** 1.6
            gd.line([x1, y1, x2, y2], fill=scol((150, 210, 255), 0.6 * tb), width=int(3.0 * SS))
            sd.line([x1, y1, x2, y2], fill=scol((220, 245, 255), tb) + (255,), width=max(1, int(1.3 * SS)))
        hr = 3.2 * SS
        gd.ellipse([hx - hr * 2, hy - hr * 2, hx + hr * 2, hy + hr * 2], fill=scol((180, 225, 255), mb))
        sd.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=scol((230, 248, 255), mb) + (255,))

    # composite glow
    base = add_glow(base, glow, blur=7 * SS, gain=1.35)

    # wordmark + subtitle (own soft glow so blur stays tight)
    tg = Image.new("RGB", (CW, CH), 0)
    td = ImageDraw.Draw(tg)
    draw_tracked(td, (320 * SS, 140 * SS), "orion", font_word, scol(CYAN, master), 4)
    base = add_glow(base, tg, blur=2.6 * SS, gain=word_glow * master)

    base = Image.alpha_composite(base.convert("RGBA"), sharp).convert("RGB")
    fd = ImageDraw.Draw(base)
    draw_tracked(fd, (320 * SS, 140 * SS), "orion", font_word, scol(CYAN, master), 4)
    draw_tracked(fd, (324 * SS, 178 * SS), "claude code skills", font_sub, scol(SUB, master), 5)

    return base.resize((W, H), Image.LANCZOS)


# ---- style frame generators ------------------------------------------------
def frames_twinkle(n=36):
    out = []
    for k in range(n):
        t = k / n
        sb = [0.55 + 0.45 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + PHASE[i]))) for i in range(8)]
        ss = [0.85 + 0.25 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + PHASE[i]))) for i in range(8)]
        lb = [0.7 + 0.15 * math.sin(2 * math.pi * (t + e * 0.1)) for e in range(len(EDGES))]
        out.append(render(sb, ss, lb, twk=t, word_glow=0.55 + 0.15 * math.sin(2 * math.pi * t)))
    return out


def frames_pulse(n=40):
    """A wave of light sweeps through the constellation by star index."""
    out = []
    sigma = 0.13
    for k in range(n):
        t = k / n
        sb, ss = [], []
        for i in range(8):
            u = i / 7.0
            d = abs(t - u)
            d = min(d, 1 - d)
            g = math.exp(-(d / sigma) ** 2)
            sb.append(0.5 + 0.9 * g)
            ss.append(0.85 + 0.6 * g)
        lb = []
        for (a, b) in EDGES:
            um = ((a + b) / 2) / 7.0
            d = abs(t - um); d = min(d, 1 - d)
            lb.append(0.55 + 0.55 * math.exp(-(d / sigma) ** 2))
        out.append(render(sb, ss, lb, twk=t * 0.5))
    return out


def frames_drawin(n=44):
    """Lines draw themselves in sequence, hold + twinkle, then fade and loop."""
    out = []
    slot = [0, 1, 2, 3, 4, 5, 6, 7, 8]          # edge reveal order = list order
    es = [0.04 * s for s in slot]
    dur = 0.14
    # star appears when its first incident edge starts revealing
    star_thresh = [1.0] * 8
    for k, (a, b) in enumerate(EDGES):
        star_thresh[a] = min(star_thresh[a], es[k])
        star_thresh[b] = min(star_thresh[b], es[k])
    star_thresh[0] = 0.0
    for k in range(n):
        t = k / n
        # master fade for seamless loop: hold, then fade out at the very end
        if t < 0.78:
            master = 1.0
        else:
            master = max(0.0, 1 - (t - 0.78) / 0.22)
        lb = []
        for j in range(len(EDGES)):
            f = (t - es[j]) / dur
            lb.append(max(0.0, min(1.0, f)))
        sb, ss = [], []
        for i in range(8):
            f = (t - star_thresh[i]) / 0.10
            appear = max(0.0, min(1.0, f))
            tw = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 1.5 + PHASE[i]))
            sb.append(appear * (0.6 + 0.4 * tw))
            ss.append(0.8 + 0.3 * appear)
        out.append(render(sb, ss, lb, master=master, twk=t))
    return out


def frames_shooting(n=44):
    """Gentle twinkle + a meteor streaks across the panel once per loop."""
    out = []
    for k in range(n):
        t = k / n
        sb = [0.55 + 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + PHASE[i]))) for i in range(8)]
        ss = [0.85 + 0.2 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + PHASE[i]))) for i in range(8)]
        lb = [0.7] * len(EDGES)
        meteor = None
        m0, m1 = 0.12, 0.40
        if m0 <= t <= m1:
            u = (t - m0) / (m1 - m0)
            hx = (-0.08 + 0.6 * u) * CW
            hy = (-0.05 + 0.7 * u) * CH
            dxn, dyn = 0.6, 0.7
            nrm = math.hypot(dxn, dyn)
            mb = math.sin(math.pi * u)        # fade in/out
            meteor = (hx, hy, dxn / nrm, dyn / nrm, 0.16 * CW, mb)
        out.append(render(sb, ss, lb, meteor=meteor, twk=t))
    return out


# ---- global palette + save -------------------------------------------------
def build_palette(all_frames):
    sample = all_frames[::max(1, len(all_frames) // 12)]
    cols = len(sample)
    montage = Image.new("RGB", (W * cols, H))
    for i, f in enumerate(sample):
        montage.paste(f, (i * W, 0))
    return montage.quantize(colors=256, method=Image.MEDIANCUT)


def save_gif(frames, name, ms):
    pal = build_palette(frames)
    mapped = [f.quantize(palette=pal, dither=Image.FLOYDSTEINBERG) for f in frames]
    path = os.path.join(OUT, name)
    mapped[0].save(path, save_all=True, append_images=mapped[1:], duration=ms,
                   loop=0, optimize=True, disposal=2)
    kb = os.path.getsize(path) / 1024
    print(f"  {name}: {len(frames)} frames, {kb:.0f} KB")
    return path


if __name__ == "__main__":
    jobs = [
        ("orion-twinkle.gif", frames_twinkle, 60),
        ("orion-pulse.gif", frames_pulse, 55),
        ("orion-drawin.gif", frames_drawin, 55),
        ("orion-shooting-star.gif", frames_shooting, 55),
    ]
    print("Rendering...")
    for name, fn, ms in jobs:
        print(f"- {name}")
        save_gif(fn(), name, ms)
    print(f"Done -> {OUT}")
