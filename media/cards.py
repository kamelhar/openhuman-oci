#!/usr/bin/env python3
"""Render the title, outro and screenshot cards for both showcase films.

Cards are 1600x1000 (the terminal capture size), dark Catppuccin Mocha base to
match the VHS theme, with the OpenHuman wordmark (TinyHumans' white variant)
and a light badge strip carrying the official OCI service icons and product
logos in their own colours. Sources and terms: media/logos/SOURCES.md.

    python3 media/cards.py            # all cards (PNG + 7 s / 10 s MP4)
    python3 media/cards.py --png      # PNGs only
"""
from __future__ import annotations

import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGOS = os.path.join(HERE, "logos")
CACHE = os.path.join(HERE, "diagrams", ".cache")
W, H = 1600, 1000
BG = (30, 30, 46)          # #1e1e2e Catppuccin Mocha base
TEXT = (205, 214, 244)     # #cdd6f4
SUB = (166, 173, 200)      # #a6adc8
BLUE = (137, 180, 250)     # #89b4fa
DIM = (108, 112, 134)      # #6c7086
STRIP = (245, 244, 242)    # Redwood Neutral 1


def font(size, bold=False):
    for path in ("/System/Library/Fonts/HelveticaNeue.ttc", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(path):
            for idx in ([1, 2, 3] if bold else [0]):
                try:
                    f = ImageFont.truetype(path, size, index=idx)
                    name = " ".join(f.getname())
                    if (bold and "Bold" in name and "Italic" not in name) or (not bold and "Bold" not in name and "Italic" not in name and "Light" not in name):
                        return f
                except OSError:
                    pass
    return ImageFont.load_default()


def logo(path, h, w=None):
    """Load a logo (SVG or PNG) scaled to height h (or to fit w x h)."""
    full = os.path.join(LOGOS, path)
    if full.lower().endswith(".svg"):
        os.makedirs(CACHE, exist_ok=True)
        out = os.path.join(CACHE, f"card-{os.path.basename(path)}-{h}.png")
        if not os.path.exists(out):
            args = ["rsvg-convert", "-h", str(h), "-a", full, "-o", out]
            if w:
                args[1:3] = ["-w", str(w), "-h", str(h)]
            subprocess.run(args, check=True)
        im = Image.open(out).convert("RGBA")
    else:
        im = Image.open(full).convert("RGBA")
        im.thumbnail((w or 10000, h), Image.LANCZOS)
    return im


def ctext(d, cx, y, s, f, fill):
    w = f.getlength(s)
    d.text((cx - w / 2, y), s, font=f, fill=fill)
    return f.getbbox("Ag")[3]


def wordmark(im, cx, y, h=64):
    wm = logo("openhumanlogo-wordmark-white.svg", h)
    im.alpha_composite(wm, (int(cx - wm.width / 2), y))
    return wm.height


def badge_strip(im, y, items, h=96, pad=36, gap=44, label_font=None):
    """White rounded strip with logos in original colours, centred."""
    d = ImageDraw.Draw(im)
    loaded = []
    for path, label in items:
        lg = logo(path, h - 2 * 14)
        loaded.append((lg, label))
    f = label_font or font(17)
    widths = [max(lg.width, int(f.getlength(label)) if label else 0) for lg, label in loaded]
    total = sum(widths) + gap * (len(loaded) - 1) + 2 * pad
    x0 = (W - total) // 2
    strip_h = h + (34 if any(l for _, l in loaded) else 0)
    d.rounded_rectangle((x0, y, x0 + total, y + strip_h), radius=18, fill=STRIP)
    x = x0 + pad
    for (lg, label), wdt in zip(loaded, widths):
        im.alpha_composite(lg, (int(x + (wdt - lg.width) / 2), y + 14))
        if label:
            lw = f.getlength(label)
            d.text((x + (wdt - lw) / 2, y + h + 2), label, font=f, fill=(49, 45, 42))
        x += wdt + gap
    return strip_h


STACK = [
    ("oci/oci-generative-ai.png", "OCI Generative AI"),
    ("oci/oracle-autonomous-database.png", "Autonomous AI Database"),
    ("mcp-mark.svg", "Database Tools MCP"),
    ("oci/vault.png", "OCI Vault"),
    ("oci/flexible-load-balancer.png", "Load balancer"),
    ("searxng-wordmark.svg", "SearXNG"),
    ("playwright.svg", "Playwright MCP"),
    ("ollama.png", "Ollama"),
]


def card(name, title, sub, tags, strip_items, strip_label=None):
    im = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(im)
    y = 150
    y += wordmark(im, W / 2, y, 60) + 54
    tf = font(64, True)
    while tf.getlength(title) > W - 120 and tf.size > 36:
        tf = font(tf.size - 2, True)
    y += ctext(d, W / 2, y, title, tf, TEXT) + 40
    y += ctext(d, W / 2, y, sub, font(30), SUB) + 26
    y += ctext(d, W / 2, y, tags, font(26), BLUE) + 70
    if strip_label:
        y += ctext(d, W / 2, y, strip_label, font(18), DIM) + 16
    y += badge_strip(im, y, strip_items) + 48
    oracle = logo("oracle.svg", 34)
    im.alpha_composite(oracle, (int(W / 2 - oracle.width / 2), H - 120))
    ctext(d, W / 2, H - 70, "github.com/kamelhar/openhuman-oci", font(24), DIM)
    out = os.path.join(HERE, name)
    im.convert("RGB").save(out, optimize=True)
    print(out)


def browser_card():
    im = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(im)
    f = font(30)
    s = "What the headless browser saw: oracle.com/mcp, screenshot taken by the agent on the OCI VM"
    pw = logo("playwright.svg", 40)
    tw = f.getlength(s)
    x0 = (W - (pw.width + 18 + tw)) / 2
    im.alpha_composite(pw, (int(x0), 28))
    d.text((x0 + pw.width + 18, 32), s, font=f, fill=SUB)
    frame = Image.open(os.path.join(HERE, "frames", "oracle-mcp-clean.png")).convert("RGB")
    box_w, box_h = W - 200, H - 160
    frame.thumbnail((box_w, box_h), Image.LANCZOS)
    fx, fy = (W - frame.width) // 2, 100 + (box_h - frame.height) // 2
    d.rounded_rectangle((fx - 3, fy - 3, fx + frame.width + 3, fy + frame.height + 3), radius=8, fill=(205, 214, 244))
    im.paste(frame, (fx, fy))
    out = os.path.join(HERE, "browser-card.png")
    im.convert("RGB").save(out, optimize=True)
    print(out)


def encode(png, seconds):
    mp4 = png[:-4] + ".mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-i", png, "-t", str(seconds),
                    "-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-an", mp4], check=True)
    print(mp4, seconds, "s")


if __name__ == "__main__":
    card("title.png", "OpenHuman on OCI",
         "A personal AI agent with web navigation, deep research and memory",
         "OCI Generative AI  ·  Always Free  ·  no vendor account  ·  Oracle AI Database via managed MCP",
         STACK, "runs on")
    card("outro.png", "Everything you saw is one terraform apply",
         "Ampere A1 · Ubuntu 24.04 · Docker Compose · OCI Vault · Autonomous AI Database 26ai",
         "github.com/kamelhar/openhuman-oci  ·  Apache-2.0  ·  upstream issues and PRs on tinyhumansai/openhuman",
         [("terraform.svg", "Terraform"), ("ubuntu.png", "Ubuntu 24.04"), ("docker.svg", "Docker Compose")] + STACK[:5], "built with")
    card("title-research.png", "Deep research on a clinical dataset",
         "4,300 Alzheimer's trials in Oracle Autonomous AI Database  ·  parallel researcher agents on the live web",
         "OpenHuman on OCI  ·  OCI Generative AI  ·  no vendor account  ·  public registry data, no patient data",
         STACK, "runs on")
    card("outro-research.png", "The database says who was big. The web says who is live.",
         "Governed data  ·  parallel agents  ·  regulator sources  ·  memory  ·  all inside one OCI tenancy",
         "OpenHuman on OCI  ·  OCI Generative AI  ·  Autonomous AI Database  ·  Database Tools MCP Server",
         STACK, "runs on")
    browser_card()
    if "--png" not in sys.argv:
        for n, secs in (("title.png", 7), ("outro.png", 7), ("browser-card.png", 10), ("title-research.png", 7), ("outro-research.png", 7)):
            encode(os.path.join(HERE, n), secs)
