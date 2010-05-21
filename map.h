/* Map representation in memory:

   The map is a contiguous array of some type, in column-major format
   (e.g. access with [x][y]).  To avoid range checks, we surround the
   map with a border of dummy locations. Thus, the array is actually
   (2*border + width) * (2*border + height) in size.  A simulation
   step that uses neighboring values will reset the border spaces with
   some initial value.

   A Layout object maps x,y to the position in the array. The layout
   object also provides a list of border locations.

   Simulation steps can iterate over a contiguous range of the array,
   using *(p+1), *(p-1), *(p+stride), *(p-stride) to access
   neighbors. The range won't include the left/right borders but it
   will include the top/bottom borders. This simplifies the loops.
   The simulation can access only up to `border` in each direction.

   Some simulations need to output to a second array.  Sometimes this
   can be swapped for the original, and sometimes they are merged with
   a second pass.

   Some simulations need to know x,y positions; they're best written
   as a loop over x and y instead of using the contiguous range.
   
*/

#ifndef _MAP_H_
#define _MAP_H_

#include <stdint.h>
#include "vec.h"

const int SIZE = 1024;
const int SIZE_BORDER = 2;

struct Layout {
  Layout(int width_, int height_, int border_)
  : width(width_), height(height_), border(border_) { }
  
  int width, height;
  int border;

  int size() const {
    return (width+2*border) * (height+2*border);
  }
  
  int position(int x, int y) const {
    return (x+border)*(height+2*border) + (y+border);
  }

  // TODO: list of border locations
};
  
template<typename Element>
struct Block {
  Block(const Layout& layout_, const Element& initial_value)
  : layout(layout_) {
    int size = layout.size();
    _block = new Element[size];
    for (int i = 0; i < size; i++) {
      _block[i] = initial_value;
    }
  }

  ~Block() {
    delete [] _block;
  }
  
  Element* _block;
  const Layout& layout;
  
  Element& operator()(int x, int y) { return _block[layout.position(x, y)]; }
  const Element& operator()(int x, int y) const { return _block[layout.position(x, y)]; }

  // TODO: iterator over the main portion
  // TODO: reset border values
  // TODO: iterator over a column
};

struct Map {
  Layout layout;
  Block<int16_t> altitude;
  Block<vec> slope_dir;
  Block<int16_t> water_depth;
  
  Map()
  : layout(SIZE, SIZE, SIZE_BORDER),
    altitude(layout, 100),
    slope_dir(layout, vec()),
    water_depth(layout, 0)
  { }
};

#endif
