import fs from 'node:fs';
import path from 'node:path';

const outputDir = path.resolve('designs');

const dark = {
  board: '#17181D',
  boardAlt: '#121A24',
  screen: '#0E1319',
  panel: '#151B22',
  panelAlt: '#141B22',
  panelDeep: '#0F151B',
  outline: '#27313C',
  outlineStrong: '#31404D',
  text: '#E7EDF2',
  textSoft: '#D7DEE5',
  muted: '#7F92A3',
  mutedSoft: '#9AA9B8',
  signal: '#6EC7FF',
  accent: '#A78BFA',
  primary: '#A3FF12',
  onPrimary: '#09110A',
  successBg: '#132018',
  successStroke: '#285641',
  successText: '#E5FFF1',
  warningBg: '#291C12',
  warningStroke: '#A05A1B',
  warningText: '#FFD9A8',
  warningMuted: '#E8C9A2',
  danger: '#FF7A7A',
  idle: '#7F92A3',
};

const light = {
  board: '#F4F0E8',
  boardAlt: '#E8EEF3',
  screen: '#F3F0EA',
  panel: '#F7F9FC',
  panelAlt: '#E7EDF3',
  panelDeep: '#E7EDF3',
  outline: '#CDD6E0',
  outlineStrong: '#C7D0DA',
  text: '#10161D',
  textSoft: '#1A2430',
  muted: '#748292',
  mutedSoft: '#536170',
  signal: '#66C8FF',
  accent: '#8B5CF6',
  primary: '#B2FF2E',
  onPrimary: '#0F151B',
  successBg: '#EAF7E9',
  successStroke: '#7DCCA0',
  successText: '#10321F',
  warningBg: '#FFF2E6',
  warningStroke: '#F2B57E',
  warningText: '#8C4A18',
  warningMuted: '#9A693E',
  danger: '#D85C5C',
  idle: '#8E98A4',
};

const spacing = {
  micro: 4,
  compact: 8,
  tileY: 10,
  tileX: 12,
  stack: 12,
  card: 14,
  block: 16,
  screenX: 18,
  screenBottom: 18,
  screenTop: 28,
  insetWide: 30,
  section: 24,
  shell: 32,
};

const radius = {
  screen: 28,
  card: 14,
  tile: 12,
  control: 10,
  capsule: 8,
  pill: 999,
};

const boardShadow = {
  type: 'shadow',
  color: '#11182714',
  offset: { x: 0, y: 10 },
  blur: 24,
  spread: 0,
};

const cardShadow = {
  type: 'shadow',
  color: '#11182710',
  offset: { x: 0, y: 18 },
  blur: 42,
  spread: 0,
};

const darkCardShadow = {
  type: 'shadow',
  color: '#0B0F151C',
  offset: { x: 0, y: 22 },
  blur: 44,
  spread: 0,
};

const variables = {
  '--font-display': { type: 'string', value: 'JetBrains Mono' },
  '--font-body': { type: 'string', value: 'JetBrains Mono' },
  '--space-micro': { type: 'number', value: spacing.micro },
  '--space-compact': { type: 'number', value: spacing.compact },
  '--space-tile-y': { type: 'number', value: spacing.tileY },
  '--space-tile-x': { type: 'number', value: spacing.tileX },
  '--space-stack': { type: 'number', value: spacing.stack },
  '--space-card': { type: 'number', value: spacing.card },
  '--space-block': { type: 'number', value: spacing.block },
  '--space-screen-x': { type: 'number', value: spacing.screenX },
  '--space-screen-bottom': { type: 'number', value: spacing.screenBottom },
  '--space-screen-top': { type: 'number', value: spacing.screenTop },
  '--radius-screen': { type: 'number', value: radius.screen },
  '--radius-card': { type: 'number', value: radius.card },
  '--radius-tile': { type: 'number', value: radius.tile },
  '--radius-control': { type: 'number', value: radius.control },
  '--radius-capsule': { type: 'number', value: radius.capsule },
  '--radius-pill': { type: 'number', value: radius.pill },
};

function themedColor(name, darkValue, lightValue) {
  variables[name] = {
    type: 'color',
    value: [
      { value: darkValue, theme: { theme: 'dark' } },
      { value: lightValue, theme: { theme: 'light' } },
    ],
  };
}

themedColor('--color-board', dark.board, light.board);
themedColor('--color-board-alt', dark.boardAlt, light.boardAlt);
themedColor('--color-screen', dark.screen, light.screen);
themedColor('--color-panel', dark.panel, light.panel);
themedColor('--color-panel-alt', dark.panelAlt, light.panelAlt);
themedColor('--color-panel-deep', dark.panelDeep, light.panelDeep);
themedColor('--color-outline', dark.outline, light.outline);
themedColor('--color-outline-strong', dark.outlineStrong, light.outlineStrong);
themedColor('--color-text', dark.text, light.text);
themedColor('--color-text-soft', dark.textSoft, light.textSoft);
themedColor('--color-muted', dark.muted, light.muted);
themedColor('--color-muted-soft', dark.mutedSoft, light.mutedSoft);
themedColor('--color-signal', dark.signal, light.signal);
themedColor('--color-accent', dark.accent, light.accent);
themedColor('--color-primary', dark.primary, light.primary);
themedColor('--color-on-primary', dark.onPrimary, light.onPrimary);
themedColor('--color-success-surface', dark.successBg, light.successBg);
themedColor('--color-success-border', dark.successStroke, light.successStroke);
themedColor('--color-success-text', dark.successText, light.successText);
themedColor('--color-warning-surface', dark.warningBg, light.warningBg);
themedColor('--color-warning-border', dark.warningStroke, light.warningStroke);
themedColor('--color-warning-text', dark.warningText, light.warningText);
themedColor('--color-warning-muted', dark.warningMuted, light.warningMuted);
themedColor('--color-danger', dark.danger, light.danger);
themedColor('--color-idle', dark.idle, light.idle);

let idCounter = 0;

function id(prefix) {
  idCounter += 1;
  return `${prefix}-${idCounter}`;
}

function wrapText(content, maxChars) {
  if (!content || !maxChars || content.length <= maxChars) {
    return content;
  }

  return content
    .split('\n')
    .map((paragraph) => {
      const words = paragraph.split(/\s+/).filter(Boolean);
      if (words.length <= 1) {
        return paragraph;
      }

      const lines = [];
      let line = '';

      for (const word of words) {
        const next = line ? `${line} ${word}` : word;
        if (next.length <= maxChars) {
          line = next;
          continue;
        }
        if (line) {
          lines.push(line);
        }
        line = word;
      }

      if (line) {
        lines.push(line);
      }

      return lines.join('\n');
    })
    .join('\n');
}

function frame(options) {
  return {
    type: 'frame',
    id: id('frame'),
    name: options.name,
    width: options.width,
    height: options.height,
    fill: options.fill,
    stroke: options.stroke,
    cornerRadius: options.cornerRadius,
    effect: options.effect,
    padding: options.padding,
    gap: options.gap,
    layout: options.layout,
    justifyContent: options.justifyContent,
    alignItems: options.alignItems,
    clip: options.clip,
    theme: options.theme,
    x: options.x,
    y: options.y,
    opacity: options.opacity,
    children: options.children ?? [],
  };
}

function rect(options) {
  return {
    type: 'rectangle',
    id: id('rect'),
    name: options.name,
    width: options.width,
    height: options.height,
    fill: options.fill,
    stroke: options.stroke,
    cornerRadius: options.cornerRadius,
    effect: options.effect,
    x: options.x,
    y: options.y,
    opacity: options.opacity,
  };
}

function text(options) {
  return {
    type: 'text',
    id: id('text'),
    name: options.name ?? options.content,
    content: options.content,
    width: options.width,
    height: options.height,
    fill: options.fill ?? '$--color-text',
    fontFamily: options.fontFamily ?? '$--font-body',
    fontSize: options.fontSize,
    fontWeight: options.fontWeight,
    lineHeight: options.lineHeight,
    letterSpacing: options.letterSpacing,
    textAlign: options.textAlign,
    opacity: options.opacity,
  };
}

function boardCard(title, body, children = []) {
  return frame({
    name: title,
    width: 'fill_container',
    fill: '$--color-panel',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.card,
    padding: [spacing.card, spacing.card, spacing.card, spacing.card],
    layout: 'column',
    gap: spacing.compact,
    effect: boardShadow,
    children: [
      text({
        content: title,
        fontSize: 16,
        fontWeight: 'extrabold',
        lineHeight: 1.25,
      }),
      text({
        content: body,
        fontSize: 11,
        fontWeight: 'medium',
        fill: '$--color-muted',
        lineHeight: 1.5,
        width: 'fill_container',
      }),
      ...children,
    ],
  });
}

function stroke(fill, thickness = 1) {
  return {
    align: 'inside',
    thickness,
    fill,
  };
}

function pill(label, fillColor, textColor, width = undefined) {
  return frame({
    name: label,
    width,
    fill: fillColor,
    cornerRadius: radius.pill,
    padding: [6, 10, 6, 10],
    layout: 'row',
    gap: 0,
    children: [
      text({
        content: label,
        fontSize: 9,
        fontWeight: 'bold',
        fill: textColor,
        lineHeight: 1.2,
      }),
    ],
  });
}

function symbolGlyph(symbol, color, size = 12, width = undefined) {
  return text({
    content: symbol,
    width,
    fontSize: size,
    fontWeight: 'bold',
    fill: color,
    textAlign: 'center',
    lineHeight: 1.0,
  });
}

function iconSearch(color) {
  return frame({
    name: 'Search Icon',
    width: 14,
    height: 14,
    children: [
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Lens',
        x: 1,
        y: 1,
        width: 8,
        height: 8,
        stroke: stroke(color),
      },
      rect({
        name: 'Handle',
        x: 8,
        y: 9,
        width: 5,
        height: 1,
        fill: color,
        rotation: 45,
      }),
    ],
  });
}

function iconPlus(color, size = 18) {
  return frame({
    name: 'Plus Icon',
    width: size,
    height: size,
    children: [
      rect({
        name: 'Plus H',
        x: 3,
        y: Math.floor(size / 2) - 1,
        width: size - 6,
        height: 2,
        fill: color,
        cornerRadius: 1,
      }),
      rect({
        name: 'Plus V',
        x: Math.floor(size / 2) - 1,
        y: 3,
        width: 2,
        height: size - 6,
        fill: color,
        cornerRadius: 1,
      }),
    ],
  });
}

function iconFolder(color) {
  return frame({
    name: 'Folder Icon',
    width: 18,
    height: 18,
    children: [
      rect({
        name: 'Folder Tab',
        x: 2,
        y: 3,
        width: 7,
        height: 4,
        stroke: stroke(color),
        cornerRadius: 1,
      }),
      rect({
        name: 'Folder Body',
        x: 2,
        y: 6,
        width: 14,
        height: 9,
        stroke: stroke(color),
        cornerRadius: 2,
      }),
    ],
  });
}

function iconShield(color) {
  return frame({
    name: 'Shield Icon',
    width: 18,
    height: 20,
    children: [
      rect({
        name: 'Shield Crest',
        x: 5,
        y: 2,
        width: 8,
        height: 3,
        fill: color,
        cornerRadius: 2,
      }),
      rect({
        name: 'Shield Body',
        x: 4,
        y: 5,
        width: 10,
        height: 8,
        stroke: stroke(color),
        cornerRadius: 4,
      }),
      {
        type: 'path',
        id: id('path'),
        name: 'Shield Tail',
        width: 10,
        height: 6,
        x: 4,
        y: 11,
        fill: color,
        geometry: 'M5 6 L0 0 H10 Z',
      },
    ],
  });
}

function iconBadge(color) {
  return frame({
    name: 'Badge Icon',
    width: 18,
    height: 18,
    layout: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    children: [
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Badge Dot',
        width: 12,
        height: 12,
        fill: color,
      },
    ],
  });
}

function iconPhone(color) {
  return frame({
    name: 'Phone Icon',
    width: 18,
    height: 18,
    children: [
      rect({
        name: 'Phone Top',
        x: 10,
        y: 2,
        width: 4,
        height: 7,
        fill: color,
        cornerRadius: 2,
        rotation: 38,
      }),
      rect({
        name: 'Phone Bottom',
        x: 3,
        y: 9,
        width: 4,
        height: 7,
        fill: color,
        cornerRadius: 2,
        rotation: 38,
      }),
      rect({
        name: 'Phone Bridge',
        x: 6,
        y: 8,
        width: 7,
        height: 2,
        fill: color,
        cornerRadius: 1,
        rotation: 38,
      }),
    ],
  });
}

function iconChevronLeft(color) {
  return frame({
    name: 'Chevron Left',
    width: 12,
    height: 14,
    children: [
      {
        type: 'path',
        id: id('path'),
        name: 'Chevron Left Path',
        width: 12,
        height: 14,
        fill: color,
        geometry: 'M8.6 1 L10 2.4 L5 7 L10 11.6 L8.6 13 L2.2 7 Z',
      },
    ],
  });
}

function iconChevronRight(color) {
  return frame({
    name: 'Chevron Right',
    width: 12,
    height: 14,
    children: [
      {
        type: 'path',
        id: id('path'),
        name: 'Chevron Right Path',
        width: 12,
        height: 14,
        fill: color,
        geometry: 'M3.4 1 L1.9 2.4 L7 7 L1.9 11.6 L3.4 13 L9.8 7 Z',
      },
    ],
  });
}

function iconBuild(color) {
  return frame({
    name: 'Build Icon',
    width: 14,
    height: 14,
    children: [
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Tool Head',
        x: 1,
        y: 1,
        width: 4,
        height: 4,
        fill: color,
      },
      rect({
        name: 'Tool Neck',
        x: 4,
        y: 4,
        width: 3,
        height: 2,
        fill: color,
        rotation: 45,
      }),
      rect({
        name: 'Tool Handle',
        x: 6,
        y: 6,
        width: 7,
        height: 2,
        fill: color,
        cornerRadius: 1,
        rotation: 45,
      }),
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Handle End',
        x: 10,
        y: 10,
        width: 3,
        height: 3,
        stroke: stroke(color),
      },
    ],
  });
}

function iconGear(color) {
  return frame({
    name: 'Gear Icon',
    width: 18,
    height: 18,
    children: [
      rect({
        name: 'Tooth Top',
        x: 7,
        y: 1,
        width: 4,
        height: 3,
        fill: color,
        cornerRadius: 1,
      }),
      rect({
        name: 'Tooth Bottom',
        x: 7,
        y: 14,
        width: 4,
        height: 3,
        fill: color,
        cornerRadius: 1,
      }),
      rect({
        name: 'Tooth Left',
        x: 1,
        y: 7,
        width: 3,
        height: 4,
        fill: color,
        cornerRadius: 1,
      }),
      rect({
        name: 'Tooth Right',
        x: 14,
        y: 7,
        width: 3,
        height: 4,
        fill: color,
        cornerRadius: 1,
      }),
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Gear Ring',
        x: 4,
        y: 4,
        width: 10,
        height: 10,
        stroke: stroke(color),
      },
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Gear Core',
        x: 7,
        y: 7,
        width: 4,
        height: 4,
        fill: color,
      },
    ],
  });
}

function iconWave(color) {
  return frame({
    name: 'Wave Icon',
    width: 18,
    height: 18,
    layout: 'row',
    alignItems: 'end',
    gap: 2,
    children: [
      rect({ name: 'Bar 1', width: 3, height: 8, fill: color, cornerRadius: 2 }),
      rect({ name: 'Bar 2', width: 3, height: 14, fill: color, cornerRadius: 2 }),
      rect({ name: 'Bar 3', width: 3, height: 10, fill: color, cornerRadius: 2 }),
    ],
  });
}

function iconDots(color) {
  return frame({
    name: 'Dots Icon',
    width: 14,
    height: 14,
    layout: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    children: [
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Dot 1',
        width: 2,
        height: 2,
        fill: color,
      },
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Dot 2',
        width: 2,
        height: 2,
        fill: color,
      },
      {
        type: 'ellipse',
        id: id('ellipse'),
        name: 'Dot 3',
        width: 2,
        height: 2,
        fill: color,
      },
    ],
  });
}

function circleIconButton(children, accent = false) {
  return frame({
    name: 'Icon Action',
    width: 34,
    height: 34,
    fill: accent ? '$--color-primary' : '$--color-panel-deep',
    stroke: accent ? undefined : stroke('$--color-outline-strong'),
    cornerRadius: radius.pill,
    layout: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    children: Array.isArray(children) ? children : [children],
  });
}

function plainIconAction(children) {
  return frame({
    name: 'Plain Icon Action',
    width: 28,
    height: 28,
    layout: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    children: Array.isArray(children) ? children : [children],
  });
}

function statChip(accent, label, body) {
  return frame({
    name: label,
    width: 'fill_container',
    fill: '$--color-panel',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.tile,
    padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
    layout: 'row',
    gap: spacing.tileY,
    children: [
      rect({
        name: `${label} Accent`,
        width: 6,
        height: 24,
        fill: accent,
        cornerRadius: radius.pill,
      }),
      frame({
        name: `${label} Copy`,
        width: 'fill_container',
        layout: 'column',
        gap: 2,
        children: [
          text({
            content: label,
            fontSize: 10,
            fontWeight: 'bold',
            lineHeight: 1.2,
          }),
          text({
            content: body,
            fontSize: 9,
            fontWeight: 'medium',
            fill: '$--color-muted-soft',
            lineHeight: 1.3,
            width: 'fill_container',
          }),
        ],
      }),
    ],
  });
}

function actionCard(title, body, accent, iconNode) {
  return frame({
    name: title,
    width: 'fill_container',
    height: 100,
    fill: '$--color-panel',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.tile,
    padding: [spacing.tileX, spacing.tileX, spacing.tileX, spacing.tileX],
    layout: 'column',
    gap: 0,
    effect: cardShadow,
    children: [
      iconNode,
      frame({ name: 'Spacer', width: 1, height: 30, opacity: 0 }),
      text({
        content: title,
        fontSize: 12,
        fontWeight: 'bold',
        lineHeight: 1.2,
      }),
      frame({ name: 'Gap', width: 1, height: spacing.micro, opacity: 0 }),
      text({
        content: body,
        fontSize: 9,
        fontWeight: 'medium',
        fill: '$--color-muted',
        lineHeight: 1.35,
        width: 'fill_container',
      }),
    ],
  });
}

function smallButton(label, mode = 'filled', width = undefined) {
  const filled = mode === 'filled';
  const warning = mode === 'warning';
  return frame({
    name: label,
    width,
    fill: filled
      ? '$--color-primary'
      : warning
        ? '$--color-warning-surface'
        : '$--color-panel-deep',
    stroke: filled ? undefined : stroke(
      warning ? '$--color-warning-border' : '$--color-outline-strong',
    ),
    cornerRadius: radius.pill,
    padding: [9, 14, 9, 14],
    layout: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    children: [
      text({
        content: label,
        fontSize: 10,
        fontWeight: 'extrabold',
        fill: filled
          ? '$--color-on-primary'
          : warning
            ? '$--color-warning-text'
            : '$--color-text-soft',
      }),
    ],
  });
}

function iconButton(symbol, accent = false) {
  return circleIconButton(
    symbolGlyph(symbol, accent ? '$--color-on-primary' : '$--color-text-soft', 12),
    accent,
  );
}

function field(label, value, options = {}) {
  const contentWidth = options.contentWidth ?? 286;
  return frame({
    name: label,
    width: 'fill_container',
    fill: options.warning ? '$--color-warning-surface' : '$--color-panel-alt',
    stroke: stroke(options.warning ? '$--color-warning-border' : '$--color-outline'),
    cornerRadius: options.rounded ?? radius.control,
    padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
    layout: 'column',
    gap: 2,
    children: [
      text({
        content: label,
        fontSize: 9,
        fontWeight: 'medium',
        fill: options.warning ? '$--color-warning-muted' : '$--color-muted',
        width: contentWidth,
      }),
      text({
        content: options.wrapChars ? wrapText(value, options.wrapChars) : value,
        fontSize: options.valueFontSize ?? 10,
        fontWeight: 'medium',
        fill: options.warning ? '$--color-warning-text' : '$--color-text',
        lineHeight: 1.3,
        width: contentWidth,
      }),
    ],
  });
}

function helperText(content, warning = false, width = 286) {
  return text({
    content: wrapText(content, Math.max(20, Math.floor(width / 6.4))),
    fontSize: 10,
    fontWeight: 'medium',
    fill: warning ? '$--color-warning-text' : '$--color-muted-soft',
    lineHeight: 1.45,
    width,
  });
}

function divider() {
  return rect({
    name: 'Divider',
    width: 'fill_container',
    height: 1,
    fill: '$--color-outline',
  });
}

function listCard(title, subtitle, trailing, accent) {
  return frame({
    name: title,
    width: 'fill_container',
    fill: '$--color-panel',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.tile,
    padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
    layout: 'row',
    gap: spacing.tileY,
    children: [
      accent
        ? rect({
            name: `${title} Accent`,
            width: 6,
            height: 24,
            fill: accent,
            cornerRadius: radius.pill,
          })
        : rect({
            name: `${title} Accent Spacer`,
            width: 6,
            height: 24,
            fill: '$--color-panel',
          }),
      frame({
        name: `${title} Copy`,
        width: 'fill_container',
        layout: 'column',
        gap: 2,
        children: [
          text({
            content: title,
            fontSize: 11,
            fontWeight: 'bold',
            lineHeight: 1.2,
          }),
          text({
            content: subtitle,
            fontSize: 9,
            fontWeight: 'medium',
            fill: '$--color-muted',
            lineHeight: 1.35,
            width: 'fill_container',
          }),
          trailing
            ? text({
                content: trailing,
                fontSize: 8,
                fontWeight: 'bold',
                fill: '$--color-muted-soft',
                lineHeight: 1.2,
                width: 'fill_container',
              })
            : frame({
                name: 'Spacer',
                width: 1,
                height: 0,
                opacity: 0,
              }),
        ],
      }),
    ],
  });
}

function infoCard(title, body, accent, iconNode) {
  const contentWidth = 300;
  return frame({
    name: title,
    width: 'fill_container',
    fill: '$--color-panel',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.card,
    padding: [spacing.card, spacing.card, spacing.card, spacing.card],
    layout: 'column',
    alignItems: 'center',
    gap: spacing.tileY,
    effect: darkCardShadow,
    children: [
      frame({
        name: `${title} Badge`,
        width: 44,
        height: 44,
        fill: '$--color-panel-deep',
        stroke: stroke(accent),
        cornerRadius: radius.tile,
        layout: 'row',
        justifyContent: 'center',
        alignItems: 'center',
        children: [iconNode],
      }),
      text({
        content: wrapText(title, 28),
        fontSize: 14,
        fontWeight: 'bold',
        textAlign: 'center',
        lineHeight: 1.25,
        width: contentWidth,
      }),
      text({
        content: wrapText(body, 46),
        fontSize: 10,
        fontWeight: 'medium',
        textAlign: 'center',
        fill: '$--color-muted',
        lineHeight: 1.55,
        width: contentWidth,
      }),
    ],
  });
}

function warningCard(title, body, repo, buttonLabel) {
  const contentWidth = 300;
  return frame({
    name: title,
    width: 'fill_container',
    fill: '$--color-warning-surface',
    stroke: stroke('$--color-warning-border'),
    cornerRadius: radius.tile,
    padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
    layout: 'column',
    gap: spacing.compact,
    children: [
      text({
        content: wrapText(title, 30),
        fontSize: 10,
        fontWeight: 'bold',
        fill: '$--color-warning-text',
        width: contentWidth,
      }),
      text({
        content: wrapText(body, 46),
        fontSize: 10,
        fontWeight: 'medium',
        fill: '$--color-warning-text',
        lineHeight: 1.4,
        width: contentWidth,
      }),
      text({
        content: wrapText(repo, 46),
        fontSize: 9,
        fontWeight: 'bold',
        fill: '$--color-warning-muted',
        width: contentWidth,
      }),
      smallButton(buttonLabel, 'warning', 'fill_container'),
    ],
  });
}

function commandCard(command) {
  const commandWidth = 286;
  return frame({
    name: 'Approval Command',
    width: 'fill_container',
    fill: '$--color-panel',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.tile,
    padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
    layout: 'column',
    gap: spacing.compact,
    children: [
      frame({
        name: 'Command Header',
        width: 'fill_container',
        layout: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        children: [
          text({
            content: 'Run this command',
            fontSize: 10,
            fontWeight: 'bold',
            fill: '$--color-text-soft',
          }),
          smallButton('COPY', 'outlined'),
        ],
      }),
      frame({
        name: 'Command Box',
        width: 'fill_container',
        fill: '$--color-panel-deep',
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.control,
        padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
        layout: 'column',
        children: [
          text({
            content: wrapText(command, 40),
            fontSize: 9,
            fontWeight: 'medium',
            fill: '$--color-text-soft',
            width: commandWidth,
            lineHeight: 1.45,
          }),
        ],
      }),
    ],
  });
}

function searchBar(hint) {
  return frame({
    name: hint,
    width: 'fill_container',
    height: 40,
    fill: '$--color-panel-deep',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.control,
    padding: [0, spacing.tileX, 0, spacing.tileX],
    layout: 'row',
    alignItems: 'center',
    gap: spacing.compact,
    children: [
      iconSearch('$--color-muted'),
      text({
        content: hint,
        fontSize: 10,
        fontWeight: 'medium',
        fill: '$--color-muted',
        width: 'fill_container',
      }),
    ],
  });
}

function topHeader(title, subtitle, trailing) {
  return frame({
    name: title,
    width: 'fill_container',
    layout: 'row',
    justifyContent: 'space-between',
    alignItems: 'start',
    children: [
      frame({
        name: `${title} Copy`,
        width: 'fill_container',
        layout: 'column',
        gap: spacing.micro,
        children: [
          text({
            content: title,
            fontFamily: '$--font-display',
            fontSize: 24,
            fontWeight: 'extrabold',
            lineHeight: 1.1,
            letterSpacing: 0.6,
            width: 'fill_container',
          }),
          text({
            content: subtitle,
            fontSize: 10,
            fontWeight: 'medium',
            fill: '$--color-muted',
            lineHeight: 1.45,
            width: 'fill_container',
          }),
        ],
      }),
      trailing ?? frame({ name: 'Header Spacer', width: 1, height: 1, opacity: 0 }),
    ],
  });
}

function backHeader(title, trailing) {
  return frame({
    name: `${title} Back Header`,
    width: 'fill_container',
    layout: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    children: [
      frame({
        name: `${title} Back Copy`,
        width: 'fill_container',
        layout: 'row',
        alignItems: 'center',
        gap: spacing.compact,
        children: [
          iconChevronLeft('$--color-text-soft'),
          text({
            content: title,
            fontFamily: '$--font-display',
            fontSize: 24,
            fontWeight: 'extrabold',
            lineHeight: 1.1,
            letterSpacing: 0.6,
            width: 'fill_container',
          }),
        ],
      }),
      trailing ?? frame({ name: 'Header Spacer', width: 1, height: 1, opacity: 0 }),
    ],
  });
}

function sectionLabel(label) {
  return text({
    content: label,
    fontSize: 10,
    fontWeight: 'extrabold',
    fill: '$--color-muted',
    letterSpacing: 0.3,
  });
}

function phoneShell(name, title, subtitle, children, options = {}) {
  const trailing = options.trailing ?? undefined;
  return frame({
    name,
    width: 390,
    height: 844,
    fill: '$--color-screen',
    stroke: stroke('$--color-outline'),
    cornerRadius: radius.screen,
    padding: [spacing.screenTop, spacing.screenX, spacing.screenBottom, spacing.screenX],
    layout: 'column',
    gap: spacing.card,
    clip: true,
    theme: { theme: options.theme ?? 'dark' },
    effect: darkCardShadow,
    children: [
      topHeader(title, subtitle, trailing),
      ...children,
    ],
  });
}

function connectPhone() {
  return phoneShell(
    'Home Connect Bridge',
    'CONNECT BRIDGE',
    'Connect your Bridge to get started.',
    [
      infoCard(
        'Welcome to Omni Code',
        'Run the Bridge service on your computer, then authorize this device.',
        '$--color-signal',
        iconShield('$--color-signal'),
      ),
      frame({
        name: 'Bridge Config',
        width: 'fill_container',
        fill: '$--color-panel',
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.tile,
        padding: [spacing.tileX, spacing.tileX, spacing.tileX, spacing.tileX],
        layout: 'column',
        gap: spacing.compact,
        children: [
          frame({
            name: 'Bridge Header',
            width: 'fill_container',
            layout: 'row',
            justifyContent: 'space-between',
            alignItems: 'center',
            children: [
              text({
                content: 'Bridge URL',
                fontSize: 10,
                fontWeight: 'bold',
                fill: '$--color-text-soft',
              }),
              smallButton('SAVE', 'filled'),
            ],
          }),
          field('Bridge endpoint', 'http://127.0.0.1:8787'),
          helperText('Client uses the configured bridge URL or ECHO_MATE_BRIDGE_URL.'),
        ],
      }),
      warningCard(
        'Download Bridge service',
        'Get the service from GitHub on the computer hosting your local projects.',
        'github.com/omni-stream-ai/omni-code-bridge',
        'DOWNLOAD BRIDGE',
      ),
      smallButton('AUTHORIZE THIS DEVICE', 'filled', 'fill_container'),
      text({
        content: 'Next: approval screen',
        fontSize: 10,
        fontWeight: 'medium',
        fill: '$--color-muted',
        textAlign: 'center',
        lineHeight: 1.4,
        width: 'fill_container',
      }),
    ],
  );
}

function waitingPhone() {
  return phoneShell(
    'Home Waiting Approval',
    'AUTHORIZATION',
    'Remote approval handshake for a new client.',
    [
      frame({
        name: 'Back',
        width: 'fill_container',
        layout: 'row',
        alignItems: 'center',
        gap: spacing.compact,
        children: [
          iconChevronLeft('$--color-muted'),
          text({
            content: 'Back to welcome',
            fontSize: 10,
            fontWeight: 'bold',
            fill: '$--color-muted',
          }),
        ],
      }),
      infoCard(
        'Waiting for approval',
        'Approve this request on the Bridge host. The app continues automatically.',
        '$--color-signal',
        iconShield('$--color-signal'),
      ),
      smallButton('DOWNLOAD BRIDGE', 'warning', 'fill_container'),
      commandCard('omni-code-bridge client-auth approve --request-id req_9f3d'),
      frame({
        name: 'Listening Row',
        width: 'fill_container',
        layout: 'row',
        justifyContent: 'center',
        alignItems: 'center',
        gap: spacing.compact,
        children: [
          rect({
            name: 'Listening Dot',
            width: 8,
            height: 8,
            fill: '$--color-signal',
            cornerRadius: radius.pill,
          }),
          text({
            content: 'Listening for approval...',
            fontSize: 10,
            fontWeight: 'medium',
            fill: '$--color-muted',
          }),
        ],
      }),
      smallButton('REQUEST AGAIN', 'outlined', 'fill_container'),
    ],
  );
}

function dashboardPhone() {
  return phoneShell(
    'Home Dashboard',
    'OMNI CODE',
    'Remote agent cockpit',
    [
      frame({
        name: 'Action Row',
        width: 'fill_container',
        layout: 'row',
        gap: spacing.tileY,
        children: [
          actionCard('New session', 'Add local codebase', '$--color-signal', iconPlus('$--color-signal')),
          actionCard('Projects', '3 projects', '$--color-accent', iconFolder('$--color-accent')),
        ],
      }),
      sectionLabel('RECENT SESSIONS'),
      statChip('$--color-success-text', 'Tunnel online', '2 agents active · approvals routed to mobile bridge'),
      listCard(
        'Flutter UI refactor',
        'codex · reply ready',
        'omni-code · Idle',
        '$--color-success-text',
      ),
      listCard(
        'Release workflow failed',
        'help me inspect why the latest build failed',
        'mobile-client · Running',
        '$--color-primary',
      ),
      listCard(
        'Approve cargo run',
        'Need permission to run cargo test on omni-code-bridge.',
        'bridge-ops · Awaiting approval',
        '$--color-warning-text',
      ),
      smallButton('LOAD MORE SESSIONS', 'outlined', 'fill_container'),
    ],
    {
      trailing: circleIconButton(iconGear('$--color-text-soft')),
    },
  );
}

function projectsPhone() {
  return frame({
    ...phoneShell('Projects List', '', '', [], {}),
    children: [
      backHeader('PROJECTS', circleIconButton(iconPlus('$--color-on-primary'), true)),
      searchBar('Search project name or path'),
      text({
        content: '3 projects',
        fontSize: 10,
        fontWeight: 'medium',
        fill: '$--color-muted',
      }),
      listCard('omni-code', '/home/junjie/code/omni-code', 'updated 13:08', undefined),
      listCard('omni-code-bridge', '/home/junjie/code/omni-code-bridge', 'updated 11:12', undefined),
      listCard('notes', '/home/junjie/docs/engineering/notes', 'updated yesterday', undefined),
    ],
  });
}

function projectSessionsPhone() {
  return frame({
    ...phoneShell(
    'Project Sessions',
    'SESSIONS',
    '',
    [
      frame({
        name: 'Project Summary',
        width: 'fill_container',
        fill: '$--color-panel',
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.card,
        padding: [spacing.card, spacing.card, spacing.card, spacing.card],
        layout: 'column',
        gap: spacing.compact,
        children: [
          text({
            content: 'omni-code',
            fontSize: 13,
            fontWeight: 'extrabold',
          }),
          text({
            content: '/home/junjie/code/omni-code',
            fontSize: 10,
            fontWeight: 'medium',
            fill: '$--color-muted',
          }),
        ],
      }),
      searchBar('Search session title or summary'),
      listCard(
        'Design system polish',
        'codex · Running',
        'updated 2026-05-10 12:41',
        '$--color-primary',
      ),
      listCard(
        'Client auth flow',
        'codex · Awaiting approval',
        'updated 2026-05-10 11:03',
        '$--color-warning-text',
      ),
      listCard(
        'Web persistence bug',
        'claude · Idle',
        'updated 2026-05-09 20:14',
        '$--color-success-text',
      ),
      smallButton('LOAD MORE SESSIONS', 'outlined', 'fill_container'),
    ],
    {
      trailing: frame({
        name: 'Header Actions',
        layout: 'row',
        gap: spacing.compact,
        children: [
          circleIconButton(iconPlus('$--color-on-primary'), true),
          circleIconButton(symbolGlyph('↻', '$--color-text-soft', 12)),
        ],
      }),
    },
  ),
    children: [
      backHeader(
        'SESSIONS',
        frame({
          name: 'Header Actions',
          layout: 'row',
          gap: spacing.compact,
          children: [
            circleIconButton(iconPlus('$--color-on-primary'), true),
            circleIconButton(symbolGlyph('↻', '$--color-text-soft', 12)),
          ],
        }),
      ),
      ...phoneShell(
        'Project Sessions Content',
        '',
        '',
        [
          frame({
            name: 'Project Summary',
            width: 'fill_container',
            fill: '$--color-panel',
            stroke: stroke('$--color-outline'),
            cornerRadius: radius.card,
            padding: [spacing.card, spacing.card, spacing.card, spacing.card],
            layout: 'column',
            gap: spacing.compact,
            children: [
              text({ content: 'omni-code', fontSize: 13, fontWeight: 'extrabold' }),
              text({
                content: '/home/junjie/code/omni-code',
                fontSize: 10,
                fontWeight: 'medium',
                fill: '$--color-muted',
              }),
            ],
          }),
          searchBar('Search session title or summary'),
          listCard('Design system polish', 'codex · Running', 'updated 2026-05-10 12:41', '$--color-primary'),
          listCard('Client auth flow', 'codex · Awaiting approval', 'updated 2026-05-10 11:03', '$--color-warning-text'),
          listCard('Web persistence bug', 'claude · Idle', 'updated 2026-05-09 20:14', '$--color-success-text'),
          smallButton('LOAD MORE SESSIONS', 'outlined', 'fill_container'),
        ],
        {},
      ).children.slice(1),
    ],
  });
}

function bubble(body, fillColor, textColor, width, assistant = false) {
  const contentWidth =
    typeof width === 'number' ? Math.max(120, width - (spacing.card * 2)) : 240;
  return frame({
    name: assistant ? 'Assistant Bubble' : 'User Bubble',
    width,
    fill: fillColor,
    stroke: assistant ? stroke('$--color-outline') : undefined,
    cornerRadius: radius.card + 4,
    padding: [spacing.card, spacing.card, spacing.card, spacing.card],
    layout: 'column',
    gap: spacing.compact,
    children: [
      text({
        content: wrapText(body, Math.max(18, Math.floor(contentWidth / 6.2))),
        fontSize: 10,
        fontWeight: 'medium',
        fill: textColor,
        lineHeight: 1.45,
        width: contentWidth,
      }),
      assistant
        ? smallButton('PLAY', 'outlined', 66)
        : frame({ name: 'Bubble Spacer', width: 1, height: 0, opacity: 0 }),
    ],
  });
}

function toolActivityChip(count) {
  return frame({
    name: 'Tool Activity',
    layout: 'row',
    alignItems: 'center',
    gap: spacing.micro,
    fill: '$--color-panel-deep',
    stroke: stroke('$--color-outline-strong'),
    cornerRadius: radius.pill,
    padding: [5, 10, 5, 10],
    children: [
      iconBuild('$--color-muted-soft'),
      text({
        content: 'TOOL ACTIVITY',
        fontSize: 9,
        fontWeight: 'bold',
        fill: '$--color-muted-soft',
      }),
      text({
        content: `${count}`,
        fontSize: 9,
        fontWeight: 'bold',
        fill: '$--color-muted',
      }),
    ],
  });
}

function sessionDetailPhone() {
  return frame({
    ...phoneShell('Session Detail', '', '', [], {}),
    children: [
      backHeader('FLUTTER UI REFACTOR', plainIconAction(iconPhone('$--color-text-soft'))),
      frame({
        name: 'Top Banner',
        width: 'fill_container',
        fill: '$--color-warning-surface',
        stroke: stroke('$--color-warning-border'),
        cornerRadius: radius.card,
        padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
        children: [
          text({
            content: 'Agent awaiting permission · cargo test',
            fontSize: 10,
            fontWeight: 'bold',
            fill: '$--color-warning-text',
          }),
        ],
      }),
      frame({
        name: 'Conversation Area',
        width: 'fill_container',
        height: 460,
        fill: '$--color-panel',
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.card,
        padding: [spacing.card, spacing.card, spacing.card, spacing.card],
        layout: 'column',
        gap: spacing.tileY,
        children: [
          bubble(
            'Help me inspect why the latest build failed after the release workflow change.',
            '$--color-primary',
            '$--color-on-primary',
            226,
          ),
          toolActivityChip(12),
          bubble(
            'I traced it to the release job using an unsigned APK path. Next I will patch the workflow and re-run checks.',
            '$--color-panel-deep',
            '$--color-text',
            268,
            true,
          ),
          frame({
            name: 'Approval Card',
            width: 'fill_container',
            fill: '$--color-warning-surface',
            stroke: stroke('$--color-warning-border'),
            cornerRadius: radius.card,
            padding: [spacing.tileY, spacing.tileX, spacing.tileY, spacing.tileX],
            layout: 'column',
            gap: spacing.compact,
            children: [
              text({
                content: 'Awaiting approval',
                fontSize: 10,
                fontWeight: 'bold',
                fill: '$--color-warning-text',
              }),
              text({
                content: wrapText(
                  'Purpose: run flutter analyze outside the sandbox to verify the release fix.',
                  42,
                ),
                fontSize: 10,
                fontWeight: 'medium',
                fill: '$--color-warning-text',
                lineHeight: 1.4,
                width: 286,
              }),
              frame({
                name: 'Approval Actions',
                width: 'fill_container',
                layout: 'row',
                gap: spacing.compact,
                children: [
                  smallButton('APPROVE', 'filled'),
                  smallButton('REJECT', 'outlined'),
                ],
              }),
            ],
          }),
        ],
      }),
      frame({
        name: 'Composer',
        width: 'fill_container',
        fill: '$--color-screen',
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.card,
        padding: [spacing.card, spacing.card, spacing.card, spacing.card],
        layout: 'column',
        gap: spacing.stack,
        children: [
          field(
            'Message',
            'Enter a task, for example: Help me inspect why the latest build failed',
            { rounded: radius.control, contentWidth: 270, valueFontSize: 9 },
          ),
          frame({
            name: 'Composer Actions',
            width: 'fill_container',
            layout: 'row',
            gap: spacing.tileY,
            children: [
              smallButton('VOICE INPUT', 'outlined', 'fill_container'),
              smallButton('SEND', 'filled', 'fill_container'),
            ],
          }),
        ],
      }),
    ],
  });
}

function switchRow(label, active = false) {
  return frame({
    name: label,
    width: 'fill_container',
    layout: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    children: [
      text({
        content: label,
        fontSize: 11,
        fontWeight: 'medium',
        lineHeight: 1.25,
      }),
      frame({
        name: `${label} Toggle`,
        width: 44,
        height: 24,
        fill: active ? '$--color-primary' : '$--color-panel-deep',
        stroke: active ? undefined : stroke('$--color-outline'),
        cornerRadius: radius.pill,
        layout: 'row',
        justifyContent: active ? 'end' : 'start',
        alignItems: 'center',
        padding: [2, 2, 2, 2],
        children: [
          rect({
            name: 'Thumb',
            width: 20,
            height: 20,
            fill: active ? '$--color-on-primary' : '$--color-muted-soft',
            cornerRadius: radius.pill,
          }),
        ],
      }),
    ],
  });
}

function labeledRow(label, value) {
  return frame({
    name: label,
    width: 'fill_container',
    height: 40,
    layout: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    children: [
      text({
        content: label,
        fontSize: 10,
        fontWeight: 'medium',
        fill: '$--color-muted',
      }),
      text({
        content: value,
        fontSize: 10,
        fontWeight: 'bold',
        fill: '$--color-text',
      }),
    ],
  });
}

function sectionCard(title, children, options = {}) {
  return frame({
    name: title,
    width: 'fill_container',
    layout: 'column',
    gap: spacing.micro,
    children: [
      sectionLabel(title),
      frame({
        name: `${title} Surface`,
        width: 'fill_container',
        fill: '$--color-panel',
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.card,
        padding: [spacing.card, spacing.card, spacing.card, spacing.card],
        layout: 'column',
        gap: options.gap ?? spacing.compact,
        effect: cardShadow,
        children,
      }),
    ],
  });
}

function settingsPhone() {
  return frame({
    ...phoneShell(
    'Settings Screen',
    'SETTINGS',
    '',
    [
      frame({ name: 'Placeholder', width: 1, height: 0, opacity: 0 }),
    ],
    {
      trailing: smallButton('SAVE', 'filled', 72),
    },
  ),
    children: [
      backHeader('SETTINGS', smallButton('SAVE', 'filled', 72)),
      sectionCard('SPEECH', [
        frame({
          name: 'Speech Row',
          width: 'fill_container',
          layout: 'row',
          alignItems: 'center',
          gap: spacing.stack,
          children: [
            frame({
              name: 'Speech Icon Box',
              width: 32,
              height: 32,
              fill: '$--color-panel-deep',
              cornerRadius: radius.control,
              layout: 'row',
              justifyContent: 'center',
              alignItems: 'center',
              children: [iconWave('$--color-signal')],
            }),
            text({
              content: 'SPEECH',
              fontSize: 12,
              fontWeight: 'extrabold',
              width: 'fill_container',
            }),
            iconChevronRight('$--color-text-soft'),
          ],
        }),
      ], { gap: spacing.compact }),
      sectionCard('AI APPROVAL', [
        switchRow('Enable AI approval', true),
        field('Base URL', 'https://api.openai.com/v1'),
        field('API key', 'sk-•••••••••••••••'),
        field('Model', 'gpt-4.1-mini'),
        field('Max risk', 'medium'),
      ]),
      sectionCard('REPLY BEHAVIOR', [
        switchRow('Auto speak replies', true),
        switchRow('Compress assistant replies', false),
        field('Notification preview max chars', '160'),
      ]),
      sectionCard('SYSTEM', [
        field('Bridge URL', 'http://127.0.0.1:8787'),
        field('Client ID', 'mobile-omni-code-8a1d'),
        field('Language', 'English'),
        field('Theme mode', 'System'),
      ]),
      sectionCard('APP UPDATE', [
        labeledRow('Current version', 'v0.2.1-beta.1'),
        labeledRow('Update manifest', 'GitHub releases'),
        smallButton('CHECK FOR UPDATE', 'outlined', 'fill_container'),
      ]),
    ],
  });
}

function speechSettingsPhone() {
  return frame({
    ...phoneShell(
    'Speech Settings Screen',
    'SPEECH',
    '',
    [
      frame({ name: 'Placeholder', width: 1, height: 0, opacity: 0 }),
    ],
    {
      trailing: smallButton('SAVE', 'filled', 72),
    },
  ),
    children: [
      backHeader('SPEECH', smallButton('SAVE', 'filled', 72)),
      sectionCard('SPEECH', [
        field('TTS Provider', 'System / Zhipu'),
        helperText('System voice stays preferred where the platform supports it.'),
        field('ASR Provider', 'System / Zhipu / Whisper / Tencent Streaming'),
        helperText('macOS and Linux availability hints are surfaced inline in the screen.'),
      ]),
      sectionCard('ZHIPU API', [
        field('API key', 'zhipu-•••••••••••'),
      ]),
      sectionCard('WHISPER API', [
        field('API key', 'openai-•••••••••••'),
        field('Base URL', 'https://api.openai.com/v1'),
      ]),
      sectionCard('TENCENT CLOUD STREAMING ASR', [
        field('App ID', '1000-2000-3000'),
        field('Secret ID', 'AKID••••••••'),
        field('Secret Key', '••••••••••••••'),
      ]),
    ],
  });
}

function swatch(label, variableName) {
  return frame({
    name: label,
    width: 'fill_container',
    layout: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    children: [
      frame({
        name: `${label} Copy`,
        width: 'fill_container',
        layout: 'column',
        gap: 2,
        children: [
          text({
            content: label,
            fontSize: 10,
            fontWeight: 'bold',
          }),
          text({
            content: variableName,
            fontSize: 9,
            fontWeight: 'medium',
            fill: '$--color-muted-soft',
          }),
        ],
      }),
      rect({
        name: `${label} Swatch`,
        width: 48,
        height: 28,
        fill: variableName,
        stroke: stroke('$--color-outline'),
        cornerRadius: radius.control,
      }),
    ],
  });
}

function dualSwatch(label, darkHex, lightHex) {
  return frame({
    name: label,
    width: 'fill_container',
    layout: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    children: [
      frame({
        name: `${label} Copy`,
        width: 'fill_container',
        layout: 'column',
        gap: 2,
        children: [
          text({ content: label, fontSize: 10, fontWeight: 'bold' }),
          text({
            content: `${darkHex} / ${lightHex}`,
            fontSize: 9,
            fontWeight: 'medium',
            fill: '$--color-muted-soft',
          }),
        ],
      }),
      frame({
        name: `${label} Swatches`,
        layout: 'row',
        gap: 6,
        children: [
          rect({
            name: `${label} Dark`,
            width: 22,
            height: 22,
            fill: darkHex,
            stroke: stroke('#27313C'),
            cornerRadius: 6,
          }),
          rect({
            name: `${label} Light`,
            width: 22,
            height: 22,
            fill: lightHex,
            stroke: stroke('#CDD6E0'),
            cornerRadius: 6,
          }),
        ],
      }),
    ],
  });
}

function typographySpec(label, size, weight, role) {
  return frame({
    name: label,
    width: 'fill_container',
    layout: 'column',
    gap: 2,
    children: [
      text({
        content: label,
        fontFamily: '$--font-display',
        fontSize: size,
        fontWeight: weight,
        lineHeight: 1.2,
      }),
      text({
        content: role,
        fontSize: 9,
        fontWeight: 'medium',
        fill: '$--color-muted-soft',
      }),
    ],
  });
}

function previewPhone(themeName) {
  const palette = themeName === 'light' ? light : dark;
  const surface = palette.panel;
  const surfaceDeep = palette.panelDeep;
  const outline = palette.outline;
  const textColor = palette.text;
  const muted = palette.muted;
  const signal = palette.signal;
  const accent = palette.accent;
  const primary = palette.primary;
  const onPrimary = palette.onPrimary;
  const success = palette.successText;
  const warningSurface = palette.warningBg;
  const warningText = palette.warningText;
  const warningBorder = palette.warningStroke;
  return {
    type: 'frame',
    id: id('frame'),
    name: `${themeName} Preview`,
    width: 332,
    height: 612,
    fill: palette.screen,
    stroke: stroke(outline),
    cornerRadius: 26,
    padding: [14, 14, 14, 14],
    layout: 'column',
    gap: 12,
    children: [
      frame({
        name: 'Preview Header',
        width: 'fill_container',
        layout: 'row',
        justifyContent: 'space-between',
        alignItems: 'start',
        children: [
          frame({
            name: 'Header Copy',
            width: 'fill_container',
            layout: 'column',
            gap: 4,
            children: [
              text({
                content: 'OMNI CODE',
                fontFamily: '$--font-display',
                fontSize: 12,
                fontWeight: 'bold',
                fill: textColor,
                width: 'fill_container',
              }),
              text({
                content: 'Remote agent cockpit',
                fontSize: 8,
                fontWeight: 'medium',
                fill: muted,
              }),
            ],
          }),
          pill(themeName.toUpperCase(), surfaceDeep, signal, 48),
        ],
      }),
      {
        type: 'frame',
        id: id('frame'),
        name: 'Status',
        width: 'fill_container',
        fill: surface,
        stroke: stroke(outline),
        cornerRadius: 12,
        padding: [10, 12, 10, 12],
        layout: 'row',
        gap: 10,
        children: [
          rect({ name: 'Accent', width: 6, height: 24, fill: success, cornerRadius: 999 }),
          frame({
            name: 'Status Copy',
            width: 'fill_container',
            layout: 'column',
            gap: 2,
            children: [
              text({ content: 'Tunnel online', fontSize: 10, fontWeight: 'bold', fill: textColor }),
              text({ content: '2 agents active · approvals routed to mobile bridge', fontSize: 8, fontWeight: 'medium', fill: muted }),
            ],
          }),
        ],
      },
      {
        type: 'frame',
        id: id('frame'),
        name: 'Action Row',
        width: 'fill_container',
        layout: 'row',
        gap: 10,
        children: [
          {
            type: 'frame',
            id: id('frame'),
            name: 'New Session',
            width: 'fill_container',
            height: 78,
            fill: surface,
            stroke: stroke(outline),
            cornerRadius: 12,
            padding: [12, 12, 12, 12],
            layout: 'column',
            children: [
              iconPlus(signal),
              frame({ name: 'Spacer', width: 1, height: 20, opacity: 0 }),
              text({ content: 'New session', fontSize: 10, fontWeight: 'bold', fill: textColor }),
              text({ content: 'spawn', fontSize: 8, fontWeight: 'medium', fill: muted }),
            ],
          },
          {
            type: 'frame',
            id: id('frame'),
            name: 'Projects',
            width: 'fill_container',
            height: 78,
            fill: surface,
            stroke: stroke(outline),
            cornerRadius: 12,
            padding: [12, 12, 12, 12],
            layout: 'column',
            children: [
              iconFolder(accent),
              frame({ name: 'Spacer', width: 1, height: 20, opacity: 0 }),
              text({ content: 'Projects', fontSize: 10, fontWeight: 'bold', fill: textColor }),
              text({ content: 'watch 07', fontSize: 8, fontWeight: 'medium', fill: muted }),
            ],
          },
        ],
      },
      {
        type: 'frame',
        id: id('frame'),
        name: 'Warning Row',
        width: 'fill_container',
        fill: warningSurface,
        stroke: stroke(warningBorder),
        cornerRadius: 12,
        padding: [10, 12, 10, 12],
        layout: 'column',
        gap: 2,
        children: [
          text({ content: 'approval / high risk', fontSize: 10, fontWeight: 'bold', fill: warningText }),
          text({ content: 'Need permission to run flutter analyze on omni-code-client.', fontSize: 8, fontWeight: 'medium', fill: warningText, width: 'fill_container' }),
          text({ content: 'bridge · Awaiting approval', fontSize: 7, fontWeight: 'bold', fill: palette.warningMuted }),
        ],
      },
      {
        type: 'frame',
        id: id('frame'),
        name: 'Session Row',
        width: 'fill_container',
        fill: surface,
        stroke: stroke(outline),
        cornerRadius: 12,
        padding: [10, 12, 10, 12],
        layout: 'row',
        gap: 10,
        children: [
          rect({ name: 'Accent', width: 6, height: 24, fill: success, cornerRadius: 999 }),
          frame({
            name: 'Copy',
            width: 'fill_container',
            layout: 'column',
            gap: 2,
            children: [
              text({ content: 'Flutter UI refactor', fontSize: 10, fontWeight: 'bold', fill: textColor }),
              text({ content: 'codex · reply ready', fontSize: 8, fontWeight: 'medium', fill: muted }),
              text({ content: 'omni-code · Idle', fontSize: 7, fontWeight: 'bold', fill: palette.mutedSoft }),
            ],
          }),
        ],
      },
      {
        type: 'frame',
        id: id('frame'),
        name: 'CTA',
        width: 'fill_container',
        fill: primary,
        cornerRadius: 999,
        padding: [9, 14, 9, 14],
        layout: 'row',
        justifyContent: 'center',
        alignItems: 'center',
        children: [
          text({ content: 'NEW SESSION', fontSize: 9, fontWeight: 'extrabold', fill: onPrimary }),
        ],
      },
    ],
  };
}

function buildThemeDocument() {
  return {
    version: '1.0.0',
    themes: { theme: ['dark', 'light'] },
    variables,
    children: [
      frame({
        name: 'Omni Code Theme From Code',
        width: 2260,
        height: 2120,
        fill: '$--color-board',
        theme: { theme: 'light' },
        padding: [72, 72, 72, 72],
        layout: 'column',
        gap: 40,
        children: [
          frame({
            name: 'Theme Header',
            width: 'fill_container',
            layout: 'row',
            justifyContent: 'space-between',
            alignItems: 'start',
            children: [
              frame({
                name: 'Header Copy',
                width: 1100,
                layout: 'column',
                gap: spacing.compact,
                children: [
                  pill('UI', '$--color-primary', '$--color-on-primary', 46),
                  text({
                    content: 'Omni Code / Theme Board',
                    fontFamily: '$--font-display',
                    fontSize: 34,
                    fontWeight: 'extrabold',
                    lineHeight: 1.05,
                  }),
                  text({
                    content: 'Derived from lib/src/theme/app_colors.dart, app_spacing.dart, app_theme.dart, and the live screen composition in Home, Projects, Sessions, and Settings.',
                    fontSize: 13,
                    fontWeight: 'medium',
                    fill: '$--color-muted',
                    lineHeight: 1.55,
                    width: 940,
                  }),
                ],
              }),
              boardCard(
                'Live Sources',
                'The board follows code-first inputs rather than legacy manual design sources.',
                [
                  helperText('lib/src/theme/app_colors.dart'),
                  helperText('lib/src/theme/app_spacing.dart'),
                  helperText('lib/src/theme/app_theme.dart'),
                  helperText('lib/src/screens/home_screen.dart'),
                  helperText('lib/src/screens/project_detail_screen.dart'),
                  helperText('lib/src/screens/session_detail_screen.dart'),
                  helperText('lib/src/screens/settings_screen.dart'),
                  helperText('lib/src/screens/speech_settings_screen.dart'),
                ],
              ),
            ],
          }),
          frame({
            name: 'Preview Row',
            width: 'fill_container',
            layout: 'row',
            gap: 32,
            alignItems: 'start',
            children: [
              previewPhone('dark'),
              previewPhone('light'),
              frame({
                name: 'Theme Notes',
                width: 650,
                layout: 'column',
                gap: spacing.card,
                children: [
                  boardCard(
                    'Theme DNA',
                    'The app reads as a remote operations console: mono typography, layered steel surfaces, neon-green primary actions, and blue-violet secondary accents.',
                    [
                      statChip('$--color-primary', 'Primary action', 'Solid confirm, send, authorize, and new-session surfaces'),
                      statChip('$--color-signal', 'Signal accent', 'Sync, bridge, and live session telemetry'),
                      statChip('$--color-accent', 'Project accent', 'Project browsing and secondary navigation emphasis'),
                      statChip('$--color-warning-text', 'Approval state', 'Awaiting permission, downloads, and blocked actions'),
                    ],
                  ),
                  boardCard(
                    'Layout Rules',
                    'The spacing and radius scale maps directly to AppSpacing and AppTheme.',
                    [
                      helperText('Screen shell: 28 / 18 / 18 / 18'),
                      helperText('Card padding: 14 · dense row: 10 / 12'),
                      helperText('Radii: 28 / 14 / 12 / 10 / 8 / 999'),
                      helperText('Content max width: 620 in Flutter, previewed here as mobile-first shells'),
                    ],
                  ),
                ],
              }),
            ],
          }),
          frame({
            name: 'Token Panels',
            width: 'fill_container',
            layout: 'row',
            gap: 32,
            alignItems: 'start',
            children: [
              boardCard(
                'Typography',
                'JetBrains Mono drives both display and body roles in the app theme.',
                [
                  typographySpec('HEADLINE / 24 / 800', 24, 'extrabold', 'headlineMedium'),
                  typographySpec('TITLE / 18 / 800', 18, 'extrabold', 'titleLarge'),
                  typographySpec('SECTION / 15 / 800', 15, 'extrabold', 'titleMedium'),
                  typographySpec('BODY / 14 / 400', 14, 'medium', 'bodyLarge'),
                  typographySpec('META / 11 / 400', 11, 'medium', 'bodySmall'),
                ],
              ),
              boardCard(
                'Foundation',
                'Spacing and radius tokens shared across Home, Sessions, and Settings.',
                [
                  labeledRow('--radius-screen', '28'),
                  labeledRow('--radius-card', '14'),
                  labeledRow('--radius-tile', '12'),
                  labeledRow('--radius-control', '10'),
                  labeledRow('--space-card', '14'),
                  labeledRow('--space-block', '16'),
                  labeledRow('--space-screen-x', '18'),
                  labeledRow('--space-screen-top', '28'),
                ],
              ),
              frame({
                name: 'Color Columns',
                width: 780,
                layout: 'column',
                gap: spacing.card,
                children: [
                  boardCard(
                    'Surface Roles',
                    'Board, screen, panel, and chrome surfaces used throughout the app.',
                    [
                      dualSwatch('Board', dark.board, light.board),
                      dualSwatch('Board alt', dark.boardAlt, light.boardAlt),
                      dualSwatch('Screen shell', dark.screen, light.screen),
                      dualSwatch('Panel', dark.panel, light.panel),
                      dualSwatch('Panel alt', dark.panelAlt, light.panelAlt),
                      dualSwatch('Panel deep', dark.panelDeep, light.panelDeep),
                    ],
                  ),
                  boardCard(
                    'Accent & State Roles',
                    'Action, telemetry, approval, success, and failure states.',
                    [
                      dualSwatch('Primary', dark.primary, light.primary),
                      dualSwatch('Signal', dark.signal, light.signal),
                      dualSwatch('Projects accent', dark.accent, light.accent),
                      dualSwatch('Success', dark.successText, light.successText),
                      dualSwatch('Warning', dark.warningText, light.warningText),
                      dualSwatch('Danger', dark.danger, light.danger),
                    ],
                  ),
                ],
              }),
            ],
          }),
        ],
      }),
    ],
  };
}

function buildScreensDocument() {
  return {
    version: '1.0.0',
    themes: { theme: ['dark', 'light'] },
    variables,
    children: [
      frame({
        name: 'Omni Code Screens From Code',
        width: 1968,
        height: 2200,
        fill: '$--color-board',
        theme: { theme: 'light' },
        padding: [64, 64, 64, 64],
        layout: 'column',
        gap: 36,
        children: [
          frame({
            name: 'Screens Header',
            width: 'fill_container',
            layout: 'column',
            gap: spacing.compact,
            children: [
              pill('APP SCREENS', '$--color-primary', '$--color-on-primary', 138),
              text({
                content: 'Omni Code / App Screens',
                fontFamily: '$--font-display',
                fontSize: 34,
                fontWeight: 'extrabold',
                lineHeight: 1.05,
              }),
              text({
                content: 'Eight production-backed surfaces reconstructed from the Flutter code paths and current l10n copy.',
                fontSize: 13,
                fontWeight: 'medium',
                fill: '$--color-muted',
                lineHeight: 1.5,
                width: 900,
              }),
            ],
          }),
          frame({
            name: 'Row One',
            width: 'fill_container',
            layout: 'row',
            gap: 24,
            children: [
              connectPhone(),
              waitingPhone(),
              dashboardPhone(),
              projectsPhone(),
            ],
          }),
          frame({
            name: 'Row Two',
            width: 'fill_container',
            layout: 'row',
            gap: 24,
            children: [
              projectSessionsPhone(),
              sessionDetailPhone(),
              settingsPhone(),
              speechSettingsPhone(),
            ],
          }),
        ],
      }),
    ],
  };
}

function writeDoc(name, doc) {
  const target = path.join(outputDir, name);
  fs.writeFileSync(target, `${JSON.stringify(doc, null, 2)}\n`);
  return target;
}

fs.mkdirSync(outputDir, { recursive: true });

const themePath = writeDoc('omni-code-theme-from-code.pen', buildThemeDocument());
const screensPath = writeDoc('omni-code-screens-from-code.pen', buildScreensDocument());

console.log(`Wrote ${path.relative(process.cwd(), themePath)}`);
console.log(`Wrote ${path.relative(process.cwd(), screensPath)}`);
