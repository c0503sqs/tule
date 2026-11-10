"""把原始线稿处理成透明背景的 *_line.png 和 *_paper.png。"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SAMPLES = {
    "cat_balloon_01.jpeg": "cat",
    "bear_flower_01.jpeg": "bear",
    "bunny_carrot_01.jpeg": "bunny",
}
OUT_DIR = ROOT / "assets" / "pages"
MAGENTA = (255, 0, 255)
LONG_EDGE = 2048


def background_mask(gray: Image.Image) -> Image.Image:
    """从四角灌入洋红，返回 255 表示与边缘连通的背景。"""
    filled = gray.convert("RGB")
    width, height = filled.size
    for xy in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
        ImageDraw.floodfill(filled, xy, MAGENTA, thresh=30)
    return ImageChops.difference(
        filled, Image.new("RGB", filled.size, MAGENTA)
    ).convert("L").point(lambda v: 255 if v == 0 else 0)


def process(source: Path, name: str) -> None:
    gray = Image.open(source).convert("L")
    gray.thumbnail((LONG_EDGE, LONG_EDGE), Image.Resampling.LANCZOS)

    background = background_mask(gray)
    foreground = ImageChops.invert(background)

    line = Image.new("RGBA", gray.size, (0, 0, 0, 0))
    line_alpha = gray.point(lambda v: 0 if v >= 200 else round((200 - v) / 200 * 255))
    line.putalpha(ImageChops.multiply(line_alpha, foreground))
    line.save(OUT_DIR / f"{name}_line.png")

    paper = Image.new("RGBA", gray.size, (255, 255, 255, 0))
    paper.putalpha(foreground)
    paper.save(OUT_DIR / f"{name}_paper.png")

    pixels = background.size[0] * background.size[1]
    ratio = sum(1 for v in background.get_flattened_data() if v == 255) / pixels
    print(f"{name}: {background.size[0]}x{background.size[1]}, 背景占比 {ratio:.1%}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, name in SAMPLES.items():
        process(ROOT / "assets" / "samples" / filename, name)


if __name__ == "__main__":
    main()
