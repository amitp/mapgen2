#ifndef _WRITE_PNG_H_
#define _WRITE_PNG_H_

// Right now we can only write a png with a 0-255 colormap

class PngPalette;

class PngWriter {
 public:
  PngWriter(const char* filename_, int width_, int height_)
    :filename(filename_), width(width_), height(height_),
    palette(0) {}

  ~PngWriter();
  
  void set_palette_gray();
  void set_palette_color();
  
  int write(unsigned char* brightness);

 private:
  const char* filename;
  int width, height;

  PngPalette* palette;
};

#endif
