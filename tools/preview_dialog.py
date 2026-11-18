"""Draws the admin screen from gui/AutoAdminDialog.xml with sample players, to see the layout without the game.

Usage: python tools/preview_dialog.py [out.png]      (default previews/admin_screen.png)

It reads our own profiles and elements (positions, sizes, anchors, colours, text settings) and the GUI sheet
gui/autoAdmin_ui.dds, and fills the dynamic parts with the sample data below. The game's own pieces (dialog
frame, slider, button bar with key glyphs) and its font are drawn as look-alikes, so they are close, not exact.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
XML = ROOT / "gui" / "AutoAdminDialog.xml"
SHEET = ROOT / "gui" / "autoAdmin_ui.dds"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "previews" / "admin_screen.png"
FONTS = {False: "C:/Windows/Fonts/segoeui.ttf", True: "C:/Windows/Fonts/segoeuib.ttf"}
SCREEN = (1920, 1080)

CELLS = ["solid", "circle", "tile", "shield", "user", "key", "clock", "pause",
         "play", "trash", "plus", "refresh", "check", "power", "ring", "chevron",
         "crown", "lock", "up", "down"]
COLOR = {
    "gold": (0.851, 0.643, 0.255, 1), "green": (0.435, 0.749, 0.541, 1), "member": (0.659, 0.671, 0.639, 1),
    "online": (0.373, 0.816, 0.478, 1), "offline": (0.345, 0.357, 0.337, 1), "night": (0.078, 0.200, 0.149, 1),
    "white": (0.957, 0.945, 0.910, 1), "off": (0.290, 0.298, 0.282, 1),
}
ROLE_COLOR = {2: "gold", 1: "green", 0: "member"}
ROLE_ICON = {2: "crown", 1: "shield", 0: "user"}
ROLE_TEXT = {2: "SUPER ADMIN", 1: "ADMIN", 0: "MEMBER"}

# sample players, sorted like the server sorts them (role, online, name)
PLAYERS = [
    dict(name="Chris", role=2, online=True, admin=True, you=True, last="2026-11-18 21:04"),
    dict(name="Steve", role=2, online=False, admin=False, last="2026-11-17 19:42"),
    dict(name="FarmerJoe", role=1, online=True, admin=True, last="2026-11-18 20:51"),
    dict(name="Tractor_Tina", role=1, online=False, admin=False, last="2026-11-16 22:10"),
    dict(name="HayBaleHank", role=0, online=True, admin=False, last="2026-11-18 20:33"),
    dict(name="Mud_Mike", role=0, online=False, admin=False, locked=True, last="2026-11-15 18:07"),
    dict(name="Wheatley", role=0, online=False, admin=False, last="2026-11-12 16:55"),
]
SELECTED = 2


def status(p):
    parts = []
    if p.get("you"):
        parts.append("You")
    parts.append(("Online, admin now" if p["admin"] else "Online") if p["online"] else "Offline")
    if p.get("locked"):
        parts.append("Locked out")
    return "  ·  ".join(parts)


sel = PLAYERS[SELECTED]
TEXT = {
    "subtitleText": "3 online now  ·  7 players on the list",
    "statSuper": "2", "statAdmin": "2", "statMember": "3",
    "detailName": sel["name"], "detailRole": ROLE_TEXT[sel["role"]],
    "valStatus": status(sel), "valFirstSeen": "2026-10-02 18:30", "valLastSeen": sel["last"],
    "valChanged": "2026-11-03 20:12", "valChangedBy": "Chris", "valRestored": "14",
    "detailNote": "", "rememberPillText": "ON",
    "permissionNote": "You are a super admin: you can change every role except other super admins'. "
                      "Super admins can only be removed in admins.xml on the server.",
    "statusText": "FarmerJoe is now an admin.",
}
HIDDEN = {"loadingText", "emptyText", "detailEmpty"}
TEXT_L10N = {
    "aa_brand": "Auto Admin", "aa_title": "Server roles", "aa_stat_super": "Super admins", "aa_stat_admin": "Admins",
    "aa_stat_member": "Members", "aa_players": "Players", "aa_col_player": "Player", "aa_col_role": "Role",
    "aa_col_last": "Last joined", "aa_details": "Details", "aa_info_status": "Status",
    "aa_info_firstSeen": "First seen", "aa_info_lastSeen": "Last joined", "aa_info_changed": "Role given",
    "aa_info_changedBy": "Given by", "aa_info_restored": "Admin restored", "aa_setting": "Server setting",
    "aa_remember": "Remember password logins",
    "aa_rememberHint": "Members who log in with the admin password become admins.",
}


def rgba(c, alpha=None):
    r, g, b, a = c
    if alpha is not None:
        a = alpha
    return tuple(int(round(v * 255)) for v in (r, g, b, a))


def parse_color(text):
    return tuple(float(v) for v in text.split())


def px(value):
    out = []
    for part in value.split():
        part = part.replace("px", "").replace("dp", "")
        out.append(float(part.rstrip("%")) if part else 0.0)
    return out


class Profiles:
    def __init__(self, root):
        self.items = {}
        for p in root.find("GUIProfiles"):
            values = {c.tag: c.get("value") for c in p}
            self.items[p.get("name")] = (p.get("extends"), p.get("with"), values)

    def resolve(self, name):
        values, traits = {}, []
        chain = []
        while name in self.items:
            chain.append(self.items[name])
            name = self.items[name][0]
        for ext, with_, vals in reversed(chain):
            values.update(vals)
            if with_:
                traits.append(with_)
        return values, (traits[-1] if traits else "anchorTopLeft")


sheet = Image.open(SHEET).convert("RGBA")


def cell_image(name, size, color):
    i = CELLS.index(name)
    col, row = i % 8, i // 8
    crop = sheet.crop((col * 64 + 2, row * 64 + 2, col * 64 + 62, row * 64 + 62))
    w, h = max(1, int(round(size[0]))), max(1, int(round(size[1])))
    crop = crop.resize((w, h), Image.LANCZOS)
    tint = Image.new("RGBA", (w, h), rgba(color)[:3] + (255,))
    alpha = crop.getchannel("A").point(lambda v: v * color[3])
    tint.putalpha(alpha)
    return tint


def font(size, bold):
    return ImageFont.truetype(FONTS[bool(bold)], int(round(size)))


def draw_text(img, box, text, v):
    if not text:
        return
    d = ImageDraw.Draw(img)
    size = px(v.get("textSize", "14px"))[0]
    bold = v.get("textBold") == "true"
    if v.get("textUpperCase") == "true":
        text = text.upper()
    f = font(size, bold)
    color = rgba(parse_color(v.get("textColor", "1 1 1 1")))
    x, y, w, h = box
    lines = [text]
    if "textWrapWidth" in v:
        ww = px(v["textWrapWidth"])[0]
        lines, cur = [], ""
        for word in text.split():
            test = (cur + " " + word).strip()
            if d.textlength(test, font=f) > ww and cur:
                lines.append(cur)
                cur = word
            else:
                cur = test
        lines.append(cur)
    lh = size * 1.25
    total = lh * len(lines)
    va = v.get("textVerticalAlignment", "middle")
    ty = y + (h - total) / 2 if va == "middle" else y
    for line in lines:
        tw = d.textlength(line, font=f)
        al = v.get("textAlignment", "left")
        tx = x if al == "left" else (x + (w - tw) / 2 if al == "center" else x + w - tw)
        d.text((tx, ty + (lh - size * 1.33) / 2), line, font=f, fill=color)
        ty += lh


def place(parent, v, anchor, attrs):
    pos = px(attrs.get("position") or v.get("position", "0px 0px"))
    size = px(attrs.get("size") or v.get("size", "0px 0px"))
    px0, py0, pw, ph = parent
    if anchor == "anchorTopStretchingX":
        return (px0, py0, pw, px(v.get("height", "0px"))[0])
    w, h = size
    if anchor == "anchorTopRight":
        x = px0 + pw + pos[0] - w
    elif anchor == "anchorTopCenter":
        x = px0 + (pw - w) / 2 + pos[0]
    else:
        x = px0 + pos[0]
    return (x, py0 - pos[1], w, h)


def render_element(img, el, parent, profiles, ctx):
    attrs = el.attrib
    key = attrs.get("id") or attrs.get("name") or ""
    if key in HIDDEN:
        return
    v, anchor = profiles.resolve(attrs.get("profile", ""))
    box = place(parent, v, anchor, attrs)
    tag = el.tag
    selected = ctx.get("selected", False)
    if tag == "Bitmap":
        color_key = "imageSelectedColor" if selected and "imageSelectedColor" in v else "imageColor"
        color = parse_color(v.get(color_key, "1 1 1 1"))
        cell = None
        if key.startswith("aaImg_"):
            cell = key[6:]
        dyn = ctx.get("dynamic", {}).get(key)
        if dyn is not None:
            cell, color = dyn
        if cell is not None and box[2] >= 1 and box[3] >= 1 and color[3] > 0:
            img.alpha_composite(cell_image(cell, box[2:], color), (int(round(box[0])), int(round(box[1]))))
    elif tag == "Text":
        text = ctx.get("text", {}).get(key)
        if text is None:
            t = attrs.get("text", "")
            text = TEXT_L10N.get(t[6:], t) if t.startswith("$l10n_") else t
        tv = dict(v)
        if selected and "textSelectedColor" in v:
            tv["textColor"] = v["textSelectedColor"]
        override = ctx.get("textColor", {}).get(key)
        if override:
            tv["textColor"] = " ".join(str(c) for c in override)
        draw_text(img, box, text, tv)
    elif tag == "SmoothList":
        template = el.find("ListItem")
        spacing = px(attrs.get("listItemSpacing", "0px"))[0]
        y = box[1]
        for i, p in enumerate(PLAYERS):
            rv, ranchor = profiles.resolve(template.get("profile"))
            rh = px(rv.get("height", "64px"))[0]
            if y + rh > box[1] + box[3]:
                break
            row_ctx = dict(ctx)
            row_ctx["selected"] = i == SELECTED
            rc = ROLE_COLOR[p["role"]]
            row_ctx["dynamic"] = {
                "avatarTile": ("tile", parse_color(rv.get("imageColor", "1 1 1 1")) if False else
                               ((0.231, 0.208, 0.141, 1) if i == SELECTED else (0.157, 0.169, 0.149, 1))),
                "avatarIcon": (ROLE_ICON[p["role"]], COLOR[rc]),
                "onlineDot": ("circle", COLOR["online" if p["online"] else "offline"]),
                "badgeBg": ("solid", COLOR[rc][:3] + (0.16,)),
            }
            row_ctx["text"] = {"name": p["name"], "sub": status(p), "badge": ROLE_TEXT[p["role"]],
                               "lastDate": p["last"].split()[0], "lastTime": p["last"].split()[1]}
            row_ctx["textColor"] = {"badge": COLOR[rc]}
            for child in template:
                render_element(img, child, (box[0], y, box[2], rh), profiles, row_ctx)
            y += rh + spacing
        return
    elif tag == "ThreePartBitmap" and "listSliderBox" in attrs.get("profile", ""):
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x, y, w, h = place(parent, {}, attrs.get("with", "anchorTopLeft"), attrs)
        d.rounded_rectangle([x + 2, y, x + w - 2, y + h], radius=3, fill=(255, 255, 255, 20))
        d.rounded_rectangle([x + 2, y + 4, x + w - 2, y + h * 0.62], radius=3, fill=rgba(COLOR["gold"], 0.9))
        img.alpha_composite(layer)
        return
    elif tag in ("ThreePartBitmap", "BoxLayout", "Button", "Slider"):
        return
    for child in el:
        render_element(img, child, box, profiles, ctx)


def draw_backdrop():
    img = Image.new("RGBA", SCREEN, (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    # a soft field-at-dusk backdrop, dimmed like the game does behind a dialog
    for y in range(SCREEN[1]):
        t = y / SCREEN[1]
        c = (int(70 + 60 * (1 - t)), int(88 + 50 * (1 - t)), int(96 - 20 * t))
        d.line([(0, y), (SCREEN[0], y)], fill=c + (255,))
    for i in range(14):
        y0 = 620 + i * 34
        d.polygon([(0, y0), (SCREEN[0], y0 - 80), (SCREEN[0], y0 - 60), (0, y0 + 18)],
                  fill=(60 + i * 3, 78 + i * 4, 40 + i, 255) if i % 2 else (88, 96, 46, 255))
    img = img.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(Image.new("RGBA", SCREEN, (0, 0, 0, 150)))
    return img


def draw_dialog_frame(img, box):
    x, y, w, h = box
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w, y + h], fill=(12, 13, 12, 246))
    d.rectangle([x, y, x + w, y + 3], fill=rgba(COLOR["gold"]))


def draw_buttons(img, dialog):
    x, y, w, h = dialog
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bar_y = y + h - 70
    d.line([(x + 30, bar_y - 6), (x + w - 30, bar_y - 6)], fill=(255, 255, 255, 25))
    buttons = [("Enter", "Make member"), ("Space", "Make super admin"), ("Esc", "Back")]
    f = font(16, True)
    fk = font(13, True)
    cx = x + w - 30
    for i, (key, label) in enumerate(reversed(buttons)):
        lw = d.textlength(label.upper(), font=f)
        kw = max(30, d.textlength(key, font=fk) + 16)
        bw = kw + 12 + lw + 20
        bx = cx - bw
        d.rounded_rectangle([bx + 10, bar_y + 16, bx + 10 + kw, bar_y + 44], radius=5, outline=(230, 230, 225, 255), width=2)
        d.text((bx + 10 + (kw - d.textlength(key, font=fk)) / 2, bar_y + 20), key, font=fk, fill=(235, 235, 230, 255))
        d.text((bx + 10 + kw + 12, bar_y + 18), label.upper(), font=f, fill=(240, 240, 235, 255))
        cx = bx - 16
        if i < len(buttons) - 1:
            d.line([(cx + 8, bar_y + 14), (cx + 8, bar_y + 46)], fill=(255, 255, 255, 40), width=1)
    img.alpha_composite(layer)


def main():
    root = ET.parse(XML).getroot()
    profiles = Profiles(root)
    img = draw_backdrop()
    dialog_v, _ = profiles.resolve("aaDialogBg")
    dw, dh = px(dialog_v["size"])
    dialog = ((SCREEN[0] - dw) / 2, (SCREEN[1] - dh) / 2, dw, dh)
    draw_dialog_frame(img, dialog)
    content_parent = (dialog[0], dialog[1] + 28, dw, dh - 100)
    content = root.find(".//GuiElement[@profile='aaContent']")
    ctx = {
        "text": TEXT,
        "textColor": {"detailRole": COLOR[ROLE_COLOR[sel["role"]]], "rememberPillText": COLOR["night"]},
        "dynamic": {
            "detailAvatarIcon": (ROLE_ICON[sel["role"]], COLOR[ROLE_COLOR[sel["role"]]]),
            "detailAccent": ("solid", COLOR[ROLE_COLOR[sel["role"]]]),
            "rememberPill": ("solid", COLOR["green"]),
        },
    }
    render_element(img, content, content_parent, profiles, ctx)
    draw_buttons(img, dialog)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
