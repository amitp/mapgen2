// Make a map out of a voronoi graph
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.events.*;
  import flash.text.TextField;
  import flash.utils.Dictionary;
  import flash.utils.ByteArray;
  import flash.utils.getTimer;
  import flash.net.FileReference;
  import flash.system.System;
  import com.nodename.geom.Circle;
  import com.nodename.geom.LineSegment;
  import com.nodename.Delaunay.Edge;
  import com.nodename.Delaunay.Voronoi;
  import de.polygonal.math.PM_PRNG;

  // TODO: add more points near coastlines (shrink beach areas). TODO:
  // remove ocean points (maybe) (may speed up code). TODO: remove
  // points that are too close to another point (voronoi edge is very
  // straight and we can't make it noisy) (also, when corners are too
  // close together, rivers connect to each other or coastlines
  // connect to each other)
  
  public class voronoi_set extends Sprite {
    static public var NUM_POINTS:int = 2000;
    static public var SIZE:int = 600;
    static public var ISLAND_FACTOR:Number = 1.07;  // 1.0 means no small islands; 2.0 leads to a lot
    static public var NOISY_LINE_TRADEOFF:Number = 0.1;  // low: jagged vedge; high: jagged dedge
    static public var FRACTION_LAVA_FISSURES:Number = 0.2;  // 0 to 1, probability of fissure
    static public var LAKE_THRESHOLD:Number = 0.3;  // 0 to 1, fraction of water corners for water polygon
    
    static public var displayColors:Object = {
      OCEAN: 0x555599,
      COAST: 0x444477,
      LAKESHORE: 0x225588,
      LAKE: 0x336699,
      RIVER: 0x336699,
      MARSH: 0x116655,
      ICE: 0x99ffff,
      SCORCHED: 0x444433,
      BARE: 0x666666,
      BEACH: 0xa09077,
      LAVA: 0xcc3333,
      SNOW: 0xffffff,
      DESERT: 0xc9d29b,
      SAVANNAH: 0xaabb88,
      GRASSLANDS: 0x88aa55,
      DRY_FOREST: 0x679459,
      RAIN_FOREST: 0x449955,
      SWAMP: 0x337744,
      ROAD: 0x664433
    };

    static public var elevationGradientColors:Object = {
      OCEAN: 0x008800,
      GRADIENT_LOW: 0x008800,
      GRADIENT_HIGH: 0xffff00
    };

    static public var moistureGradientColors:Object = {
      OCEAN: 0x4466ff,
      GRADIENT_LOW: 0xbbaa33,
      GRADIENT_HIGH: 0x4466ff
    };
      
    public var islandRandom:PM_PRNG = new PM_PRNG(487);
    public var mapRandom:PM_PRNG = new PM_PRNG(487);

    // This is the current map style. UI buttons change this, and it
    // persists when you make a new map.
    public var mapMode:String = 'biome';
    
    // These store the graph data
    public var voronoi:Voronoi;
    public var points:Vector.<Point>;
    public var corners:Vector.<Point>;
    public var attr:Dictionary;

    public function voronoi_set() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      addChild(new Debug(this));

      addExportButtons();
      addGenerateButtons();
      newIsland();
      go();
    }

    // Random parameters governing the overall shape of the island
    public var island:Object;
    public function newIsland():void {
      island = {
        bumps: islandRandom.nextIntRange(1, 6),
        startAngle: islandRandom.nextDoubleRange(0, 2*Math.PI),
        dipAngle: islandRandom.nextDoubleRange(0, 2*Math.PI),
        dipWidth: islandRandom.nextDoubleRange(0.2, 0.7)
      };
    }

    public function reset():void {
      // Break cycles before we remove the reference to attr;
      // otherwise the garbage collector won't release it.
      if (attr) {
        for (var key:Object in attr) {
          delete attr[key];
        }
      }
      if (points) {
        points.splice(0, points.length);
      }
      if (corners) {
        corners.splice(0, corners.length);
      }
      if (voronoi) {
        voronoi.dispose();
        voronoi = null;
      }

      // Clear the previous graph data. We'll reuse attr and points
      // when we can, but there's no easy way to reuse the Voronoi
      // object, so we'll allocate a new one.
      if (!attr) attr = new Dictionary(true);
      if (!points) points = new Vector.<Point>();
      if (!corners) corners = new Vector.<Point>();
      
      System.gc();
      Debug.trace("MEMORY BEFORE:", System.totalMemory);
    }
      

    public function graphicsReset():void {
      graphics.clear();
      graphics.beginFill(0x555599);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();
    }

    
    public function go():void {
      reset();

      var i:int, j:int, t:Number;
      var p:Point, q:Point, r:Point, s:Point;
      var t0:Number = getTimer();

      
      // Generate the initial random set of points
      t = getTimer();
      generateRandomPoints();
      Debug.trace("TIME for random points:", getTimer()-t);

      
      // Build the Voronoi structure with our random points
      t = getTimer();
      voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));
      Debug.trace("TIME for voronoi:", getTimer()-t);


      // Create a graph structure from the Voronoi edge list. The
      // methods in the Voronoi object are somewhat inconvenient for
      // my needs, so I transform that data into the data I actually
      // need: edges connected to the Delaunay triangles and the
      // Voronoi polygons, a reverse map from those four points back
      // to the edge, a map from these four points to the points
      // they connect to (both along the edge and crosswise).
      t = getTimer();
      buildGraph();
      Debug.trace("TIME for buildGraph:", getTimer()-t);
      

      // Determine the elevations and water at Voronoi corners.
      t = getTimer();
      assignCornerElevations();
      Debug.trace("TIME for elevation queue processing:", getTimer()-t);

      
      // Determine polygon type: ocean, coast, land, and assign
      // elevation to land polygons based on corner elevations. We
      // have to do this before rescaling because rescaling only
      // applies to land corners.
      t = getTimer();
      assignOceanCoastAndLand();
      Debug.trace("TIME for ocean/coast/land:", getTimer()-t);

      
      // Rescale elevations so that the highest is 1.0, and they're
      // distributed well. We want lower elevations to be more common
      // than higher elevations, in proportions approximately matching
      // concentric rings. That is, the lowest elevation is the
      // largest ring around the island, and therefore should more
      // land area than the highest elevation, which is the very
      // center of a perfectly circular island.
      t = getTimer();

      var landPoints:Vector.<Point> = new Vector.<Point>();  // only non-ocean
      for each (p in corners) {
          if (attr[p].ocean || attr[p].coast) {
            attr[p].elevation = 0.0;
          } else {
            landPoints.push(p);
          }
        }
      for (i = 0; i < 10; i++) {
        redistributeElevations(landPoints);
      }
      assignPolygonElevations();
      Debug.trace("TIME for elevation rescaling:", getTimer()-t);
      

      // Determine downslope paths.
      t = getTimer();
      calculateDownslopes();
      Debug.trace("TIME for downslope paths:", getTimer()-t);


      // Determine watersheds: for every corner, where does it flow
      // out into the ocean? 
      t = getTimer();
      i = calculateWatersheds();
      Debug.trace("TIME for", i, "steps of watershed:", getTimer()-t);

      
      // Create rivers.
      t = getTimer();
      createRivers();
      Debug.trace("TIME for river paths:", getTimer()-t);

      
      // Calculate moisture, starting at rivers and lakes, but not oceans.
      t = getTimer();
      calculateMoisture();
      Debug.trace("TIME for moisture calculation:", getTimer()-t);

      
      // Choose polygon biomes based on elevation, water, ocean
      t = getTimer();
      assignTerrains();
      Debug.trace("TIME for terrain assignment:", getTimer()-t);


      // Mark areas in each contour area and place roads along the
      // contour lines.
      t = getTimer();
      createRoads();
      Debug.trace("TIME for roads:", getTimer()-t);
      
      
      // For all edges between polygons, build a noisy line path that
      // we can reuse while drawing both polygons connected to that
      // edge. The noisy lines are constructed in two sections, going
      // from the vertex to the midpoint. We don't construct the noisy
      // lines from the polygon centers to the midpoints, because
      // they're not needed for polygon filling.
      t = getTimer();
      buildNoisyEdges(points, attr);
      Debug.trace("TIME for noisy edge construction:", getTimer()-t);


      // Render the polygons first, including polygon edges
      // (coastline, lakeshores), then other edges (rivers, lava).
      t = getTimer();
      drawMap();
      Debug.trace("TIME for rendering:", getTimer()-t);

      Debug.trace("MEMORY AFTER:", System.totalMemory, " TIME taken:", getTimer()-t0,"ms");
    }

    
    // Generate random points and assign them to be on the island or
    // in the water. Some water points are inland lakes; others are
    // ocean. We'll determine ocean later by looking at what's
    // connected to ocean.
    public function generateRandomPoints():void {
      for (var i:int = 0; i < NUM_POINTS; i++) {
        var p:Point = new Point(mapRandom.nextDoubleRange(10, SIZE-10),
                                mapRandom.nextDoubleRange(10, SIZE-10));
        points.push(p);
        attr[p] = {
          type: 'v'
        };
      }
    }

    
    // Build graph data structure in the 'attr' objects, based on
    // information in the Voronoi results: attr[point].neighbors will
    // be a list of neighboring points of the same type (corner or
    // center); attr[point].edges will be a list of edges that include
    // that point; attr[point].type will be 'd' if it's a Delaunay
    // triangle center and 'v' if it's a Voronoi polygon center. Each
    // edge connects to four points: the Voronoi edge
    // attr[edge].{v0,v1} and its dual Delaunay triangle edge
    // attr[edge].{d0,d1}.  Also, attr[edge].type is 'e'. For boundary
    // polygons, the Delaunay edge will have one null point, and the
    // Voronoi edge may be null.
    public function buildGraph():void {
      var point:Point, other:Point;
      var edges:Vector.<Edge> = voronoi.edges();
      
      // Workaround for Voronoi lib bug: we need to call region()
      // before Edges or neighboringSites are available
      for each (point in points) {
          voronoi.region(point);
        }
      
      // Build the graph skeleton for the polygon centers
      for each (point in points) {
          attr[point].edges = new Vector.<Edge>();
          attr[point].neighbors = new  Vector.<Point>();
          attr[point].corners = new Vector.<Point>();
        }

      // Workaround: the Voronoi library will allocate multiple corner
      // Point objects; we need to put them into the corners list only
      // once, so that we can use these points in a Dictionary.  To
      // make lookup fast, we keep an array of points, bucketed by x
      // value, and then we only have to look at other points in
      // nearby buckets.
      var _cornerMap:Array = [];
      function makeCorner(p:Point):Point {
        if (p == null) return p;
        for (var bucket:int = int(p.x)-1; bucket <= int(p.x)+1; bucket++) {
          for each (var q:Point in _cornerMap[bucket]) {
              var dx:Number = p.x - q.x;
              var dy:Number = p.y - q.y;
              if (dx*dx + dy*dy < 1e-6) {
                return q;
              }
            }
        }
        bucket = int(p.x);
        if (!_cornerMap[bucket]) _cornerMap[bucket] = [];
        _cornerMap[bucket].push(p);
        return p;
      }
    
      function fillAttr(edge:Edge, points:Array, duals:Array):void {
        var point:Point, other:Point;
        for each (point in points) {
            var A:Object = attr[point];
            A.edges.push(edge);
            for each (other in points) {
                if (point != other) A.neighbors.push(other);
              }
            for each (other in duals) {
                if (A.corners.indexOf(other) < 0) A.corners.push(other);
              }
          }
      }

      for each (var edge:Edge in edges) {
          var dedge:LineSegment = edge.delaunayLine();
          var vedge:LineSegment = edge.voronoiEdge();

          // The Voronoi library generates multiple Point objects for
          // corners, and we need to have just one so we can index.
          vedge.p0 = makeCorner(vedge.p0);
          vedge.p1 = makeCorner(vedge.p1);
          
          // Build the graph skeleton for the corners
          for each (point in [vedge.p0, vedge.p1]) {
              if (point != null && attr[point] == null) {
                corners.push(point);
                attr[point] = {
                  type: 'd',
                  edges: new Vector.<Edge>(),
                  neighbors: new Vector.<Point>(),
                  corners: new Vector.<Point>()
                };
              }
          }
          // Fill the graph data for polygons and corners
          var vpoints:Array = [];
          var dpoints:Array = [];
          if (dedge.p0 != null) vpoints.push(dedge.p0);
          if (dedge.p1!= null) vpoints.push(dedge.p1);
          if (vedge.p0 != null) dpoints.push(vedge.p0);
          if (vedge.p1 != null) dpoints.push(vedge.p1);
          fillAttr(edge, dpoints, vpoints);
          fillAttr(edge, vpoints, dpoints);
          
          // Per edge attributes
          attr[edge] = {type: 'e'};
          attr[edge].v0 = vedge.p0;
          attr[edge].v1 = vedge.p1;
          attr[edge].d0 = dedge.p0;
          attr[edge].d1 = dedge.p1;
          attr[edge].midpoint = vedge.p0 && vedge.p1 && Point.interpolate(vedge.p0, vedge.p1, 0.5);
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
      var p:Point, q:Point;
      var queue:Array = [];
      
      for each (p in corners) {
          attr[p].water = !inside(island, p);
        }

      for each (p in corners) {
          // The edges of the map are elevation 0
          if (p.x == 0 || p.x == SIZE || p.y == 0 || p.y == SIZE) {
            attr[p].elevation = 0.0;
            attr[p].border = true;
            queue.push(p);
          }
        }
      // Traverse the graph and assign elevations to each point. As we
      // move away from the coastline, increase the elevations. This
      // guarantees that rivers always have a way down to the coast by
      // going downhill (no local minima).
      while (queue.length > 0) {
        p = queue.shift();

        for each (q in attr[p].neighbors) {
            // Every step up is epsilon over water or 1 over land. The
            // number doesn't matter because we'll rescale the
            // elevations later.
            var newElevation:Number = 0.01 + attr[p].elevation;
            if (!attr[q].water && !attr[p].water) {
              newElevation += 1;
            }
            // If this point changed, we'll add it to the queue so
            // that we can process its neighbors too.
            if (attr[q].elevation == null || newElevation < attr[q].elevation) {
              attr[q].elevation = newElevation;
              queue.push(q);
            }
          }
      }
    }
    
    // Change the overall distribution of elevations so that lower
    // elevations are more common than higher
    // elevations. Specifically, we want elevation X to have
    // frequency (K+maxElevation-X), for some value of K.  To do
    // this we will compute a histogram of the elevations, then
    // compute the cumulative sum, then try to make that match the
    // desired cumulative sum. The desired cumulative sum is the
    // integral of the desired frequency distribution.
    public function redistributeElevations(points:Vector.<Point>):void {
      var maxElevation:int = 20;
      var M:Number = 1+maxElevation;
      var p:Point, i:int, x:Number, x0:Number, x1:Number, f:Number, y0:Number, y1:Number;
      var histogram:Array = [];

      // First, rescale the points so that none is greater than maxElevation
      x = 1.0;
      for each (p in points) {
          if (attr[p].elevation > x) {
            x = attr[p].elevation;
          }
        }
      // As we rescale, build a histogram of the resulting elevations
      for each (p in points) {
          attr[p].elevation *= maxElevation / x;
          i = int(Math.floor(attr[p].elevation));
          histogram[i] = (histogram[i] || 0) + 1;
        }

      // Build a cumulative sum of the histogram. We want this to
      // match a target distribution, and will adjust all the
      // elevations to get closer to that.
      var cumulative:Array = [];
      cumulative[0] = 0.0;
      for (i = 0; i < maxElevation; i++) {
        cumulative[i+1] = (cumulative[i] || 0) + (histogram[i] || 0);
      }

      // Remap each point's elevation (x) to be closer to the target
      // distribution. We have an actual cumulative distribution y(x)
      // and a desired cumulative distribution y'(x).  Given x, we
      // compute y(x), then set y(x) = y'(x), then solve for x in the
      // y'(x)=... equation. That gives us the corresponding elevation
      // in the target distribution.
      function remap(x:Number):Number {
          // We don't have the actual cumulative distribution computed
          // for all points. x falls into a histogram bucket from x0
          // to x1, and we can interpolate.
          x0 = Math.floor(x);
          if (x0 >= maxElevation) x0 = maxElevation-1.0;
          x1 = x0 + 1.0;
          f = x - x0;  /* fractional part */
          // We'll map x0 and x1 into the actual cumulative sum, y0 and y1
          y0 = cumulative[int(x0)];
          y1 = cumulative[int(x1)];

          // We need to map these cumulative y's back to a desired
          // x. The desired histogram at x is (M-x). The
          // integral of this is (-0.5*x^2 + M*x). To
          // solve for x, we need to use the quadratic formula.
          x0 = M * (1 - Math.sqrt(1 - y0/points.length));
          x1 = M * (1 - Math.sqrt(1 - y1/points.length));
          // Since we only have mapped the values at the histogram
          // boundaries, we need to interpolate to get the value for
          // this point.
          x = (1-f)*x0 + f*x1;

          if (x > maxElevation) x = maxElevation;
          return x/maxElevation;
      }
      
      for each (p in points) {
          attr[p].elevation = remap(attr[p].elevation);
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
      var p:Point, q:Point;
      
      for each (p in points) {
          for each (q in attr[p].corners) {
              if (attr[q].border) {
                attr[p].border = true;
                attr[p].ocean = true;
                queue.push(p);
              }
              if (attr[q].water) {
                attr[p].water = (attr[p].water || 0) + 1;
              }
            }
          if (attr[p].water && attr[p].water < attr[p].corners.length * LAKE_THRESHOLD) {
            delete attr[p].water;
          }
        }
      while (queue.length > 0) {
        p = queue.shift();
        for each (q in attr[p].neighbors) {
            if (attr[q].water && !attr[q].ocean) {
              attr[q].ocean = true;
              queue.push(q);
            }
          }
      }
      
      // Set the polygon attribute 'coast' based on its neighbors. If
      // it has at least one ocean and at least one land neighbor,
      // then this is a coastal polygon.
      for each (p in points) {
          var numOcean:int = 0;
          var numLand:int = 0;
          for each (q in attr[p].neighbors) {
              numOcean += int(attr[q].ocean);
              numLand += int(!attr[q].water);
            }
          attr[p].coast = (numOcean > 0) && (numLand > 0);
        }


      // Set the corner attributes based on the computed polygon
      // attributes. If all polygons connected to this corner are
      // ocean, then it's ocean; if all are land, then it's land;
      // otherwise it's coast. We no longer want the 'water'
      // attribute; that was used only to determine polygon types.
      for each (p in corners) {
          numOcean = 0;
          numLand = 0;
          for each (q in attr[p].corners) {
              numOcean += int(attr[q].ocean);
              numLand += int(!attr[q].water);
            }
          attr[p].ocean = (numOcean == attr[p].corners.length);
          attr[p].coast = (numOcean > 0) && (numLand > 0);
          attr[p].water = (numLand != attr[p].corners.length) && !attr[p].coast;
        }
    }
  

    // Polygon elevations are the average of the elevations of their corners.
    public function assignPolygonElevations():void {
      var p:Point, q:Point, sumElevation:Number;
      for each (p in points) {
          sumElevation = 0.0;
          for each (q in attr[p].corners) {
              sumElevation += attr[q].elevation;
            }
          attr[p].elevation = sumElevation / attr[p].corners.length;
        }
    }

    
    // Calculate downslope pointers.  At every point, we point to the
    // point downstream from it, or to itself.  This is used for
    // generating rivers and watersheds.
    public function calculateDownslopes():void {
      var p:Point, q:Point, r:Point;
      
      for each (p in corners) {
          r = p;
          for each (q in attr[p].neighbors) {
              if (attr[q].elevation <= attr[r].elevation) {
                r = q;
              }
            }
          attr[p].downslope = r;
        }
    }


    // Calculate the watershed of every land point. The watershed is
    // the last downstream land point in the downslope graph.
    public function calculateWatersheds():int {
      var p:Point, q:Point, i:int, changed:Boolean;
      
      // Initially the watershed pointer points downslope one step.      
      for each (p in corners) {
          attr[p].watershed = p;
          if (!attr[p].ocean && !attr[p].coast) {
            attr[p].watershed = attr[p].downslope;
          }
        }
      // Follow the downslope pointers to the coast. Limit to 100
      // iterations although most of the time with NUM_POINTS=2000 it
      // only takes 20 iterations because most points are not far from
      // a coast.  TODO: can run faster by looking at
      // p.watershed.watershed instead of p.downslope.watershed.
      for (i = 0; i < 100; i++) {
        changed = false;
        for each (p in corners) {
            if (!attr[p].ocean && !attr[p].coast && !attr[attr[p].watershed].coast) {
              q = attr[attr[p].downslope].watershed;
              if (!attr[q].ocean) attr[p].watershed = q;
              changed = true;
            }
          }
        if (!changed) break;
      }
      // How big is each watershed?
      for each (p in corners) {
          q = attr[p].watershed;
          attr[q].watershed_size = 1 + (attr[q].watershed_size || 0);
        }
      return i;
    }


    // Create rivers along edges. Pick a random corner point, then
    // move downslope. Mark the edges and corners as rivers.
    public function createRivers():void {
      var i:int, p:Point, edge:Edge;
      
      for (i = 0; i < SIZE/2; i++) {
        p = corners[mapRandom.nextIntRange(0, corners.length-1)];
        if (attr[p].ocean || attr[p].elevation < 0.3 || attr[p].elevation > 0.9) continue;
        // Bias rivers to go west: if (attr[p].downslope.x > p.x) continue;
        while (!attr[p].coast) {
          if (p == attr[p].downslope) {
            Debug.trace("Downslope failed", attr[p].elevation);
            break;
          }
          edge = lookupEdgeFromCorner(p, attr[p].downslope);
          attr[edge].river = (attr[edge].river || 0) + 1;
          attr[p].river = (attr[p].river || 0) + 1;
          attr[attr[p].downslope].river = (attr[attr[p].downslope].river || 0) + 1;
          p = attr[p].downslope;
        }
      }
    }


    // Calculate moisture. Freshwater sources spread moisture: rivers
    // and lakes (not oceans). Saltwater sources have moisture but do
    // not spread it (we set it at the end, after propagation). TODO:
    // the parameters (1.5, 0.2, 0.9) are tuned for NUM_POINTS = 2000,
    // and it's not clear how they should be adjusted for other
    // scales. Redistributing moisture might be the simplest solution.
    public function calculateMoisture():void {
      var p:Point, q:Point, sumMoisture:Number;
      var queue:Array = [];
      // Fresh water
      for each (p in corners) {
          if ((attr[p].water || attr[p].river) && !attr[p].ocean) {
            attr[p].moisture = attr[p].river? Math.min(1.8, (0.2 * attr[p].river)) : 1.0;
            queue.push(p);
          } else {
            attr[p].moisture = 0.0;
          }
        }
      while (queue.length > 0) {
        p = queue.shift();

        for each (q in attr[p].neighbors) {
            var newMoisture:Number = attr[p].moisture * 0.85;
            if (newMoisture > attr[q].moisture) {
              attr[q].moisture = newMoisture;
              queue.push(q);
            }
          }
      }
      // Salt water
      for each (p in corners) {
          if (attr[p].ocean) attr[p].moisture = 1.0;
        }
      // Polygon moisture is the average of the moisture at corners
      for each (p in points) {
          sumMoisture = 0.0;
          for each (q in attr[p].corners) {
              if (attr[q].moisture > 1.0) attr[q].moisture = 1.0;
              sumMoisture += attr[q].moisture;
            }
          attr[p].moisture = sumMoisture / attr[p].corners.length;
        }
    }


    // We want to mark different elevation zones so that we can draw
    // island-circling roads that divide the areas.
    public function createRoads():void {
      // Oceans and coastal polygons are the lowest contour zone
      // (1). Anything connected to contour level K, if it's below
      // elevation threshold K, or if it's water, gets contour level
      // K.  (2) Anything not assigned a contour level, and connected
      // to contour level K, gets contour level K+1.
      var queue:Array = [];
      var p:Point, q:Point, edge:Edge, newLevel:int;
      var elevationThresholds:Array = [0, 0.05, 0.25, 0.55, 1.0];

      for each (p in points) {
          if (attr[p].coast || attr[p].ocean) {
            attr[p].contour = 1;
            queue.push(p);
          }
        }
      while (queue.length > 0) {
        p = queue.shift();
        for each (q in attr[p].neighbors) {
            newLevel = attr[p].contour || 0;
            while (attr[q].elevation > elevationThresholds[newLevel] && !attr[q].water) {
              // NOTE: extend the contour line past bodies of
              // water so that roads don't terminate inside lakes.
              newLevel += 1;
            }
            if (newLevel < (attr[q].contour || 999)) {
              attr[q].contour = newLevel;
              queue.push(q);
            }
          }
      }

      // A corner's contour level is the MIN of its polygons
      for each (p in points) {
          for each (q in attr[p].corners) {
              attr[q].contour = Math.min(attr[q].contour || 999, attr[p].contour || 999);
            }
        }

      // Roads go between polygons that have different contour levels
      for each (p in points) {
          for each (edge in attr[p].edges) {
              if (attr[edge].v0 && attr[edge].v1
                  && attr[attr[edge].v0].contour != attr[attr[edge].v1].contour) {
                attr[edge].road = true;
                attr[p].road_connections = (attr[p].road_connections || 0) + 1;
              }
            }
        }
    }
      
    
    // Assign a terrain type to each polygon. If it has
    // ocean/coast/water, then that's the terrain type; otherwise it
    // depends on low/high elevation and low/medium/high moisture.
    public function assignTerrains():void {
      for each (var p:Point in points) {
          var A:Object = attr[p];
          if (A.ocean) {
            A.biome = 'OCEAN';
          } else if (A.water) {
            A.biome = 'LAKE';
            if (A.elevation < 0.1) A.biome = 'MARSH';
            if (A.elevation > 0.85) A.biome = 'ICE';
          } else if (A.coast) {
            A.biome = 'BEACH';
          } else if (A.elevation > 0.85) {
            if (A.moisture > 0.5) A.biome = 'SNOW';
            else if (A.moisture > 0.3) A.biome = 'BARE'; 
            else A.biome = 'SCORCHED';
          } else if (A.elevation > 0.3) {
            if (A.moisture > 0.8) A.biome = 'DRY_FOREST';
            else if (A.moisture > 0.5) A.biome = 'GRASSLANDS';
            else if (A.moisture > 0.235) A.biome = 'SAVANNAH';
            else A.biome = 'DESERT';
          } else {
            if (A.moisture > 0.9) A.biome = 'SWAMP';
            else if (A.moisture > 0.5) A.biome = 'RAIN_FOREST';
            else if (A.moisture > 0.235) A.biome = 'GRASSLANDS';
            else A.biome = 'DESERT';
          }
        }
    }
    
    // Build noisy line paths for each of the Voronoi edges. There are
    // two noisy line paths for each edge, each covering half the
    // distance: attr[edge].path0 will be from v0 to the midpoint and
    // attr[edge].path1 will be from v1 to the midpoint. When drawing
    // the polygons, one or the other must be drawn in reverse order.
    public function buildNoisyEdges(points:Vector.<Point>, attr:Dictionary):void {
      var _count:int = 0;
      for each (var point:Point in points) {
          for each (var edge:Edge in attr[point].edges) {
              if (attr[edge].d0 && attr[edge].d1 && attr[edge].v0 && attr[edge].v1
                  && !attr[edge].path0) {
                var f:Number = NOISY_LINE_TRADEOFF;
                var p:Point = Point.interpolate(attr[edge].v0, attr[edge].d0, f);
                var q:Point = Point.interpolate(attr[edge].v0, attr[edge].d1, f);
                var r:Point = Point.interpolate(attr[edge].v1, attr[edge].d0, f);
                var s:Point = Point.interpolate(attr[edge].v1, attr[edge].d1, f);

                var minLength:int = 4;
                if (attr[attr[edge].d0].water != attr[attr[edge].d1].water) minLength = 3;
                if (attr[attr[edge].d0].biome == attr[attr[edge].d1].biome) minLength = 8;
                if (attr[attr[edge].d0].ocean && attr[attr[edge].d1].ocean) minLength = 100;
                
                attr[edge].path0 = noisy_line.buildLineSegments(attr[edge].v0, p, attr[edge].midpoint, q, minLength);
                attr[edge].path1 = noisy_line.buildLineSegments(attr[edge].v1, s, attr[edge].midpoint, r, minLength);
                _count++;
              }
            }
        }
    }
    

    // Look up a Voronoi Edge object given two adjacent Voronoi
    // polygons, or two adjacent Voronoi corners
    public function lookupEdgeFromCenter(p:Point, q:Point):Edge {
      for each (var edge:Edge in attr[p].edges) {
          if (attr[edge].d0 == q || attr[edge].d1 == q) return edge;
        }
      return null;
    }

    public function lookupEdgeFromCorner(p:Point, q:Point):Edge {
      for each (var edge:Edge in attr[p].edges) {
          if (attr[edge].v0 == q || attr[edge].v1 == q) return edge;
        }
      return null;
    }

    
    // Determine whether a given point should be on the island or in the water.
    public function inside(island:Object, p:Point):Boolean {
      var q:Point = new Point(p.x-SIZE/2, p.y-SIZE/2);  // normalize to center of island
      var angle:Number = Math.atan2(q.y, q.x);
      var length:Number = 0.5 * (Math.max(Math.abs(q.x), Math.abs(q.y)) + q.length) / (SIZE/2);
      var r1:Number = 0.5 + 0.40*Math.sin(island.startAngle + island.bumps*angle + Math.cos((island.bumps+3)*angle));
      var r2:Number = 0.7 - 0.20*Math.sin(island.startAngle + island.bumps*angle - Math.sin((island.bumps+2)*angle));
      if (Math.abs(angle - island.dipAngle) < island.dipWidth
          || Math.abs(angle - island.dipAngle + 2*Math.PI) < island.dipWidth
          || Math.abs(angle - island.dipAngle - 2*Math.PI) < island.dipWidth) {
        r1 = r2 = 0.2;
      }
      return  (length < r1 || (length > r1*ISLAND_FACTOR && length < r2));
    }


    // Helper functions for rendering paths
    private function drawPathForwards(graphics:Graphics, path:Vector.<Point>):void {
      for (var i:int = 0; i < path.length; i++) {
        graphics.lineTo(path[i].x, path[i].y);
      }
    }
    private function drawPathBackwards(graphics:Graphics, path:Vector.<Point>):void {
      for (var i:int = path.length-1; i >= 0; i--) {
        graphics.lineTo(path[i].x, path[i].y);
      }
    }


    // Helper function for color manipulation
    private function interpolateColor(color1:uint, color2:uint, f:Number):uint {
      var r:uint = uint((1-f)*(color1 >> 16) + f*(color2 >> 16));
      var g:uint = uint((1-f)*((color1 >> 8) & 0xff) + f*((color2 >> 8) & 0xff));
      var b:uint = uint((1-f)*(color1 & 0xff) + f*(color2 & 0xff));
      if (r > 255) r = 255;
      if (g > 255) g = 255;
      if (b > 255) b = 255;
      return (r << 16) | (g << 8) | b;
    }

    
    // Helper function for drawing triangles with gradients. This
    // function sets up the fill on the graphics object, and then
    // calls fillFunction to draw the desired path.
    private function drawGradientTriangle(graphics:Graphics,
                                          v1:Vector3D, v2:Vector3D, v3:Vector3D,
                                          color1:uint, color2:uint,
                                          fillFunction:Function):void {
      var m:Matrix = new Matrix();

      // Center of triangle:
      var V:Vector3D = v1.add(v2).add(v3);
      V.scaleBy(1/3.0);

      // Normal of the plane containing the triangle:
      var N:Vector3D = v2.subtract(v1).crossProduct(v3.subtract(v1));
      N.normalize();

      // Gradient vector in x-y plane pointing in the direction of increasing z
      var G:Vector3D = new Vector3D(-N.x/N.z, -N.y/N.z, 0);

      // Center of the color gradient
      var C:Vector3D = new Vector3D(V.x - G.x*((V.z-0.5)/G.length/G.length), V.y - G.y*((V.z-0.5)/G.length/G.length));

      if (G.length < 1e-6) {
        // If the gradient vector is small, there's not much
        // difference in colors across this triangle. Use a plain
        // fill, because the numeric accuracy of 1/G.length is not to
        // be trusted.
        graphics.beginFill(interpolateColor(color1, color2, V.z));
      } else {
        // The gradient box is weird to set up, so we let Flash set up
        // a basic matrix and then we alter it:
        m.createGradientBox(1, 1, 0, 0, 0);
        m.translate(-0.5, -0.5);
        m.scale((1/G.length), (1/G.length));
        m.rotate(Math.atan2(G.y, G.x));
        m.translate(C.x, C.y);
        graphics.beginGradientFill(GradientType.LINEAR, [color1, color2],
                                   [1, 1], [0x00, 0xff], m, SpreadMethod.PAD);
      }
      fillFunction();
      graphics.endFill();
    }
    

    // Draw the map in the current map mode
    public function drawMap():void {
      graphicsReset();
      if (mapMode == 'biome') {
        renderPolygons(graphics, displayColors, true, null, null);
      } else if (mapMode == 'slopes') {
        renderPolygons(graphics, displayColors, true, null, colorWithSlope);
      } else if (mapMode == 'smooth') {
        renderPolygons(graphics, displayColors, false, null, colorWithSmoothColors);
      } else if (mapMode == 'elevation') {
        renderPolygons(graphics, elevationGradientColors, false, 'elevation', null);
      } else if (mapMode == 'moisture') {
        renderPolygons(graphics, moistureGradientColors, false, 'moisture', null);
      }

      if (mapMode != 'slopes' && mapMode != 'moisture') {
        renderRoads(graphics, displayColors);
      }
      renderEdges(graphics, displayColors);
    }

    
    // Render the interior of polygons
    public function renderPolygons(graphics:Graphics, colors:Object, texturedFills:Boolean, gradientFillProperty:String, colorOverrideFunction:Function):void {
      var p:Point, q:Point;

      // My Voronoi polygon rendering doesn't handle the boundary
      // polygons, so I just fill everything with ocean first.
      graphics.beginFill(colors.OCEAN);
      graphics.drawRect(0, 0, SIZE, SIZE);
      graphics.endFill();
      
      for each (p in points) {
          for each (q in attr[p].neighbors) {
              var edge:Edge = lookupEdgeFromCenter(p, q);
              var color:int = colors[attr[p].biome];
              if (colorOverrideFunction != null) {
                color = colorOverrideFunction(color, p, q, edge);
              }

              function drawPath0():void {
                graphics.moveTo(p.x, p.y);
                graphics.lineTo(attr[edge].path0[0].x, attr[edge].path0[0].y);
                drawPathForwards(graphics, attr[edge].path0);
                graphics.lineTo(p.x, p.y);
              }

              function drawPath1():void {
                graphics.moveTo(p.x, p.y);
                graphics.lineTo(attr[edge].path1[0].x, attr[edge].path1[0].y);
                drawPathForwards(graphics, attr[edge].path1);
                graphics.lineTo(p.x, p.y);
              }

              if (attr[edge].path0 == null || attr[edge].path1 == null) {
                // It's at the edge of the map, where we don't have
                // the noisy edges computed. TODO: figure out how to
                // fill in these edges from the voronoi library.
                continue;
              }

              if (gradientFillProperty != null) {
                // We'll draw two triangles: center - corner0 -
                // midpoint and center - midpoint - corner1.
                var corner0:Point = attr[edge].v0;
                var corner1:Point = attr[edge].v1;

                // We pick the midpoint elevation/moisture between
                // corners instead of between polygon centers because
                // the resulting gradients tend to be smoother.
                var midpoint:Point = attr[edge].midpoint;
                var midpointAttr:Number = 0.5*(attr[corner0][gradientFillProperty]+attr[corner1][gradientFillProperty]);
                drawGradientTriangle
                  (graphics,
                   new Vector3D(p.x, p.y, attr[p][gradientFillProperty]),
                   new Vector3D(corner0.x, corner0.y, attr[corner0][gradientFillProperty]),
                   new Vector3D(midpoint.x, midpoint.y, midpointAttr),
                   colors.GRADIENT_LOW, colors.GRADIENT_HIGH, drawPath0);
                drawGradientTriangle
                  (graphics,
                   new Vector3D(p.x, p.y, attr[p][gradientFillProperty]),
                   new Vector3D(midpoint.x, midpoint.y, midpointAttr),
                   new Vector3D(corner1.x, corner1.y, attr[corner1][gradientFillProperty]),
                   colors.GRADIENT_LOW, colors.GRADIENT_HIGH, drawPath1);
              } else if (texturedFills) {
                graphics.beginBitmapFill(getBitmapTexture(color));
                drawPath0();
                drawPath1();
                graphics.endFill();
              } else {
                graphics.beginFill(color);
                drawPath0();
                drawPath1();
                graphics.endFill();
              }
            }
        }
    }


    // Render roads. We draw these before polygon edges, so that rivers overwrite roads.
    public function renderRoads(graphics:Graphics, colors:Object):void {
      // First draw the roads, because any other feature should draw
      // over them. Also, roads don't use the noisy lines.
      var p:Point, q:Point, A:Point, B:Point, C:Point;
      var i:int, j:int, d:Number, edge1:Edge, edge2:Edge, edges:Vector.<Edge>;

      // Helper function: find the normal vector across edge 'e' and
      // make sure to point it in a direction towards 'c'.
      function normalTowards(e:Edge, c:Point, len:Number):Point {
        // Rotate the v0-->v1 vector by 90 degrees:
        var n:Point = new Point(-(attr[e].v1.y - attr[e].v0.y),
                                attr[e].v1.x - attr[e].v0.x);
        // Flip it around it if doesn't point towards c
        var d:Point = c.subtract(attr[e].midpoint);
        if (n.x * d.x + n.y * d.y < 0) {
          n.x = -n.x;
          n.y = -n.y;
        }
        n.normalize(len);
        return n;
      }
      
      for each (p in points) {
          if (attr[p].road_connections == 2) {
            // Regular road: draw a spline from one edge to the other.
            edges = attr[p].edges;
            for (i = 0; i < edges.length; i++) {
              edge1 = edges[i];
              if (attr[edge1].road) {
                for (j = i+1; j < edges.length; j++) {
                  edge2 = edges[j];
                  if (attr[edge2].road) {
                    // The spline connects the midpoints of the edges
                    // and at right angles to them. In between we
                    // generate two control points A and B and one
                    // additional vertex C.  This usually works but
                    // not always. TODO: compute d as the distance
                    // from the center to the line instead of center
                    // to the midpoint.
                    d = 0.4*Math.min
                      (attr[edge1].midpoint.subtract(p).length,
                       attr[edge2].midpoint.subtract(p).length);
                    A = normalTowards(edge1, p, d).add(attr[edge1].midpoint);
                    B = normalTowards(edge2, p, d).add(attr[edge2].midpoint);
                    C = Point.interpolate(A, B, 0.5);
                    graphics.lineStyle(1.1, colors.ROAD);
                    graphics.moveTo(attr[edge1].midpoint.x, attr[edge1].midpoint.y);
                    graphics.curveTo(A.x, A.y, C.x, C.y);
                    graphics.curveTo(B.x, B.y, attr[edge2].midpoint.x, attr[edge2].midpoint.y);
                    graphics.lineStyle();
                  }
                }
              }
            }
          }
          if (attr[p].road_connections && attr[p].road_connections != 2) {
            // Intersection: draw a road spline from each edge to the center
            for each (edge1 in attr[p].edges) {
                if (attr[edge1].road) {
                  d = 0.25*attr[edge1].midpoint.subtract(p).length;
                  A = normalTowards(edge1, p, d).add(attr[edge1].midpoint);
                  graphics.lineStyle(1.4, colors.ROAD);
                  graphics.moveTo(attr[edge1].midpoint.x, attr[edge1].midpoint.y);
                  graphics.curveTo(A.x, A.y, p.x, p.y);
                  graphics.lineStyle();
                }
              }
          }
        }
    }

    
    // Render the exterior of polygons: coastlines, lake shores,
    // rivers, lava fissures. We draw all of these after the polygons
    // so that polygons don't overwrite any edges.
    public function renderEdges(graphics:Graphics, colors:Object):void {
      var p:Point, q:Point, edge:Edge;

      for each (p in points) {
          for each (q in attr[p].neighbors) {
              edge = lookupEdgeFromCenter(p, q);
              if (attr[edge].path0 == null || attr[edge].path1 == null) {
                // It's at the edge of the map, where we don't have
                // the noisy edges computed. TODO: fill these in with
                // non-noisy lines.
                continue;
              }
              if (attr[p].ocean != attr[q].ocean) {
                // One side is ocean and the other side is land -- coastline
                graphics.lineStyle(2, colors.COAST);
              } else if ((attr[p].water > 0) != (attr[q].water > 0) && attr[p].biome != 'ICE' && attr[q].biome != 'ICE') {
                // Lake boundary
                graphics.lineStyle(1, colors.LAKESHORE);
              } else if (attr[p].water || attr[q].water) {
                // Lake interior – we don't want to draw the rivers here
                continue;
              } else if (attr[edge].river != null) {
                // River edge
                graphics.lineStyle(Math.sqrt(attr[edge].river), colors.RIVER);
              } else if (!attr[edge].river && !attr[p].water && !attr[q].water
                         && attr[p].elevation > 0.85 && attr[q].elevation > 0.85
                         && attr[p].moisture < 0.5 && attr[q].moisture < 0.5
                         && mapRandom.nextDouble() < FRACTION_LAVA_FISSURES) {
                // Lava flow
                graphics.lineStyle(1, colors.LAVA);
              } else {
                // No edge
                continue;
              }
              
              graphics.moveTo(attr[edge].path0[0].x, attr[edge].path0[0].y);
              drawPathForwards(graphics, attr[edge].path0);
              drawPathBackwards(graphics, attr[edge].path1);
              graphics.lineStyle();
            }
        }
    }


    private function DEBUG_drawPoints():void {
      var p:Point, q:Point;

      for each (p in points) {
          graphics.beginFill(attr[p].water? 0x0000ff : 0x008800);
          graphics.drawRect(p.x-1,p.y-1,2,2);
          graphics.endFill();
        }

      for each (p in corners) {
          graphics.beginFill(attr[p].ocean? 0x0000ff : 0x008800);
          graphics.drawCircle(p.x, p.y, 1.2);
          graphics.endFill();
        }
    }


    private function DEBUG_drawWatersheds():void {
      var p:Point, q:Point;

      for each (p in corners) {
          if (!attr[p].ocean) {
            q = attr[p].downslope;
            graphics.lineStyle(1.2, attr[p].watershed == attr[q].watershed? 0x00ffff : 0xff00ff,
                               0.1*Math.sqrt(attr[attr[p].watershed].watershed_size || 1));
            graphics.moveTo(p.x, p.y);
            graphics.lineTo(q.x, q.y);
            graphics.lineStyle();
          }
        }
      
      for each (p in corners) {
          for each (q in attr[p].neighbors) {
              if (!attr[p].ocean && !attr[q].ocean && attr[p].watershed != attr[q].watershed && !attr[p].coast && !attr[q].coast) {
                var edge:Edge = lookupEdgeFromCorner(p, q);
                graphics.lineStyle(2.5, 0x000000, 0.05*Math.sqrt((attr[attr[p].watershed].watershed_size || 1) + (attr[attr[q].watershed].watershed_size || 1)));
                graphics.moveTo(attr[edge].d0.x, attr[edge].d0.y);
                graphics.lineTo(attr[edge].midpoint.x, attr[edge].midpoint.y);
                graphics.lineTo(attr[edge].d1.x, attr[edge].d1.y);
                graphics.lineStyle();
              }
            }
        }
    }
    

    // Build a noisy bitmap tile for a given color
    private var _textures:Array = [];
    public function getBitmapTexture(color:uint):BitmapData {
      if (!_textures[color]) {
        var texture:BitmapData = new BitmapData(256, 256);
        texture.noise(487 + color /* random seed */);
        var paletteMap:Array = new Array(256);
        var zeroMap:Array = new Array(256);
        for (var i:int = 0; i < 256; i++) {
          var level:Number = 0.9 + 0.2 * (i / 255.0);

          /* special case */ if (color == 0xffffff) level = 0.95 + 0.1 * (i / 255.0);
          
          var r:int = level * (color >> 16);
          var g:int = level * ((color >> 8) & 0xff);
          var b:int = level * (color & 0xff);

          if (r < 0) r = 0; if (r > 255) r = 255;
          if (g < 0) g = 0; if (g > 255) g = 255;
          if (b < 0) b = 0; if (b > 255) b = 255;
          
          paletteMap[i] = 0xff000000 | (r << 16) | (g << 8) | b;
          zeroMap[i] = 0x00000000;
        }
        texture.paletteMap(texture, texture.rect, new Point(0, 0),
                           paletteMap, zeroMap, zeroMap, zeroMap);
        _textures[color] = texture;
      }
      return _textures[color];
    }


    private var lightVector:Vector3D = new Vector3D(-1, -1, 0);
    public function colorWithSlope(color:int, p:Point, q:Point, edge:Edge):int {
      var r:Point = attr[edge].v0;
      var s:Point = attr[edge].v1;
      if (!r || !s) {
        // Edge of the map
        return displayColors.OCEAN;
      } else if (attr[p].biome == 'LAKE' || attr[p].biome == 'ICE' || attr[p].biome == 'SNOW'
                 || attr[p].biome == 'SCORCHED' || attr[p].biome == 'BARE' || attr[p].biome == 'OCEAN') {
        return color;
      }
      var A:Vector3D = new Vector3D(p.x, p.y, attr[p].elevation);
      var B:Vector3D = new Vector3D(r.x, r.y, attr[r].elevation);
      var C:Vector3D = new Vector3D(s.x, s.y, attr[s].elevation);
      var normal:Vector3D = B.subtract(A).crossProduct(C.subtract(A));
      if (normal.z < 0) { normal.scaleBy(-1); }
      normal.normalize();
      var light:Number = 0.5 + 25*normal.dotProduct(lightVector);
      if (light < 0) light = 0;
      if (light > 1) light = 1;
      light = Math.round(light*100)/100;  // Discrete steps for easier shading
      return interpolateColor(0x1d8e39, 0xcfb78b, light);
    }

    
    public function colorWithSmoothColors(color:int, p:Point, q:Point, edge:Edge):int {
      var biome:String = attr[p].biome;
              
      if (biome != 'ICE' && biome != 'OCEAN' && biome != 'LAKE'
          && biome != 'SCORCHED' && biome != 'BARE' && biome != 'SNOW') {
        function smoothColor(elevation:Number, moisture:Number):int {
          return interpolateColor
            (interpolateColor(0xb19772, 0xcfb78b, elevation),
             interpolateColor(0x1d8e39, 0x97cb1b, elevation),
             moisture);
        }
        color = interpolateColor(smoothColor(attr[p].elevation, attr[p].moisture),
                                 smoothColor(attr[q].elevation, attr[q].moisture),
                                 0.5);
        if (biome == 'BEACH') {
          color = interpolateColor(color, displayColors.BEACH, 0.7);
        }
      }
      
      return color;
    }

    
    //////////////////////////////////////////////////////////////////////
    // The following code is used to export the maps to disk

    // We export elevation, moisture, and an override byte. Instead of
    // rendering with RGB values, we render with bytes 0x00-0xff as
    // colors, and then save these bytes in a ByteArray. For override
    // codes, we turn off anti-aliasing.
    static public var exportOverrideColors:Object = {
      /* override codes are 0:none, 0x10:river water, 0x20:lava,
         0x30:snow, 0x40:ice, 0x50:ocean, 0x60:lake, 0x70:lake shore,
         0x80:ocean shore, 0x90:road.  These are ORed with 0x01:
         polygon center, 0x02: safe polygon center. */
      POLYGON_CENTER: 0x01,
      POLYGON_CENTER_SAFE: 0x03,
      OCEAN: 0x50,
      COAST: 0x80,
      LAKE: 0x60,
      LAKESHORE: 0x70,
      RIVER: 0x10,
      MARSH: 0x10,
      ICE: 0x40,
      SCORCHED: 0x00,
      BEACH: 0x00,
      BARE: 0x00,
      LAVA: 0x20,
      SNOW: 0x30,
      DESERT: 0x00,
      SAVANNAH: 0x00,
      GRASSLANDS: 0x00,
      DRY_FOREST: 0x00,
      RAIN_FOREST: 0x00,
      SWAMP: 0x00,
      ROAD: 0x90
    };

    static public var exportElevationColors:Object = {
      OCEAN: 0x00,
      GRADIENT_LOW: 0x00,
      GRADIENT_HIGH: 0xff
    };

    static public var exportMoistureColors:Object = {
      OCEAN: 0xff,
      GRADIENT_LOW: 0x00,
      GRADIENT_HIGH: 0xff
    };
      
    
    // This function draws to a bitmap and copies that data into the
    // three export byte arrays.  The layer parameter should be one of
    // 'elevation', 'moisture', 'overrides'.
    public function makeExport(layer:String):ByteArray {
      var exportBitmap:BitmapData = new BitmapData(2048, 2048);
      var exportGraphics:Shape = new Shape();
      var exportData:ByteArray = new ByteArray();
      
      var m:Matrix = new Matrix();
      m.scale(2048.0 / SIZE, 2048.0 / SIZE);

      function saveBitmapToArray():void {
        for (var x:int = 0; x < 2048; x++) {
          for (var y:int = 0; y < 2048; y++) {
            exportData.writeByte(exportBitmap.getPixel(x, y) & 0xff);
          }
        }
      }

      if (layer == 'overrides') {
        renderPolygons(exportGraphics.graphics, exportOverrideColors, false, null, null);
        renderRoads(exportGraphics.graphics, exportOverrideColors);
        renderEdges(exportGraphics.graphics, exportOverrideColors);

        stage.quality = 'low';
        exportBitmap.draw(exportGraphics, m);
        stage.quality = 'best';

        // Mark the polygon centers in the export bitmap
        for each (var p:Point in points) {
            if (!attr[p].ocean) {
              var q:Point = new Point(Math.floor(p.x * 2048/SIZE),
                                    Math.floor(p.y * 2048/SIZE));
              exportBitmap.setPixel(q.x, q.y,
                                    exportBitmap.getPixel(q.x, q.y)
                                    | (attr[p].road_connections?
                                       exportOverrideColors.POLYGON_CENTER_SAFE
                                       : exportOverrideColors.POLYGON_CENTER));
            }
          }
        
        saveBitmapToArray();
      } else if (layer == 'elevation') {
        renderPolygons(exportGraphics.graphics, exportElevationColors, false, 'elevation', null);
        exportBitmap.draw(exportGraphics, m);
        saveBitmapToArray();
      } else if (layer == 'moisture') {
        renderPolygons(exportGraphics.graphics, exportMoistureColors, false, 'moisture', null);
        exportBitmap.draw(exportGraphics, m);
        saveBitmapToArray();
      }
      return exportData;
    }


    public function makeButton(label:String, x:int, y:int, callback:Function):TextField {
      var button:TextField = new TextField();
      button.text = label;
      button.selectable = false;
      button.background = true;
      button.backgroundColor = 0xffffcc;
      button.x = x;
      button.y = y;
      button.height = 20;
      button.addEventListener(MouseEvent.CLICK, callback);
      return button;
    }

    
    public function addGenerateButtons():void {
      addChild(makeButton("new shape", 650, 50,
                          function (e:Event):void {
                            newIsland();
                            go();
                          }));
      addChild(makeButton("same shape", 650, 80,
                          function (e:Event):void {
                            go();
                          }));
      
      addChild(makeButton("see biomes", 650, 150,
                          function (e:Event):void {
                            mapMode = 'biome';
                            drawMap();
                          }));
      addChild(makeButton("see smooth", 650, 180,
                          function (e:Event):void {
                            mapMode = 'smooth';
                            drawMap();
                          }));
      addChild(makeButton("see slopes", 650, 210,
                          function (e:Event):void {
                            mapMode = 'slopes';
                            drawMap();
                          }));
      addChild(makeButton("see elevation", 650, 240,
                          function (e:Event):void {
                            mapMode = 'elevation';
                            drawMap();
                          }));
      addChild(makeButton("see moisture", 650, 270,
                          function (e:Event):void {
                            mapMode = 'moisture';
                            drawMap();
                          }));
    }

               
    public function addExportButtons():void {
      addChild(makeButton("export elevation", 650, 400,
                          function (e:Event):void {
                            new FileReference().save(makeExport('elevation'), 'elevation.data');
                            e.stopPropagation();
                          }));
      addChild(makeButton("export moisture", 650, 430,
                          function (e:Event):void {
                            new FileReference().save(makeExport('moisture'), 'moisture.data');
                            e.stopPropagation();
                          }));
      addChild(makeButton("export overrides", 650, 460,
                          function (e:Event):void {
                            new FileReference().save(makeExport('overrides'), 'overrides.data');
                            e.stopPropagation();
                          }));
    }
    
  }
  
}
