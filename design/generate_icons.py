
"""Generate Android and iOS launcher icons from app-icon.svg."""

import json
from io import BytesIO
from pathlib import Path

import cairosvg
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent

SOURCE = ROOT / "design/app-icon.svg"

ANDROID_RES = ROOT / "android/app/src/main/res"

IOS_ICONSET = (
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
)

ANDROID_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def generate_icon(svg, destination, width, height):
    png = cairosvg.svg2png(
        bytestring=svg,
        output_width=width,
        output_height=height,
    )

    with Image.open(BytesIO(png)) as image:
        # 背景が完全に不透明であることを確認する。
        alpha = image.convert("RGBA").getchannel("A")

        if alpha.getextrema() != (255, 255):
            raise ValueError("Icon contains transparent pixels")

        # iOSでも使用できるよう、アルファなしのRGB PNGにする。
        image.convert("RGB").save(destination, format="PNG")

    # 保存した画像の形式・寸法を確認する。
    with Image.open(destination) as generated:
        assert generated.format == "PNG"
        assert generated.mode == "RGB"
        assert generated.size == (width, height)

    print(
        f"OK: {destination.relative_to(ROOT)} "
        f"({width}x{height})"
    )


def main():
    svg = SOURCE.read_bytes()

    # Android用のアイコン。
    targets = {
        ANDROID_RES / f"mipmap-{density}/ic_launcher.png":
        (size, size)
        for density, size in ANDROID_SIZES.items()
    }

    # iOS用のアイコン。
    contents = json.loads(
        (IOS_ICONSET / "Contents.json").read_text(
            encoding="utf-8"
        )
    )

    for item in contents["images"]:
        filename = item["filename"]

        scale = int(item["scale"].removesuffix("x"))

        width, height = (
            int(float(value) * scale)
            for value in item["size"].split("x")
        )

        # iPhoneとiPadで共有するファイルは1回だけ生成する。
        targets[IOS_ICONSET / filename] = (width, height)

    # 既存アイコンを置き換えることを確認する。
    for destination in targets:
        if not destination.is_file():
            raise FileNotFoundError(destination)

    for destination, (width, height) in targets.items():
        generate_icon(svg, destination, width, height)

    print(f"\nGenerated {len(targets)} icons.")


if __name__ == "__main__":
    main()
