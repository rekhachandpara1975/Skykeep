"""Google Play listing graphics for SkyKeep.

usage: python3 tool/store_assets.py <raw_screens_dir> <out_dir>

Makes:
  icon-512.png                 app icon (512 x 512, 32-bit PNG)
  feature-graphic-1024x500.png feature graphic
  phone-1..7.png               framed phone screenshots (1080 x 1920, 9:16) with captions
Fonts: tool/fonts/Poppins-*.ttf (SIL Open Font License).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOLD = os.path.join(ROOT, 'tool', 'fonts', 'Poppins-Bold.ttf')
MEDIUM = os.path.join(ROOT, 'tool', 'fonts', 'Poppins-Medium.ttf')
ICON = os.path.join(ROOT, 'docs', 'brand', 'play-store-icon-512.png')

TOP, BOTTOM = (56, 189, 248), (37, 99, 235)  # sky -> brand blue (app gradient)
NAVY = (11, 18, 32)

CAPTIONS = {
    '1_home': ('Your cloud + creators', 'Files, channels and shows in one app'),
    '2_plans': ('Simple plans, pay with UPI', 'From 2 days to 1 year — no auto-renewal'),
    '3_cloud': ('2 TB cloud storage', 'Photos, videos and documents, safe online'),
    '4_channels': ('Follow channels you love', 'Travel, food, fitness, tech and more'),
    '5_payment': ('Plan active in seconds', 'Pay with GPay, PhonePe, Paytm or any UPI app'),
    '6_profile': ('Start free as a guest', 'Add your email any time to keep everything'),
    '7_welcome': ('Your privacy first', 'Clear terms, delete your account any time'),
}


def gradient(w, h, a=TOP, b=BOTTOM):
    sw, sh = max(2, w // 10), max(2, h // 10)  # small, then smooth upscale (fast)
    img = Image.new('RGB', (sw, sh))
    px = img.load()
    for y in range(sh):
        for x in range(sw):
            t = (x / sw * 0.35 + y / sh * 0.65)
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return img.resize((w, h), Image.BILINEAR)


def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], r, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def centered(draw, y, text, font, fill, width):
    w = draw.textlength(text, font=font)
    draw.text(((width - w) / 2, y), text, font=font, fill=fill)


def phone(raw_path, title, subtitle):
    W, H = 1080, 1920
    bg = gradient(W, H).convert('RGBA')
    d = ImageDraw.Draw(bg)
    centered(d, 90, title, ImageFont.truetype(BOLD, 64), 'white', W)
    centered(d, 200, subtitle, ImageFont.truetype(MEDIUM, 40), (230, 242, 255), W)

    shot = Image.open(raw_path).convert('RGB')
    sw = 760
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    frame_w, pad = sw + 36, 18
    top = 320
    visible_h = H - top + 200  # phone runs off the bottom edge
    frame = Image.new('RGBA', (frame_w, visible_h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle([0, 0, frame_w - 1, visible_h - 1], 70, fill=NAVY)
    screen = rounded(shot.crop((0, 0, sw, min(sh, visible_h - pad))), 52)
    frame.paste(screen, (pad, pad), screen)

    shadow = Image.new('RGBA', bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([(W - frame_w) // 2 + 10, top + 24, (W + frame_w) // 2 + 10, H + 200], 70, fill=(0, 0, 0, 90))
    bg = Image.alpha_composite(bg, shadow.filter(ImageFilter.GaussianBlur(30)))
    bg.paste(frame, ((W - frame_w) // 2, top), frame)
    return bg.convert('RGB')


def feature(raw_dir):
    W, H = 1024, 500
    bg = gradient(W, H).convert('RGBA')
    d = ImageDraw.Draw(bg)
    icon = Image.open(ICON).convert('RGBA').resize((150, 150), Image.LANCZOS)
    bg.paste(rounded(icon, 34), (70, 70), rounded(icon, 34))
    d.text((70, 240), 'SkyKeep', font=ImageFont.truetype(BOLD, 76), fill='white')
    d.text((72, 345), '2 TB cloud storage · Creator channels', font=ImageFont.truetype(MEDIUM, 28), fill=(230, 242, 255))
    d.text((72, 385), 'Simple plans · Pay with UPI', font=ImageFont.truetype(MEDIUM, 28), fill=(230, 242, 255))
    shot_path = os.path.join(raw_dir, '2_plans.png')
    if os.path.exists(shot_path):
        shot = Image.open(shot_path).convert('RGB')
        sw = 300
        shot = shot.resize((sw, int(shot.height * sw / shot.width)), Image.LANCZOS).crop((0, 0, sw, 470))
        frame = Image.new('RGBA', (sw + 20, 480), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rounded_rectangle([0, 0, sw + 19, 520], 40, fill=NAVY)
        s = rounded(shot, 30)
        frame.paste(s, (10, 10), s)
        bg.paste(frame, (W - sw - 90, 40), frame)
    return bg.convert('RGB')


def main(raw_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    Image.open(ICON).convert('RGBA').resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, 'icon-512.png'))
    feature(raw_dir).save(os.path.join(out_dir, 'feature-graphic-1024x500.png'))
    n = 0
    for key, (title, sub) in CAPTIONS.items():
        p = os.path.join(raw_dir, key + '.png')
        if not os.path.exists(p):
            print('missing', p)
            continue
        n += 1
        phone(p, title, sub).save(os.path.join(out_dir, f'phone-{n}.png'), optimize=True)
    print(f'wrote icon, feature graphic and {n} phone screenshots to {out_dir}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
