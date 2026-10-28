"""QR code for the workshop page, with an icon in the centre.

    uv run --with segno python make_qr.py molecule qr-code        # CO adsorbed on a metal surface
    uv run --with segno python make_qr.py github qr-code-github   # GitHub mark
    rsvg-convert -w 1200 qr-code.svg -o qr-code.png              # PNG for slides

Error correction H tolerates ~30% damage; the icon tile covers about 7% of the symbol.
To use another logo, add an entry to ICONS: SVG markup drawn in a 16x16 box.
"""
import sys

import segno

URL = "https://haraldsr.github.io/claude-in-science/"

ICONS = {
    # Octicons mark-github
    "github": '<path fill="#000" d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/>',
    # CO on top of a metal surface atom: O (red) over C (dark) over three surface atoms (DTU blue)
    "molecule": (
        '<g stroke="#fff" stroke-width=".6">'
        '<circle cx="2.6" cy="12.7" r="2.9" fill="#2f3eea"/>'
        '<circle cx="13.4" cy="12.7" r="2.9" fill="#2f3eea"/>'
        '<circle cx="8" cy="12.7" r="2.9" fill="#2f3eea"/>'
        '<circle cx="8" cy="3.5" r="2.5" fill="#e03a3a"/>'
        '<circle cx="8" cy="7.6" r="2.1" fill="#11142e"/>'
        "</g>"
    ),
}


def main(icon: str, out: str = "qr-code") -> None:
    border = 4
    qr = segno.make(URL, error="h", micro=False)
    n = qr.symbol_size(scale=1, border=0)[0]
    total = n + 2 * border
    # Dark modules as one path, on white so the code also scans on dark slides.
    cells = "".join(
        f"M{x + border} {y + border}h1v1h-1z"
        for y, row in enumerate(qr.matrix)
        for x, v in enumerate(row)
        if v
    )
    pad = 11 if n % 2 else 10  # white tile, odd/even so it stays on the module grid
    tile = border + (n - pad) / 2
    size = pad - 2
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total} {total}" shape-rendering="crispEdges">
<rect width="{total}" height="{total}" fill="#fff"/>
<path d="{cells}" fill="#000"/>
<g shape-rendering="geometricPrecision">
<rect x="{tile}" y="{tile}" width="{pad}" height="{pad}" rx="1.6" fill="#fff"/>
<g transform="translate({tile + 1} {tile + 1}) scale({size / 16})">{ICONS[icon]}</g>
</g>
</svg>
"""
    with open(f"{out}.svg", "w") as f:
        f.write(svg)


if __name__ == "__main__":
    main(*sys.argv[1:])
