"""生成即刻日志（JikeLog）应用图标：Android 各密度 PNG、Windows .ico/.png 与官网 apple-touch-icon。

设计语言「瞬刻书签 · J-Log Emblem」：
- 底层：深邃午夜群青至曜石靛蓝对角渐变圆角方块，叠加极光微光与细腻玻璃内描边；
- 中层：双层磨砂玻璃日志页（叠层书页象征「日志 / Log」），左侧镌刻两条极简记录线；
- 主体：珠光银白无衬线几何「J」字标（象征「JikeLog / 即刻」），纯净竖干顺滑收束为半圆底钩，配柔和悬浮阴影；
- 点睛：左上负空间内嵌天青四角星芒 ✦（象征「即刻 / 瞬时灵感」）。

用法：python scripts/gen-app-icons.py（需要 Pillow）
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MOBILE = ROOT / "apps" / "mobile"
SITE_PUBLIC = ROOT / "apps" / "site" / "src" / "public"

BG_TOP = (0x2D, 0x46, 0xD8)     # 左上深群青
BG_MID = (0x1B, 0x2A, 0x86)     # 中段皇家靛蓝
BG_BOT = (0x0D, 0x14, 0x42)     # 右下曜石夜蓝
SPARK = (0x67, 0xE8, 0xF9, 255) # 冰川天青星芒
SPARK_CORE = (0xEC, 0xFE, 0xFF, 255)

SIZE = 1024
SS = 2  # 2048px 绘制再 LANCZOS 缩至 1024px，兼顾柔和光晕与锐利边缘


def _lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def _gradient_bg(n: int) -> Image.Image:
    """三段深海靛蓝渐变 + 双焦点冷光极光氛围 + 圆角玻璃高光描边。"""
    g = 256
    grad = Image.new("RGBA", (g, g))
    px = grad.load()
    denom = float(2 * (g - 1))
    for y in range(g):
        yn = y / (g - 1)
        for x in range(g):
            xn = x / (g - 1)
            t = (x + y) / denom
            if t < 0.5:
                k = t * 2.0
                r = _lerp(BG_TOP[0], BG_MID[0], k)
                gr = _lerp(BG_TOP[1], BG_MID[1], k)
                b = _lerp(BG_TOP[2], BG_MID[2], k)
            else:
                k = (t - 0.5) * 2.0
                r = _lerp(BG_MID[0], BG_BOT[0], k)
                gr = _lerp(BG_MID[1], BG_BOT[1], k)
                b = _lerp(BG_MID[2], BG_BOT[2], k)

            # 左上角星芒方向的冷青极光微光
            d1 = math.hypot(xn - 0.24, yn - 0.20)
            g1 = max(0.0, 1.0 - d1 / 0.68) ** 2.4
            # 右下偏中柔和靛紫回光，避免底角发死
            d2 = math.hypot(xn - 0.78, yn - 0.80)
            g2 = max(0.0, 1.0 - d2 / 0.55) ** 2.6

            r = min(255, round(r + 42 * g1 + 22 * g2))
            gr = min(255, round(gr + 78 * g1 + 26 * g2))
            b = min(255, round(b + 86 * g1 + 58 * g2))
            px[x, y] = (r, gr, b, 255)
    bg = grad.resize((n, n), Image.BILINEAR)

    radius = int(n * 0.225)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)

    # 细腻玻璃内描边（上方偏亮、整体克制）
    rim = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    inset = max(2, round(n * 0.008))
    ImageDraw.Draw(rim).rounded_rectangle(
        (inset, inset, n - 1 - inset, n - 1 - inset),
        radius=radius - inset,
        outline=(255, 255, 255, 48),
        width=max(2, round(n * 0.0055)),
    )
    out = Image.alpha_composite(out, rim)
    return out


def _spark_polygon(cx: float, cy: float, r: float, inner_ratio: float = 0.22, steps: int = 24) -> list[tuple[float, float]]:
    """构造平滑内凹四角星芒（✦）顶点列表。"""
    pts: list[tuple[float, float]] = []
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    controls = [
        (cx + r * inner_ratio * 0.34, cy - r * inner_ratio * 0.34),
        (cx + r * inner_ratio * 0.34, cy + r * inner_ratio * 0.34),
        (cx - r * inner_ratio * 0.34, cy + r * inner_ratio * 0.34),
        (cx - r * inner_ratio * 0.34, cy - r * inner_ratio * 0.34),
    ]
    for i in range(4):
        p0 = tips[i]
        pc = controls[i]
        p1 = tips[(i + 1) % 4]
        for s in range(steps):
            t = s / steps
            mt = 1.0 - t
            x = mt * mt * p0[0] + 2 * mt * t * pc[0] + t * t * p1[0]
            y = mt * mt * p0[1] + 2 * mt * t * pc[1] + t * t * p1[1]
            pts.append((x, y))
    return pts


def _draw_capsule(draw: ImageDraw.ImageDraw, a: tuple[float, float], b: tuple[float, float], width: int, color) -> None:
    draw.line((*a, *b), fill=color, width=width)
    r = width / 2.0
    for pt in (a, b):
        draw.ellipse((pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r), fill=color)


def _j_mask(n: int, p, unit: float, dy: float = 0.0) -> Image.Image:
    """绘制纯粹优雅的无衬线几何「J」字标蒙版（无笨重横帽，黄金比例竖干+圆弧钩）。"""
    mask = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(mask)
    stroke = max(2, round(2.55 * unit))
    r = stroke / 2.0

    def pt(x: float, y: float) -> tuple[float, float]:
        px, py = p(x, y)
        return px, py + dy

    def cap(c: tuple[float, float]) -> None:
        draw.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=255)

    # 右侧纯净竖干：顶部略微收高，呈现挺拔书签气质
    stem_x = 15.55
    arc_cy = 13.85
    cx_u = 11.75
    rad_u = stem_x - cx_u  # 3.80 单位圆弧半径

    stem_top = pt(stem_x, 6.25)
    stem_bot = pt(stem_x, arc_cy)
    draw.line((*stem_top, *stem_bot), fill=255, width=stroke)
    cap(stem_top)
    cap(stem_bot)

    # 顺滑半圆底钩：从 0° 扫到 156°，起笔柔和收锋
    prev = pt(cx_u + rad_u, arc_cy)
    steps = 96
    max_deg = 156.0
    for i in range(1, steps + 1):
        ang = math.radians(max_deg * i / steps)
        cur = pt(cx_u + rad_u * math.cos(ang), arc_cy + rad_u * math.sin(ang))
        draw.line((*prev, *cur), fill=255, width=stroke)
        cap(cur)
        prev = cur

    return mask


def _pearl_gradient(n: int) -> Image.Image:
    """云雾白到淡月光银的纵向柔和渐变，赋予字标金属丝光质感。"""
    strip = Image.new("RGBA", (1, 256))
    px = strip.load()
    top = (0xFF, 0xFF, 0xFF)
    bot = (0xD8, 0xE5, 0xFF)
    for y in range(256):
        t = y / 255.0
        px[0, y] = (_lerp(top[0], bot[0], t), _lerp(top[1], bot[1], t), _lerp(top[2], bot[2], t), 255)
    return strip.resize((n, n), Image.BILINEAR)


def master() -> Image.Image:
    n = SIZE * SS
    img = _gradient_bg(n)

    # 24 单位设计网格居中，占画布 80%，让主体更大气舒展
    unit = n * 0.80 / 24.0
    off = (n - 24.0 * unit) / 2.0

    def p(x: float, y: float) -> tuple[float, float]:
        return off + x * unit, off + y * unit

    # 1. 背景叠层书页（仅在前页外部微露边缘，不穿透前页玻璃，强化「日志 / Log」意象）
    card_box = (*p(2.6, 3.2), *p(19.8, 21.8))
    card_r = round(3.8 * unit)
    front_cutout = Image.new("L", (n, n), 255)
    ImageDraw.Draw(front_cutout).rounded_rectangle(card_box, radius=card_r, fill=0)

    back_card = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    bcd = ImageDraw.Draw(back_card)
    bcd.rounded_rectangle(
        (*p(4.4, 1.8), *p(21.4, 20.2)),
        radius=round(3.6 * unit),
        fill=(255, 255, 255, 18),
        outline=(255, 255, 255, 52),
        width=max(2, round(0.36 * unit)),
    )
    back_card.putalpha(ImageChops.multiply(back_card.getchannel("A"), front_cutout))
    img = Image.alpha_composite(img, back_card)

    # 2. 前景磨砂玻璃日志卡（通透纯净无交叉杂线）
    card = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle(
        card_box,
        radius=card_r,
        fill=(255, 255, 255, 28),
        outline=(255, 255, 255, 84),
        width=max(2, round(0.42 * unit)),
    )
    # 左侧两条极简日志微线（位于星芒与 J 底钩之间的留白，零重叠）
    line_w = max(2, round(0.76 * unit))
    _draw_capsule(cd, p(5.6, 11.45), p(10.6, 11.45), line_w, (226, 238, 255, 118))
    _draw_capsule(cd, p(5.6, 13.25), p(8.5, 13.25), line_w, (226, 238, 255, 76))
    img = Image.alpha_composite(img, card)

    # 3. 主体「J」字标悬浮柔影
    shadow_mask = _j_mask(n, p, unit, dy=0.58 * unit)
    shadow = Image.new("RGBA", (n, n), (7, 12, 42, 0))
    shadow_alpha = shadow_mask.point(lambda v: round(v * 0.56))
    shadow.putalpha(shadow_alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=round(0.85 * unit)))
    img = Image.alpha_composite(img, shadow)

    # 4. 珠光银白「J」字标主体
    j_mask = _j_mask(n, p, unit)
    j_layer = _pearl_gradient(n)
    j_layer.putalpha(j_mask)
    img = Image.alpha_composite(img, j_layer)

    # 5. 天青四角星芒（✦ 即刻灵感）+ 柔和外发光 + 纯白内核
    sx, sy = p(8.2, 8.2)
    sr = 2.75 * unit

    glow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(_spark_polygon(sx, sy, sr * 1.28), fill=(103, 232, 249, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=round(1.10 * unit)))
    img = Image.alpha_composite(img, glow)

    spark_layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    spd = ImageDraw.Draw(spark_layer)
    spd.polygon(_spark_polygon(sx, sy, sr), fill=SPARK)
    spd.polygon(_spark_polygon(sx, sy, sr * 0.48), fill=SPARK_CORE)
    img = Image.alpha_composite(img, spark_layer)

    # 最终仅保留圆角裁切区域内像素，防止极光/模糊外溢
    final_mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(final_mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.225), fill=255)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), final_mask))

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    img = master()

    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in android.items():
        out = MOBILE / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png"
        img.resize((px, px), Image.LANCZOS).save(out, optimize=True)

    res = MOBILE / "windows" / "runner" / "resources"
    if res.is_dir():
        img.save(res / "app_icon.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
        # MSIX 的应用图标（msix_config.logo_path，至少 400px）
        img.resize((512, 512), Image.LANCZOS).save(res / "app_icon.png", optimize=True)

    if SITE_PUBLIC.is_dir():
        img.resize((180, 180), Image.LANCZOS).save(SITE_PUBLIC / "apple-touch-icon.png", optimize=True)

    print("ok")


if __name__ == "__main__":
    main()
