// GENERATED CODE - DO NOT MODIFY BY HAND
// 来源：packages/design-tokens/tokens，修改令牌后运行 `pnpm tokens` 重新生成。

export const colors = {
  "light": {
    "primary": "#334AC0",
    "onPrimary": "#FFFFFF",
    "primaryContainer": "#E0E7FF",
    "onPrimaryContainer": "#131E54",
    "background": "#F6F8FC",
    "surface": "#FFFFFF",
    "surfaceVariant": "#ECF0F7",
    "scrim": "#0000007A",
    "textPrimary": "#1E2636",
    "textSecondary": "#4F5B70",
    "textDisabled": "#8E9BB0",
    "border": "#C5D0E0",
    "divider": "#DFE6F0",
    "success": "#1E7A4C",
    "onSuccess": "#FFFFFF",
    "successContainer": "#E3F5EC",
    "onSuccessContainer": "#145032",
    "warning": "#9A5B08",
    "onWarning": "#FFFFFF",
    "warningContainer": "#FDF3DF",
    "onWarningContainer": "#613A05",
    "error": "#BE2B25",
    "onError": "#FFFFFF",
    "errorContainer": "#FCE8E7",
    "onErrorContainer": "#751916",
    "info": "#1B6B8A",
    "onInfo": "#FFFFFF",
    "infoContainer": "#E2F2F7",
    "onInfoContainer": "#114459"
  },
  "dark": {
    "primary": "#8FA8FF",
    "onPrimary": "#131E54",
    "primaryContainer": "#263999",
    "onPrimaryContainer": "#E0E7FF",
    "background": "#0F141F",
    "surface": "#161D2B",
    "surfaceVariant": "#1E2636",
    "scrim": "#000000A3",
    "textPrimary": "#E8EEF7",
    "textSecondary": "#C5D0E0",
    "textDisabled": "#6B788E",
    "border": "#4F5B70",
    "divider": "#2D3648",
    "success": "#6FD0A0",
    "onSuccess": "#0B2D1C",
    "successContainer": "#145032",
    "onSuccessContainer": "#E3F5EC",
    "warning": "#ECC06B",
    "onWarning": "#382103",
    "warningContainer": "#613A05",
    "onWarningContainer": "#FDF3DF",
    "error": "#F49E97",
    "onError": "#450D0B",
    "errorContainer": "#751916",
    "onErrorContainer": "#FCE8E7",
    "info": "#7CC6DF",
    "onInfo": "#092633",
    "infoContainer": "#114459",
    "onInfoContainer": "#E2F2F7"
  }
} as const;

export type ThemeName = keyof typeof colors;
export type ColorTokens = Record<keyof typeof colors.light, string>;

export const tokens = {
  "font": {
    "family": {
      "latin": "Space Grotesk",
      "cjk": "MiSans"
    },
    "size": {
      "caption": 12,
      "body": 14,
      "bodyLarge": 16,
      "title": 18,
      "headline": 22,
      "display": 28
    },
    "weight": {
      "regular": 400,
      "medium": 500,
      "semibold": 600,
      "bold": 700
    },
    "lineHeight": {
      "tight": 1.25,
      "normal": 1.5,
      "relaxed": 1.7
    }
  },
  "spacing": {
    "xxs": 2,
    "xs": 4,
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 24,
    "xxl": 32
  },
  "radius": {
    "sm": 6,
    "md": 10,
    "lg": 16,
    "full": 999
  },
  "motion": {
    "duration": {
      "fast": 120,
      "normal": 200,
      "slow": 320
    }
  },
  "breakpoint": {
    "medium": 600,
    "expanded": 840,
    "large": 1200
  }
} as const;
