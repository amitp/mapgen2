// Randomly place lava on high elevation dry land.
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import graph.*;
  
  public class Lava {
    static public var FRACTION_LAVA_FISSURES:Number = 0.2;  // 0 to 1, probability of fissure
    
    // The lava array marks the edges that hava lava.
    public var lava:Array = [];  // edge index -> Boolean

    // Lava fissures are at high elevations where moisture is low
    public function createLava(map:voronoi_set, randomDouble:Function):void {
      var edge:Edge;
      for each (edge in map.edges) {
          if (!edge.river && !edge.d0.water && !edge.d1.water
              && edge.d0.elevation > 0.8 && edge.d1.elevation > 0.8
              && edge.d0.moisture < 0.3 && edge.d1.moisture < 0.3
              && randomDouble() < FRACTION_LAVA_FISSURES) {
            lava[edge.index] = true;
          }
        }
    }
  }
}

