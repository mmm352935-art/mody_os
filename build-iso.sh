#!/usr/bin/env bash
# MODY OS: builds a custom 32-bit (i386) Debian 12 live ISO for old PCs.
#
#  - Boots straight from the USB (no boot menu), fully live, nothing installed
#  - Boot splash: the word MODY with a glowing ring spinning around it
#  - After login: a full-screen "اختار" page with two cards: جيمينج / شغل
#       جيمينج -> games launcher (CPU governor = performance)
#       شغل    -> work apps launcher (browser, word processor, spreadsheet...)
#  - Lightweight LXDE desktop, Arabic + English (Alt+Shift), Arabic fonts
#  - Non-PAE 686 kernel (works on very old CPUs)
#  - "persistence" support: keep files/settings on the USB
#
# Run as root on Debian/Ubuntu, or inside a debian:bookworm container.
# Output: ./out/custom-live-i386.iso
set -euo pipefail

OUT_DIR="$(pwd)/out"
BUILD_DIR="/tmp/lb-build"
APPEND="boot=live components persistence quiet splash locales=ar_EG.UTF-8 keyboard-layouts=us,ar timezone=Africa/Cairo"

apt-get update
apt-get install -y live-build debootstrap debian-archive-keyring \
  syslinux syslinux-utils isolinux xorriso squashfs-tools mtools dosfstools \
  python3 python3-pil fonts-dejavu-core

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

lb config \
  --distribution bookworm \
  --architectures i386 \
  --linux-flavours 686 \
  --binary-images iso-hybrid \
  --bootloaders syslinux \
  --debian-installer none \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --memtest none \
  --iso-volume "MODY" \
  --bootappend-live "$APPEND"

# ---------------------------------------------------------------
# Core packages (must exist, or the build stops)
# ---------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/custom.list.chroot <<'EOF'
# Desktop
xorg
xserver-xorg
lxde-core
lightdm
lightdm-gtk-greeter
lxterminal
pcmanfm
policykit-1
sudo
network-manager
network-manager-gnome
wpasupplicant
# Boot splash + chooser app
plymouth
python3
python3-gi
gir1.2-gtk-3.0
gir1.2-gdkpixbuf-2.0
adwaita-icon-theme
lxde-icon-theme
# Locale / keyboard
locales
keyboard-configuration
# Sound
pulseaudio
alsa-utils
pavucontrol
# Everyday apps
firefox-esr
firefox-esr-l10n-ar
mpv
mupdf
gparted
htop
nano
# Fonts (Arabic support)
fonts-noto-core
fonts-hosny-amiri
fonts-kacst
fonts-dejavu
# Hardware firmware (Wi-Fi, etc.)
firmware-linux-free
firmware-linux-nonfree
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-misc-nonfree
# Live system
live-boot
live-config
EOF

# ---------------------------------------------------------------
# Generated artwork + files baked into the image
# ---------------------------------------------------------------
INC=config/includes.chroot
PLY=$INC/usr/share/plymouth/themes/mody
SHARE=$INC/usr/share/mody
mkdir -p "$PLY" "$SHARE" "$INC/usr/local/bin" "$INC/etc/xdg/autostart" \
  "$INC/usr/share/applications" "$INC/etc/default" "$INC/etc/lightdm/lightdm.conf.d"

cat > /tmp/gen_assets.py <<'MODY_EOF_GEN'
#!/usr/bin/env python3
"""Generates all MODY artwork (boot logo, spinning ring frames, card images).
Usage: gen_assets.py <plymouth_dir> <share_dir>
Everything is drawn from scratch with Pillow; no external images are used.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

PLY_DIR, SHARE_DIR = sys.argv[1], sys.argv[2]
os.makedirs(PLY_DIR, exist_ok=True)
os.makedirs(SHARE_DIR, exist_ok=True)

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def get_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vgradient(size, top, bottom):
    w, h = size
    mask = Image.linear_gradient("L").resize((w, h))
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), mask)


def hgradient(size, left, right):
    w, h = size
    mask = Image.linear_gradient("L").rotate(90).resize((w, h))
    return Image.composite(Image.new("RGB", size, right), Image.new("RGB", size, left), mask)


def glow(img, radius, strength=1.0, color=(76, 201, 240)):
    """Soft glow built from the alpha of `img`, filled with one flat colour."""
    alpha = img.split()[3].filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        alpha = alpha.point(lambda v: min(255, int(v * strength)))
    out = Image.new("RGBA", img.size, tuple(color) + (0,))
    out.putalpha(alpha)
    return out


CYAN = (76, 201, 240)
VIOLET = (181, 23, 158)
PURPLE = (114, 9, 183)
BLUE = (67, 97, 238)
TEAL = (6, 214, 160)

# ---------------------------------------------------------------- logo
def make_logo():
    scale = 3
    text = "MODY"
    font = get_font(62 * scale)
    spacing = 11 * scale
    widths = [font.getbbox(ch)[2] - font.getbbox(ch)[0] for ch in text]
    total_w = sum(widths) + spacing * (len(text) - 1)
    h = 110 * scale
    pad = 26 * scale
    W = total_w + pad * 2
    cap = font.getbbox("M")
    y = (h - (cap[3] - cap[1])) // 2 - cap[1]
    mask = Image.new("L", (W, h), 0)
    d = ImageDraw.Draw(mask)
    x = pad
    for ch, cw in zip(text, widths):
        bb = font.getbbox(ch)
        d.text((x - bb[0], y), ch, font=font, fill=255)
        x += cw + spacing
    fill = hgradient((W, h), CYAN, VIOLET)
    logo = Image.new("RGBA", (W, h), (0, 0, 0, 0))
    logo.paste(fill, (0, 0), mask)
    out = Image.alpha_composite(glow(logo, 9 * scale, 0.9, CYAN), logo)
    out = out.resize((W // scale, h // scale), Image.LANCZOS)
    out.save(os.path.join(PLY_DIR, "logo.png"))
    return out.size


# ---------------------------------------------------------------- ring
def make_ring_frames(frames=36, final=360):
    S = 4
    size = final * S
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(ring)
    cx = cy = size // 2
    r = size // 2 - 18 * S
    width = 11 * S
    box = (cx - r, cy - r, cx + r, cy + r)
    # faint track
    d.arc(box, 0, 360, fill=(255, 255, 255, 28), width=width // 2)
    # comet: head at angle 0 (3 o'clock) fading backwards
    sweep, step = 250, 1.0
    a = 0.0
    while a < sweep:
        t = a / sweep  # 0 at head, 1 at tail
        alpha = int(255 * (1 - t) ** 1.6)
        col = lerp(CYAN, VIOLET, t) + (alpha,)
        d.arc(box, -a - step - 0.6, -a + 0.6, fill=col, width=width)
        a += step
    # round head cap
    hx = cx + r
    d.ellipse((hx - width // 2, cy - width // 2, hx + width // 2, cy + width // 2), fill=CYAN + (255,))
    ring = Image.alpha_composite(glow(ring, 9 * S, 0.9, CYAN), ring)
    for i in range(frames):
        frame = ring.rotate(-i * (360 / frames), resample=Image.BICUBIC)
        frame = frame.resize((final, final), Image.LANCZOS)
        frame.save(os.path.join(PLY_DIR, "ring-%d.png" % i))


# ---------------------------------------------------------------- cards
CARD_W, CARD_H = 460, 320


def card_base(top, bottom, accent):
    S = 2
    W, H = CARD_W * S, CARD_H * S
    bg = vgradient((W, H), top, bottom).convert("RGBA")
    # soft spotlight
    spot = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(spot).ellipse((W * 0.18, H * 0.05, W * 0.82, H * 0.95), fill=accent + (90,))
    bg = Image.alpha_composite(bg, spot.filter(ImageFilter.GaussianBlur(70)))
    # rounded corners mask
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, W - 1, H - 1), radius=36 * S, fill=255)
    return bg, m, S


def finish_card(img, mask, S, name):
    img.putalpha(mask)
    img = img.resize((CARD_W, CARD_H), Image.LANCZOS)
    img.save(os.path.join(SHARE_DIR, name))


def make_gaming():
    bg, m, S = card_base((22, 8, 52), (60, 16, 120), (125, 60, 255))
    W, H = bg.size
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = W // 2, int(H * 0.52)

    # controller body = union of shapes
    body = Image.new("L", (W, H), 0)
    b = ImageDraw.Draw(body)
    b.rounded_rectangle((cx - 230, cy - 120, cx + 230, cy + 60), radius=90, fill=255)
    b.ellipse((cx - 330, cy - 40, cx - 110, cy + 220), fill=255)
    b.ellipse((cx + 110, cy - 40, cx + 330, cy + 220), fill=255)
    body = body.filter(ImageFilter.GaussianBlur(3)).point(lambda v: 255 if v > 128 else 0)
    shade = vgradient((W, H), (235, 238, 255), (150, 160, 215)).convert("RGBA")
    # glow behind the body
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gl.putalpha(body)
    layer = Image.alpha_comp
