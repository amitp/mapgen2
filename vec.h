/* A vec is a 2d vector (x, y). */

#ifndef _VEC_H_
#define _VEC_H_

struct vec {
  float x;
  float y;
};

bool operator == (const vec& a, const vec& b) {
  return a.x == b.x && a.y == b.y;
}

#endif
