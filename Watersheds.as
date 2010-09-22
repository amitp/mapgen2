// Define watersheds: if a drop of rain falls on any polygon, where
// does it exit the island? We follow the map corner downslope field.
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import graph.*;
  
  public class Watersheds {
    public var lowestCorner:Array = [];  // polygon index -> corner index
    public var watersheds:Array = [];  // polygon index -> corner index

    // We want to mark each polygon with the corner where water would
    // exit the island.
    public function createWatersheds(map:Map):void {
      var p:Center, q:Corner, s:Corner;

      // Find the lowest corner of the polygon, and set that as the
      // exit point for rain falling on this polygon
      for each (p in map.centers) {
          s = null;
          for each (q in p.corners) {
              if (s == null || q.elevation < s.elevation) {
                s = q;
              }
            }
          lowestCorner[p.index] = (s == null)? -1 : s.index;
          watersheds[p.index] = (s == null)? -1 : (s.watershed == null)? -1 : s.watershed.index;
        }
    }
    
  }
}

