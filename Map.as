// Make a map out of a voronoi graph
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import graph.*;
  import flash.geom.*;
  import flash.utils.Dictionary;
  import flash.utils.getTimer;
  import flash.system.System;
  import com.nodename.geom.LineSegment;
  import com.nodename.Delaunay.Voronoi;
  import de.polygonal.math.PM_PRNG;

  public class Map {
    static public var NUM_POINTS:int = 2000;
    static public var LAKE_THRESHOLD:Number = 0.3;  // 0 to 1, fraction of water corners for water polygon
    static public var NUM_LLOYD_ITERATIONS:int = 2;

    // Passed in by the caller:
    public var SIZE:Number;
    
    // Island shape is controlled by the islandRandom seed and the
    // type of island, passed in when we set the island shape. The
    // islandShape function uses both of them to determine whether any
    // point should be water or land.
    public var islandShape:Function;

    // Island details are controlled by this random generator. The
    // initial map upon loading is always deterministic, but
    // subsequent maps reset this random number generator with a
    // random seed.
    public var mapRandom:PM_PRNG = new PM_PRNG(100);

    // These store the graph data
    public var points:Vector.<Point>;  // Only useful during map construction
    public var centers:Vector.<Center>;
    public var corners:Vector.<Corner>;
    public var edges:Vector.<Edge>;

    public function Map(size:Number) {
      SIZE = size;
      reset();
    }
    
    // Random parameters governing the overall shape of the island
    public function newIsland(type:String, seed:int, variant:int):void {
      islandShape = IslandShape['make'+type](seed);
      mapRandom.seed = variant;
    }

    
    public function reset():void {
      var p:Center, q:Corner, edge:Edge;

      // Break cycles so the garbage collector will release data.
      if (points) {
        points.splice(0, points.length);
      }
      if (edges) {
        for each (edge in edges) {
            edge.d0 = edge.d1 = null;
            edge.v0 = edge.v1 = null;
          }
        edges.splice(0, edges.length);
      }
      if (centers) {
        for each (p in centers) {
            p.neighbors.splice(0, p.neighbors.length);
            p.corners.splice(0, p.corners.length);
            p.borders.splice(0, p.borders.length);
          }
        centers.splice(0, centers.length);
      }
      if (corners) {
        for each (q in corners) {
            q.adjacent.splice(0, q.adjacent.length);
            q.touches.splice(0, q.touches.length);
            q.protrudes.splice(0, q.protrudes.length);
            q.downslope = null;
            q.watershed = null;
          }
        corners.splice(0, corners.length);
      }

      // Clear the previous graph data.
      if (!points) points = new Vector.<Point>();
      if (!edges) edges = new Vector.<Edge>();
      if (!centers) centers = new Vector.<Center>();
      if (!corners) corners = new Vector.<Corner>();
      
      System.gc();
    }
      

    public function go(first:int, last:int):void {
      var stages:Array = [];

      function timeIt(name:String, fn:Function):void {
        var t:Number = getTimer();
        fn();
        Debug.trace("TIME for", name, ":", getTimer()-t);
      }
      
      // Generate the initial random set of points
      stages.push
        (["Place points...",
          function():void {
            reset();
            points = generateRandomPoints();
          }]);

      stages.push
        (["Improve points...",
          function():void {
            improveRandomPoints(points);
          }]);

      
      // Create a graph structure from the Voronoi edge list. The
      // methods in the Voronoi object are somewhat inconvenient for
      // my needs, so I transform that data into the data I actually
      // need: edges connected to the Delaunay triangles and the
      // Voronoi polygons, a reverse map from those four points back
      // to the edge, a map from these four points to the points
      // they connect to (both along the edge and crosswise).
      stages.push
        ( ["Build graph...",
             function():void {
               var voronoi:Voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));
               buildGraph(points, voronoi);
               voronoi.dispose();
               voronoi = null;
               points = null;
          }]);

      stages.push
        (["Assign elevations...",
             function():void {
               // Determine the elevations and water at Voronoi corners.
               assignCornerElevations();

               // Determine polygon and corner type: ocean, coast, land.
               assignOceanCoastAndLand();

               // Rescale elevations so that the highest is 1.0, and they're
               // distributed well. We want lower elevations to be more common
               // than higher elevations, in proportions approximately matching
               // concentric rings. That is, the lowest elevation is the
               // largest ring around the island, and therefore should more
               // land area than the highest elevation, which is the very
               // center of a perfectly circular island.
               redistributeElevations(landCorners(corners));

               // Assign elevations to non-land corners
               for each (var q:Corner in corners) {
                   if (q.ocean || q.coast) {
                     q.elevation = 0.0;
                   }
                 }
               
               // Polygon elevations are the average of their corners
               assignPolygonElevations();
          }]);
             

      stages.push
        (["Assign moisture...",
             function():void {
               // Determine downslope paths.
               calculateDownslopes();

               // Determine watersheds: for every corner, where does it flow
               // out into the ocean? 
               calculateWatersheds();

               // Create rivers.
               createRivers();

               // Determine moisture at corners, starting at rivers
               // and lakes, but not oceans. Then redistribute
               // moisture to cover the entire range evenly from 0.0
               // to 1.0. Then assign polygon moisture as the average
               // of the corner moisture.
               assignCornerMoisture();
               redistributeMoisture(landCorners(corners));
               assignPolygonMoisture();
             }]);

      stages.push
        (["Decorate map...",
             function():void {
               assignBiomes();
             }]);
      
      for (var i:int = first; i < last; i++) {
          timeIt(stages[i][0], stages[i][1]);
        }
    }

    
    // Generate random points and assign them to be on the island or
    // in the water. Some water points are inland lakes; others are
    // ocean. We'll determine ocean later by looking at what's
    // connected to ocean.
    public function generateRandomPoints():Vector.<Point> {
      var p:Point, i:int, points:Vector.<Point> = new Vector.<Point>();
      for (i = 0; i < NUM_POINTS; i++) {
        p = new Point(mapRandom.nextDoubleRange(10, SIZE-10),
                      mapRandom.nextDoubleRange(10, SIZE-10));
        points.push(p);
      }
      return points;
    }

    
    // Improve the random set of points with Lloyd Relaxation.
    public function improveRandomPoints(points:Vector.<Point>):void {
      // We'd really like to generate "blue noise". Algorithms:
      // 1. Poisson dart throwing: check each new point against all
      //     existing points, and reject it if it's too close.
      // 2. Start with a hexagonal grid and randomly perturb points.
      // 3. Lloyd Relaxation: move each point to the centroid of the
      //     generated Voronoi polygon, then generate Voronoi again.
      // 4. Use force-based layout algorithms to push points away.
      // 5. More at http://www.cs.virginia.edu/~gfx/pubs/antimony/
      // Option 3 is implemented here. If it's run for too many iterations,
      // it will turn into a grid, but convergence is very slow, and we only
      // run it a few times.
      var i:int, p:Point, q:Point, voronoi:Voronoi, region:Vector.<Point>;
      for (i = 0; i < NUM_LLOYD_ITERATIONS; i++) {
        voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));
        for each (p in points) {
            region = voronoi.region(p);
            p.x = 0.0;
            p.y = 0.0;
            for each (q in region) {
                p.x += q.x;
                p.y += q.y;
              }
            p.x /= region.length;
            p.y /= region.length;
            region.splice(0, region.length);
          }
        voronoi.dispose();
      }
    }
    

    // Create an array of corners that are on land only, for use by
    // algorithms that work only on land.  We return an array instead
    // of a vector because the redistribution algorithms want to sort
    // this array using Array.sortOn.
    public function landCorners(corners:Vector.<Corner>):Array {
      var q:Corner, locations:Array = [];
      for each (q in corners) {
          if (!q.ocean && !q.coast) {
            locations.push(q);
          }
        }
      return locations;
    }

    
    // Build graph data structure in 'edges', 'centers', 'corners',
    // based on information in the Voronoi results: point.neighbors
    // will be a list of neighboring points of the same type (corner
    // or center); point.edges will be a list of edges that include
    // that point. Each edge connects to four points: the Voronoi edge
    // edge.{v0,v1} and its dual Delaunay triangle edge edge.{d0,d1}.
    // For boundary polygons, the Delaunay edge will have one null
    // point, and the Voronoi edge may be null.
    public function buildGraph(points:Vector.<Point>, voronoi:Voronoi):void {
      var p:Center, q:Corner, point:Point, other:Point;
      var libedges:Vector.<com.nodename.Delaunay.Edge> = voronoi.edges();
      var centerLookup:Dictionary = new Dictionary();

      // Build Center objects for each of the points, and a lookup map
      // to find those Center objects again as we build the graph
      for each (point in points) {
          p = new Center();
          p.index = centers.length;
          p.point = point;
          p.neighbors = new  Vector.<Center>();
          p.borders = new Vector.<Edge>();
          p.corners = new Vector.<Corner>();
          centers.push(p);
          centerLookup[point] = p;
        }
      
      // Workaround for Voronoi lib bug: we need to call region()
      // before Edges or neighboringSites are available
      for each (p in centers) {
          voronoi.region(p.point);
        }
      
      // The Voronoi library generates multiple Point objects for
      // corners, and we need to canonicalize to one Corner object.
      // To make lookup fast, we keep an array of Points, bucketed by
      // x value, and then we only have to look at other Points in
      // nearby buckets. When we fail to find one, we'll create a new
      // Corner object.
      var _cornerMap:Array = [];
      function makeCorner(point:Point):Corner {
        var q:Corner;
        
        if (point == null) return null;
        for (var bucket:int = int(point.x)-1; bucket <= int(point.x)+1; bucket++) {
          for each (q in _cornerMap[bucket]) {
              var dx:Number = point.x - q.point.x;
              var dy:Number = point.y - q.point.y;
              if (dx*dx + dy*dy < 1e-6) {
                return q;
              }
            }
        }
        bucket = int(point.x);
        if (!_cornerMap[bucket]) _cornerMap[bucket] = [];
        q = new Corner();
        q.index = corners.length;
        corners.push(q);
        q.point = point;
        q.touches = new Vector.<Center>();
        q.protrudes = new Vector.<Edge>();
        q.adjacent = new Vector.<Corner>();
        _cornerMap[bucket].push(q);
        return q;
      }
    
      for each (var libedge:com.nodename.Delaunay.Edge in libedges) {
          var dedge:LineSegment = libedge.delaunayLine();
          var vedge:LineSegment = libedge.voronoiEdge();

          // Fill the graph data. Make an Edge object corresponding to
          // the edge from the voronoi library.
          var edge:Edge = new Edge();
          edge.index = edges.length;
          edge.river = 0;
          edges.push(edge);
          edge.midpoint = vedge.p0 && vedge.p1 && Point.interpolate(vedge.p0, vedge.p1, 0.5);

          // Edges point to corners. Edges point to centers. 
          edge.v0 = makeCorner(vedge.p0);
          edge.v1 = makeCorner(vedge.p1);
          edge.d0 = centerLookup[dedge.p0];
          edge.d1 = centerLookup[dedge.p1];

          // Centers point to edges. Corners point to edges.
          if (edge.d0 != null) { edge.d0.borders.push(edge); }
          if (edge.d1 != null) { edge.d1.borders.push(edge); }
          if (edge.v0 != null) { edge.v0.protrudes.push(edge); }
          if (edge.v1 != null) { edge.v1.protrudes.push(edge); }

          function addToCornerList(v:Vector.<Corner>, x:Corner):void {
            if (x != null && v.indexOf(x) < 0) { v.push(x); }
          }
          function addToCenterList(v:Vector.<Center>, x:Center):void {
            if (x != null && v.indexOf(x) < 0) { v.push(x); }
          }
          
          // Centers point to centers.
          if (edge.d0 != null && edge.d1 != null) {
            addToCenterList(edge.d0.neighbors, edge.d1);
            addToCenterList(edge.d1.neighbors, edge.d0);
          }

          // Corners point to corners
          if (edge.v0 != null && edge.v1 != null) {
            addToCornerList(edge.v0.adjacent, edge.v1);
            addToCornerList(edge.v1.adjacent, edge.v0);
          }

          // Centers point to corners
          if (edge.d0 != null) {
            addToCornerList(edge.d0.corners, edge.v0);
            addToCornerList(edge.d0.corners, edge.v1);
          }
          if (edge.d1 != null) {
            addToCornerList(edge.d1.corners, edge.v0);
            addToCornerList(edge.d1.corners, edge.v1);
          }

          // Corners point to centers
          if (edge.v0 != null) {
            addToCenterList(edge.v0.touches, edge.d0);
            addToCenterList(edge.v0.touches, edge.d1);
          }
          if (edge.v1 != null) {
            addToCenterList(edge.v1.touches, edge.d0);
            addToCenterList(edge.v1.touches, edge.d1);
          }
        }
    }


    // Determine elevations and water at Voronoi corners. By
    // construction, we have no local minima. This is important for
    // the downslope vectors later, which are used in the river
    // construction algorithm. Also by construction, inlets/bays
    // push low elevation areas inland, which means many rivers end
    // up flowing out through them. Also by construction, lakes
    // often end up on river paths because they don't raise the
    // elevation as much as other terrain does.
    public function assignCornerElevations():void {
      var q:Corner, s:Corner;
      var queue:Array = [];
      
      for each (q in corners) {
          q.water = !inside(q.point);
        }

      for each (q in corners) {
          // The edges of the map are elevation 0
          if (q.point.x == 0 || q.point.x == SIZE || q.point.y == 0 || q.point.y == SIZE) {
            q.elevation = 0.0;
            q.border = true;
            queue.push(q);
          } else {
            q.elevation = Infinity;
          }
        }
      // Traverse the graph and assign elevations to each point. As we
      // move away from the map border, increase the elevations. This
      // guarantees that rivers always have a way down to the coast by
      // going downhill (no local minima).
      while (queue.length > 0) {
        q = queue.shift();

        for each (s in q.adjacent) {
            // Every step up is epsilon over water or 1 over land. The
            // number doesn't matter because we'll rescale the
            // elevations later.
            var newElevation:Number = 0.01 + q.elevation;
            if (!s.water && !s.water) {
              newElevation += 1;
            }
            // If this point changed, we'll add it to the queue so
            // that we can process its neighbors too.
            if (newElevation < s.elevation) {
              s.elevation = newElevation;
              queue.push(s);
            }
          }
      }
    }

    
    // Change the overall distribution of elevations so that lower
    // elevations are more common than higher
    // elevations. Specifically, we want elevation X to have frequency
    // (1-X).  To do this we will sort the corners, then set each
    // corner to its desired elevation.
    public function redistributeElevations(locations:Array):void {
      // SCALE_FACTOR increases the mountain area. At 1.0 the maximum
      // elevation barely shows up on the map, so we set it to 1.1.
      var SCALE_FACTOR:Number = 1.1;
      var i:int, y:Number, x:Number;

      locations.sortOn('elevation', Array.NUMERIC);
      for (i = 0; i < locations.length; i++) {
        // Let y(x) be the total area that we want at elevation <= x.
        // We want the higher elevations to occur less than lower
        // ones, and set the area to be y(x) = 1 - (1-x)^2.
        y = i/(locations.length-1);
        // Now we have to solve for x, given the known y.
        //  *  y = 1 - (1-x)^2
        //  *  y = 1 - (1 - 2x + x^2)
        //  *  y = 2x - x^2
        //  *  x^2 - 2x + y = 0
        // From this we can use the quadratic equation to get:
        x = Math.sqrt(SCALE_FACTOR) - Math.sqrt(SCALE_FACTOR*(1-y));
        if (x > 1.0) x = 1.0;  // TODO: does this break downslopes?
        locations[i].elevation = x;
      }
    }


    // Change the overall distribution of moisture to be evenly distributed.
    public function redistributeMoisture(locations:Array):void {
      var i:int;
      locations.sortOn('moisture', Array.NUMERIC);
      for (i = 0; i < locations.length; i++) {
        locations[i].moisture = i/(locations.length-1);
      }
    }


    // Determine polygon and corner types: ocean, coast, land.
    public function assignOceanCoastAndLand():void {
      // Compute polygon attributes 'ocean' and 'water' based on the
      // corner attributes. Count the water corners per
      // polygon. Oceans are all polygons connected to the edge of the
      // map. In the first pass, mark the edges of the map as ocean;
      // in the second pass, mark any water-containing polygon
      // connected an ocean as ocean.
      var queue:Array = [];
      var p:Center, q:Corner, r:Center, numWater:int;
      
      for each (p in centers) {
          numWater = 0;
          for each (q in p.corners) {
              if (q.border) {
                p.border = true;
                p.ocean = true;
                q.water = true;
                queue.push(p);
              }
              if (q.water) {
                numWater += 1;
              }
            }
          p.water = (p.ocean || numWater >= p.corners.length * LAKE_THRESHOLD);
        }
      while (queue.length > 0) {
        p = queue.shift();
        for each (r in p.neighbors) {
            if (r.water && !r.ocean) {
              r.ocean = true;
              queue.push(r);
            }
          }
      }
      
      // Set the polygon attribute 'coast' based on its neighbors. If
      // it has at least one ocean and at least one land neighbor,
      // then this is a coastal polygon.
      for each (p in centers) {
          var numOcean:int = 0;
          var numLand:int = 0;
          for each (r in p.neighbors) {
              numOcean += int(r.ocean);
              numLand += int(!r.water);
            }
          p.coast = (numOcean > 0) && (numLand > 0);
        }


      // Set the corner attributes based on the computed polygon
      // attributes. If all polygons connected to this corner are
      // ocean, then it's ocean; if all are land, then it's land;
      // otherwise it's coast.
      for each (q in corners) {
          numOcean = 0;
          numLand = 0;
          for each (p in q.touches) {
              numOcean += int(p.ocean);
              numLand += int(!p.water);
            }
          q.ocean = (numOcean == q.touches.length);
          q.coast = (numOcean > 0) && (numLand > 0);
          q.water = q.border || ((numLand != q.touches.length) && !q.coast);
        }
    }
  

    // Polygon elevations are the average of the elevations of their corners.
    public function assignPolygonElevations():void {
      var p:Center, q:Corner, sumElevation:Number;
      for each (p in centers) {
          sumElevation = 0.0;
          for each (q in p.corners) {
              sumElevation += q.elevation;
            }
          p.elevation = sumElevation / p.corners.length;
        }
    }

    
    // Calculate downslope pointers.  At every point, we point to the
    // point downstream from it, or to itself.  This is used for
    // generating rivers and watersheds.
    public function calculateDownslopes():void {
      var q:Corner, s:Corner, r:Corner;
      
      for each (q in corners) {
          r = q;
          for each (s in q.adjacent) {
              if (s.elevation <= r.elevation) {
                r = s;
              }
            }
          q.downslope = r;
        }
    }


    // Calculate the watershed of every land point. The watershed is
    // the last downstream land point in the downslope graph. TODO:
    // watersheds are currently calculated on corners, but it'd be
    // more useful to compute them on polygon centers so that every
    // polygon can be marked as being in one watershed.
    public function calculateWatersheds():void {
      var q:Corner, r:Corner, i:int, changed:Boolean;
      
      // Initially the watershed pointer points downslope one step.      
      for each (q in corners) {
          q.watershed = q;
          if (!q.ocean && !q.coast) {
            q.watershed = q.downslope;
          }
        }
      // Follow the downslope pointers to the coast. Limit to 100
      // iterations although most of the time with NUM_POINTS=2000 it
      // only takes 20 iterations because most points are not far from
      // a coast.  TODO: can run faster by looking at
      // p.watershed.watershed instead of p.downslope.watershed.
      for (i = 0; i < 100; i++) {
        changed = false;
        for each (q in corners) {
            if (!q.ocean && !q.coast && !q.watershed.coast) {
              r = q.downslope.watershed;
              if (!r.ocean) q.watershed = r;
              changed = true;
            }
          }
        if (!changed) break;
      }
      // How big is each watershed?
      for each (q in corners) {
          r = q.watershed;
          r.watershed_size = 1 + (r.watershed_size || 0);
        }
    }


    // Create rivers along edges. Pick a random corner point, then
    // move downslope. Mark the edges and corners as rivers.
    public function createRivers():void {
      var i:int, q:Corner, edge:Edge;
      
      for (i = 0; i < SIZE/2; i++) {
        q = corners[mapRandom.nextIntRange(0, corners.length-1)];
        if (q.ocean || q.elevation < 0.3 || q.elevation > 0.9) continue;
        // Bias rivers to go west: if (q.downslope.x > q.x) continue;
        while (!q.coast) {
          if (q == q.downslope) {
            Debug.trace("Downslope failed", q.elevation);
            break;
          }
          edge = lookupEdgeFromCorner(q, q.downslope);
          edge.river = edge.river + 1;
          q.river = (q.river || 0) + 1;
          q.downslope.river = (q.downslope.river || 0) + 1;  // TODO: fix double count
          q = q.downslope;
        }
      }
    }


    // Calculate moisture. Freshwater sources spread moisture: rivers
    // and lakes (not oceans). Saltwater sources have moisture but do
    // not spread it (we set it at the end, after propagation).
    public function assignCornerMoisture():void {
      var q:Corner, r:Corner, newMoisture:Number;
      var queue:Array = [];
      // Fresh water
      for each (q in corners) {
          if ((q.water || q.river > 0) && !q.ocean) {
            q.moisture = q.river > 0? Math.min(3.0, (0.2 * q.river)) : 1.0;
            queue.push(q);
          } else {
            q.moisture = 0.0;
          }
        }
      while (queue.length > 0) {
        q = queue.shift();

        for each (r in q.adjacent) {
            newMoisture = q.moisture * 0.9;
            if (newMoisture > r.moisture) {
              r.moisture = newMoisture;
              queue.push(r);
            }
          }
      }
      // Salt water
      for each (q in corners) {
          if (q.ocean || q.coast) {
            q.moisture = 1.0;
          }
        }
    }


    // Polygon moisture is the average of the moisture at corners
    public function assignPolygonMoisture():void {
      var p:Center, q:Corner, sumMoisture:Number;
      for each (p in centers) {
          sumMoisture = 0.0;
          for each (q in p.corners) {
              if (q.moisture > 1.0) q.moisture = 1.0;
              sumMoisture += q.moisture;
            }
          p.moisture = sumMoisture / p.corners.length;
        }
    }


    // Assign a biome type to each polygon. If it has
    // ocean/coast/water, then that's the biome; otherwise it depends
    // on low/high elevation and low/medium/high moisture. This is
    // roughly based on the Whittaker diagram but adapted to fit the
    // needs of the island map generator.
    public function assignBiomes():void {
      var p:Center;
      for each (p in centers) {
          if (p.ocean) {
            p.biome = 'OCEAN';
          } else if (p.water) {
            p.biome = 'LAKE';
            if (p.elevation < 0.1) p.biome = 'MARSH';
            if (p.elevation > 0.8) p.biome = 'ICE';
          } else if (p.coast) {
            p.biome = 'BEACH';
          } else if (p.elevation > 0.8) {
            if (p.moisture > 0.50) p.biome = 'SNOW';
            else if (p.moisture > 0.33) p.biome = 'TUNDRA';
            else if (p.moisture > 0.16) p.biome = 'BARE';
            else p.biome = 'SCORCHED';
          } else if (p.elevation > 0.6) {
            if (p.moisture > 0.66) p.biome = 'TAIGA';
            else if (p.moisture > 0.33) p.biome = 'SHRUBLAND';
            else p.biome = 'TEMPERATE_DESERT';
          } else if (p.elevation > 0.3) {
            if (p.moisture > 0.83) p.biome = 'TEMPERATE_RAIN_FOREST';
            else if (p.moisture > 0.50) p.biome = 'TEMPERATE_DECIDUOUS_FOREST';
            else if (p.moisture > 0.16) p.biome = 'GRASSLAND';
            else p.biome = 'TEMPERATE_DESERT';
          } else {
            if (p.moisture > 0.66) p.biome = 'TROPICAL_RAIN_FOREST';
            else if (p.moisture > 0.33) p.biome = 'TROPICAL_SEASONAL_FOREST';
            else if (p.moisture > 0.16) p.biome = 'GRASSLAND';
            else p.biome = 'SUBTROPICAL_DESERT';
          }
        }
    }


    // Look up a Voronoi Edge object given two adjacent Voronoi
    // polygons, or two adjacent Voronoi corners
    public function lookupEdgeFromCenter(p:Center, r:Center):Edge {
      for each (var edge:Edge in p.borders) {
          if (edge.d0 == r || edge.d1 == r) return edge;
        }
      return null;
    }

    public function lookupEdgeFromCorner(q:Corner, s:Corner):Edge {
      for each (var edge:Edge in q.protrudes) {
          if (edge.v0 == s || edge.v1 == s) return edge;
        }
      return null;
    }

    
    // Determine whether a given point should be on the island or in the water.
    public function inside(p:Point):Boolean {
      return islandShape(new Point(2*(p.x/SIZE - 0.5), 2*(p.y/SIZE - 0.5)));
    }
  }
}


// Factory class to build the 'inside' function that tells us whether
// a point should be on the island or in the water.
import flash.geom.Point;
import flash.display.BitmapData;
import de.polygonal.math.PM_PRNG;
class IslandShape {
  // This class has factory functions for generating islands of
  // different shapes. The factory returns a function that takes a
  // normalized point (x and y are -1 to +1) and returns true if the
  // point should be on the island, and false if it should be water
  // (lake or ocean).

  
  // The radial island radius is based on overlapping sine waves 
  static public var ISLAND_FACTOR:Number = 1.07;  // 1.0 means no small islands; 2.0 leads to a lot
  static public function makeRadial(seed:int):Function {
    var islandRandom:PM_PRNG = new PM_PRNG(seed);
    var bumps:int = islandRandom.nextIntRange(1, 6);
    var startAngle:Number = islandRandom.nextDoubleRange(0, 2*Math.PI);
    var dipAngle:Number = islandRandom.nextDoubleRange(0, 2*Math.PI);
    var dipWidth:Number = islandRandom.nextDoubleRange(0.2, 0.7);
    
    function inside(q:Point):Boolean {
      var angle:Number = Math.atan2(q.y, q.x);
      var length:Number = 0.5 * (Math.max(Math.abs(q.x), Math.abs(q.y)) + q.length);

      var r1:Number = 0.5 + 0.40*Math.sin(startAngle + bumps*angle + Math.cos((bumps+3)*angle));
      var r2:Number = 0.7 - 0.20*Math.sin(startAngle + bumps*angle - Math.sin((bumps+2)*angle));
      if (Math.abs(angle - dipAngle) < dipWidth
          || Math.abs(angle - dipAngle + 2*Math.PI) < dipWidth
          || Math.abs(angle - dipAngle - 2*Math.PI) < dipWidth) {
        r1 = r2 = 0.2;
      }
      return  (length < r1 || (length > r1*ISLAND_FACTOR && length < r2));
    }

    return inside;
  }


  // The Perlin-based island combines perlin noise with the radius
  static public function makePerlin(seed:int):Function {
    var perlin:BitmapData = new BitmapData(256, 256);
    perlin.perlinNoise(64, 64, 8, seed, false, true);
    
    return function (q:Point):Boolean {
      var c:Number = (perlin.getPixel(int((q.x+1)*128), int((q.y+1)*128)) & 0xff) / 255.0;
      return c > (0.3+0.3*q.length*q.length);
    };
  }


  // The square shape fills the entire space with land
  static public function makeSquare(seed:int):Function {
    return function (q:Point):Boolean {
      return true;
    };
  }


  // The blob island is shaped like Amit's blob logo
  static public function makeBlob(seed:int):Function {
    return function(q:Point):Boolean {
      var eye1:Boolean = new Point(q.x-0.2, q.y/2+0.2).length < 0.05;
      var eye2:Boolean = new Point(q.x+0.2, q.y/2+0.2).length < 0.05;
      var body:Boolean = q.length < 0.8 - 0.18*Math.sin(5*Math.atan2(q.y, q.x));
      return body && !eye1 && !eye2;
    };
  }
  
}
