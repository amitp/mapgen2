After working on a [Perlin-noise-based map
generator](http://simblob.blogspot.com/2010/01/simple-map-generation.html)
I had wanted something with islands and rivers and volcanoes and
lava. However, I had a lot of trouble getting that map generator to
generate any more than what it did at first. This project is my
exploration of many different techniques for map generation.

The goal is to make continent/island style maps (surrounded by water)
that can be used by a variety of games. The implementation will be a
standalone C++ binary (or library).  

Nice to have:

*   **Size independence**. Generate roughly the same map at various sizes. Intended use would be to generate lots of small maps, then rate them (either by machine or by human), and generate detail maps for the best ones.

*   **Nameable areas**. Forests, oceans, rivers, swamps, deserts, mountains, etc. would all be better with names.

*   **Vector features** such as rivers and roads would be more useful than a bunch of tiles, so that you can use them in pathfinding and other game features. Depending on how experiments go, it may be useful to make the entire map vector based.

Non-goals:

*   **Impassable areas**, except for the ocean surrounding the continent.

*   **Maze-like structures**, or areas that are disproportionately difficult to reach compared to the bird's eye distance. In particular, long peninsulas or bays are undesirable. These same features look neat on maps though, so I may change my mind. Maybe the games can have bridges or boats or other transportation shortcuts.

*   **Realistic height maps**.  My goal is to make interesting 2D overhead maps, and not 3D terrain.

History:

*   I started out with C++ code that used mountains, soil erosion, water flow, water erosion, water evaporation, volanoes, lava flow, and other physical processes to sculpt terrain expressed in a 2d array of tiles. However as described [in this blog post](http://simblob.blogspot.com/2010/06/teleological-vs-ontogenetic-map.html) I decided to abandon this approach.

*   Since my initial approach failed, I am writing several small prototypes to figure out how to make rivers, coastlines, and mountains. These are the key features I want to support. I will then figure out how to combine them into a map.
