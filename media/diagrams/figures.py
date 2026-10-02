#!/usr/bin/env python3
"""Render the hand-laid figures (architecture, research session) as PNGs.

Style follows the OCI Architecture Diagram Toolkit: Redwood palette, official
OCI service icons (media/logos/oci), product logos as published by their
owners (media/logos). Coordinates are in a 1600-wide logical space and
rendered at SCALE for print.

    python3 media/diagrams/figures.py            # all figures
    python3 media/diagrams/figures.py architecture
"""
from __future__ import annotations

import os
import subprocess
import sys
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LOGOS = os.path.join(HERE, "..", "logos")
CACHE = os.path.join(HERE, ".cache")
SCALE = 2

# Redwood palette (OCI toolkit, slide 5)
BARK = "#312D2A"
NEUTRAL1 = "#F5F4F2"
NEUTRAL2 = "#DFDCD8"
NEUTRAL3 = "#9E9892"
OCEAN = "#2C5967"
IVY = "#759C6C"
SIENNA = "#AE562C"
ROSE = "#A36472"
AIR = "#FCFBFA"
ORED = "#C74634"
WHITE = "#FFFFFF"
MIST = "#EEF3F4"
GREY_TEXT = "#6B655F"

FONT_CANDIDATES = {
    "regular": ["/System/Library/Fonts/HelveticaNeue.ttc", "/System/Library/Fonts/Helvetica.ttc"],
    "bold": ["/System/Library/Fonts/HelveticaNeue.ttc", "/System/Library/Fonts/Helvetica.ttc"],
}


@lru_cache(maxsize=None)
def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    px = int(size * SCALE)
    for path in FONT_CANDIDATES["bold" if bold else "regular"]:
        if not os.path.exists(path):
            continue
        # Helvetica Neue ttc: 0 regular, 1 bold; Helvetica.ttc: 0 regular, 1 bold
        for idx in ([1, 2, 3] if bold else [0]):
            try:
                f = ImageFont.truetype(path, px, index=idx)
                name = " ".join(f.getname())
                if (bold and "Bold" in name and "Italic" not in name) or (not bold and "Bold" not in name and "Italic" not in name and "Light" not in name):
                    return f
            except OSError:
                continue
    return ImageFont.load_default()


@lru_cache(maxsize=None)
def icon(path: str, size: int) -> Image.Image:
    """Load an icon (PNG or SVG) as RGBA at `size` logical px, fitted, centered."""
    px = int(size * SCALE)
    full = os.path.join(LOGOS, path)
    if full.lower().endswith(".svg"):
        os.makedirs(CACHE, exist_ok=True)
        out = os.path.join(CACHE, f"{os.path.basename(path)}-{px}.png")
        if not os.path.exists(out):
            subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), "-a", full, "-o", out], check=True)
        im = Image.open(out).convert("RGBA")
    else:
        im = Image.open(full).convert("RGBA")
        im.thumbnail((px, px), Image.LANCZOS)
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((px - im.width) // 2, (px - im.height) // 2))
    return canvas


class Canvas:
    def __init__(self, w: int, h: int, bg=WHITE):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SCALE, h * SCALE), bg)
        self.d = ImageDraw.Draw(self.im)

    # ---- primitives -------------------------------------------------------
    def s(self, v):
        return int(round(v * SCALE))

    def rect(self, x, y, w, h, fill=WHITE, stroke=OCEAN, width=2, radius=8, dash=None):
        box = (self.s(x), self.s(y), self.s(x + w), self.s(y + h))
        if dash:
            self.d.rounded_rectangle(box, radius=self.s(radius), fill=fill)
            self._dashed_rect(box, stroke, self.s(width), self.s(dash), self.s(radius))
        else:
            self.d.rounded_rectangle(box, radius=self.s(radius), fill=fill, outline=stroke, width=self.s(width))

    def _dashed_rect(self, box, color, width, dash, radius):
        x0, y0, x1, y1 = box
        r = radius
        segs = [((x0 + r, y0), (x1 - r, y0)), ((x1, y0 + r), (x1, y1 - r)), ((x1 - r, y1), (x0 + r, y1)), ((x0, y1 - r), (x0, y0 + r))]
        for a, b in segs:
            self._dashed_line(a, b, color, width, dash)
        # corner arcs (solid, small)
        for (cx, cy, s0) in ((x0, y0, 180), (x1 - 2 * r, y0, 270), (x1 - 2 * r, y1 - 2 * r, 0), (x0, y1 - 2 * r, 90)):
            self.d.arc((cx, cy, cx + 2 * r, cy + 2 * r), s0, s0 + 90, fill=color, width=width)

    def _dashed_line(self, a, b, color, width, dash):
        (x0, y0), (x1, y1) = a, b
        length = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
        if length == 0:
            return
        ux, uy = (x1 - x0) / length, (y1 - y0) / length
        pos = 0.0
        on = True
        while pos < length:
            seg = min(dash, length - pos)
            if on:
                self.d.line((x0 + ux * pos, y0 + uy * pos, x0 + ux * (pos + seg), y0 + uy * (pos + seg)), fill=color, width=width)
            pos += seg
            on = not on

    def text(self, x, y, s, size=13, bold=False, color=BARK, anchor="la", spacing=4):
        f = font(size, bold)
        self.d.multiline_text((self.s(x), self.s(y)), s, font=f, fill=color, anchor=anchor if "\n" not in s else None, spacing=self.s(spacing), align="center" if anchor[0] == "m" else "left")

    def ctext(self, cx, y, s, size=13, bold=False, color=BARK, spacing=3):
        """Centered multi-line text whose top is at y."""
        f = font(size, bold)
        lines = s.split("\n")
        lh = f.getbbox("Ag")[3] - f.getbbox("Ag")[1] + self.s(spacing)
        for i, line in enumerate(lines):
            w = f.getlength(line)
            self.d.text((self.s(cx) - w / 2, self.s(y) + i * lh), line, font=f, fill=color)
        return len(lines) * lh / SCALE

    def icon(self, path, cx, top, size):
        im = icon(path, size)
        self.im.alpha_composite(im, (self.s(cx) - im.width // 2, self.s(top)))

    def icon_node(self, path, cx, top, size, label, label_size=13, bold=True, color=BARK):
        self.icon(path, cx, top, size)
        self.ctext(cx, top + size + 6, label, size=label_size, bold=bold, color=color)

    def card(self, x, y, w, h, title, icon_path=None, icon_size=44, body=None, fill=WHITE, stroke=OCEAN, title_size=13, body_size=11.5):
        """Box with a bold title, optional icon, and optional body lines."""
        self.rect(x, y, w, h, fill=fill, stroke=stroke, width=2, radius=8)
        cx = x + w / 2
        th = self.ctext(cx, y + 10, title, size=title_size, bold=True)
        cy = y + 10 + th + 4
        if icon_path:
            self.icon(icon_path, cx, cy, icon_size)
            cy += icon_size + 6
        if body:
            self.ctext(cx, cy, body, size=body_size, bold=False, color=GREY_TEXT)

    def group(self, x, y, w, h, label, fill=NEUTRAL1, stroke=NEUTRAL3, dash=8, label_size=14, label_color=BARK, radius=10, width=2):
        self.rect(x, y, w, h, fill=fill, stroke=stroke, width=width, radius=radius, dash=dash)
        self.ctext(x + w / 2, y + 8, label, size=label_size, bold=True, color=label_color)

    def arrow(self, pts, color=BARK, width=2.5, dash=None, head=True, label=None, label_at=None, label_size=11, label_color=None, label_dx=0, label_dy=-14):
        P = [(self.s(px), self.s(py)) for px, py in pts]
        wpx = self.s(width)
        for a, b in zip(P, P[1:]):
            if dash:
                self._dashed_line(a, b, color, wpx, self.s(dash))
            else:
                self.d.line((a, b), fill=color, width=wpx)
        # round joints
        for p in P[1:-1]:
            self.d.ellipse((p[0] - wpx / 2, p[1] - wpx / 2, p[0] + wpx / 2, p[1] + wpx / 2), fill=color)
        if head:
            (x0, y0), (x1, y1) = P[-2], P[-1]
            L = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
            ux, uy = (x1 - x0) / L, (y1 - y0) / L
            hl, hw = self.s(11), self.s(6)
            bx, by = x1 - ux * hl, y1 - uy * hl
            self.d.polygon([(x1, y1), (bx - uy * hw, by + ux * hw), (bx + uy * hw, by - ux * hw)], fill=color)
        if label:
            if label_at is None:
                # midpoint of the longest segment
                seg = max(zip(pts, pts[1:]), key=lambda ab: abs(ab[1][0] - ab[0][0]) + abs(ab[1][1] - ab[0][1]))
                lx, ly = (seg[0][0] + seg[1][0]) / 2, (seg[0][1] + seg[1][1]) / 2
            else:
                lx, ly = label_at
            self.ctext(lx + label_dx, ly + label_dy, label, size=label_size, bold=False, color=label_color or (GREY_TEXT if dash else BARK))

    def save(self, name):
        out = os.path.join(HERE, name)
        self.im.convert("RGB").save(out, optimize=True)
        print(f"{name}: {self.im.width}x{self.im.height}")


# ---------------------------------------------------------------------------
def architecture():
    c = Canvas(1600, 900)
    OCI = "oci/"

    # --- operator, left
    c.card(30, 120, 180, 150, "Operator laptop", "openhumanlogo-black.svg", 46,
           "OpenHuman desktop app\nor any client\nBearer <core token>")

    # --- region / compartment
    c.group(250, 30, 1090, 845, "OCI region · one compartment · everything Always Free except Generative AI tokens")

    # VCN
    c.group(280, 70, 870, 595, "VCN 10.80.0.0/16", fill=AIR, stroke=SIENNA, dash=None)

    # public subnet with LB
    c.group(300, 115, 220, 300, "Public subnet 10.80.0.0/24", fill=WHITE, stroke=OCEAN, dash=5, label_size=12.5, label_color=OCEAN)
    c.icon_node(OCI + "flexible-load-balancer.png", 410, 165, 64,
                "Flexible load balancer\n10 Mbps · reserved IP · own CA\nforwards /rpc /health /events\nanything else gets 502", label_size=11.5)

    # private subnet
    c.group(545, 115, 585, 405, "Private subnet 10.80.1.0/24 · no public IPs", fill=WHITE, stroke=OCEAN, dash=5, label_size=12.5, label_color=OCEAN)

    # VM container
    c.group(560, 150, 555, 265, "Ampere A1 Flex VM · 3 OCPU / 18 GB · Ubuntu 24.04 · Docker Compose", fill=MIST, stroke=OCEAN, dash=None, label_size=12.5)
    c.icon(OCI + "flex-vm.png", 590, 158, 34)
    c.card(575, 190, 180, 150, "openhuman-core", "openhumanlogo-black.svg", 44,
           "upstream aarch64 release\nJSON-RPC :7788\nkeyring=file · local-openai")
    # tools group
    c.rect(775, 188, 325, 154, fill=WHITE, stroke=NEUTRAL3, width=1.5, radius=8, dash=4)
    c.ctext(937, 193, "compose network only · never published", size=10, color=GREY_TEXT)
    c.card(783, 214, 100, 118, "SearXNG", "searxng-wordmark.svg", 34, "web search", title_size=11.5, body_size=10.5)
    c.card(890, 214, 100, 118, "Playwright MCP", "playwright.svg", 34, "headless Chromium\n25 browser tools", title_size=11.5, body_size=10)
    c.card(997, 214, 100, 118, "Ollama", "ollama.png", 34, "bge-m3 embeddings", title_size=11.5, body_size=10.5)
    # block volume
    c.icon_node(OCI + "block-storage.png", 940, 352, 32, "Block volume 50 GB · memory, sessions, models", label_size=10.5)

    # private endpoint, below the tools
    c.card(900, 440, 200, 60, "Database Tools private endpoint", None, 0, "VNIC in this subnet", title_size=11.5, body_size=10.5)

    # gateways row (inside VCN, below the subnets)
    c.icon_node(OCI + "internet-gateway.png", 400, 530, 44, "Internet gateway", label_size=11)
    c.icon_node(OCI + "nat-gateway.png", 720, 530, 44, "NAT gateway", label_size=11)
    c.icon_node(OCI + "service-gateway.png", 1000, 530, 44, "Service gateway", label_size=11)

    # right strip inside the region: database and secrets reached through the service gateway
    c.icon_node(OCI + "vault.png", 1250, 150, 50,
                "OCI Vault\ncore token · GenAI key\nADB password · MCP user token", label_size=11)
    c.icon_node(OCI + "oracle-autonomous-database.png", 1250, 390, 56,
                "Autonomous AI Database 26ai\nAlways Free · TLS, no wallet\nACL: this VCN + operator IP\nCLINICAL_TRIALS · 4,300 rows", label_size=11)

    # services row (inside region, below the VCN)
    c.icon_node(OCI + "iam.png", 340, 690, 50,
                "IAM\n1 policy · dynamic group\ndomain group + MCP_Operator\nauthorises MCP callers", label_size=11)
    c.icon_node(OCI + "bastion.png", 470, 690, 50, "Bastion\nadmin only\n3 h sessions", label_size=11)
    c.card(590, 680, 240, 112, "Database Tools MCP Server", "mcp-mark.svg", 36,
           "managed · resource principal\ncallers need MCP_Operator", title_size=12.5)
    c.icon_node(OCI + "logging.png", 940, 690, 50, "Logging\nMCP invoke log", label_size=11)

    # --- outside, right
    c.icon_node(OCI + "oci-generative-ai.png", 1470, 180, 64,
                "OCI Generative AI\nus-chicago-1\nOpenAI-compatible endpoint\nopenai.gpt-4.1 · API key", label_size=11.5)
    c.icon_node(OCI + "internet.png", 1470, 400, 56, "Public web\nsearch · fetch · browse", label_size=11.5)
    c.icon_node("github-mark.png", 1470, 560, 48, "GitHub releases\ncore tarball at boot", label_size=11)

    # --- flows (solid) ------------------------------------------------------
    c.arrow([(210, 197), (376, 197)], label="HTTPS 443\noperator CIDRs only", label_at=(293, 197), label_dy=-36)
    c.arrow([(444, 215), (575, 215)])
    c.ctext(509, 199, "7788 · from the LB only", size=10, color=BARK)
    c.arrow([(755, 265), (775, 265)])
    # core -> NAT (straight down) -> right -> external
    c.arrow([(720, 340), (720, 528)], label="egress", label_at=(720, 440), label_dx=24, label_dy=-8, label_size=10.5)
    c.arrow([(744, 552), (790, 552), (790, 655), (1360, 655), (1360, 212), (1436, 212)], label="chat completions · API key", label_at=(1250, 655), label_dy=-18, label_size=10.5)
    c.arrow([(1360, 428), (1436, 428)])
    c.arrow([(1360, 584), (1436, 584)], dash=5, color=NEUTRAL3)
    # core -> MCP server (straight down)
    c.arrow([(610, 340), (610, 680)], label="streamable HTTP MCP\nBearer <user token>", label_at=(610, 606), label_dx=70, label_dy=0, label_size=10.5)
    # MCP -> private endpoint
    c.arrow([(820, 680), (820, 615), (1120, 615), (1120, 470), (1100, 470)], label="dbtools_execute_sql", label_at=(960, 615), label_dy=-16, label_size=10.5)
    # PE -> service gateway -> ADB
    c.arrow([(1000, 500), (1000, 528)])
    c.arrow([(1022, 552), (1160, 552), (1160, 418), (1222, 418)])
    c.ctext(1265, 560, "TLS 1521\nvia Oracle Services Network", size=10.5, color=BARK)
    # --- control (dashed) --------------------------------------------------
    c.arrow([(1115, 300), (1170, 300), (1170, 175), (1222, 175)], dash=5, color=NEUTRAL3)
    c.ctext(1252, 262, "instance principal\nreads secret bundles", size=10, color=GREY_TEXT)
    c.arrow([(470, 688), (470, 630), (566, 630), (566, 415)], dash=5, color=NEUTRAL3, label="SSH 22", label_at=(518, 630), label_dy=-16, label_size=10)
    c.arrow([(830, 715), (914, 715)], dash=5, color=NEUTRAL3, label="invoke log", label_at=(872, 715), label_dy=-16, label_size=10)

    c.save("architecture.png")


def research():
    c = Canvas(1600, 560)
    cols = [(20, 290), (350, 330), (720, 260), (1020, 270), (1330, 250)]
    titles = ["1 · the data", "2 · three researchers in parallel · 13 s", "3 · synthesis, no tools", "4 · deep dive · 16–21 s", "5 · memory"]
    for (x, w), t in zip(cols, titles):
        c.group(x, 20, w, 520, t, fill=NEUTRAL1, stroke=NEUTRAL3, dash=8, label_size=14)

    # scene 1
    c.card(40, 100, 250, 230, "Autonomous AI Database", "oci/oracle-autonomous-database.png", 56,
           "CLINICAL_TRIALS · 4,300 studies\nClinicalTrials.gov v2, registry only\nSQL over TLS from inside the VCN\n319 Phase 3 · 312,397 enrolled\ntop Phase 3 industry sponsors", title_size=13.5, body_size=11.5)
    # scene 2
    for i, who in enumerate(["Eli Lilly", "Roche", "Otsuka"]):
        y = 60 + i * 158
        c.card(370, y, 290, 140, f"researcher · {who}", "openhumanlogo-black.svg", 34,
               "SearXNG search, then web_fetch ≤ 12 kB\n(Playwright when a site blocks)\n3 verified bullets + URLs, stored", title_size=12.5, body_size=10.5)
    # scene 3
    c.card(740, 110, 220, 230, "gpt-4.1 @ 0.2", "oci/oci-generative-ai.png", 56,
           "on OCI Generative AI\nregistry history vs live pipeline\n'a shift to a competitive,\ndynamic landscape'\nPfizer: history, no late-stage today", title_size=13.5, body_size=11)
    # scene 4
    c.card(1040, 110, 230, 230, "donanemab brief", "oci/internet.png", 56,
           "fda.gov pages, nothing else\nmechanism · TRAILBLAZER-ALZ 2\napproval · updated dosing\nARIA-E ~24 % (~6 % symptomatic)\nopen questions · 2 sources", title_size=13.5, body_size=11)
    # scene 5
    c.card(1350, 110, 210, 230, "memory tree", "ollama.png", 56,
           "bge-m3 embeddings on Ollama\nmemory_store, MEMORY_SAVED\nread back next turn by\nmemory_recall_memories\nwith its URLs", title_size=13.5, body_size=11)

    # arrows
    c.arrow([(290, 215), (330, 215), (330, 130), (370, 130)])
    c.ctext(165, 345, "top 3 sponsors derived from the query, not scripted", size=10, color=GREY_TEXT)
    c.arrow([(330, 215), (330, 288), (370, 288)])
    c.arrow([(330, 288), (330, 446), (370, 446)])
    for y in (130, 288, 446):
        c.arrow([(660, y), (700, y), (700, 225), (740, 225)], head=(y == 130))
    c.arrow([(960, 225), (1040, 225)], label="approved drug", label_dy=-20, label_size=10.5)
    c.arrow([(1270, 225), (1350, 225)], label="brief + sources", label_dy=-20, label_size=10.5)
    c.save("research.png")


FIGURES = {"architecture": architecture, "research": research}

if __name__ == "__main__":
    names = sys.argv[1:] or list(FIGURES)
    for n in names:
        FIGURES[n]()
