#!/usr/bin/env python3
"""Genera el icono de la app (Assets/ClaudePet.icns y su iconset) a partir del sprite real de la mascota (Assets/sprite-idle.png).
Uso: python3 tools/make-icon.py   (necesita Pillow y iconutil)"""
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "Assets")
N = 1024
SPRITE = Image.open(os.path.join(A, "sprite-idle.png")).convert("RGBA")

def squircle_mask(size, margin, n=5.0):
    ss = 4
    big = size * ss
    m = Image.new("L", (big, big), 0)
    px = m.load()
    c = big / 2
    r = (big - 2 * margin * ss) / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        ct, st = math.cos(t), math.sin(t)
        pts.append((c + r * math.copysign(abs(ct) ** (2 / n), ct), c + r * math.copysign(abs(st) ** (2 / n), st)))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)

def vgrad(size, top, bottom):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((size, size))

def build():
    margin = 100
    bg = vgrad(N, (24, 20, 18), (8, 8, 9)).convert("RGBA")
    # brillo de brasa detras de la mascota
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((190, 330, 834, 860), fill=(224, 100, 40, 120))
    bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(120)))
    # trama de puntos de 8 bits, casi invisible
    dots = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(dots)
    step = 36
    for gy in range(margin + 18, N - margin, step):
        for gx in range(margin + 18, N - margin, step):
            d.rectangle((gx, gy, gx + 3, gy + 3), fill=(255, 255, 255, 14))
    bg = Image.alpha_composite(bg, dots)
    # el sprite: celdas enteras, sombra dura de un cuadro y nada de suavizado
    cell = 36
    w, h = SPRITE.size
    sp = SPRITE.resize((w * cell, h * cell), Image.NEAREST)
    x, y = (N - sp.width) // 2, (N - sp.height) // 2 + 14
    shadow = Image.new("RGBA", sp.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 170), mask=sp.split()[3])
    bg.alpha_composite(shadow, (x + cell // 2, y + cell // 2 + 6))
    bg.alpha_composite(sp, (x, y))
    # marco fino de ficha tecnica y marcas en las esquinas
    fr = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    f = ImageDraw.Draw(fr)
    ins = margin + 34
    f.rounded_rectangle((ins, ins, N - ins, N - ins), radius=120, outline=(244, 241, 234, 26), width=3)
    bg = Image.alpha_composite(bg, fr)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.paste(bg, (0, 0), squircle_mask(N, margin))
    return out

def main():
    icon = build()
    icon.save(os.path.join(A, "IconSource.png"))
    iset = os.path.join(A, "ClaudePet.iconset")
    os.makedirs(iset, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        icon.resize((base, base), Image.LANCZOS).save(os.path.join(iset, f"icon_{base}x{base}.png"))
        icon.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(iset, f"icon_{base}x{base}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iset, "-o", os.path.join(A, "ClaudePet.icns")], check=True)
    print("icono generado")

if __name__ == "__main__":
    sys.exit(main())
