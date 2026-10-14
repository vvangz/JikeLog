"""生成 App 图标：Android 启动图标（各密度 PNG）与 Windows 图标（.ico）。

图形与管理后台的 logo.svg 相同（24×24 网格：圆角文档、三行文字、右下角圆点），
改为咖色底、奶油白线条，便于在桌面与启动器上辨认。颜色取自设计令牌。

用法：python scripts/gen-app-icons.py（需要 Pillow）
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MOBILE = ROOT / "apps" / "mobile"

COFFEE = (0x6F, 0x4E, 0x37, 255)  # 主色（浅色主题）
CREAM = (0xFA, 0xF7, 0xF2, 255)  # 底色（浅色主题）

SIZE = 1024  # 母版边长
SS = 4  # 超采样倍数，缩小时抗锯齿


def master() -> Image.Image:
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 底：圆角正方形（与系统图标的视觉重量相近）
    d.rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.22), fill=COFFEE)

    # 24 单位网格居中缩放到边长的 62.5%
    unit = n * 0.625 / 24
    off = (n - 24 * unit) / 2

    def p(x: float, y: float) -> tuple[float, float]:
        return off + x * unit, off + y * unit

    w = max(1, round(1.5 * unit))  # 描边 1.5 单位

    # 圆角文档
    d.rounded_rectangle((*p(4, 3), *p(20, 21)), radius=3 * unit, outline=CREAM, width=w)

    # 三行文字（圆头端点：两端补圆）
    for y, x2 in ((8, 16), (12, 16), (16, 13)):
        a, b = p(8, y), p(x2, y)
        d.line((*a, *b), fill=CREAM, width=w)
        for cx, cy in (a, b):
            r = w / 2
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=CREAM)

    # 右下角圆点：先挖出咖色间隙，再画实心圆
    cx, cy = p(17, 17)
    gap = 2.5 * unit + w * 0.4
    d.ellipse((cx - gap, cy - gap, cx + gap, cy + gap), fill=COFFEE)
    r = 2.5 * unit
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=CREAM)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    img = master()

    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in android.items():
        out = MOBILE / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png"
        img.resize((px, px), Image.LANCZOS).save(out, optimize=True)

    ico = MOBILE / "windows" / "runner" / "resources" / "app_icon.ico"
    if ico.parent.is_dir():
        img.save(ico, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    print("ok")


if __name__ == "__main__":
    main()
