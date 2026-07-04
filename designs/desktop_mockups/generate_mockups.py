from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUT_DIR = Path(__file__).resolve().parent
WIDTH = 1600
HEIGHT = 1000

BG = "#F6F3EC"
PANEL = "#FFFEFB"
PANEL_ALT = "#F2F5F9"
SOFT = "#EEF3FB"
BORDER = "#D6DEE7"
TEXT = "#1A2430"
TEXT_SOFT = "#5C6B7D"
MUTED = "#7B8999"
BLUE = "#66C8FF"
BLUE_STRONG = "#2D79D8"
PURPLE = "#8B5CF6"
GREEN = "#B2FF2E"
GREEN_SOFT = "#ECF8D8"
GREEN_TEXT = "#213108"
AMBER = "#F2B57E"
AMBER_SOFT = "#FFF1E4"


def font(size: int, bold: bool = False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/TTF/DejaVuSans.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


F_TITLE = font(34, True)
F_H1 = font(22, True)
F_H2 = font(15, True)
F_BODY = font(13)
F_SMALL = font(11)
F_TINY = font(10)


def rr(draw, box, radius=22, fill=PANEL, outline=BORDER, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def txt(draw, xy, value, fill=TEXT, f=F_BODY):
    draw.text(xy, value, font=f, fill=fill)


def measure(draw, value, f):
    return int(draw.textlength(value, font=f))


def pill(draw, x, y, label, fg=TEXT_SOFT, bg=PANEL, border=BORDER, dot=None, min_w=78):
    w = max(min_w, measure(draw, label, F_SMALL) + 28 + (14 if dot else 0))
    rr(draw, (x, y, x + w, y + 28), radius=14, fill=bg, outline=border)
    tx = x + 12
    if dot:
        draw.ellipse((x + 10, y + 10, x + 18, y + 18), fill=dot)
        tx = x + 24
    txt(draw, (tx, y + 6), label, fill=fg, f=F_SMALL)
    return w


def base():
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(img)
    for x in range(-100, WIDTH + 100, 42):
        draw.line((x, 0, x + 150, HEIGHT), fill="#E9EDF4", width=1)
    for y in [164, 320, 520, 760]:
        draw.arc((-120, y - 56, WIDTH + 120, y + 56), start=184, end=356, fill="#DAE6FA", width=2)
    return img, draw


def top(draw):
    txt(draw, (48, 48), "Omni Code", f=F_TITLE)
    txt(draw, (48, 100), "Inbox-first home refined: sessions lead, support rail stays dense and secondary.", fill=TEXT_SOFT, f=F_BODY)
    pill(draw, 48, 150, "Refined layout")


def left_nav(draw):
    rr(draw, (36, 214, 278, 948), radius=30)
    txt(draw, (60, 248), "OMNI CODE", f=F_H1)
    txt(draw, (60, 282), "Desktop workspace", fill=MUTED, f=F_SMALL)
    y = 332
    for item in ["Home", "Projects", "Sessions", "Settings"]:
        active = item == "Home"
        rr(draw, (56, y, 258, y + 48), radius=16, fill=SOFT if active else PANEL, outline=BORDER)
        if active:
            rr(draw, (68, y + 13, 74, y + 35), radius=3, fill=BLUE_STRONG, outline=BLUE_STRONG)
        txt(draw, (90, y + 15), item, f=F_BODY)
        y += 60
    rr(draw, (56, 816, 258, 892), radius=20, fill=GREEN_SOFT, outline="#D4E8B7")
    txt(draw, (78, 838), "New Session", f=F_H2)
    txt(draw, (78, 864), "Primary create action", fill=TEXT_SOFT, f=F_SMALL)


def session_card(draw, x, y, w, h, title, meta, preview, accent, pinned=False):
    rr(draw, (x, y, x + w, y + h), radius=20, fill=PANEL, outline=BORDER)
    rr(draw, (x + 14, y + 14, x + 20, y + h - 14), radius=3, fill=accent, outline=accent)
    txt(draw, (x + 34, y + 14), title, f=F_H2)
    txt(draw, (x + 34, y + 38), meta, fill=MUTED, f=F_SMALL)
    txt(draw, (x + 34, y + 66), preview, fill=TEXT_SOFT, f=F_SMALL)
    if pinned:
        pill(draw, x + w - 94, y + 14, "Pinned", fg=BLUE_STRONG, bg=SOFT, border="#C7DBF4", dot=BLUE, min_w=84)


def compact_rail_card(draw, x, y, w, h, title, body, tone="neutral", action=None):
    fill = PANEL_ALT
    border = BORDER
    if tone == "warning":
        fill = AMBER_SOFT
        border = "#EBC594"
    rr(draw, (x, y, x + w, y + h), radius=18, fill=fill, outline=border)
    txt(draw, (x + 18, y + 16), title, f=F_H2)
    txt(draw, (x + 18, y + 40), body, fill=TEXT_SOFT, f=F_SMALL)
    if action:
        pill(draw, x + 18, y + h - 38, action, fg=GREEN_TEXT, bg=GREEN, border=GREEN, dot=GREEN_TEXT, min_w=96)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img, draw = base()
    top(draw)
    left_nav(draw)

    rr(draw, (304, 214, 972, 948), radius=30)
    rr(draw, (994, 214, 1550, 948), radius=30)

    txt(draw, (334, 246), "Session Inbox", f=F_H1)
    txt(draw, (334, 278), "The homepage should answer one question first: what should I continue right now?", fill=TEXT_SOFT, f=F_SMALL)

    rr(draw, (334, 316, 606, 366), radius=16, fill=PANEL_ALT)
    txt(draw, (352, 332), "Search sessions, prompts, files...", fill=MUTED, f=F_BODY)
    fx = 698
    fx += pill(draw, fx, 326, "All", dot=BLUE, min_w=66) + 10
    fx += pill(draw, fx, 326, "Running", fg=PURPLE, dot=PURPLE, min_w=88) + 10
    pill(draw, fx, 326, "Needs approval", fg="#A86A28", dot=AMBER, min_w=118)

    txt(draw, (334, 392), "Pinned", fill=MUTED, f=F_TINY)
    session_card(
        draw,
        334,
        410,
        606,
        106,
        "Continuous voice conversations",
        "omni-code-client  •  codex  •  Running",
        "The call mode view can live beside project context and device status on desktop.",
        BLUE,
        pinned=True,
    )

    txt(draw, (334, 542), "Recent", fill=MUTED, f=F_TINY)
    y = 560
    rows = [
        ("Bridge approval flow", "omni-code-bridge  •  Awaiting approval", "Pending approvals should surface directly in the inbox ordering.", AMBER),
        ("Desktop adaptation pass", "omni-code  •  gpt-5  •  Running", "Session continuation is the primary desktop home behavior.", GREEN),
        ("Release checklist", "release-tools  •  Waiting", "Structured progress still reads as one row, not a dashboard tile.", PURPLE),
        ("Prompt routing audit", "omni-code  •  codex  •  Running", "Long-running work should always be resumable from home.", BLUE_STRONG),
    ]
    for title, meta, body, accent in rows:
        session_card(draw, 334, y, 606, 98, title, meta, body, accent)
        y += 112

    pill(draw, 334, 922, "Load more", fg=TEXT_SOFT, bg=PANEL, border=BORDER, min_w=96)

    txt(draw, (1024, 246), "Right Rail", f=F_H1)
    txt(draw, (1024, 278), "Pinned support information. Secondary, dense, and always visible.", fill=TEXT_SOFT, f=F_SMALL)

    compact_rail_card(
        draw,
        1024,
        316,
        496,
        116,
        "Pending approvals",
        "3 waiting actions. This is the strongest card in the rail.",
        tone="warning",
        action="Review now",
    )
    compact_rail_card(
        draw,
        1024,
        448,
        496,
        84,
        "Bridge status",
        "Connected  •  localhost  •  synced 1 min ago",
    )
    compact_rail_card(
        draw,
        1024,
        546,
        496,
        84,
        "Voice / device",
        "Microphone ready  •  system speech available",
    )
    compact_rail_card(
        draw,
        1024,
        644,
        496,
        92,
        "Projects overview",
        "3 active projects. Keep this compressed; projects are not primary home content.",
    )
    compact_rail_card(
        draw,
        1024,
        750,
        496,
        74,
        "Quick actions",
        "Open Projects  •  Settings",
    )

    rr(draw, (1024, 842, 496 + 1024, 918), radius=18, fill=PANEL_ALT, outline=BORDER)
    txt(draw, (1042, 860), "Optional space for one rotating surface", f=F_H2)
    txt(draw, (1042, 886), "Example: active voice session, update notice, or bridge setup guidance.", fill=TEXT_SOFT, f=F_SMALL)

    output = OUT_DIR / "home_layout_inbox_refined_v2.png"
    img.save(output)
    print(output)


if __name__ == "__main__":
    main()
