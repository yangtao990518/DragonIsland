"""Locate empty atlas gutters before keying/splitting, without changing poses."""
import argparse
from pathlib import Path
from PIL import Image


def regrid(source, destination, rows, cols):
    image = Image.open(source).convert('RGB')
    # The generated 2x4 sheet's last hair tuft overlaps the nominal 1/4 line
    # by a few pixels. Find the actual blank separator instead of cutting hair.
    pixels = image.load()
    counts = [sum(not (r > 190 and b > 190 and g < 100)
                  for r, g, b in (pixels[x, y] for x in range(image.width)))
              for y in range(image.height)]
    bounds = [0]
    for row in range(1, rows):
        center = row * image.height / rows
        radius = image.height / rows * .16
        candidates = range(round(center-radius), round(center+radius))
        boundary = min(candidates, key=lambda y: (counts[y], abs(y-center)))
        if counts[boundary] > 2:
            raise ValueError(f'No empty gutter before row {row}; regenerate atlas')
        bounds.append(boundary)
    bounds.append(image.height)
    width = round(image.width/cols)
    height = max(b-a for a, b in zip(bounds, bounds[1:]))
    canvas = Image.new('RGB', ((width+32)*cols, (height+32)*rows), '#FF00FF')
    for row in range(rows):
        for col in range(cols):
            cell = image.crop((round(col*image.width/cols), bounds[row],
                               round((col+1)*image.width/cols), bounds[row+1]))
            canvas.paste(cell, (col*(width+32)+16, row*(height+32)+16))
    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)
    print('Gutters:', bounds)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source'); parser.add_argument('destination')
    parser.add_argument('--rows', type=int, required=True)
    parser.add_argument('--cols', type=int, required=True)
    args = parser.parse_args()
    regrid(args.source, args.destination, args.rows, args.cols)
