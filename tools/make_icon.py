#!/usr/bin/env python3
"""Rasterize our rect/polygon SVG to a deterministic DXT5 DDS with all mipmaps.

This intentionally supports only the simple original artwork in assets/icon.svg;
it is not a general SVG converter. No external imaging dependency is required.
"""
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def inside_polygon(x, y, vertices):
    inside = False
    previous = vertices[-1]
    for current in vertices:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y) and x < (x2-x1)*(y-y1)/(y2-y1)+x1:
            inside = not inside
        previous = current
    return inside


def rasterize(path):
    svg = ET.parse(path).getroot()
    width, height = int(svg.attrib["width"]), int(svg.attrib["height"])
    pixels = [(0, 0, 0)] * (width * height)
    for element in svg:
        tag = element.tag.rsplit("}", 1)[-1]
        if tag == "title":
            continue
        fill = element.attrib["fill"].lstrip("#")
        color = tuple(int(fill[i:i+2], 16) for i in (0, 2, 4))
        if tag == "rect":
            x, y, w, h = (int(element.attrib[k]) for k in ("x", "y", "width", "height"))
            for py in range(y, y+h):
                pixels[py*width+x:py*width+x+w] = [color] * w
        elif tag == "polygon":
            vertices = [tuple(map(int, pair.split(","))) for pair in element.attrib["points"].split()]
            for py in range(min(p[1] for p in vertices), max(p[1] for p in vertices)):
                for px in range(min(p[0] for p in vertices), max(p[0] for p in vertices)):
                    if inside_polygon(px+.5, py+.5, vertices):
                        pixels[py*width+px] = color
        else:
            raise ValueError("Unsupported icon SVG element: " + tag)
    return width, height, pixels


def rgb565(color):
    r, g, b = color
    return ((r * 31 + 127) // 255 << 11) | ((g * 63 + 127) // 255 << 5) | ((b * 31 + 127) // 255)


def expand565(value):
    return ((value >> 11 & 31) * 255 // 31, (value >> 5 & 63) * 255 // 63, (value & 31) * 255 // 31)


def compress_level(width, height, pixels):
    output = bytearray()
    for by in range(0, height, 4):
        for bx in range(0, width, 4):
            block = [pixels[min(by+y, height-1)*width+min(bx+x, width-1)] for y in range(4) for x in range(4)]
            darkest = min(block, key=sum)
            lightest = max(block, key=sum)
            a, b = sorted((rgb565(darkest), rgb565(lightest)), reverse=True)
            c0, c1 = expand565(a), expand565(b)
            palette = (c0, c1, tuple((2*x+y)//3 for x, y in zip(c0, c1)), tuple((x+2*y)//3 for x, y in zip(c0, c1)))
            indices = 0
            for index, color in enumerate(block):
                best = min(range(4), key=lambda k: sum((color[c]-palette[k][c])**2 for c in range(3)))
                indices |= best << (index * 2)
            output += b"\xff\xff\0\0\0\0\0\0" + struct.pack("<HHI", a, b, indices)
    return bytes(output)


def generate(root=ROOT):
    width, height, pixels = rasterize(root / "assets/icon.svg")
    if width != height or width != 512:
        raise ValueError("The mod icon must be 512 x 512")
    levels = []
    w, h = width, height
    while True:
        levels.append(compress_level(w, h, pixels))
        if w == 1 and h == 1:
            break
        nw, nh = max(1, w//2), max(1, h//2)
        pixels = [tuple(sum(pixels[min(y*2+dy, h-1)*w+min(x*2+dx, w-1)][c] for dy in range(2) for dx in range(2))//4 for c in range(3)) for y in range(nh) for x in range(nw)]
        w, h = nw, nh
    header = [124, 0xA1007, height, width, len(levels[0]), 0, len(levels)] + [0]*11
    header += [32, 4, int.from_bytes(b"DXT5", "little"), 0, 0, 0, 0, 0]
    header += [0x401008, 0, 0, 0, 0]
    result = b"DDS " + struct.pack("<31I", *header) + b"".join(levels)
    destination = root / "assets/icon.dds"
    if not destination.exists() or destination.read_bytes() != result:
        destination.write_bytes(result)
    return destination


if __name__ == "__main__":
    print(generate().relative_to(ROOT))
