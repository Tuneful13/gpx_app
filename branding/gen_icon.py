"""Genera el icono de gpx_app (estilo Web 2.0) como SVG: fondo, primer plano y versión clásica."""
import sys
from pathlib import Path

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

DEFS = """
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#C9F6FF"/>
    <stop offset="0.45" stop-color="#3EC1F3"/>
    <stop offset="1" stop-color="#0369B5"/>
  </linearGradient>
  <radialGradient id="sun" cx="54" cy="40" r="40" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/>
    <stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.25"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="back" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#4DB6AC"/>
    <stop offset="1" stop-color="#00695C"/>
  </linearGradient>
  <linearGradient id="front" x1="0" y1="0" x2="0.3" y2="1">
    <stop offset="0" stop-color="#B2F25C"/>
    <stop offset="0.5" stop-color="#4CAF50"/>
    <stop offset="1" stop-color="#1B5E20"/>
  </linearGradient>
  <linearGradient id="pin" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFB74D"/>
    <stop offset="0.55" stop-color="#FF5722"/>
    <stop offset="1" stop-color="#C62828"/>
  </linearGradient>
  <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.08"/>
  </linearGradient>
  <linearGradient id="pingloss" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.85"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </linearGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="1.4"/>
    <feOffset dx="0" dy="1.6" result="b"/>
    <feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <clipPath id="round"><rect x="0" y="0" width="108" height="108" rx="24"/></clipPath>
</defs>
"""


def rays():
    # Rayos de sol alternos, muy dosmileros.
    import math
    parts = []
    cx, cy, r = 54, 40, 120
    n = 16
    for i in range(0, n, 2):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        parts.append(
            f'<path d="M{cx},{cy} L{cx + r * math.cos(a0):.2f},{cy + r * math.sin(a0):.2f} '
            f'L{cx + r * math.cos(a1):.2f},{cy + r * math.sin(a1):.2f} Z"/>')
    return f'<g fill="#FFFFFF" opacity="0.13">{"".join(parts)}</g>'


def sparkle(x, y, s, op=1.0):
    return (f'<path transform="translate({x},{y}) scale({s})" opacity="{op}" fill="#FFFFFF" '
            'd="M0,-5 C0.6,-1.2 1.2,-0.6 5,0 C1.2,0.6 0.6,1.2 0,5 C-0.6,1.2 -1.2,0.6 -5,0 '
            'C-1.2,-0.6 -0.6,-1.2 0,-5 Z"/>')


BACKGROUND = f"""
<rect width="108" height="108" fill="url(#sky)"/>
{rays()}
<circle cx="54" cy="40" r="40" fill="url(#sun)"/>
"""

FOREGROUND = f"""
{sparkle(29, 31, 1.0, 0.95)}
{sparkle(81, 27, 0.7, 0.9)}
{sparkle(84, 44, 0.45, 0.8)}
<path d="M-4,84 L28,58 L40,66 L58,46 L80,62 L112,44 L112,112 L-4,112 Z" fill="url(#back)"/>
<g filter="url(#shadow)">
  <path d="M-2,112 L36,66 L45,72 L60,50 L76,68 L83,63 L112,96 L112,112 Z" fill="url(#front)"/>
  <path d="M60,50 L53.6,59.6 L57,57.6 L60,60.4 L63.2,57.4 L66.4,59.2 Z" fill="#FFFFFF"/>
</g>
<path d="M38,106 C56,100 30,92 46,85 S68,76 56,70 S60,60 60,55" fill="none"
      stroke="#0B3D12" stroke-opacity="0.35" stroke-width="3.6" stroke-linecap="round"/>
<path d="M38,106 C56,100 30,92 46,85 S68,76 56,70 S60,60 60,55" fill="none"
      stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round" stroke-dasharray="3.6 3"/>
<g filter="url(#shadow)">
  <path d="M60,50 C56,44 50.5,40.5 50.5,34.5 A9.5,9.5 0 1 1 69.5,34.5 C69.5,40.5 64,44 60,50 Z"
        fill="url(#pin)" stroke="#FFFFFF" stroke-width="1.6" stroke-linejoin="round"/>
  <circle cx="60" cy="34.5" r="3.6" fill="#FFFFFF"/>
  <ellipse cx="57.4" cy="29.6" rx="5" ry="2.8" fill="url(#pingloss)"/>
</g>
"""

GLOSS = '<path d="M-10,-10 L118,-10 L118,40 C90,52 18,52 -10,40 Z" fill="url(#gloss)" opacity="0.8"/>'


def svg(body, size=432):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 108 108">{DEFS}{body}</svg>')


(out / "background.svg").write_text(svg(BACKGROUND))
(out / "foreground.svg").write_text(svg(FOREGROUND + GLOSS))
legacy = (f'<g clip-path="url(#round)">{BACKGROUND}{FOREGROUND}{GLOSS}</g>'
          '<rect x="0.8" y="0.8" width="106.4" height="106.4" rx="23.3" fill="none" '
          'stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="1.6"/>')
(out / "legacy.svg").write_text(svg(legacy, 1024))
