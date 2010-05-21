#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <algorithm>

#include "map.h"
#include "write_png.h"

using namespace std;


void place_volcano(Map& map, int cx, int cy, double height, double cap, double slope) {
  int max_radius = int(height/slope);
  int x0 = max(0, cx - max_radius);
  int x1 = min(map.layout.width-1, cx + max_radius);
  int y0 = max(0, cy - max_radius);
  int y1 = min(map.layout.height-1, cy + max_radius);
  for (int x = x0; x <= x1; x++) {
    for (int y = y0; y <= y1; y++) {
      double dx = x - cx;
      double dy = y - cy;
      double r = sqrt(dx*dx + dy*dy);
      double h = height - slope*r;
      if (h > cap) h = cap;
      if (h > 0) {
        map.altitude(x, y) += int(h);
      }
    }
  }
}


void random_altitude_noise(Map& map) {
  for (int x = 0; x < map.layout.width; x++) {
    for (int y = 0; y < map.layout.height; y++) {
      map.altitude(x, y) += random() % 10;
    }
  }
}


void calculate_slope(Map& map) {
  for (int x = 0; x < map.layout.width; x++) {
    for (int y = 0; y < map.layout.height; y++) {
      map.slope_dir(x, y).x =
        map.altitude(x+1, y) + map.water_depth(x+1, y)
        - map.altitude(x-1, y) - map.water_depth(x-1, y);
      map.slope_dir(x, y).y =
        map.altitude(x, y+1) + map.water_depth(x, y+1)
        - map.altitude(x, y-1) - map.water_depth(x, y-1);
    }
  }
}


void soil_erosion(Map& map) {
  Block<int16_t> &A = map.altitude;
  Block<int16_t> B(map.layout, 100);
  
  for (int x = 0; x < map.layout.width; x++) {
    for (int y = 0; y < map.layout.height; y++) {
      B(x, y) = (A(x, y) + A(x-1, y) + A(x, y-1) + A(x+1, y) + A(x, y+1)) / 5;
    }
  }

  // TODO: proper swap
  int16_t* temp = B._block;
  B._block = A._block;
  A._block = temp;
}


void water_flow_everywhere(Map& map) {
  int min_altitude = 6*64;
  const double max_step = 2.0;
  
  Block<int16_t> da(map.layout, 0);
  
  for (int x = 0; x < SIZE; x++) {
    for (int y = 0; y < SIZE; y++) {
      if (map.altitude(x, y) < min_altitude) {
        // reached the ocean
        continue;
      }
      int change = map.altitude(x, y) / 10;
      if (change > 100) change = 100;
      da(x, y) -= change;

      double dx = map.slope_dir(x, y).x;
      double dy = map.slope_dir(x, y).y;
      double d = 1.0;
      if (dx > d) d = dx;
      if (dy > d) d = dy;
      if (-dx > d) d = -dx;
      if (-dy > d) d = -dy;
      int x2 = int(x + max_step*dx/d);
      int y2 = int(y + max_step*dy/d);
      da(x2, y2) += change;
    }
  }

  for (int x = 0; x < SIZE; x++) {
    for (int y = 0; y < SIZE; y++) {
      map.altitude(x, y) += da(x, y);
    }
  }
}


void water_to_land(Map& map) {
  for (int x = 0; x < SIZE; x++) {
    for (int y = 0; y < SIZE; y++) {
      map.altitude(x, y) += map.water_depth(x, y);
      map.water_depth(x, y) = 0;
    }
  }
}


void water_flow(Map& map, int cx, int cy) {
  double x = cx, y = cy;
  double dx = 0.0, dy = 0.0;
  double alpha = 0.2;
  int min_altitude = (4*64) + random() % (20*64);
  
  for (int i = 0; i < 1000; i++) {
    int ix = int(x);
    int iy = int(y);
    if (!(0 <= ix && ix < SIZE && 0 <= iy && iy < SIZE)) {
      // reached the edge of the map
      break;
    }
    if (map.altitude(ix, iy) < min_altitude) {
      // reached the ocean
      break;
    }

    dx = dx*(1-alpha) + alpha*(map.slope_dir(ix, iy).x + (random()%100 - 50));
    dy = dy*(1-alpha) + alpha*(map.slope_dir(ix, iy).y + (random()%100 - 50));
    double step = 1.0;
    if (dx > step) step = dx;
    if (dy > step) step = dy;
    if (-dx > step) step = -dx;
    if (-dy > step) step = -dy;
    x -= dx/step;
    y -= dy/step;
    
    map.water_depth(ix, iy) += int(step);
    if (int(x) == ix && int(y) == iy) {
      break;
    }
    map.altitude(ix, iy) -= int(step);
  }
}


int main() {
  Map map;

  srandomdev();
  for (int i = 0; i < 1000; i++) {
    int x = SIZE/2 + (random() % SIZE - random() % SIZE) * 2/5;
    int y = SIZE/2 + (random() % SIZE - random() % SIZE) * 2/5;
    place_volcano(map, x, y, (300 + random() % 1000), 1000, 15000/SIZE);
  }

  for (int j = 0; j < 10; j++) {
    random_altitude_noise(map);
    calculate_slope(map);
    water_flow_everywhere(map);
  }
  soil_erosion(map);

  for (int j = 0; j < 100; j++) {
    calculate_slope(map);
    for (int i = 0; i < 300; i++) {
      int x = random() % SIZE;
      int y = random() % SIZE;
      if (map.altitude(x, y) > 1000 & (map.slope_dir(x, y).x+map.slope_dir(x,y).y) > -10) {
        water_flow(map, x, y);
      }
    }
    if (j < 97) water_to_land(map);
    soil_erosion(map);
  }
  soil_erosion(map);
  calculate_slope(map);
  
  // Export to png
  unsigned char brightness[SIZE][SIZE];
  for (int x = 0; x < SIZE; x++) {
    for (int y = 0; y < SIZE; y++) {
      int b = map.altitude(x, y) / 64;
      if (map.water_depth(x, y) > 0) {
        int b2 = 10 - map.water_depth(x, y) / 30;
        if (b2 < b) b = b2;
      }
      if (b < 0) b = 0;
      if (b > 255) b = 255;
      brightness[x][y] = b;
    }
  }

  PngWriter output("output.png", SIZE, SIZE);
  output.set_palette_color();
  output.write(&brightness[0][0]);

  for (int x = 0; x < SIZE; x++) {
    for (int y = 0; y < SIZE; y++) {
      int a = map.altitude(x, y);
      int w = map.water_depth(x, y);
      int b = 0;
      if (a > 1000) {
        b = 10 + (a-1000)/1500;
        if (b > 19) b = 19;
      }

      // Contour lines
      int a2 = map.altitude(x+1, y);
      int a3 = map.altitude(x, y+1);
      for (int level = 3000; level < 16000; level += 1000) {
        if (a < level && (a2 >= level || a3 >= level)) b = 2;
        if (a >= level && (a2 < level || a3 < level)) b = 2;
      }
      if (w > 0) b = 1;
      brightness[x][y] = b;
    }
  }

  PngWriter output_map("output-map.png", SIZE, SIZE);
  output_map.set_palette_map();
  output_map.write(&brightness[0][0]);

  /* HACK: */ water_to_land(map);   calculate_slope(map);

  for (int x = 0; x < SIZE; x++) {
    for (int y = 0; y < SIZE; y++) {
      double light = map.slope_dir(x, y).x * 2 + map.slope_dir(x, y).y * 1.3;
      int b = 130 + light*0.1;
      if (b < 0) b = 0;
      if (b > 255) b = 255;
      brightness[x][y] = b;
    }
  }

  PngWriter output_slope("output-slope.png", SIZE, SIZE);
  output_slope.set_palette_gray();
  output_slope.write(&brightness[0][0]);
}

      
