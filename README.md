After working on a [Perlin-noise-based map
generator](http://simblob.blogspot.com/2010/01/simple-map-generation.html)
I had wanted something with islands and rivers and volcanoes and
lava. However, I had a lot of trouble getting that map generator to
generate any more than what it did at first. This project was my
exploration of several different techniques for map generation.

The goal is to make continent/island style maps (surrounded by water)
that can be used by a variety of games. I had originally intended to
write a reusable C++ library but ended up writing the code in
Actionscript.

The most important features I want are nice island/continent
coastlines, mountains, and rivers. Non goals include impassable areas
(except for the ocean), maze-like structures, or realistic height
maps. The high level approach is to

  1. Make a coastline.
  2. Set elevation to distance from coastline. Mountains are farthest from the coast.
  3. Create rivers in valleys, flowing down to the coast.

The implementation generates a vector map with roughly 1,000 polygons,
instead of a tile/grid map with roughly 1,000,000 tiles.  In games the
polygons can be used for distinct areas with their own story and
personality, places for towns and resources, quest locations,
conquerable territory, etc.  Polygon boundaries are used for
rivers. Polygon-to-polygon routes are used for roads. Forests, oceans,
rivers, swamps, etc. can be named. Polygons are rendered into a bitmap
to produce the tile map, but the underlying polygon structure is still
available.

The [full process is described here](http://www-cs-students.stanford.edu/~amitp/game-programming/polygon-map-generation/).

History
-------

*   I started out with C++ code that used mountains, soil erosion, water flow, water erosion, water evaporation, volanoes, lava flow, and other physical processes to sculpt terrain expressed in a 2d array of tiles. However as described [in this blog post](http://simblob.blogspot.com/2010/06/teleological-vs-ontogenetic-map.html) I decided to abandon this approach.

*   Since my initial approach failed, I wrote several small prototypes to figure out how to make rivers, coastlines, and mountains. These are the key features I want to support. I will then figure out how to combine them into a map.

*   The voronoi_set.as prototype worked well and I continued adding to it (instead of converting to C++). It supports terrain types: ocean, land, beach, lake, forest, swamp, desert, ice, rocky, grassland, savannah. It has rivers and roads. I decided not to convert it to C++ for now. Instead, I've refactored it into the core map generation (Map.as), display and GUI (mapgen2.as), graph representation (graph/*.as), decorative elements (Roads.as, Lava.as), and noisy edge generation (NoisyEdges.as).


Requirements
------------

These third-party requirements have been added to the ``third-party`` directory:

* [My fork of as3delaunay](http://github.com/amitp/as3delaunay)
* The AS3 version of [de.polygonal.math.PM_PRNG.as](http://lab.polygonal.de/2007/04/21/a-good-pseudo-random-number-generator-prng/)

Make sure you run ``git submodule update --init`` to check out the third-party libraries.

Compiling
---------

To compile ``mapgen2.as`` to ``mapgen2.swf``, use the following command:

    mxmlc -source-path+=third-party/PM_PRNG -source-path+=third-party/as3delaunay/src mapgen2.as

