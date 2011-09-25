// Place roads on the polygonal island map using a minimal spanning tree
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import graph.*;
  
  public class RoadsSpanningTree {
    // The road array marks the edges that are roads.
    public var road:Array;  // edge index -> boolean
    public var roadConnections:Array;  // center index -> array of Edges with roads

    public function RoadsSpanningTree() {
      road = [];
      roadConnections = [];
    }


    public function createRoads(map:Map):void {
      var status:Array = [];  // index -> status (undefined for unvisited, 'fringe', or 'closed')
      var fringe:Array = [];  // locations that are still being analyzed
      var p:Center, q:Corner, r:Center, edge:Edge, i:int;

      // Initialize
      for each (edge in map.edges) {
          road[edge.index] = 0;
        }
      
      // Start with the highest elevation Center -- everything else
      // will connect to this location
      r = map.centers[0];
      for each (p in map.centers) {
          if (p.elevation > r.elevation) {
            r = p;
          }
        }
      status[r.index] = 'fringe';
      fringe = [r];
      
      while (fringe.length > 0) {
        // Pick a node randomly. Also interesting is to always pick the first or last node.
        i = Math.floor(Math.random() * fringe.length);
        // i = 0;
        // i = fringe.length - 1;
        if (i > 0 && Math.random() < 0.5) i -= 1;
        p = fringe[i];
        fringe[i] = fringe[0];
        fringe.shift();
        status[p.index] = 'closed';
        
        for each (edge in p.borders) {
            r = (edge.d0 == p)? edge.d1 : edge.d0;
            if (r && !r.water) {
              if (!status[r.index]) {
                // We've never been here, so let's add this to the fringe
                status[r.index] = 'fringe';
                fringe.push(r);
                road[edge.index] = 1;
              } else if (status[r.index] == 'fringe') {
                // We've been here -- what if the cost is lower?  TODO: ignore for now
              }
            }
          }
      }

      // Build the roadConnections list from roads
      for each (edge in map.edges) {
          if (road[edge.index] > 0) {
            for each (p in [edge.d0, edge.d1]) {
                if (p) {
                  if (!roadConnections[p.index]) {
                    roadConnections[p.index] = [];
                  }
                  roadConnections[p.index].push(edge);
                }
              }
            }
        }
      // Rebuild roads from roadConnections
      for each (edge in map.edges) {
          if (road[edge.index] > 0) {
            for each (p in [edge.d0, edge.d1]) {
                if (p) {
                  road[edge.index] = Math.max(road[edge.index], roadConnections[p.index].length);
                }
              }
          }
          road[edge.index] = Math.min(3, Math.max(0, road[edge.index] - 2));
        }
    }
  }
}

