from pathlib import Path
from PIL import Image, ImageDraw
source = Image.open('assets/icon.png').convert('RGB')
out = Path('build/ios/Shiro.app')
# ios 5 launch images cannot read the saved theme, so use the default dark background
launch_color = '#3d2130'
for name, size in [('Icon.png', 57), ('Icon@2x.png', 114), ('Icon-72.png', 72), ('Icon-72@2x.png', 144), ('Icon-60@2x.png', 120), ('Icon-60@3x.png', 180), ('Icon-76.png', 76), ('Icon-76@2x.png', 152), ('Icon-83.5@2x.png', 167)]:
    icon = source.resize((size, size), Image.Resampling.LANCZOS).convert('RGBA')
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=size * 0.88, fill=255)
    icon.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    icon.save(out / name)
for name, size in [('Default.png', (320, 480)), ('Default@2x.png', (640, 960)), ('Default-568h@2x.png', (640, 1136))]:
    Image.new('RGB', size, launch_color).save(out / name)

for asset in ('sqmrak.jpg', 'qwertyu1opz.png', 'cloudflare.png'):
    image = Image.open(Path('assets') / asset)
    image.thumbnail((144, 144), Image.Resampling.LANCZOS)
    image.save(out / asset)

# launch images let iOS choose native bounds instead of the 320-point compatibility canvas
import plistlib
info = plistlib.loads(Path('packaging/Info.plist').read_bytes())
for key in ('UILaunchImages', 'UILaunchImages~ipad'):
    for entry in info[key]:
        width, height = (int(value.strip()) for value in entry['UILaunchImageSize'].strip('{}').split(','))
        name = entry['UILaunchImageName']
        scale = 2 if 'pad' in name or width in (320, 375) and height in (480, 568, 667) else 3
        Image.new('RGB', (width * scale, height * scale), launch_color).save(out / (name + '@%dx.png' % scale))
for name, size in [('Default-Portrait.png', (768, 1004)), ('Default-Landscape.png', (1024, 748)), ('Default-Portrait@2x.png', (1536, 2008)), ('Default-Landscape@2x.png', (2048, 1496))]:
    Image.new('RGB', size, launch_color).save(out / name)
