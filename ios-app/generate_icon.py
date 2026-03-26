#!/usr/bin/env python3
"""
Génère l'icône 1024x1024 de Basket Trainer.
Design : ballon orange dominant + silhouette épurée shooting machine.
"""
import math, os
from PIL import Image, ImageDraw

SIZE = 1024

def make_icon():
    img  = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ── Fond arrondi ──
    radius = int(SIZE * 0.225)
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    bg_draw = ImageDraw.Draw(bg)

    # Dégradé radial sombre (centre légèrement plus clair)
    cx0, cy0 = SIZE // 2, SIZE // 2
    max_r = math.sqrt(2) * SIZE / 2
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.sqrt((x - cx0)**2 + (y - cy0)**2)
            t = min(d / max_r, 1.0)
            r = int(28 * (1 - t) + 10 * t)
            g = int(22 * (1 - t) + 8  * t)
            b = int(18 * (1 - t) + 6  * t)
            bg.putpixel((x, y), (r, g, b, 255))

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
    img.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(img)

    # ─────────────────────────────────────────────
    # SHOOTING MACHINE (dessinée en premier = derrière le ballon)
    # Silhouette épurée, coin bas-gauche
    # ─────────────────────────────────────────────
    ORANGE = (255, 102,   0)
    LGRAY  = (200, 200, 200)
    MGRAY  = (110, 110, 110)
    DGRAY  = ( 55,  55,  55)

    # Base avec roues
    base_x,  base_y  = int(SIZE * 0.06), int(SIZE * 0.74)
    base_w,  base_h  = int(SIZE * 0.19), int(SIZE * 0.09)
    draw.rounded_rectangle(
        [base_x, base_y, base_x + base_w, base_y + base_h],
        radius=16, fill=DGRAY, outline=MGRAY, width=3
    )
    # Orange stripe
    draw.rounded_rectangle(
        [base_x + 6, base_y + 6, base_x + base_w - 6, base_y + 20],
        radius=6, fill=ORANGE
    )
    # Roues
    wr = int(SIZE * 0.030)
    for wx in [base_x + wr + 10, base_x + base_w - wr - 10]:
        wy = base_y + base_h + wr - 6
        draw.ellipse([wx-wr, wy-wr, wx+wr, wy+wr], fill=DGRAY, outline=MGRAY, width=3)
        draw.ellipse([wx-wr//2, wy-wr//2, wx+wr//2, wy+wr//2], fill=MGRAY)

    # Colonne verticale
    col_cx  = base_x + base_w // 2
    col_w   = int(SIZE * 0.055)
    col_top = int(SIZE * 0.22)
    draw.rounded_rectangle(
        [col_cx - col_w//2, col_top, col_cx + col_w//2, base_y],
        radius=10, fill=DGRAY, outline=MGRAY, width=2
    )
    # Encoche déco
    for ey in range(col_top + 40, base_y - 30, 55):
        draw.rectangle(
            [col_cx - col_w//2 + 6, ey, col_cx + col_w//2 - 6, ey + 20],
            fill=MGRAY
        )

    # Bras horizontal → vers le ballon
    ball_cx = int(SIZE * 0.60)
    ball_cy = int(SIZE * 0.46)
    ball_r  = int(SIZE * 0.315)

    arm_y   = col_top + int(SIZE * 0.12)
    arm_x0  = col_cx + col_w // 2
    arm_x1  = ball_cx - int(ball_r * 0.78)

    arm_h   = int(SIZE * 0.046)
    draw.rounded_rectangle(
        [arm_x0, arm_y - arm_h//2, arm_x1, arm_y + arm_h//2],
        radius=arm_h//2, fill=LGRAY
    )

    # Joint colonne–bras
    jr = int(SIZE * 0.038)
    draw.ellipse([arm_x0 - jr, arm_y - jr, arm_x0 + jr, arm_y + jr], fill=ORANGE)

    # Joint bras–lanceur
    jr2 = int(SIZE * 0.030)
    draw.ellipse([arm_x1 - jr2, arm_y - jr2, arm_x1 + jr2, arm_y + jr2], fill=DGRAY, outline=LGRAY, width=3)

    # Rouleaux lanceur
    rl = int(SIZE * 0.060)
    for dy in [-rl//2 - 4, rl//2 + 4]:
        rx = arm_x1
        ry = arm_y + dy
        draw.ellipse([rx-rl, ry-rl//2, rx+rl, ry+rl//2], fill=DGRAY, outline=ORANGE, width=4)
        # Rayons
        for a in range(0, 360, 60):
            rad = math.radians(a)
            ex2 = int(rx + (rl - 8) * math.cos(rad))
            ey2 = int(ry + (rl//2 - 4) * math.sin(rad))
            draw.line([rx, ry, ex2, ey2], fill=MGRAY, width=2)

    # ─────────────────────────────────────────────
    # BALLON DE BASKET
    # ─────────────────────────────────────────────
    # Dégradé radial orange → orange foncé
    ball_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ball_draw = ImageDraw.Draw(ball_img)

    for i in range(ball_r, 0, -2):
        t = i / ball_r
        # Orange vif au centre, plus sombre sur les bords
        r = int(255 * (0.65 + 0.35 * t))
        g = int(102 * (0.5  + 0.5  * t))
        b = 0
        ball_draw.ellipse(
            [ball_cx - i, ball_cy - i, ball_cx + i, ball_cy + i],
            fill=(r, g, b, 255)
        )

    # Lumière (highlight)
    hl_x = ball_cx - int(ball_r * 0.38)
    hl_y = ball_cy - int(ball_r * 0.38)
    hl_r = int(ball_r * 0.28)
    for i in range(hl_r, 0, -1):
        alpha = int(110 * (1 - i / hl_r) * (i / hl_r))
        ball_draw.ellipse(
            [hl_x - i, hl_y - i, hl_x + i, hl_y + i],
            fill=(255, 220, 170, alpha)
        )

    # Seams
    slw = max(9, SIZE // 65)
    sc  = (160, 48, 0, 220)

    # Ligne équatoriale
    ball_draw.arc(
        [ball_cx - ball_r, ball_cy - ball_r, ball_cx + ball_r, ball_cy + ball_r],
        start=0, end=180, fill=sc, width=slw
    )
    ball_draw.arc(
        [ball_cx - ball_r, ball_cy - ball_r, ball_cx + ball_r, ball_cy + ball_r],
        start=180, end=360, fill=sc, width=slw
    )

    # Lignes verticales
    ir = int(ball_r * 0.56)
    ball_draw.arc(
        [ball_cx - ir, ball_cy - ball_r, ball_cx + ir, ball_cy + ball_r],
        start=270, end=90, fill=sc, width=slw
    )
    ball_draw.arc(
        [ball_cx - ir, ball_cy - ball_r, ball_cx + ir, ball_cy + ball_r],
        start=90, end=270, fill=sc, width=slw
    )

    # Masque circulaire pour le ballon
    ball_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(ball_mask).ellipse(
        [ball_cx - ball_r, ball_cy - ball_r, ball_cx + ball_r, ball_cy + ball_r],
        fill=255
    )
    img.paste(ball_img, (0, 0), ball_mask)

    draw = ImageDraw.Draw(img)

    # ─────────────────────────────────────────────
    # PANIER (en haut à droite, épuré)
    # ─────────────────────────────────────────────
    hx  = int(SIZE * 0.83)
    hy  = int(SIZE * 0.14)
    hr  = int(SIZE * 0.072)

    # Panneau
    pw = int(SIZE * 0.095)
    ph = int(SIZE * 0.085)
    draw.rectangle([hx - pw//2, hy - ph, hx + pw//2, hy], fill=(35, 35, 35, 230), outline=LGRAY, width=3)
    # Carré intérieur
    m = 10
    draw.rectangle([hx - pw//2 + m, hy - ph + m, hx + pw//2 - m, hy - m],
                   fill=None, outline=LGRAY, width=2)

    # Arceau (demi-cercle)
    draw.arc(
        [hx - hr, hy - hr//3, hx + hr, hy + hr - hr//3],
        start=0, end=180, fill=ORANGE, width=10
    )

    # Filet (lignes verticales)
    net_top = hy + hr//2 - hr//3
    net_bot = hy + hr
    for fx in range(hx - hr + 6, hx + hr, 9):
        draw.line([(fx, net_top), (fx + 2, net_bot)], fill=(180, 180, 180, 160), width=2)
    # Horizontales filet
    for ny in range(net_top, net_bot, 8):
        draw.line([(hx - hr + 4, ny), (hx + hr - 4, ny)], fill=(180, 180, 180, 80), width=1)

    # ─────────────────────────────────────────────
    # TRAJECTOIRE (arc de points orange)
    # ─────────────────────────────────────────────
    # Du dessus du ballon vers le panier
    traj_pts = []
    steps = 14
    start_x = ball_cx
    start_y = ball_cy - ball_r - 10
    end_x   = hx
    end_y   = hy + 10
    peak_x  = (start_x + end_x) // 2 + 20
    peak_y  = int(SIZE * 0.05)

    for i in range(steps + 1):
        t2 = i / steps
        # Courbe de Bezier quadratique
        bx2 = int((1-t2)**2 * start_x + 2*(1-t2)*t2 * peak_x + t2**2 * end_x)
        by2 = int((1-t2)**2 * start_y + 2*(1-t2)*t2 * peak_y + t2**2 * end_y)
        traj_pts.append((bx2, by2))

    dot_r = int(SIZE * 0.016)
    for i, (px2, py2) in enumerate(traj_pts):
        alpha = int(180 * (i / steps))
        r2    = max(4, int(dot_r * (0.5 + 0.5 * i / steps)))
        draw.ellipse([px2 - r2, py2 - r2, px2 + r2, py2 + r2],
                     fill=(255, 120, 0, alpha))

    # ─────────────────────────────────────────────
    # Appliquer le masque arrondi final
    # ─────────────────────────────────────────────
    final = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    final.paste(img, (0, 0), mask)

    out_dir  = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "BasketTrainer/Assets.xcassets/AppIcon.appiconset")
    out_path = os.path.join(out_dir, "AppIcon-1024.png")
    final.save(out_path, "PNG")
    print(f"Icône générée : {out_path}")

make_icon()
