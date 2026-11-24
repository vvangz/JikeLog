"""生成 App 图标：Android 启动图标（各密度 PNG）与 Windows 图标（.ico/.png）。

图形与管理后台的 logo.svg 相同（24×24 网格：圆角文档、三行文字、右下角圆点），
采用深海群青对角渐变底、云雾白线条与天青亮点，颜色与设计令牌呼应。

用法：python scripts/gen-app-icons.py（需要 Pillow）
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MOBILE = ROOT / "apps" / "mobile"

BG_TOP = (0x3D, 0x58, 0xDB)  # 左上亮群青
BG_BOTTOM = (0x1E, 0x30, 0x8A)  # 右下深群青
STROKE = (0xF6, 0xF8, 0xFC, 255)  # 云雾白线条
DOT = (0x7C, 0xDC, 0xF8, 255)  # 天青亮点

SIZE = 1024  # 母版边长
SS = 4  # 超采样倍数，缩小时抗锯齿


def _gradient_bg(n: int) -> Image.Image:
    """构造左上到右下的平滑对角渐变图，并裁成圆角正方形。"""
    # 在低分辨率生成渐变后双线性放大，既快又平滑无色带
    g = 256
    grad = Image.new("RGBA", (g, g))
    px = grad.load()
    denom = float(2 * (g - 1))
    for y in range(g):
        for x in range(g):
            t = (x + y) / denom
            r = round(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
            gr = round(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
            b = round(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
            px[x, y] = (r, gr, b, 255)
    bg = grad.resize((n, n), Image.BILINEAR)

    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.22), fill=255)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    return out


def master() -> Image.Image:
    n = SIZE * SS
    img = _gradient_bg(n)
    d = ImageDraw.Draw(img)

    # 24 单位网格居中缩放到边长的 62.5%
    unit = n * 0.625 / 24
    off = (n - 24 * unit) / 2

    def p(x: float, y: float) -> tuple[float, float]:
        return off + x * unit, off + y * unit

    w = max(1, round(1.5 * unit))  # 描边 1.5 单位

    # 圆角文档
    d.rounded_rectangle((*p(4, 3), *p(20, 21)), radius=3 * unit, outline=STROKE, width=w)

    # 三行文字（圆头端点：两端补圆）
    for y, x2 in ((8, 16), (12, 16), (16, 13)):
        a, b = p(8, y), p(x2, y)
        d.line((*a, *b), fill=STROKE, width=w)
        for cx, cy in (a, b):
            r = w / 2
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=STROKE)

    # 右下角圆点：先用底色局部采样挖出间隙，再画天青实心圆
    cx, cy = p(17, 17)
    gap_color = img.getpixel((int(cx), int(cy)))
    gap = 2.5 * unit + w * 0.4
    d.ellipse((cx - gap, cy - gap, cx + gap, cy + gap), fill=gap_color)
    r = 2.5 * unit
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=DOT)

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

    print("ok")


if __name__ == "__main__":
    main()
