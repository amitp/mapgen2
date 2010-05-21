#include <stdio.h>
#include <png.h>

#include "write_png.h"


struct PngPalette {
  enum {size = 256};
  png_color P[size];
};


PngWriter::~PngWriter() {
  if (palette) {
    delete palette;
    palette = 0;
  }
}


// Colors for map palette:
// dark sand = b19772
// light sand = cfb78b
// light ocean = 3d526d
// dark ocean = 374b63


png_color hexcolor(int rgb) {
  png_color c;
  c.red = rgb >> 16;
  c.green = (rgb >> 8) & 0xff;
  c.blue = rgb & 0xff;
  return c;
}


png_color interpolate_color(png_color a, png_color b, double frac) {
  png_color c;
  c.red = int(a.red * (1.0-frac) + b.red * frac);
  c.green = int(a.green * (1.0-frac) + b.green * frac);
  c.blue = int(a.blue * (1.0-frac) + b.blue * frac);
  return c;
}


void PngWriter::set_palette_map() {
  palette = new PngPalette();

  palette->P[0] = hexcolor(0x3d526d);
  palette->P[1] = hexcolor(0x374b63);
  palette->P[2] = hexcolor(0xa18762);  // contour lines
  for (int i = 10; i < 20; i++) {
    palette->P[i] = interpolate_color
      (hexcolor(0xb19772), hexcolor(0xcfb78b), (i-10)/9.0);
  }
  palette->P[15] = hexcolor(0x60b030);
}


void PngWriter::set_palette_gray() {
  palette = new PngPalette();

  for (int i = 0; i < palette->size; i++) {
    palette->P[i].red = palette->P[i].green = palette->P[i].blue = i;
  }
}


void PngWriter::set_palette_color() {
  palette = new PngPalette();

  for (int i = 0; i < palette->size; i++) {
    if (i < 10) {
      palette->P[i].red = i*6;
      palette->P[i].green = 32 + i*6;
      palette->P[i].blue = 64 + i*6;
    } else if (i == 10) {
      palette->P[i].red = 32;
      palette->P[i].green = 100;
      palette->P[i].blue = 80;
    } else {
      palette->P[i].red = i;
      palette->P[i].green = 128+i/2;
      palette->P[i].blue = 64-i/4;
      if (i % 16 == 1) {
        palette->P[i].red /= 2;
        palette->P[i].green /= 2;
        palette->P[i].blue /= 2;
      }
    }
  }
}


int PngWriter::write(unsigned char* brightness) {
  if (!palette) return 1;
  
  FILE* fp = fopen(filename, "wb");
  if (!fp) return 1;

  png_byte** row_pointers = new png_byte*[height];
  for (int y = 0; y < height; y++) {
    row_pointers[y] = new png_byte[width];
    for (int x = 0; x < width; x++) {
      row_pointers[y][x] = brightness[x*height + y];
    }
  }

  png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
  if (!png_ptr) return 1;

  png_init_io(png_ptr, fp);
  
  png_infop info_ptr = png_create_info_struct(png_ptr);

  if (!info_ptr || setjmp(png_jmpbuf(png_ptr))) {
    // This is the exception handler for the rest of the function
    fclose(fp);
    png_destroy_write_struct(&png_ptr, 0);
    
    for (int y = 0; y < height; y++) {
      delete[] row_pointers[y];
    }
    delete[] row_pointers;
  
    return 1;
  }
  
  png_set_IHDR(png_ptr, info_ptr, width, height, 8, PNG_COLOR_TYPE_PALETTE,
               PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
               PNG_FILTER_TYPE_DEFAULT);
  png_set_PLTE(png_ptr, info_ptr, palette->P, palette->size);

  /*
  png_text_struct text[2];
  text[0].key = const_cast<char *>("Title");
  text[0].text = const_cast<char *>("mapgen2 output");
  text[0].compression = PNG_TEXT_COMPRESSION_NONE;
  text[1].key = const_cast<char *>("Author");
  text[1].text = const_cast<char *>("amitp@cs.stanford.edu");
  text[1].compression = PNG_TEXT_COMPRESSION_NONE;
  png_set_text(png_ptr, info_ptr, text, 2);
  */
  
  png_set_rows(png_ptr, info_ptr, row_pointers);
  png_write_png(png_ptr, info_ptr, PNG_TRANSFORM_IDENTITY, 0);

  png_write_end(png_ptr, 0);

  for (int y = 0; y < height; y++) {
    delete[] row_pointers[y];
  }
  delete[] row_pointers;
  
  fclose(fp);

  return 0;
}
