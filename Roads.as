// Place roads on the polygonal island map roughly following contour lines.
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import graph.*;
  
  public class Roads {
    // The road array marks the edges that are roads.  The mark is 1,
    // 2, or 3, corresponding to the three contour levels. Note that
    // these are sparse arrays, only filled in where there are roads.
    public var road:Array;  // edge index -> int contour level
    public var roadConnections:Array;  // center index -> array of Edges with roads

    public function Roads() {
      road = [];
      roadConnections = [];
    }


    // We want to mark different elevation zones so that we can draw
    // island-circling roads that divide the areas.
    public function createRoads(map:voronoi_set):void {
      // Oceans and coastal polygons are the lowest contour zone
      // (1). Anything connected to contour level K, if it's below
      // elevation threshold K, or if it's water, gets contour level
      // K.  (2) Anything not assigned a contour level, and connected
      // to contour level K, gets contour level K+1.
      var queue:Array = [];
      var p:Center, q:Corner, r:Center, edge:Edge, newLevel:int;
      var elevationThresholds:Array = [0, 0.05, 0.37, 0.64];
      var cornerContour:Array = [];  // corner index -> int contour level
      var centerContour:Array = [];  // center index -> int contour level
    
      for each (p in map.centers) {
          if (p.coast || p.ocean) {
            centerContour[p.index] = 1;
            queue.push(p);
          }
        }
      
      while (queue.length > 0) {
        p = queue.shift();
        for each (r in p.neighbors) {
            newLevel = centerContour[p.index] || 0;
            while (r.elevation > elevationThresholds[newLevel] && !r.water) {
              // NOTE: extend the contour line past bodies of
              // water so that roads don't terminate inside lakes.
              newLevel += 1;
            }
            if (newLevel < (centerContour[r.index] || 999)) {
              centerContour[r.index] = newLevel;
              queue.push(r);
            }
          }
      }

      // A corner's contour level is the MIN of its polygons
      for each (p in map.centers) {
          for each (q in p.corners) {
              cornerContour[q.index] = Math.min(cornerContour[q.index] || 999,
                                                centerContour[p.index] || 999);
            }
        }

      // Roads go between polygons that have different contour levels
      for each (p in map.centers) {
          for each (edge in p.edges) {
              if (edge.v0 && edge.v1
                  && cornerContour[edge.v0.index] != cornerContour[edge.v1.index]) {
                road[edge.index] = Math.min(cornerContour[edge.v0.index],
                                            cornerContour[edge.v1.index]);
                if (!roadConnections[p.index]) {
                  roadConnections[p.index] = [];
                }
                roadConnections[p.index].push(edge);
              }
            }
        }
    }
    
  }
}

