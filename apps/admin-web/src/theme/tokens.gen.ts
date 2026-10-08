// GENERATED CODE - DO NOT MODIFY BY HAND
// 来源：packages/design-tokens/tokens，修改令牌后运行 `pnpm tokens` 重新生成。

export const colors = {
  "light": {
    "primary": "#6F4E37",
    "onPrimary": "#FFFFFF",
    "primaryContainer": "#EDE0D4",
    "onPrimaryContainer": "#2B1D14",
    "background": "#FAF7F2",
    "surface": "#FFFFFF",
    "surfaceVariant": "#F2EDE6",
    "scrim": "#0000007A",
    "textPrimary": "#2A2420",
    "textSecondary": "#5E554D",
    "textDisabled": "#A89C8F",
    "border": "#D1C6B9",
    "divider": "#E6DED4",
    "success": "#2F7A4D",
    "onSuccess": "#FFFFFF",
    "successContainer": "#E4F2E9",
    "onSuccessContainer": "#1E4D31",
    "warning": "#93590A",
    "onWarning": "#FFFFFF",
    "warningContainer": "#FBF0DC",
    "onWarningContainer": "#5E3A08",
    "error": "#B3261E",
    "onError": "#FFFFFF",
    "errorContainer": "#FBE6E4",
    "onErrorContainer": "#6E1A15",
    "info": "#2F6596",
    "onInfo": "#FFFFFF",
    "infoContainer": "#E3EEF8",
    "onInfoContainer": "#1D4062"
  },
  "dark": {
    "primary": "#C8A27C",
    "onPrimary": "#2B1D14",
    "primaryContainer": "#5A3E2B",
    "onPrimaryContainer": "#EDE0D4",
    "background": "#171311",
    "surface": "#221C19",
    "surfaceVariant": "#2A2420",
    "scrim": "#000000A3",
    "textPrimary": "#EDE6DF",
    "textSecondary": "#D1C6B9",
    "textDisabled": "#7D7267",
    "border": "#5E554D",
    "divider": "#3F3832",
    "success": "#7CC59A",
    "onSuccess": "#10301D",
    "successContainer": "#1E4D31",
    "onSuccessContainer": "#E4F2E9",
    "warning": "#E5B567",
    "onWarning": "#3A2404",
    "warningContainer": "#5E3A08",
    "onWarningContainer": "#FBF0DC",
    "error": "#F2A39C",
    "onError": "#410E0B",
    "errorContainer": "#6E1A15",
    "onErrorContainer": "#FBE6E4",
    "info": "#93BDE4",
    "onInfo": "#0F2438",
    "infoContainer": "#1D4062",
    "onInfoContainer": "#E3EEF8"
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
