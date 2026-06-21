#!/usr/bin/env node
/**
 * Regenerate AltArmy_TBC/Textures/ScrollFade.tga — vertical alpha fade with 8x8 Bayer dither.
 * Usage: node scripts/generate-scroll-fade-tga.js
 */

const fs = require("fs");
const path = require("path");

const OUT = path.join(__dirname, "..", "AltArmy_TBC", "Textures", "ScrollFade.tga");
const WIDTH = 8;
const HEIGHT = 128;

const BAYER_8 = [
  [0, 32, 8, 40, 2, 34, 10, 42],
  [48, 16, 56, 24, 50, 18, 58, 26],
  [12, 44, 4, 36, 14, 46, 6, 38],
  [60, 28, 52, 20, 62, 30, 54, 22],
  [3, 35, 11, 43, 1, 33, 9, 41],
  [51, 19, 59, 27, 49, 17, 57, 25],
  [15, 47, 7, 39, 13, 45, 5, 37],
  [63, 31, 55, 23, 61, 29, 53, 21],
];

function ditherAlpha(t, x, y) {
  const scaled = t * 255;
  const threshold = (BAYER_8[y % 8][x % 8] + 0.5) / 64;
  return Math.min(255, Math.max(0, Math.floor(scaled + threshold - 0.5)));
}

function writeTga(filePath, width, height, rgbaFn) {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header[12] = width & 255;
  header[13] = (width >> 8) & 255;
  header[14] = height & 255;
  header[15] = (height >> 8) & 255;
  header[16] = 32;
  header[17] = 8;

  const pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const t = height <= 1 ? 1 : y / (height - 1);
      const a = rgbaFn(t, x, y);
      const i = (y * width + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = a;
    }
  }

  fs.writeFileSync(filePath, Buffer.concat([header, pixels]));
}

writeTga(OUT, WIDTH, HEIGHT, ditherAlpha);
console.log("Wrote", OUT, `(${WIDTH}x${HEIGHT}, Bayer-dithered alpha)`);
