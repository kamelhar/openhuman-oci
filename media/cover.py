#!/usr/bin/env python3
"""Render the document cover (portrait, for the Word file) and the landscape
title card (for the blog and social posts), in the same visual language as the
NeMo Relay on Oracle Cloud cover: deep green field, soft shapes, Oracle wordmark
and the OpenHuman wordmark, title, subtitle, a gold rule, the byline block.

    python3 media/cover.py [--title ...] [--subtitle ...] [--date ...] [--version ...]

Outputs media/cover-portrait.png (2550x3300, 8.5x11 in at 300 dpi) and
media/cover.png (1920x1080).
"""
from __future__ import annotations

import argparse
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGOS = os.path.join(HERE, "logos")
CACHE = os.path.join(HERE, "diagrams", ".cache")

GREEN = (23, 59, 46)        # field
GREEN_DEEP = (16, 44, 34)
GREEN_SOFT = (111, 158, 122)
GOLD = (230, 192, 106)
WHITE = (255, 255, 255)
MIST = (214, 226, 218)
ORED = (199, 70, 52)


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    """Oracle Sans by weight via fontconfig, Helvetica Neue as fallback."""
    try:
        path = subprocess.run(["fc-match", "-f", "%{file}", f"Oracle Sans:style={weight}"],
                              capture_output=True, text=True, check=True).stdout.strip()
        if path and "OracleSans" in path:
            return ImageFont.truetype(path, size)
    except Exception:
        pass
    fallback = "/System/Library/Fonts/HelveticaNeue.ttc"
    idx = {"Bold": 1, "Semi Bold": 1, "Light": 0, "Regular": 0}.get(weight, 0)
    return ImageFont.truetype(fallback, size, index=idx)


def logo(path: str, h: int) -> Image.Image:
    full = os.path.join(LOGOS, path)
    if full.lower().endswith(".svg"):
        os.makedirs(CACHE, exist_ok=True)
        out = os.path.join(CACHE, f"cover-{os.path.basename(path)}-{h}.png")
        if not os.path.exists(out):
            subprocess.run(["rsvg-convert", "-h", str(h), "-a", full, "-o", out], check=True)
        return Image.open(out).convert("RGBA")
    im = Image.open(full).convert("RGBA")
    im.thumbnail((10000, h), Image.LANCZOS)
    return im


def field(w: int, h: int) -> Image.Image:
    """Deep green background with two soft shapes and a faint diagonal band."""
    im = Image.new("RGBA", (w, h), GREEN)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # large soft green ellipse, upper right
    d.ellipse((int(w * 0.62), int(-h * 0.18), int(w * 1.25), int(h * 0.42)), fill=GREEN_SOFT + (235,))
    # gold blob, top centre-right
    d.ellipse((int(w * 0.46), int(-h * 0.14), int(w * 0.78), int(h * 0.10)), fill=GOLD + (245,))
    # deep band, lower left to right
    d.polygon([(0, int(h * 0.78)), (w, int(h * 0.56)), (w, h), (0, h)], fill=GREEN_DEEP + (255,))
    layer = layer.filter(ImageFilter.GaussianBlur(2))
    im.alpha_composite(layer)
    # subtle concentric rings texture at the right
    tex = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    td = ImageDraw.Draw(tex)
    cx, cy = int(w * 0.86), int(h * 0.70)
    for r in range(80, int(w * 0.55), 46):
        td.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 255, 255, 14), width=3)
    im.alpha_composite(tex)
    return im


def oracle_tile(size: int) -> Image.Image:
    """The red square tile with the Oracle O, as on Oracle title slides."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, size, size), radius=int(size * 0.06), fill=ORED)
    m = int(size * 0.26)
    d.rounded_rectangle((m, int(size * 0.36), size - m, int(size * 0.64)), radius=int(size * 0.14), outline=WHITE, width=max(3, size // 24))
    return im


def compose(w: int, h: int, title: str, subtitle: str, kicker: str, name: str, role: str, org: str, date: str, portrait: bool) -> Image.Image:
    im = field(w, h)
    d = ImageDraw.Draw(im)
    s = w / 1920.0 if not portrait else w / 1920.0  # scale factor against the 1920 reference width
    x0 = int(0.065 * w)
    y = int((0.15 if not portrait else 0.11) * h)

    # logos row: Oracle wordmark, divider, OpenHuman wordmark
    orc = logo("oracle.svg", int(64 * s))
    im.alpha_composite(orc, (x0, y))
    oh = logo("openhumanlogo-wordmark-white.svg", int(78 * s))
    gap = int(70 * s)
    d.line((x0 + orc.width + gap // 2, y - int(6 * s), x0 + orc.width + gap // 2, y + orc.height + int(6 * s)), fill=(255, 255, 255, 110), width=max(2, int(2 * s)))
    im.alpha_composite(oh, (x0 + orc.width + gap, y - int(8 * s)))
    y += int((190 if not portrait else 260) * s)

    # kicker
    d.text((x0, y), kicker, font=font(int(30 * s), "Semi Bold"), fill=GOLD)
    y += int(62 * s)

    # title, wrapped to two lines if needed
    tf = font(int(104 * s), "Bold")
    words = title.split()
    lines, cur = [], ""
    for wd in words:
        trial = (cur + " " + wd).strip()
        if tf.getlength(trial) > w * 0.58 and cur:
            lines.append(cur); cur = wd
        else:
            cur = trial
    lines.append(cur)
    for ln in lines:
        d.text((x0, y), ln, font=tf, fill=WHITE)
        y += int(118 * s)
    y += int(22 * s)
    d.text((x0, y), subtitle, font=font(int(44 * s), "Light"), fill=MIST)
    y += int(96 * s)
    d.rectangle((x0, y, x0 + int(60 * s), y + int(6 * s)), fill=GOLD)
    y += int(70 * s)

    # byline
    d.text((x0, y), name, font=font(int(34 * s), "Bold"), fill=WHITE); y += int(54 * s)
    for line in (role, org, date):
        d.text((x0, y), line, font=font(int(30 * s), "Regular"), fill=MIST); y += int(48 * s)

    if portrait:
        facts = "OCI Generative AI  ·  Autonomous AI Database 26ai  ·  Database Tools MCP Server  ·  Always Free  ·  Terraform"
        ff = font(int(26 * s), "Semi Bold")
        d.text((x0, h - int(0.062 * h)), facts, font=ff, fill=GOLD)

    # tile bottom right
    tile = oracle_tile(int(64 * s))
    im.alpha_composite(tile, (w - tile.width - int(0.034 * w), h - tile.height - int(0.034 * w)))
    return im.convert("RGB")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", default="OpenHuman on Oracle Cloud")
    ap.add_argument("--subtitle", default="A governed personal AI agent with no vendor account")
    ap.add_argument("--kicker", default="ARCHITECTURE REFERENCE")
    ap.add_argument("--name", default="Federico Kamelhar")
    ap.add_argument("--role", default="Senior Principal Architect, Agentic AI")
    ap.add_argument("--org", default="Oracle")
    ap.add_argument("--date", default="October 2026")
    ap.add_argument("--version", default="1.1")
    ap.add_argument("--out", default=HERE)
    a = ap.parse_args()
    kicker = f"{a.kicker} · VERSION {a.version}"
    landscape = compose(1920, 1080, a.title, a.subtitle, kicker, a.name, a.role, a.org, a.date, portrait=False)
    landscape.save(os.path.join(a.out, "cover.png"), optimize=True)
    portrait = compose(2550, 3300, a.title, a.subtitle, kicker, a.name, a.role, a.org, a.date, portrait=True)
    portrait.save(os.path.join(a.out, "cover-portrait.png"), optimize=True)
    print(os.path.join(a.out, "cover.png"), landscape.size)
    print(os.path.join(a.out, "cover-portrait.png"), portrait.size)
