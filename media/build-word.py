#!/usr/bin/env python3
"""Build the Word edition of docs/OPENHUMAN-ON-OCI.md, and a PDF rendered from it.

What it produces, in order: a full-bleed cover page (media/cover-portrait.png),
a title page with the byline and a document-control table, a contents field,
then the document body in Oracle Sans with a running header, page numbers,
styled tables and page-width figures. Pandoc does the Markdown conversion
against a reference file this script derives from pandoc's own; python-docx
applies everything pandoc cannot express.

    python3 media/build-word.py [--out ~/Documents/openhuman-oci] [--no-pdf]
"""
from __future__ import annotations

import argparse
import copy
import os
import re
import shutil
import subprocess
import sys
import tempfile

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "docs", "OPENHUMAN-ON-OCI.md")
COVER = os.path.join(HERE, "cover-portrait.png")

FONT = "Oracle Sans"
MONO = "Consolas"
BARK = RGBColor(0x31, 0x2D, 0x2A)
OCEAN = RGBColor(0x2C, 0x59, 0x67)
ORED = RGBColor(0xC7, 0x46, 0x34)
GREY = RGBColor(0x6B, 0x65, 0x5F)
NEUTRAL1 = "F5F4F2"
NEUTRAL2 = "DFDCD8"


# ---------------------------------------------------------------- markdown ----
def parse_front_matter(text: str):
    """Pull title, byline, version line and revision history out of the source."""
    m = re.search(r"^# (.+)$", text, re.M)
    title = m.group(1).strip()
    byline = re.search(r"^\*By ([^*]+)\*$", text, re.M).group(1).strip()
    version_line = re.search(r"^\*Architecture reference, version ([0-9.]+), ([A-Za-z]+ [0-9]{4})\.", text, re.M)
    version, date = version_line.group(1), version_line.group(2)
    rev = re.search(r"^\*Revision history\. (.+)\*$", text, re.M).group(1)
    rows = []
    for item in re.finditer(r"([0-9.]+), ([0-9]{4}-[0-9]{2}-[0-9]{2}): (.+?)(?=(?: [0-9.]+, [0-9]{4}-[0-9]{2}-[0-9]{2}:)|$)", rev):
        rows.append((item.group(1), item.group(2), item.group(3).strip()))
    return title, byline, version, date, rows


def body_markdown(text: str) -> str:
    """The Markdown pandoc should convert: no H1, no byline, no revision lines,
    figure captions folded into the image, page-width figures."""
    lines = text.split("\n")
    out = []
    skip_prefixes = ("# ", "*By ", "*Architecture reference, version", "*Revision history.", "*Repository, Terraform")
    for ln in lines:
        if ln.startswith(skip_prefixes):
            continue
        out.append(ln)
    t = "\n".join(out)
    # horizontal rules are section separators on GitHub; headings do that job here
    t = re.sub(r"^---[ \t]*$\n?", "", t, flags=re.M)
    # "![alt](path)\n\n*Figure N. caption*" -> figure with that caption
    t = re.sub(r"^!\[[^\]]*\]\(([^)]+)\)[ \t]*\n\n\*(Figure[^*]+)\*[ \t]*$", r"![\2](\1){width=6.5in}", t, flags=re.M)
    t = re.sub(r"^(!\[[^\]]*\]\([^)]+\))[ \t]*$", r"\1{width=6.5in}", t, flags=re.M)
    # the portrait identity figure must leave room for its caption
    t = t.replace("identity.png){width=6.5in}", "identity.png){width=5.6in}")
    return t


# ---------------------------------------------------------------- reference ----
def set_style_font(style, name=FONT, size=None, bold=None, italic=None, color=None):
    f = style.font
    f.name = name
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts"); rpr.append(rfonts)
    for attr in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        rfonts.set(qn(attr), name)
    for attr in ("w:asciiTheme", "w:hAnsiTheme", "w:cstheme", "w:eastAsiaTheme"):
        if rfonts.get(qn(attr)) is not None:
            del rfonts.attrib[qn(attr)]
    if size is not None:
        f.size = Pt(size)
    if bold is not None:
        f.bold = bold
    if italic is not None:
        f.italic = italic
    if color is not None:
        f.color.rgb = color


def add_page_field(paragraph):
    run = paragraph.add_run()
    for kind, text in (("begin", None), (None, " PAGE "), ("end", None)):
        if kind:
            el = OxmlElement("w:fldChar"); el.set(qn("w:fldCharType"), kind)
        else:
            el = OxmlElement("w:instrText"); el.set(qn("xml:space"), "preserve"); el.text = text
        run._r.append(el)
    return run


def make_reference(path: str, header_text: str, footer_text: str):
    subprocess.run(["pandoc", "-o", path, "--print-default-data-file", "reference.docx"], check=True)
    d = Document(path)
    s = d.sections[0]
    s.page_width, s.page_height = Inches(8.5), Inches(11)
    s.left_margin = s.right_margin = Inches(1)
    s.top_margin, s.bottom_margin = Inches(1), Inches(0.9)
    s.header_distance, s.footer_distance = Inches(0.5), Inches(0.45)

    # running header and footer
    hp = s.header.paragraphs[0]
    hp.text = header_text
    hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    for r in hp.runs:
        r.font.size = Pt(8.5); r.font.color.rgb = GREY; r.font.name = FONT
    fp = s.footer.paragraphs[0]
    fp.text = footer_text + "\t"
    fp.alignment = WD_ALIGN_PARAGRAPH.LEFT
    # right tab stop at the text width for the page number
    pf = fp.paragraph_format
    pf.tab_stops.add_tab_stop(Inches(6.5), alignment=2)  # WD_TAB_ALIGNMENT.RIGHT
    for r in fp.runs:
        r.font.size = Pt(8.5); r.font.color.rgb = GREY; r.font.name = FONT
    pr = add_page_field(fp)
    pr.font.size = Pt(8.5); pr.font.color.rgb = GREY; pr.font.name = FONT

    st = d.styles
    from docx.enum.style import WD_STYLE_TYPE
    def ensure(name, kind=WD_STYLE_TYPE.PARAGRAPH, base="Normal"):
        try:
            return st[name]
        except KeyError:
            new = st.add_style(name, kind)
            if kind == WD_STYLE_TYPE.PARAGRAPH:
                new.base_style = st[base]
            return new
    for name in ("Body Text", "First Paragraph", "Compact", "Image Caption", "Caption", "Source Code", "Block Text", "TOC Heading", "Author", "Date", "Subtitle"):
        ensure(name)
    ensure("Verbatim Char", WD_STYLE_TYPE.CHARACTER)
    set_style_font(st["Normal"], size=10.5, color=BARK)
    st["Normal"].paragraph_format.space_after = Pt(6)
    st["Normal"].paragraph_format.line_spacing = 1.12
    for name in ("Body Text", "First Paragraph", "Compact"):
        set_style_font(st[name], size=10.5, color=BARK)
    st["Body Text"].paragraph_format.space_before = Pt(0)
    st["Body Text"].paragraph_format.space_after = Pt(7)
    set_style_font(st["Title"], size=27, bold=True, color=BARK)
    st["Title"].paragraph_format.space_after = Pt(6)
    set_style_font(st["Subtitle"], size=14, bold=False, color=GREY)
    set_style_font(st["Author"], size=11, color=BARK)
    set_style_font(st["Date"], size=11, color=GREY)
    set_style_font(st["Heading 1"], size=19, bold=True, color=BARK)
    st["Heading 1"].paragraph_format.space_before = Pt(26)
    st["Heading 1"].paragraph_format.space_after = Pt(8)
    st["Heading 1"].paragraph_format.keep_with_next = True
    set_style_font(st["Heading 2"], size=13.5, bold=True, color=OCEAN)
    st["Heading 2"].paragraph_format.space_before = Pt(14)
    st["Heading 2"].paragraph_format.space_after = Pt(4)
    set_style_font(st["Heading 3"], size=11.5, bold=True, color=BARK)
    set_style_font(st["Image Caption"], size=9, italic=True, color=GREY)
    st["Image Caption"].paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    st["Image Caption"].paragraph_format.space_before = Pt(4)
    st["Image Caption"].paragraph_format.space_after = Pt(14)
    set_style_font(st["Caption"], size=9, italic=True, color=GREY)
    set_style_font(st["Source Code"], name=MONO, size=8.5, color=BARK)
    sc = st["Source Code"].paragraph_format
    sc.space_after = Pt(0); sc.space_before = Pt(0)
    sc.left_indent = Inches(0.15); sc.right_indent = Inches(0.15)
    ppr = st["Source Code"].element.get_or_add_pPr()
    shd = OxmlElement("w:shd"); shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), NEUTRAL1); ppr.append(shd)
    set_style_font(st["Verbatim Char"], name=MONO, size=9)
    set_style_font(st["Block Text"], size=10.5, italic=True, color=OCEAN)
    st["Block Text"].paragraph_format.left_indent = Inches(0.35)
    set_style_font(st["TOC Heading"], size=14, bold=True, color=BARK)
    for name in ("TOC 1", "TOC 2"):
        try:
            set_style_font(st[name], size=10, color=BARK)
        except KeyError:
            pass
    d.save(path)


# ---------------------------------------------------------------- post ----
def shade(cell, fill: str):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), fill)
    tcPr.append(shd)


def set_cell_borders(table, color="BFBAB5"):
    tblPr = table._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "bottom", "insideH"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single"); el.set(qn("w:sz"), "4"); el.set(qn("w:space"), "0"); el.set(qn("w:color"), color)
        borders.append(el)
    for edge in ("left", "right", "insideV"):
        el = OxmlElement(f"w:{edge}"); el.set(qn("w:val"), "nil"); borders.append(el)
    old = tblPr.find(qn("w:tblBorders"))
    if old is not None:
        tblPr.remove(old)
    tblPr.append(borders)


def style_by_name(doc, *names):
    for st in doc.styles:
        if st.name in names or st.name.lower() in [n.lower() for n in names]:
            return st
    return doc.styles[names[0]]


def style_tables(doc):
    for t in doc.tables:
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        tblPr = t._tbl.tblPr
        w = tblPr.find(qn("w:tblW"))
        if w is None:
            w = OxmlElement("w:tblW"); tblPr.append(w)
        w.set(qn("w:type"), "pct"); w.set(qn("w:w"), "5000")
        set_cell_borders(t)
        ncols = len(t.columns)
        size = Pt(9) if ncols <= 3 else Pt(8.5)
        for ri, row in enumerate(t.rows):
            for cell in row.cells:
                if ri == 0:
                    shade(cell, NEUTRAL1)
                for p in cell.paragraphs:
                    p.paragraph_format.space_after = Pt(2)
                    p.paragraph_format.space_before = Pt(2)
                    for r in p.runs:
                        r.font.size = size
                        r.font.name = FONT
                        if ri == 0:
                            r.font.bold = True
        # column widths proportional to content, fixed layout so Word and LibreOffice agree
        ncols = len(t.columns)
        weights = []
        for ci in range(ncols):
            longest = max((len(c.text) for c in t.columns[ci].cells), default=10)
            weights.append(min(max(longest, 10), 70))
        total = float(sum(weights))
        widths = [6.5 * w_ / total for w_ in weights]
        # no column narrower than an inch; take the difference from the widest
        for _ in range(ncols):
            short = [i for i, wd in enumerate(widths) if wd < 1.0]
            if not short:
                break
            deficit = sum(1.0 - widths[i] for i in short)
            for i in short:
                widths[i] = 1.0
            widest = max(range(ncols), key=lambda i: widths[i])
            widths[widest] -= deficit
        t.autofit = False
        layout = tblPr.find(qn("w:tblLayout"))
        if layout is None:
            layout = OxmlElement("w:tblLayout"); tblPr.append(layout)
        layout.set(qn("w:type"), "fixed")
        grid = t._tbl.find(qn("w:tblGrid"))
        if grid is not None:
            for gc, wd in zip(grid.findall(qn("w:gridCol")), widths):
                gc.set(qn("w:w"), str(int(wd * 1440)))
        for row in t.rows:
            for cell, wd in zip(row.cells, widths):
                cell.width = Inches(wd)
        # repeat header row across pages
        trPr = t.rows[0]._tr.get_or_add_trPr()
        th = OxmlElement("w:tblHeader"); th.set(qn("w:val"), "true"); trPr.append(th)


def shade_code_blocks(doc):
    """Paragraph-level shading on code blocks (some renderers ignore it at style level)."""
    for p in doc.paragraphs:
        if p.style.name == "Source Code":
            ppr = p._p.get_or_add_pPr()
            shd = OxmlElement("w:shd"); shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), NEUTRAL1)
            ppr.append(shd)
            p.paragraph_format.left_indent = Inches(0.15)
            p.paragraph_format.right_indent = Inches(0.15)


def style_table_captions(doc):
    for p in doc.paragraphs:
        txt = p.text.strip()
        if re.match(r"^Table [0-9]+[a-z]?\.", txt) and p.runs and all(r.italic for r in p.runs if r.text.strip()):
            p.style = style_by_name(doc, "Caption")
            p.paragraph_format.keep_with_next = True
            p.paragraph_format.space_before = Pt(8)
            p.paragraph_format.space_after = Pt(4)


def insert_cover(doc):
    """A first section with zero margins holding the cover image, page-size."""
    first = doc.paragraphs[0]
    p = first.insert_paragraph_before()
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.0
    run = p.add_run()
    run.add_picture(COVER, width=Inches(8.5), height=Inches(11))
    # section break after the cover paragraph: its own sectPr with zero margins, no header/footer
    pPr = p._p.get_or_add_pPr()
    sectPr = OxmlElement("w:sectPr")
    pgSz = OxmlElement("w:pgSz"); pgSz.set(qn("w:w"), "12240"); pgSz.set(qn("w:h"), "15840"); sectPr.append(pgSz)
    pgMar = OxmlElement("w:pgMar")
    for k in ("top", "right", "bottom", "left", "header", "footer", "gutter"):
        pgMar.set(qn(f"w:{k}"), "0")
    sectPr.append(pgMar)
    pPr.append(sectPr)
    # body section: numbering restarts at 1 on the title page
    body = doc.sections[-1]
    sp = body._sectPr
    pg = OxmlElement("w:pgNumType"); pg.set(qn("w:start"), "1")
    sp.append(pg)


def add_document_control(doc, byline: str, version: str, date: str, rows):
    """After pandoc's Date paragraph: a byline line, a document-control table, a Contents heading."""
    date_par = next((p for p in doc.paragraphs if p.style.name == "Date"), None)
    anchor = date_par if date_par is not None else doc.paragraphs[1]
    # pandoc already wrote Author and Date; add role and document control below
    p1 = insert_paragraph_after(anchor, "")
    p1.paragraph_format.space_before = Pt(18)
    r = p1.add_run("Document control"); r.bold = True; r.font.size = Pt(10.5); r.font.color.rgb = BARK
    tbl = doc.add_table(rows=1, cols=3)
    hdr = tbl.rows[0].cells
    for c, t in zip(hdr, ("Version", "Date", "Change")):
        c.text = t
    for v, dt, ch in rows:
        cells = tbl.add_row().cells
        cells[0].text, cells[1].text, cells[2].text = v, dt, ch
    p1._p.addnext(tbl._tbl)
    for row in tbl.rows:
        for c in row.cells:
            c.width = Inches(0.9)
    tbl.columns[2].width = Inches(4.7)
    p2 = insert_paragraph_after_element(tbl._tbl, doc, "")
    p2.paragraph_format.space_before = Pt(10)
    r = p2.add_run("This document describes the pilot as deployed and measured on 2 October 2026. The companion repository holds the Terraform, scripts, prompts and both recorded sessions: github.com/kamelhar/openhuman-oci.")
    r.font.size = Pt(9.5); r.font.color.rgb = GREY
    return tbl


def insert_paragraph_after(par, text=""):
    new_p = OxmlElement("w:p")
    par._p.addnext(new_p)
    from docx.text.paragraph import Paragraph
    np_ = Paragraph(new_p, par._parent)
    if text:
        np_.add_run(text)
    return np_


def insert_paragraph_after_element(el, doc, text=""):
    new_p = OxmlElement("w:p")
    el.addnext(new_p)
    from docx.text.paragraph import Paragraph
    np_ = Paragraph(new_p, doc.paragraphs[0]._parent)
    if text:
        np_.add_run(text)
    return np_


def heading_pages(pdf_path: str, headings):
    """Map heading text -> first page on which it appears as a line of its own."""
    import subprocess as sp
    pages = {}
    n = int(re.search(r"Pages:\s+(\d+)", sp.run(["pdfinfo", pdf_path], capture_output=True, text=True).stdout).group(1))
    remaining = {h: None for h in headings}
    for pg in range(1, n + 1):
        txt = sp.run(["pdftotext", "-f", str(pg), "-l", str(pg), "-layout", pdf_path, "-"], capture_output=True, text=True).stdout
        lines = [re.sub(r"\s+", " ", ln).strip() for ln in txt.splitlines()]
        for h in list(remaining):
            if remaining[h] is not None:
                continue
            key = h[:38]
            if any(ln == h or (len(h) > 38 and ln.startswith(key)) for ln in lines):
                remaining[h] = pg
    return remaining


def fill_toc(doc, entries):
    """Write static TOC lines (title, dotted leader, page) into pandoc's TOC field
    result, so Word before an update and LibreOffice both show a contents list.
    entries: list of (level, text, page)."""
    body = doc.element.body
    sdt = None
    for el in body.iter(qn("w:sdt")):
        if el.find(".//" + qn("w:docPartGallery")) is not None:
            sdt = el; break
    if sdt is None:
        return False
    content = sdt.find(qn("w:sdtContent"))
    # pandoc: first paragraph = title (TOC Heading) ... field paragraph with begin/instr/separate ... end
    paras = content.findall(qn("w:p"))
    field_p = None
    for p in paras:
        if p.find(".//" + qn("w:instrText")) is not None:
            field_p = p; break
    if field_p is None:
        return False
    # strip everything after the 'separate' fldChar in that paragraph, keep an 'end' later
    runs = field_p.findall(qn("w:r"))
    seen_sep = False
    for r in runs:
        fc = r.find(qn("w:fldChar"))
        if seen_sep:
            field_p.remove(r)
        elif fc is not None and fc.get(qn("w:fldCharType")) == "separate":
            seen_sep = True
    # remove any following paragraphs inside the sdt (old result), then add ours and a final 'end'
    for p in paras[paras.index(field_p) + 1:]:
        content.remove(p)
    from docx.text.paragraph import Paragraph
    last = field_p
    for level, text, page in entries:
        np_ = OxmlElement("w:p"); last.addnext(np_); last = np_
        par = Paragraph(np_, doc.paragraphs[0]._parent)
        par.style = doc.styles["TOC 1" if level == 1 else "TOC 2"] if ("TOC 1" in [x.name for x in doc.styles]) else doc.styles["Normal"]
        pf = par.paragraph_format
        pf.tab_stops.add_tab_stop(Inches(6.5), alignment=2, leader=1)  # right, dots
        pf.space_after = Pt(2)
        if level == 2:
            pf.left_indent = Inches(0.3)
        run = par.add_run(f"{text}\t{page if page else ''}")
        run.font.size = Pt(10 if level == 1 else 9.5)
        run.font.name = FONT
        run.font.color.rgb = BARK
        if level == 1:
            run.font.bold = True
    endp = OxmlElement("w:p"); last.addnext(endp)
    er = OxmlElement("w:r"); fc = OxmlElement("w:fldChar"); fc.set(qn("w:fldCharType"), "end"); er.append(fc); endp.append(er)
    return True


def set_update_fields(doc):
    settings = doc.settings.element
    uf = settings.find(qn("w:updateFields"))
    if uf is None:
        uf = OxmlElement("w:updateFields"); settings.append(uf)
    uf.set(qn("w:val"), "true")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.expanduser("~/Documents/openhuman-oci"))
    ap.add_argument("--no-pdf", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    text = open(SRC, encoding="utf-8").read()
    title, byline, version, date, rows = parse_front_matter(text)
    short_title = title.split(":")[0].strip()
    subtitle = title.split(":", 1)[1].strip() if ":" in title else ""
    subtitle = subtitle[:1].upper() + subtitle[1:]
    author_name, author_role = byline.split(",", 1) if "," in byline else (byline, "")
    author_role = author_role.strip().replace(" — ", ", ")

    if not os.path.exists(COVER):
        subprocess.run([sys.executable, os.path.join(HERE, "cover.py"), "--version", version, "--date", date], check=True)

    tmp = tempfile.mkdtemp()
    docs_dir = os.path.join(tmp, "docs"); os.makedirs(docs_dir)
    shutil.copytree(os.path.join(ROOT, "media"), os.path.join(tmp, "media"), ignore=shutil.ignore_patterns("*.mp4", ".cache"))
    md_path = os.path.join(docs_dir, "doc.md")
    open(md_path, "w", encoding="utf-8").write(body_markdown(text))
    ref = os.path.join(tmp, "reference.docx")
    make_reference(ref, f"{short_title} · Architecture reference, version {version}", f"Oracle · {date}")

    out_docx = os.path.join(a.out, f"OpenHuman-on-Oracle-Cloud-architecture-reference-v{version}.docx")
    subprocess.run([
        "pandoc", md_path, "--from", "markdown-raw_html-smart", "--to", "docx",
        "--reference-doc", ref, "--resource-path", docs_dir,
        "--shift-heading-level-by=-1", "--toc", "--toc-depth=2",
        "--metadata", f"title={short_title}",
        "--metadata", f"subtitle={subtitle}",
        "--metadata", f"author={author_name.strip()}, {author_role}",
        "--metadata", f"date={date} · Architecture reference, version {version}",
        "--metadata", "toc-title=Contents",
        "-o", out_docx,
    ], check=True)

    doc = Document(out_docx)
    insert_cover(doc)
    add_document_control(doc, byline, version, date, rows)
    style_tables(doc)
    style_table_captions(doc)
    shade_code_blocks(doc)
    set_update_fields(doc)
    headings = [(1 if p.style.name == "Heading 1" else 2, p.text.strip()) for p in doc.paragraphs if p.style.name in ("Heading 1", "Heading 2") and p.text.strip()]
    doc.save(out_docx)
    # pass 1: render, read the page of every heading, write the contents list, render again
    if not a.no_pdf:
        subprocess.run(["soffice", "--headless", "--convert-to", "pdf", "--outdir", a.out, out_docx], check=True, capture_output=True)
        pages = heading_pages(out_docx[:-5] + ".pdf", [h for _, h in headings])
        # printed page numbers start at 1 on the title page (the cover is unnumbered)
        entries = [(lvl, h, (pages.get(h) - 1) if pages.get(h) else None) for lvl, h in headings]
        doc = Document(out_docx)
        if fill_toc(doc, entries):
            print(f"contents: {sum(1 for e in entries if e[2])} of {len(entries)} headings located")
    cp = doc.core_properties
    cp.title = title; cp.author = author_name.strip(); cp.subject = "Architecture reference"
    cp.keywords = "OpenHuman, OCI, Oracle Cloud, Generative AI, MCP, Autonomous Database, Terraform"
    cp.comments = f"Version {version}, {date}. Built from docs/OPENHUMAN-ON-OCI.md by media/build-word.py."
    cp.category = "Architecture"
    doc.save(out_docx)
    print(out_docx)

    if not a.no_pdf:
        subprocess.run(["soffice", "--headless", "--convert-to", "pdf", "--outdir", a.out, out_docx], check=True, capture_output=True)
        print(out_docx[:-5] + ".pdf")
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
