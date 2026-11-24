#!/usr/bin/env python3
"""Compose Tuck Notch marketing images from transparent demo-tour captures.

Usage:  python3 tools/marketing/compose.py demo-captures out Resources/AppIcon.png
Needs Pillow and NumPy, and the Inter typeface (set INTER_FONT_DIR to the folder with Inter-*.otf).

Captures are real app windows (@2x, alpha) from `TuckNotch --demo-tour`. They are placed on a
virtual 1440x900 pt (@2x = 2880x1800 px) screen with a generated wallpaper, a menu bar and the
camera notch, exactly where the app draws them, then framed for README / X / GitHub.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = Path(sys.argv[1] if len(sys.argv) > 1 else "raw")
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "out")
ICON = Path(sys.argv[3] if len(sys.argv) > 3 else "AppIcon.png")
OUT.mkdir(parents=True, exist_ok=True)

SW, SH = 2880, 1800          # virtual screen, px
MENU_H = 64                  # menu bar / notch height, px (32 pt)
FONT_DIR = os.environ.get("INTER_FONT_DIR", "/usr/share/fonts/opentype/inter/").rstrip("/") + "/"


def font(name, size):
    return ImageFont.truetype(FONT_DIR + name, size)


# ---------------------------------------------------------------- wallpaper
def wallpaper(seed=7):
    w, h = 720, 450
    base = Image.new("RGB", (w, h), (6, 8, 18))
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    blobs = [  # (cx, cy, r, color)  — brand blue → violet → magenta
        (0.20, 0.30, 0.34, (40, 110, 255)),
        (0.45, 0.62, 0.30, (110, 60, 245)),
        (0.80, 0.30, 0.30, (200, 60, 200)),
        (0.88, 0.88, 0.26, (240, 80, 140)),
        (0.08, 0.92, 0.22, (20, 170, 200)),
    ]
    for cx, cy, r, col in blobs:
        R = r * w
        d.ellipse([cx * w - R, cy * h - R, cx * w + R, cy * h + R], fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(70))
    img = Image.blend(base, layer, 0.78)
    img = img.resize((SW, SH), Image.BICUBIC)
    # gentle vignette + grain (kills gradient banding)
    a = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:SH, 0:SW]
    v = 1 - 0.35 * (((xx - SW / 2) / (SW / 2)) ** 2 + ((yy - SH / 2) / (SH / 2)) ** 2)
    a *= np.clip(v, 0.55, 1)[..., None]
    rng = np.random.default_rng(seed)
    a += rng.normal(0, 2.2, a.shape)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGBA")


WALL = wallpaper()


# ---------------------------------------------------------------- screen
def menubar(img, k=1.0, notch=True, clear=0):
    """Draw a menu bar across `img` at scale k (1.0 = @2x pixels).
    `clear`: half-width (output px) around the centre kept free, like macOS does beside the notch."""
    W = img.width
    mh = round(MENU_H * k)
    bar = Image.new("RGBA", (W, mh), (0, 0, 0, 70))
    img.alpha_composite(bar, (0, 0))
    d = ImageDraw.Draw(img)
    y = mh / 2
    pad = round(36 * k)
    fs = max(12, round(27 * k))
    x = pad
    r = 11 * k
    d.ellipse([x, y - r, x + 2 * r, y + r], fill=(255, 255, 255, 235))   # generic app glyph
    x += 2 * r + 30 * k
    limit = W / 2 - max(clear, 185 * k) - 24 * k
    for i, item in enumerate(["Finder", "File", "Edit", "View", "Go", "Window", "Help"]):
        f = font("Inter-Bold.otf" if i == 0 else "Inter-Medium.otf", fs)
        if x + d.textlength(item, font=f) > limit:
            break
        d.text((x, y), item, font=f, fill=(255, 255, 255, 235), anchor="lm")
        x += d.textlength(item, font=f) + 38 * k
    f = font("Inter-Medium.otf", fs)
    clock = "Tue Nov 24  2:37 PM"
    if W - pad - d.textlength(clock, font=f) - 80 * k < W / 2 + max(clear, 185 * k) + 24 * k:
        clock = "2:37 PM"
    tx = W - pad - d.textlength(clock, font=f)
    d.text((tx, y), clock, font=f, fill=(255, 255, 255, 235), anchor="lm")
    bx = tx - 80 * k
    if bx < W / 2 + max(clear, 185 * k) + 24 * k:
        bx = None
    if bx is not None:
        d.rounded_rectangle([bx, y - 12 * k, bx + 46 * k, y + 12 * k], radius=6 * k, outline=(255, 255, 255, 220), width=max(1, round(3 * k)))
        d.rounded_rectangle([bx + 5 * k, y - 7 * k, bx + 33 * k, y + 7 * k], radius=3 * k, fill=(255, 255, 255, 220))
        d.rounded_rectangle([bx + 49 * k, y - 5 * k, bx + 53 * k, y + 5 * k], radius=2 * k, fill=(255, 255, 255, 200))
    if notch:
        nw = 370 * k
        d.rounded_rectangle([W / 2 - nw / 2, -40, W / 2 + nw / 2, mh], radius=22 * k, fill=(0, 0, 0, 255))
    return img


def frame(capture, out_w, out_h, scale, wall=None, clear=0):
    """Wallpaper + menu bar + capture, framed around the notch at `scale`."""
    cw, ch = out_w / scale, out_h / scale
    x0 = SW / 2 - cw / 2
    w = (wall or WALL)
    bg = w.crop((round(x0), 0, round(x0 + cw), round(ch))).resize((out_w, out_h), Image.LANCZOS)
    if capture and not clear:
        bb = Image.open(RAW / f"{capture}.png").getbbox()
        clear = ((bb[2] - bb[0]) / 2 - 40) * scale   # keep menu items out from under the island
    menubar(bg, scale, clear=clear)
    if capture:
        cap = Image.open(RAW / f"{capture}.png").convert("RGBA")
        cap = cap.resize((round(cap.width * scale), round(cap.height * scale)), Image.LANCZOS)
        bg.alpha_composite(cap, (round((out_w - cap.width) / 2), 0))
    return bg


# ---------------------------------------------------------------- framing
def darken_bottom(img, start=0.5, strength=0.75):
    w, h = img.size
    grad = np.zeros((h, 1), np.float32)
    s = int(h * start)
    grad[s:, 0] = np.linspace(0, strength, h - s) ** 1.3
    mask = Image.fromarray((grad * 255).astype(np.uint8), "L").resize((w, h))
    black = Image.new("RGBA", (w, h), (4, 5, 12, 255))
    img.paste(black, (0, 0), mask)
    return img


def centered_text(d, cx, y, text, f, fill, tracking=0):
    d.text((cx, y), text, font=f, fill=fill, anchor="mt")


def caption(img, title, sub, y, title_size=64, sub_size=30, max_w=None):
    d = ImageDraw.Draw(img)
    cx = img.width / 2
    ft = font("InterDisplay-Bold.otf", title_size)
    fs = font("Inter-Regular.otf", sub_size)
    centered_text(d, cx, y, title, ft, (255, 255, 255, 255))
    yy = y + title_size * 1.28
    for line in sub.split("\n"):
        centered_text(d, cx, yy, line, fs, (205, 208, 225, 255))
        yy += sub_size * 1.45
    return img


def badge(img, xy, h=56):
    """App icon + wordmark, bottom-left or wherever."""
    icon = Image.open(ICON).convert("RGBA").resize((h, h), Image.LANCZOS)
    img.alpha_composite(icon, xy)
    d = ImageDraw.Draw(img)
    f1 = font("InterDisplay-Bold.otf", int(h * 0.5))
    f2 = font("InterDisplay-Regular.otf", int(h * 0.5))
    x = xy[0] + h + 16
    cy = xy[1] + h / 2
    d.text((x, cy), "Tuck", font=f1, fill=(255, 255, 255, 255), anchor="lm")
    x += d.textlength("Tuck ", font=f1)
    d.text((x, cy), "Notch", font=f2, fill=(255, 255, 255, 235), anchor="lm")
    return img


def pill(img, xy, text, size=24, anchor="lt"):
    d = ImageDraw.Draw(img)
    f = font("Inter-SemiBold.otf", size)
    tw = d.textlength(text, font=f)
    pw, ph = tw + size * 1.4, size * 1.9
    x, y = xy
    if anchor == "rt":
        x -= pw
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle([x, y, x + pw, y + ph], radius=ph / 2, fill=(255, 255, 255, 30),
                         outline=(255, 255, 255, 60), width=2)
    ld.text((x + pw / 2, y + ph / 2), text, font=f, fill=(255, 255, 255, 240), anchor="mm")
    img.alpha_composite(layer)
    return img


def save(img, name):
    p = OUT / name
    img.convert("RGB").save(p, optimize=True)
    print("wrote", p, img.size)


# ---------------------------------------------------------------- feature cards (X 16:9)
FEATURES = [  # (capture, slug, title, subtitle, scale)
    ("02-peek", "peek", "Peek without opening.",
     "Hover for what's playing and one-tap shelf, clipboard, mic mute, keep-awake and present mode.", 1.25),
    ("03-home", "home", "Your notch, put to work.",
     "Pick four cards: music, weather, your next meeting, to-dos and more.", 0.86),
    ("04-media", "media", "Control what's playing.",
     "Apple Music, Spotify, and YouTube or SoundCloud in your browser.", 0.86),
    ("05-calendar", "calendar", "Never miss the call.",
     "The next three days, a month grid, and one-click Join for Zoom, Meet and Teams.", 0.86),
    ("06-notes", "notes", "Jot it down, keep moving.",
     "A checklist and a scratchpad, saved on your Mac.", 0.86),
    ("07-shelf", "shelf", "A shelf for your files.",
     "Drop files on the notch, drag them out later. AirDrop or convert images from the shelf.", 0.86),
    ("08-clipboard", "clipboard", "Clipboard history.",
     "Search, pin and paste back anything you copied. Text in images is read on-device.", 0.86),
    ("09-timer", "timer", "Focus timers.",
     "Focus and break timers that live in the notch.", 0.86),
    ("10-activity", "activity", "One place for what's running.",
     "Downloads, timers and media, plus your scripts, CI jobs and AI agents.", 0.86),
    ("11-attention", "attention", "Your agents can ask first.",
     "Scripts and AI agents can post alerts with buttons. They never steal focus.", 1.25),
    ("12-glass", "glass", "See-through when you want it.",
     "Turn the opacity down and your wallpaper shows through. Frosted glass optional.", 0.86),
]


def feature(cap, slug, title, sub, scale, out_w=1600, out_h=900):
    img = frame(cap, out_w, out_h, scale)
    darken_bottom(img, 0.52, 0.80)
    caption(img, title, sub, y=out_h - 205, title_size=58, sub_size=28)
    badge(img, (36, out_h - 36 - 44), h=44)
    pill(img, (out_w - 36, out_h - 36 - 44), "Free · Open source · macOS 13+", size=20, anchor="rt")
    return img


def live_card(out_w=1600, out_h=900):
    """Closed notch with a live activity, shown big."""
    img = frame("01-live", out_w, out_h, 1.6)
    darken_bottom(img, 0.55, 0.7)
    caption(img, "Lives around the notch.",
            "Closed, it shows what's playing and what's running.\nHover to peek. Click to open.",
            y=330, title_size=76, sub_size=34)
    badge(img, (36, out_h - 36 - 44), h=44)
    pill(img, (out_w - 36, out_h - 36 - 44), "Free · Open source · macOS 13+", size=20, anchor="rt")
    return img


def settings_card(out_w=1600, out_h=900):
    img = WALL.copy().resize((out_w, round(SH * out_w / SW)), Image.LANCZOS).crop((0, 0, out_w, out_h))
    a = Image.open(RAW / "13-settings-appearance.png").convert("RGBA")
    h = 640
    a = a.resize((round(a.width * h / a.height), h), Image.LANCZOS)
    sh = Image.new("RGBA", (a.width + 160, a.height + 160), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([80, 95, 80 + a.width, 95 + a.height], radius=26, fill=(0, 0, 0, 170))
    sh = sh.filter(ImageFilter.GaussianBlur(34))
    x, y = out_w - a.width - 110, (out_h - h) // 2 - 10
    img.alpha_composite(sh, (x - 80, y - 80))
    img.alpha_composite(a, (x, y))
    d = ImageDraw.Draw(img)
    lx = 110
    d.text((lx, 250), "Make it yours.", font=font("InterDisplay-Bold.otf", 64), fill=(255, 255, 255, 255))
    lines = ["Pick your Home cards and tabs,", "set the opacity, hide it from screen", "sharing, and turn on auto-updates."]
    yy = 345
    for ln in lines:
        d.text((lx, yy), ln, font=font("Inter-Regular.otf", 30), fill=(210, 212, 228, 255))
        yy += 44
    pill(img, (lx, yy + 30), "Free · Open source · macOS 13+", size=22)
    badge(img, (lx, out_h - 36 - 44 - 40), h=48)
    return img


# ---------------------------------------------------------------- hero + social
def hero(out_w=2400, out_h=1350):
    scale = 1.08
    img = frame("03-home", out_w, out_h, scale)
    darken_bottom(img, 0.5, 0.85)
    d = ImageDraw.Draw(img)
    cx = out_w / 2
    y = out_h - 380
    icon = Image.open(ICON).convert("RGBA").resize((92, 92), Image.LANCZOS)
    ft = font("InterDisplay-Bold.otf", 92)
    word1, word2 = "Tuck ", "Notch"
    f2 = font("InterDisplay-Regular.otf", 92)
    tw = d.textlength(word1, font=ft) + d.textlength(word2, font=f2)
    total = 92 + 28 + tw
    x = cx - total / 2
    img.alpha_composite(icon, (round(x), round(y)))
    x += 92 + 28
    d.text((x, y + 46), word1, font=ft, fill=(255, 255, 255, 255), anchor="lm")
    x += d.textlength(word1, font=ft)
    d.text((x, y + 46), word2, font=f2, fill=(255, 255, 255, 240), anchor="lm")
    centered_text(d, cx, y + 140, "Your MacBook notch, put to work.", font("InterDisplay-SemiBold.otf", 52),
                  (255, 255, 255, 255))
    centered_text(d, cx, y + 215, "Music · Calendar · To-dos · File shelf · Clipboard · Timers · Live activity",
                  font("Inter-Regular.otf", 32), (200, 204, 222, 255))
    ptxt = "Free & open source  ·  Notarized  ·  macOS 13+"
    f = font("Inter-SemiBold.otf", 26)
    pw = d.textlength(ptxt, font=f) + 44
    pill(img, (round(cx - pw / 2), y + 278), ptxt, size=26)
    return img


def social(out_w=1280, out_h=640):
    img = frame("03-home", 2400, 1350, 1.08).resize((out_w, round(1350 * out_w / 2400)), Image.LANCZOS)
    img = img.crop((0, 0, out_w, out_h))
    darken_bottom(img, 0.45, 0.9)
    d = ImageDraw.Draw(img)
    cx = out_w / 2
    y = out_h - 170
    icon = Image.open(ICON).convert("RGBA").resize((60, 60), Image.LANCZOS)
    ft = font("InterDisplay-Bold.otf", 58)
    f2 = font("InterDisplay-Regular.otf", 58)
    tw = d.textlength("Tuck ", font=ft) + d.textlength("Notch", font=f2)
    x = cx - (60 + 18 + tw) / 2
    img.alpha_composite(icon, (round(x), round(y)))
    x += 78
    d.text((x, y + 30), "Tuck ", font=ft, fill=(255, 255, 255, 255), anchor="lm")
    x += d.textlength("Tuck ", font=ft)
    d.text((x, y + 30), "Notch", font=f2, fill=(255, 255, 255, 240), anchor="lm")
    centered_text(d, cx, y + 82, "Your MacBook notch, put to work. Free & open source.",
                  font("Inter-Regular.otf", 26), (210, 212, 228, 255))
    return img


if __name__ == "__main__":
    save(hero(), "hero.png")
    save(social(), "social-preview.png")
    save(live_card(), "x-01-live.png")
    for i, (cap, slug, t, s, k) in enumerate(FEATURES, start=2):
        save(feature(cap, slug, t, s, k), f"x-{i:02d}-{slug}.png")
    save(settings_card(), f"x-{len(FEATURES) + 2:02d}-settings.png")
