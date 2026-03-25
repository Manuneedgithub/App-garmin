#!/usr/bin/env python3
"""
Génère l'icône 1024x1024 de Basket Trainer.
Design : basket orange + silhouette shooting machine.
"""
import math, os
from PIL import Image, ImageDraw

SIZE = 1024
img   = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

# ── Fond avec coins arrondis iOS ──
radius = int(SIZE * 0.225)
bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
bg_draw = ImageDraw.Draw(bg)

# Fond : dégradé diagonal sombre
for y in range(SIZE):
    t = y / SIZE
    r = int(18 + 8 * (1 - t))
    g = int(18 + 4 * (1 - t))
    b = int(18 + 2 * (1 - t))
    bg_draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

mask = Image.new("L", (SIZE, SIZE), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
img.paste(bg, (0, 0), mask)

draw = ImageDraw.Draw(img)

# ── Shooting machine (dessinée AVANT le ballon → derrière) ──
ORANGE = (255, 102, 0, 255)
GRAY   = (170, 170, 170, 255)
DGRAY  = (80,  80,  80,  255)
WHITE  = (240, 240, 240, 255)

# Base
bx, by = int(SIZE * 0.10), int(SIZE * 0.72)
bw, bh  = int(SIZE * 0.20), int(SIZE * 0.10)
draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=14, fill=(50, 50, 50, 255))
draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=14, outline=ORANGE, width=4)

# Roues
for wx in [bx + 20, bx + bw - 20]:
    draw.ellipse([wx - 18, by + bh - 10, wx + 18, by + bh + 26],
                 fill=(35, 35, 35, 255), outline=(100, 100, 100, 255), width=3)
    draw.ellipse([wx - 7,  by + bh + 1,  wx + 7,  by + bh + 15],
                 fill=(80, 80, 80, 255))

# Colonne verticale
col_cx = bx + bw // 2
col_w  = int(SIZE * 0.06)
col_top = int(SIZE * 0.28)
draw.rounded_rectangle(
    [col_cx - col_w // 2, col_top, col_cx + col_w // 2, by],
    radius=10, fill=DGRAY
)

# Décorations colonne
for seg_y in range(col_top + 30, by - 20, 60):
    draw.line([(col_cx - col_w // 2 + 8, seg_y), (col_cx + col_w // 2 - 8, seg_y)],
              fill=(120, 120, 120, 255), width=2)

# Bras horizontal → vers le ballon (cx ≈ 590)
cx, cy = int(SIZE * 0.58), int(SIZE * 0.44)
arm_y   = col_top + int(SIZE * 0.10)
arm_x1  = col_cx + col_w // 2
arm_x2  = cx - int(SIZE * 0.20)

# Bras principal
draw.rounded_rectangle(
    [arm_x1, arm_y - int(SIZE * 0.025),
     arm_x2, arm_y + int(SIZE * 0.025)],
    radius=12, fill=GRAY
)

# Joint bras–colonne
draw.ellipse(
    [arm_x1 - 16, arm_y - 22, arm_x1 + 28, arm_y + 22],
    fill=ORANGE
)
# Joint avant
draw.ellipse(
    [arm_x2 - 20, arm_y - 20, arm_x2 + 20, arm_y + 20],
    fill=DGRAY
)

# Lanceur (bout du bras)
launcher_cx = arm_x2
launcher_cy = arm_y
l_r = int(SIZE * 0.048)
draw.ellipse(
    [launcher_cx - l_r, launcher_cy - l_r,
     launcher_cx + l_r, launcher_cy + l_r],
    fill=(40, 40, 40, 255), outline=ORANGE, width=5
)
# Rouleau intérieur
draw.ellipse(
    [launcher_cx - l_r + 10, launcher_cy - l_r + 10,
     launcher_cx + l_r - 10, launcher_cy + l_r - 10],
    fill=(60, 60, 60, 255)
)

# ── Ballon de basket ──
ball_r = int(SIZE * 0.30)
# Dégradé orange
for i in range(ball_r, 0, -1):
    t = i / ball_r
    r = int(255 * (0.7 + 0.3 * t))
    g = int(102 * t)
    b = 0
    draw.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(r, g, b, 255))

# Brillance
for i in range(int(ball_r * 0.35), 0, -1):
    alpha = int(90 * (1 - i / (ball_r * 0.35)))
    hx = cx - int(ball_r * 0.42)
    hy = cy - int(ball_r * 0.42)
    draw.ellipse([hx - i, hy - i, hx + i, hy + i], fill=(255, 210, 160, alpha))

# Seams (lignes du basket)
lw = max(8, SIZE // 70)
sc = (160, 50, 0, 210)

# Ligne horizontale
draw.arc([cx - ball_r, cy - ball_r, cx + ball_r, cy + ball_r],
         start=0,   end=180, fill=sc, width=lw)
draw.arc([cx - ball_r, cy - ball_r, cx + ball_r, cy + ball_r],
         start=180, end=360, fill=sc, width=lw)

# Lignes verticales courbes
ir = int(ball_r * 0.55)
draw.arc([cx - ir, cy - ball_r, cx + ir, cy + ball_r],
         start=270, end=90,  fill=sc, width=lw)
draw.arc([cx - ir, cy - ball_r, cx + ir, cy + ball_r],
         start=90,  end=270, fill=sc, width=lw)

# ── Trajectoire de tir (arc en pointillés orange) ──
arc_cx = cx + int(ball_r * 0.9)
arc_cy = cy - int(ball_r * 1.3)
for angle_deg in range(40, 200, 12):
    angle = math.radians(angle_deg)
    px = int(arc_cx + int(SIZE * 0.18) * math.cos(angle))
    py = int(arc_cy + int(SIZE * 0.12) * math.sin(angle))
    r2 = int(SIZE * 0.018)
    draw.ellipse([px - r2, py - r2, px + r2, py + r2],
                 fill=(255, 150, 0, 180))

# ── Panier (en haut à droite) ──
hoop_x = int(SIZE * 0.80)
hoop_y = int(SIZE * 0.22)
hoop_r = int(SIZE * 0.065)
# Panneau
draw.rectangle([hoop_x - 2, hoop_y - int(SIZE * 0.09),
                hoop_x + int(SIZE * 0.07), hoop_y],
               fill=(50, 50, 50, 200), outline=WHITE, width=3)
# Arceau
draw.arc([hoop_x - hoop_r, hoop_y - hoop_r // 2,
          hoop_x + hoop_r, hoop_y + hoop_r // 2],
         start=0, end=180, fill=(255, 100, 0, 240), width=8)
# Filet (quelques lignes)
for fx in range(hoop_x - hoop_r + 5, hoop_x + hoop_r, 8):
    draw.line([(fx, hoop_y + hoop_r // 4),
               (fx + 2, hoop_y + int(SIZE * 0.06))],
              fill=(200, 200, 200, 150), width=2)

# ── Sauvegarder ──
out_dir  = os.path.join(os.path.dirname(__file__),
                        "BasketTrainer/Assets.xcassets/AppIcon.appiconset")
out_path = os.path.join(out_dir, "AppIcon-1024.png")
img.save(out_path, "PNG")
print(f"Icône générée : {out_path}")
