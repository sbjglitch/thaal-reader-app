"""Generate small, purpose-built EPUB and PDF fixtures for the reader spike.

All text is generated here, so the fixtures carry no third-party copyright.
Usage: python3 -I tool/make_fixtures.py <output_dir>
"""

import sys
import zipfile
from pathlib import Path

PARAGRAPH = (
    "This paragraph is generated filler text for pagination testing. "
    "It is intentionally long enough to wrap across several lines so that "
    "each chapter spans multiple screens at the default font size. "
)


def chapter_body(number: int, paragraphs: int = 24, section: str = "") -> str:
    # Each paragraph label must be unique within the publication: Readium
    # anchors decorations by surrounding text, so duplicated passages make a
    # highlight attach to the first matching occurrence.
    label = f"Chapter {number}{f', section {section}' if section else ''}"
    rows = [f"<p>{label}, paragraph {i + 1}. {PARAGRAPH * 2}</p>" for i in range(paragraphs)]
    return "\n".join(rows)


def xhtml(title: str, body: str, epub3: bool) -> str:
    ns = ' xmlns:epub="http://www.idpf.org/2007/ops"' if epub3 else ""
    doctype = "<!DOCTYPE html>" if epub3 else (
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" '
        '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'
    )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f"{doctype}\n"
        f'<html xmlns="http://www.w3.org/1999/xhtml"{ns}>\n'
        f"<head><title>{title}</title></head>\n"
        f"<body>\n{body}\n</body>\n</html>\n"
    )


def write_epub(path: Path, files: dict, opf: str) -> None:
    container = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        '  <rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles>\n'
        "</container>\n"
    )
    with zipfile.ZipFile(path, "w") as archive:
        # The mimetype entry must be first and stored uncompressed.
        archive.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr("META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        for name, content in files.items():
            archive.writestr(f"OEBPS/{name}", content, compress_type=zipfile.ZIP_DEFLATED)


def make_epub3(path: Path) -> None:
    chapters = {}
    for n in range(1, 4):
        body = f'<h1 id="ch{n}">Chapter {n}</h1>\n'
        body += f'<h2 id="ch{n}-s1">Section {n}.1</h2>\n{chapter_body(n, 12, f"{n}.1")}\n'
        body += f'<h2 id="ch{n}-s2">Section {n}.2</h2>\n{chapter_body(n, 12, f"{n}.2")}\n'
        if n == 1:
            body += '<p>Internal link test: <a href="chapter3.xhtml#ch3-s2">jump to Section 3.2</a>.</p>\n'
            body += '<p>Footnote test<a epub:type="noteref" href="notes.xhtml#note1">1</a>.</p>\n'
        chapters[f"chapter{n}.xhtml"] = xhtml(f"Chapter {n}", body, epub3=True)
    chapters["notes.xhtml"] = xhtml(
        "Notes",
        '<aside epub:type="footnote" id="note1"><p>1. Generated footnote text.</p></aside>',
        epub3=True,
    )

    toc_items = "\n".join(
        f'<li><a href="chapter{n}.xhtml#ch{n}">Chapter {n}</a><ol>'
        f'<li><a href="chapter{n}.xhtml#ch{n}-s1">Section {n}.1</a></li>'
        f'<li><a href="chapter{n}.xhtml#ch{n}-s2">Section {n}.2</a></li></ol></li>'
        for n in range(1, 4)
    )
    chapters["nav.xhtml"] = xhtml(
        "Contents",
        f'<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>\n{toc_items}\n</ol></nav>',
        epub3=True,
    )

    manifest = "\n".join(
        f'    <item id="c{n}" href="chapter{n}.xhtml" media-type="application/xhtml+xml"/>' for n in range(1, 4)
    )
    spine = "\n".join(f'    <itemref idref="c{n}"/>' for n in range(1, 4))
    opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:5f0b3d0e-spike-epub3-0001</dc:identifier>
    <dc:title>Spike EPUB 3 Sample</dc:title>
    <dc:creator>Reader Spike Generator</dc:creator>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">2026-11-07T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
{manifest}
    <item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
{spine}
    <itemref idref="notes" linear="no"/>
  </spine>
</package>
"""
    write_epub(path, chapters, opf)


def make_epub2(path: Path) -> None:
    files = {
        f"chapter{n}.xhtml": xhtml(f"Chapter {n}", f'<h1 id="ch{n}">Chapter {n}</h1>\n{chapter_body(n)}', epub3=False)
        for n in range(1, 3)
    }
    nav_points = "\n".join(
        f'    <navPoint id="np{n}" playOrder="{n}"><navLabel><text>Chapter {n}</text></navLabel>'
        f'<content src="chapter{n}.xhtml"/></navPoint>'
        for n in range(1, 3)
    )
    files["toc.ncx"] = f"""<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:5f0b3d0e-spike-epub2-0001"/></head>
  <docTitle><text>Spike EPUB 2 Sample</text></docTitle>
  <navMap>
{nav_points}
  </navMap>
</ncx>
"""
    manifest = "\n".join(
        f'    <item id="c{n}" href="chapter{n}.xhtml" media-type="application/xhtml+xml"/>' for n in range(1, 3)
    )
    spine = "\n".join(f'    <itemref idref="c{n}"/>' for n in range(1, 3))
    opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:5f0b3d0e-spike-epub2-0001</dc:identifier>
    <dc:title>Spike EPUB 2 Sample</dc:title>
    <dc:creator>Reader Spike Generator</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
{manifest}
  </manifest>
  <spine toc="ncx">
{spine}
  </spine>
</package>
"""
    write_epub(path, files, opf)


def make_pdf(path: Path, pages: int = 12) -> None:
    """Write a minimal valid PDF with text pages of alternating sizes."""
    sizes = [(612, 792), (842, 595)]  # US Letter portrait, A4 landscape
    objects: list[bytes] = []

    def add(obj: bytes) -> int:
        objects.append(obj)
        return len(objects)

    catalog_id = add(b"")  # placeholder, filled after pages are known
    pages_id = add(b"")
    font_id = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    page_ids = []
    for index in range(pages):
        width, height = sizes[index % 2]
        text = f"BT /F1 36 Tf 72 {height - 120} Td (Spike PDF page {index + 1}) Tj ET".encode()
        content_id = add(b"<< /Length %d >>\nstream\n%s\nendstream" % (len(text), text))
        page_ids.append(
            add(
                b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %d %d] "
                b"/Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R >>"
                % (pages_id, width, height, font_id, content_id)
            )
        )
    kids = b" ".join(b"%d 0 R" % pid for pid in page_ids)
    objects[pages_id - 1] = b"<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, pages)
    objects[catalog_id - 1] = b"<< /Type /Catalog /Pages %d 0 R >>" % pages_id

    output = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(output))
        output += b"%d 0 obj\n%s\nendobj\n" % (number, body)
    xref_offset = len(output)
    output += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        output += b"%010d 00000 n \n" % offset
    output += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
        len(objects) + 1,
        catalog_id,
        xref_offset,
    )
    path.write_bytes(bytes(output))


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    make_epub2(out / "spike_epub2.epub")
    make_epub3(out / "spike_epub3.epub")
    make_pdf(out / "spike_pdf.pdf")
    (out / "corrupt.epub").write_bytes(b"This is not a ZIP archive.")
    for item in sorted(out.iterdir()):
        print(f"{item.name}: {item.stat().st_size} bytes")


if __name__ == "__main__":
    main()
