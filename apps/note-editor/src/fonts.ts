/**
 * 字体使用 App 自带的文件（apps/mobile/assets/fonts，与编辑器页面同在 flutter_assets 下）。
 * 在运行时注入 @font-face，避免构建时把 8MB 的字体内联进页面。
 */
const FONTS = [
  ['Space Grotesk', 'SpaceGrotesk-Regular.ttf', 400],
  ['Space Grotesk', 'SpaceGrotesk-Bold.ttf', 700],
  ['MiSans', 'MiSans-Regular.ttf', 400],
  ['MiSans', 'MiSans-Semibold.ttf', 600],
] as const;

export function fontFaceCss(base = '../fonts/'): string {
  return FONTS.map(
    ([family, file, weight]) =>
      `@font-face{font-family:'${family}';src:url('${base}${file}');font-weight:${weight};font-display:swap}`,
  ).join('\n');
}

export function installFonts(doc: Document = document): void {
  const style = doc.createElement('style');
  style.textContent = fontFaceCss();
  doc.head.append(style);
}
