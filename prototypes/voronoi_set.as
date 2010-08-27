// Make a map out of a voronoi graph
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.events.*;
  import flash.text.*;
  import flash.utils.Dictionary;
  import flash.utils.ByteArray;
  import flash.utils.getTimer;
  import flash.utils.Timer;
  import flash.net.FileReference;
  import flash.system.System;
  import com.nodename.geom.Circle;
  import com.nodename.geom.LineSegment;
  import com.nodename.Delaunay.Edge;
  import com.nodename.Delaunay.Voronoi;
  import de.polygonal.math.PM_PRNG;

  [SWF(width="800", height="600")]
  public class voronoi_set extends Sprite {
    static public var NUM_POINTS:int = 2000;
    static public var SIZE:int = 600;
    static public var NOISY_LINE_TRADEOFF:Number = 0.5;  // low: jagged vedge; high: jagged dedge
    static public var FRACTION_LAVA_FISSURES:Number = 0.2;  // 0 to 1, probability of fissure
    static public var LAKE_THRESHOLD:Number = 0.3;  // 0 to 1, fraction of water corners for water polygon
    static public var NUM_LLOYD_ITERATIONS:int = 2;
    
    static public var displayColors:Object = {
      // Features
      OCEAN: 0x555599,
      COAST: 0x444477,
      LAKESHORE: 0x225588,
      LAKE: 0x336699,
      RIVER: 0x225588,
      MARSH: 0x2f6666,
      ICE: 0x99ffff,
      BEACH: 0xa09077,
      ROAD: 0x664433,
      LAVA: 0xcc3333,

      // Terrain
      SNOW: 0xffffff,
      TUNDRA: 0xbbbbaa,
      BARE: 0x888888,
      SCORCHED: 0x555555,
      TAIGA: 0x99aa77,
      SHRUBLAND: 0x889977,
      TEMPERATE_DESERT: 0xc9d29b,
      TEMPERATE_RAIN_FOREST: 0x448855,
      TEMPERATE_DECIDUOUS_FOREST: 0x679459,
      GRASSLAND: 0x88aa55,
      SUBTROPICAL_DESERT: 0xd2b98b,
      TROPICAL_RAIN_FOREST: 0x337755,
      TROPICAL_SEASONAL_FOREST: 0x559944
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

    // Island shape is controlled by the islandRandom seed and the
    // type of island. The islandShape function uses both of them to
    // determine whether any point should be water or land.
    public var islandType:String = 'Perlin';
    public var islandShape:Function;

    // Island details are controlled by this random generator. The
    // initial map upon loading is always deterministic, but
    // subsequent maps reset this random number generator with a
    // random seed.
    public var mapRandom:PM_PRNG = new PM_PRNG(100);

    // GUI for controlling the map generation and view
    public var controls:Sprite = new Sprite();
    public var islandSeedInput:TextField;
    public var mapSeedOutput:TextField;

    // This is the current map style. UI buttons change this, and it
    // persists when you make a new map. The timer is used only when
    // the map mode is '3d'.
    public var mapMode:String = 'smooth';
    public var render3dTimer:Timer = new Timer(1000/20, 0);
    public var noiseLayer:Bitmap = new Bitmap(new BitmapData(SIZE, SIZE));
    
    // These store the graph data
    public var centers:Vector.<Center>;
    public var corners:Vector.<Corner>;
    public var edges:Vector.<Edge>;

    // These store 3d rendering data
    private var rotationAnimation:Number = 0.0;
    private var triangles3d:Array = [];
    private var graphicsData:Vector.<IGraphicsData>;
    

    public function voronoi_set() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      addChild(noiseLayer);
      noiseLayer.bitmapData.noise(555, 128-10, 128+10, 7, true);
      noiseLayer.blendMode = BlendMode.HARDLIGHT;

      addChild(new Debug(this));

      controls.x = SIZE;
      addChild(controls);
      
      addExportButtons();
      addViewButtons();
      addGenerateButtons();
      newIsland(islandType);
      go();

      render3dTimer.addEventListener(TimerEvent.TIMER, function (e:TimerEvent):void {
          drawMap();
        });
    }

    
    // Random parameters governing the overall shape of the island
    public function newIsland(type:String):void {
      if (islandSeedInput.text.length == 0) {
        islandSeedInput.text = (Math.random()*100000).toFixed(0);
      }
      var seed:int = parseInt(islandSeedInput.text);
      if (seed == 0) {
        // Convert the string into a number. This is a cheesy way to
        // do it but it doesn't matter. It just allows people to use
        // words as seeds.
        for (var i:int = 0; i < islandSeedInput.text.length; i++) {
          seed = (seed << 4) | islandSeedInput.text.charCodeAt(i);
        }
        seed %= 100000;
      }
      islandType = type;
      islandShape = IslandShape['make'+type](seed);
    }

    
    public function reset():void {
      var p:Center, q:Corner, edge:Edge;

      // Clear debugging area, if debug log is enabled
      Debug.clear();
      
      // Break cycles so the garbage collector will release data.
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
            p.edges.splice(0, p.edges.length);
          }
        centers.splice(0, centers.length);
      }
      if (corners) {
        for each (q in corners) {
            q.neighbors.splice(0, q.neighbors.length);
            q.corners.splice(0, q.corners.length);
            q.edges.splice(0, q.edges.length);
            q.downslope = null;
            q.watershed = null;
          }
        corners.splice(0, corners.length);
      }

      // Reset the 3d triangle data
      triangles3d = [];
      
      // Clear the previous graph data.
      if (!edges) edges = new Vector.<Edge>();
      if (!centers) centers = new Vector.<Center>();
      if (!corners) corners = new Vector.<Corner>();
      
      System.gc();
      Debug.trace("MEMORY BEFORE:", System.totalMemory);
    }
      

    public function graphicsReset():void {
      graphics.clear();
      graphics.beginFill(0x555599);
      graphics.drawRect(0, 0, SIZE, 2000);
      graphics.endFill();
      graphics.beginFill(0xbbbbaa);
      graphics.drawRect(SIZE, 0, 2000, 2000);
      graphics.endFill();
    }

    
    public function go():void {
      reset();
      mapSeedOutput.text = mapRandom.seed.toString();
      
      var i:int, j:int, t:Number;
      var p:Center, q:Corner, r:Center, s:Corner, point:Point;
      var t0:Number = getTimer();

      
      // Generate the initial random set of points
      t = getTimer();
      var points:Vector.<Point> = generateRandomPoints();
      Debug.trace("TIME for random points:", getTimer()-t);


      // Improve the quality of that set by spacing them better
      t = getTimer();
      improveRandomPoints(points);
      Debug.trace("TIME for improving point set:", getTimer()-t);

      
      // Build the Voronoi structure with our random points
      t = getTimer();
      var voronoi:Voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));
      Debug.trace("TIME for voronoi:", getTimer()-t);


      // Create a graph structure from the Voronoi edge list. The
      // methods in the Voronoi object are somewhat inconvenient for
      // my needs, so I transform that data into the data I actually
      // need: edges connected to the Delaunay triangles and the
      // Voronoi polygons, a reverse map from those four points back
      // to the edge, a map from these four points to the points
      // they connect to (both along the edge and crosswise).
      t = getTimer();
      buildGraph(points, voronoi);
      voronoi.dispose();
      voronoi = null;
      Debug.trace("TIME for buildGraph:", getTimer()-t);
      
      
      // Determine the elevations and water at Voronoi corners.
      t = getTimer();
      assignCornerElevations();
      Debug.trace("TIME for corner elevations:", getTimer()-t);


      // Determine polygon and corner type: ocean, coast, land.
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

      var landPoints:Vector.<Corner> = new Vector.<Corner>();  // only non-ocean
      for each (q in corners) {
          if (q.ocean || q.coast) {
            q.elevation = 0.0;
          } else {
            landPoints.push(q);
          }
        }
      for (i = 0; i < 10; i++) {
        redistributeElevations(landPoints);
      }
      landPoints.splice(0, landPoints.length);
      Debug.trace("TIME for elevation rescaling:", getTimer()-t);

      
      // Polygon elevations are the average of their corners
      t = getTimer();
      assignPolygonElevations();
      Debug.trace("TIME for polygon elevations:", getTimer()-t);
      

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


      // Create lava.
      t = getTimer();
      createLava();
      Debug.trace("TIME for lava:", getTimer()-t);

      
      // Choose polygon biomes based on elevation, water, ocean
      t = getTimer();
      assignBiomes();
      Debug.trace("TIME for biome assignment:", getTimer()-t);


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
      buildNoisyEdges();
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
          p.edges = new Vector.<Edge>();
          p.neighbors = new  Vector.<Center>();
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
        q.edges = new Vector.<Edge>();
        q.neighbors = new Vector.<Corner>();
        q.corners = new Vector.<Center>();
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
          edges.push(edge);
          edge.midpoint = vedge.p0 && vedge.p1 && Point.interpolate(vedge.p0, vedge.p1, 0.5);

          // Edges point to corners. Edges point to centers. 
          edge.v0 = makeCorner(vedge.p0);
          edge.v1 = makeCorner(vedge.p1);
          edge.d0 = centerLookup[dedge.p0];
          edge.d1 = centerLookup[dedge.p1];

          // Centers point to edges. Corners point to edges.
          if (edge.d0 != null) { edge.d0.edges.push(edge); }
          if (edge.d1 != null) { edge.d1.edges.push(edge); }
          if (edge.v0 != null) { edge.v0.edges.push(edge); }
          if (edge.v1 != null) { edge.v1.edges.push(edge); }

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
            addToCornerList(edge.v0.neighbors, edge.v1);
            addToCornerList(edge.v1.neighbors, edge.v0);
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
            addToCenterList(edge.v0.corners, edge.d0);
            addToCenterList(edge.v0.corners, edge.d1);
          }
          if (edge.v1 != null) {
            addToCenterList(edge.v1.corners, edge.d0);
            addToCenterList(edge.v1.corners, edge.d1);
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

        for each (s in q.neighbors) {
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
    // elevations. Specifically, we want elevation X to have
    // frequency (K+maxElevation-X), for some value of K.  To do
    // this we will compute a histogram of the elevations, then
    // compute the cumulative sum, then try to make that match the
    // desired cumulative sum. The desired cumulative sum is the
    // integral of the desired frequency distribution.
    public function redistributeElevations(points:Vector.<Corner>):void {
      var maxElevation:int = 20;
      var M:Number = 1+maxElevation;
      var q:Corner, i:int, x:Number, x0:Number, x1:Number, f:Number, y0:Number, y1:Number;
      var histogram:Array = [];

      // First, rescale the points so that none is greater than maxElevation
      x = 1.0;
      for each (q in points) {
          if (q.elevation > x) {
            x = q.elevation;
          }
        }
      // As we rescale, build a histogram of the resulting elevations
      for each (q in points) {
          q.elevation *= maxElevation / x;
          i = int(Math.floor(q.elevation));
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
      
      for each (q in points) {
          q.elevation = remap(q.elevation);
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
      var p:Center, q:Corner, r:Center;
      
      for each (p in centers) {
          for each (q in p.corners) {
              if (q.border) {
                p.border = true;
                p.ocean = true;
                q.water = true;
                queue.push(p);
              }
              if (q.water) {
                p.water = (p.water || 0) + 1;
              }
            }
          if (!p.ocean && p.water < p.corners.length * LAKE_THRESHOLD) {
            p.water = 0;
          }
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
          for each (p in q.corners) {
              numOcean += int(p.ocean);
              numLand += int(!p.water);
            }
          q.ocean = (numOcean == q.corners.length);
          q.coast = (numOcean > 0) && (numLand > 0);
          q.water = q.border || ((numLand != q.corners.length) && !q.coast);
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
          for each (s in q.neighbors) {
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
    public function calculateWatersheds():int {
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
      return i;
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
          edge.river = (edge.river || 0) + 1;
          q.river = (q.river || 0) + 1;
          q.downslope.river = (q.downslope.river || 0) + 1;
          q = q.downslope;
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
      var p:Center, q:Corner, r:Corner, sumMoisture:Number;
      var queue:Array = [];
      // Fresh water
      for each (q in corners) {
          if ((q.water || q.river) && !q.ocean) {
            q.moisture = q.river? Math.min(1.8, (0.2 * q.river)) : 1.0;
            queue.push(q);
          } else {
            q.moisture = 0.0;
          }
        }
      while (queue.length > 0) {
        q = queue.shift();

        for each (r in q.neighbors) {
            var newMoisture:Number = q.moisture * 0.85;
            if (newMoisture > r.moisture) {
              r.moisture = newMoisture;
              queue.push(r);
            }
          }
      }
      // Salt water
      for each (q in corners) {
          if (q.ocean || q.coast) q.moisture = 1.0;
        }
      // Polygon moisture is the average of the moisture at corners
      for each (p in centers) {
          sumMoisture = 0.0;
          for each (q in p.corners) {
              if (q.moisture > 1.0) q.moisture = 1.0;
              sumMoisture += q.moisture;
            }
          p.moisture = sumMoisture / p.corners.length;
        }
    }


    // Lava fissures are at high elevations where moisture is low
    public function createLava():void {
      var edge:Edge, p:Center, s:Center;
      for each (p in centers) {
          for each (s in p.neighbors) {
              edge = lookupEdgeFromCenter(p, s);
              if (!edge.river && !p.water && !s.water
                  && p.elevation > 0.8 && s.elevation > 0.8
                  && p.moisture < 0.3 && s.moisture < 0.3
                  && mapRandom.nextDouble() < FRACTION_LAVA_FISSURES) {
                edge.lava = true;
              }
            }
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
      var p:Center, q:Corner, r:Center, edge:Edge, newLevel:int;
      var elevationThresholds:Array = [0, 0.05, 0.25, 0.55, 1.0];

      for each (p in centers) {
          if (p.coast || p.ocean) {
            p.contour = 1;
            queue.push(p);
          }
        }
      while (queue.length > 0) {
        p = queue.shift();
        for each (r in p.neighbors) {
            newLevel = p.contour || 0;
            while (r.elevation > elevationThresholds[newLevel] && !r.water) {
              // NOTE: extend the contour line past bodies of
              // water so that roads don't terminate inside lakes.
              newLevel += 1;
            }
            if (newLevel < (r.contour || 999)) {
              r.contour = newLevel;
              queue.push(r);
            }
          }
      }

      // A corner's contour level is the MIN of its polygons
      for each (p in centers) {
          for each (q in p.corners) {
              q.contour = Math.min(q.contour || 999, p.contour || 999);
            }
        }

      // Roads go between polygons that have different contour levels
      for each (p in centers) {
          for each (edge in p.edges) {
              if (edge.v0 && edge.v1
                  && edge.v0.contour != edge.v1.contour) {
                edge.road = true;
                p.road_connections = (p.road_connections || 0) + 1;
              }
            }
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
            if (p.elevation > 0.85) p.biome = 'ICE';
          } else if (p.coast) {
            p.biome = 'BEACH';
          } else if (p.elevation > 0.8) {
            if (p.moisture > 0.5) p.biome = 'SNOW';
            else if (p.moisture > 0.3) p.biome = 'TUNDRA';
            else if (p.moisture > 0.1) p.biome = 'BARE';
            else p.biome = 'SCORCHED';
          } else if (p.elevation > 0.6) {
            if (p.moisture > 0.6) p.biome = 'TAIGA';
            else if (p.moisture > 0.3) p.biome = 'SHRUBLAND';
            else p.biome = 'TEMPERATE_DESERT';
          } else if (p.elevation > 0.3) {
            if (p.moisture > 0.8) p.biome = 'TEMPERATE_RAIN_FOREST';
            else if (p.moisture > 0.6) p.biome = 'TEMPERATE_DECIDUOUS_FOREST';
            else if (p.moisture > 0.3) p.biome = 'GRASSLAND';
            else p.biome = 'TEMPERATE_DESERT';
          } else {
            if (p.moisture > 0.8) p.biome = 'TROPICAL_RAIN_FOREST';
            else if (p.moisture > 0.5) p.biome = 'TROPICAL_SEASONAL_FOREST';
            else if (p.moisture > 0.3) p.biome = 'GRASSLAND';
            else p.biome = 'SUBTROPICAL_DESERT';
          }
        }
    }


    // Helper function: build a single noisy line in a quadrilateral A-B-C-D,
    // and store the output points in a Vector.
    static public function buildNoisyLineSegments(random:PM_PRNG, A:Point, B:Point, C:Point, D:Point, minLength:Number):Vector.<Point> {
      var points:Vector.<Point> = new Vector.<Point>();

      function subdivide(A:Point, B:Point, C:Point, D:Point):void {
        if (A.subtract(C).length < minLength || B.subtract(D).length < minLength) {
          return;
        }

        // Subdivide the quadrilateral
        var p:Number = random.nextDoubleRange(0.1, 0.9);  // vertical (along A-D and B-C)
        var q:Number = random.nextDoubleRange(0.1, 0.9);  // horizontal (along A-B and D-C)

        // Midpoints
        var E:Point = Point.interpolate(A, D, p);
        var F:Point = Point.interpolate(B, C, p);
        var G:Point = Point.interpolate(A, B, q);
        var I:Point = Point.interpolate(D, C, q);
        
        // Central point
        var H:Point = Point.interpolate(E, F, q);
        
        // Divide the quad into subquads, but meet at H
        var s:Number = 1.0 - random.nextDoubleRange(-0.4, +0.4);
        var t:Number = 1.0 - random.nextDoubleRange(-0.4, +0.4);

        subdivide(A, Point.interpolate(G, B, s), H, Point.interpolate(E, D, t));
        points.push(H);
        subdivide(H, Point.interpolate(F, C, s), C, Point.interpolate(I, D, t));
      }

      points.push(A);
      subdivide(A, B, C, D);
      points.push(C);
      return points;
    }
    
    
    // Build noisy line paths for each of the Voronoi edges. There are
    // two noisy line paths for each edge, each covering half the
    // distance: edge.path0 will be from v0 to the midpoint and
    // edge.path1 will be from v1 to the midpoint. When drawing
    // the polygons, one or the other must be drawn in reverse order.
    public function buildNoisyEdges():void {
      var p:Center, edge:Edge;
      for each (p in centers) {
          for each (edge in p.edges) {
              if (edge.d0 && edge.d1 && edge.v0 && edge.v1 && !edge.path0) {
                var f:Number = NOISY_LINE_TRADEOFF;
                var t:Point = Point.interpolate(edge.v0.point, edge.d0.point, f);
                var q:Point = Point.interpolate(edge.v0.point, edge.d1.point, f);
                var r:Point = Point.interpolate(edge.v1.point, edge.d0.point, f);
                var s:Point = Point.interpolate(edge.v1.point, edge.d1.point, f);

                var minLength:int = 10;
                if (edge.d0.biome != edge.d1.biome) minLength = 3;
                if (edge.d0.ocean && edge.d1.ocean) minLength = 100;
                if (edge.river || edge.lava) minLength = 1;
                
                edge.path0 = buildNoisyLineSegments(mapRandom, edge.v0.point, t, edge.midpoint, q, minLength);
                edge.path1 = buildNoisyLineSegments(mapRandom, edge.v1.point, s, edge.midpoint, r, minLength);
              }
            }
        }
    }
    

    // Look up a Voronoi Edge object given two adjacent Voronoi
    // polygons, or two adjacent Voronoi corners
    public function lookupEdgeFromCenter(p:Center, r:Center):Edge {
      for each (var edge:Edge in p.edges) {
          if (edge.d0 == r || edge.d1 == r) return edge;
        }
      return null;
    }

    public function lookupEdgeFromCorner(q:Corner, s:Corner):Edge {
      for each (var edge:Edge in q.edges) {
          if (edge.v0 == s || edge.v1 == s) return edge;
        }
      return null;
    }

    
    // Determine whether a given point should be on the island or in the water.
    public function inside(p:Point):Boolean {
      return islandShape(new Point(2*(p.x/SIZE - 0.5), 2*(p.y/SIZE - 0.5)));
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


    // Helper function for color manipulation. When f==0: color0, f==1: color1
    private function interpolateColor(color0:uint, color1:uint, f:Number):uint {
      var r:uint = uint((1-f)*(color0 >> 16) + f*(color1 >> 16));
      var g:uint = uint((1-f)*((color0 >> 8) & 0xff) + f*((color1 >> 8) & 0xff));
      var b:uint = uint((1-f)*(color0 & 0xff) + f*(color1 & 0xff));
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
      noiseLayer.visible = true;
      
      if (mapMode == '3d') {
        if (!render3dTimer.running) render3dTimer.start();
        noiseLayer.visible = false;
        render3dPolygons(graphics, displayColors, colorWithSlope);
        return;
      } else if (mapMode == 'polygons') {
        noiseLayer.visible = false;
        renderDebugPolygons(graphics, displayColors);
      } else if (mapMode == 'watersheds') {
        noiseLayer.visible = false;
        renderDebugPolygons(graphics, displayColors);
        renderWatersheds(graphics);
        return;
      } else if (mapMode == 'biome') {
        renderPolygons(graphics, displayColors, null, null);
      } else if (mapMode == 'slopes') {
        renderPolygons(graphics, displayColors, null, colorWithSlope);
      } else if (mapMode == 'smooth') {
        renderPolygons(graphics, displayColors, null, colorWithSmoothColors);
      } else if (mapMode == 'elevation') {
        renderPolygons(graphics, elevationGradientColors, 'elevation', null);
      } else if (mapMode == 'moisture') {
        renderPolygons(graphics, moistureGradientColors, 'moisture', null);
      }

      if (render3dTimer.running) render3dTimer.stop();

      if (mapMode != 'slopes' && mapMode != 'moisture') {
        renderRoads(graphics, displayColors);
      }
      if (mapMode != 'polygons') {
        renderEdges(graphics, displayColors);
      }
    }


    // 3D rendering of polygons. If the 'triangles3d' array is empty,
    // it's filled and the graphicsData is filled in as well. On
    // rendering, the triangles3d array has to be z-sorted and then
    // the resulting polygon data is transferred into graphicsData
    // before rendering.
    public function render3dPolygons(graphics:Graphics, colors:Object, colorFunction:Function):void {
      var p:Center, q:Corner, edge:Edge;
      var zScale:Number = 0.15*SIZE;
      
      graphics.beginFill(colors.OCEAN);
      graphics.drawRect(0, 0, SIZE, SIZE);
      graphics.endFill();

      if (triangles3d.length == 0) {
        graphicsData = new Vector.<IGraphicsData>();
        for each (p in centers) {
            if (p.ocean) continue;
            for each (edge in p.edges) {
                var color:int = colors[p.biome] || 0;
                if (colorFunction != null) {
                  color = colorFunction(color, p, q, edge);
                }

                // We'll draw two triangles: center - corner0 -
                // midpoint and center - midpoint - corner1.
                var corner0:Corner = edge.v0;
                var corner1:Corner = edge.v1;

                if (corner0 == null || corner1 == null) {
                  // Edge of the map; we can't deal with it right now
                  continue;
                }

                var zp:Number = zScale*p.elevation;
                var z0:Number = zScale*corner0.elevation;
                var z1:Number = zScale*corner1.elevation;
                triangles3d.push({
                    a:new Vector3D(p.point.x, p.point.y, zp),
                      b:new Vector3D(corner0.point.x, corner0.point.y, z0),
                      c:new Vector3D(corner1.point.x, corner1.point.y, z1),
                      rA:null,
                      rB:null,
                      rC:null,
                      z:0.0,
                      color:color
                      });
                graphicsData.push(new GraphicsSolidFill());
                graphicsData.push(new GraphicsPath(Vector.<int>([GraphicsPathCommand.MOVE_TO, GraphicsPathCommand.LINE_TO, GraphicsPathCommand.LINE_TO]),
                                                   Vector.<Number>([0, 0, 0, 0, 0, 0])));
                graphicsData.push(new GraphicsEndFill());
              }
          }
      }

      var camera:Matrix3D = new Matrix3D();
      camera.appendRotation(rotationAnimation, new Vector3D(0, 0, 1), new Vector3D(SIZE/2, SIZE/2));
      camera.appendRotation(60, new Vector3D(1,0,0), new Vector3D(SIZE/2, SIZE/2));
      rotationAnimation += 1;

      for each (var tri:Object in triangles3d) {
          tri.rA = camera.transformVector(tri.a);
          tri.rB = camera.transformVector(tri.b);
          tri.rC = camera.transformVector(tri.c);
          tri.z = (tri.rA.z + tri.rB.z + tri.rC.z)/3;
        }
      triangles3d.sortOn('z', Array.NUMERIC);

      for (var i:int = 0; i < triangles3d.length; i++) {
        tri = triangles3d[i];
        GraphicsSolidFill(graphicsData[i*3]).color = tri.color;
        var data:Vector.<Number> = GraphicsPath(graphicsData[i*3+1]).data;
        data[0] = tri.rA.x;
        data[1] = tri.rA.y;
        data[2] = tri.rB.x;
        data[3] = tri.rB.y;
        data[4] = tri.rC.x;
        data[5] = tri.rC.y;
      }
      graphics.drawGraphicsData(graphicsData);
    }

    
    // Render the interior of polygons
    public function renderPolygons(graphics:Graphics, colors:Object, gradientFillProperty:String, colorOverrideFunction:Function):void {
      var p:Center, r:Center;

      // My Voronoi polygon rendering doesn't handle the boundary
      // polygons, so I just fill everything with ocean first.
      graphics.beginFill(colors.OCEAN);
      graphics.drawRect(0, 0, SIZE, SIZE);
      graphics.endFill();
      
      for each (p in centers) {
          for each (r in p.neighbors) {
              var edge:Edge = lookupEdgeFromCenter(p, r);
              var color:int = colors[p.biome] || 0;
              if (colorOverrideFunction != null) {
                color = colorOverrideFunction(color, p, r, edge);
              }

              function drawPath0():void {
                graphics.moveTo(p.point.x, p.point.y);
                graphics.lineTo(edge.path0[0].x, edge.path0[0].y);
                drawPathForwards(graphics, edge.path0);
                graphics.lineTo(p.point.x, p.point.y);
              }

              function drawPath1():void {
                graphics.moveTo(p.point.x, p.point.y);
                graphics.lineTo(edge.path1[0].x, edge.path1[0].y);
                drawPathForwards(graphics, edge.path1);
                graphics.lineTo(p.point.x, p.point.y);
              }

              if (edge.path0 == null || edge.path1 == null) {
                // It's at the edge of the map, where we don't have
                // the noisy edges computed. TODO: figure out how to
                // fill in these edges from the voronoi library.
                continue;
              }

              if (gradientFillProperty != null) {
                // We'll draw two triangles: center - corner0 -
                // midpoint and center - midpoint - corner1.
                var corner0:Corner = edge.v0;
                var corner1:Corner = edge.v1;

                // We pick the midpoint elevation/moisture between
                // corners instead of between polygon centers because
                // the resulting gradients tend to be smoother.
                var midpoint:Point = edge.midpoint;
                var midpointAttr:Number = 0.5*(corner0[gradientFillProperty]+corner1[gradientFillProperty]);
                drawGradientTriangle
                  (graphics,
                   new Vector3D(p.point.x, p.point.y, p[gradientFillProperty]),
                   new Vector3D(corner0.point.x, corner0.point.y, corner0[gradientFillProperty]),
                   new Vector3D(midpoint.x, midpoint.y, midpointAttr),
                   colors.GRADIENT_LOW, colors.GRADIENT_HIGH, drawPath0);
                drawGradientTriangle
                  (graphics,
                   new Vector3D(p.point.x, p.point.y, p[gradientFillProperty]),
                   new Vector3D(midpoint.x, midpoint.y, midpointAttr),
                   new Vector3D(corner1.point.x, corner1.point.y, corner1[gradientFillProperty]),
                   colors.GRADIENT_LOW, colors.GRADIENT_HIGH, drawPath1);
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
      var p:Center, A:Point, B:Point, C:Point;
      var i:int, j:int, d:Number, edge1:Edge, edge2:Edge, edges:Vector.<Edge>;

      // Helper function: find the normal vector across edge 'e' and
      // make sure to point it in a direction towards 'c'.
      function normalTowards(e:Edge, c:Point, len:Number):Point {
        // Rotate the v0-->v1 vector by 90 degrees:
        var n:Point = new Point(-(e.v1.point.y - e.v0.point.y), e.v1.point.x - e.v0.point.x);
        // Flip it around it if doesn't point towards c
        var d:Point = c.subtract(e.midpoint);
        if (n.x * d.x + n.y * d.y < 0) {
          n.x = -n.x;
          n.y = -n.y;
        }
        n.normalize(len);
        return n;
      }
      
      for each (p in centers) {
          if (p.road_connections == 2) {
            // Regular road: draw a spline from one edge to the other.
            edges = p.edges;
            for (i = 0; i < edges.length; i++) {
              edge1 = edges[i];
              if (edge1.road) {
                for (j = i+1; j < edges.length; j++) {
                  edge2 = edges[j];
                  if (edge2.road) {
                    // The spline connects the midpoints of the edges
                    // and at right angles to them. In between we
                    // generate two control points A and B and one
                    // additional vertex C.  This usually works but
                    // not always.
                    d = 0.5*Math.min
                      (edge1.midpoint.subtract(p.point).length,
                       edge2.midpoint.subtract(p.point).length);
                    A = normalTowards(edge1, p.point, d).add(edge1.midpoint);
                    B = normalTowards(edge2, p.point, d).add(edge2.midpoint);
                    C = Point.interpolate(A, B, 0.5);
                    graphics.lineStyle(1.1, colors.ROAD);
                    graphics.moveTo(edge1.midpoint.x, edge1.midpoint.y);
                    graphics.curveTo(A.x, A.y, C.x, C.y);
                    graphics.curveTo(B.x, B.y, edge2.midpoint.x, edge2.midpoint.y);
                    graphics.lineStyle();
                  }
                }
              }
            }
          }
          if (p.road_connections && p.road_connections != 2) {
            // Intersection: draw a road spline from each edge to the center
            for each (edge1 in p.edges) {
                if (edge1.road) {
                  d = 0.25*edge1.midpoint.subtract(p.point).length;
                  A = normalTowards(edge1, p.point, d).add(edge1.midpoint);
                  graphics.lineStyle(1.4, colors.ROAD);
                  graphics.moveTo(edge1.midpoint.x, edge1.midpoint.y);
                  graphics.curveTo(A.x, A.y, p.point.x, p.point.y);
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
      var p:Center, r:Center, edge:Edge;

      for each (p in centers) {
          for each (r in p.neighbors) {
              edge = lookupEdgeFromCenter(p, r);
              if (edge.path0 == null || edge.path1 == null) {
                // It's at the edge of the map, where we don't have
                // the noisy edges computed. TODO: fill these in with
                // non-noisy lines.
                continue;
              }
              if (p.ocean != r.ocean) {
                // One side is ocean and the other side is land -- coastline
                graphics.lineStyle(2, colors.COAST);
              } else if ((p.water > 0) != (r.water > 0) && p.biome != 'ICE' && r.biome != 'ICE') {
                // Lake boundary
                graphics.lineStyle(1, colors.LAKESHORE);
              } else if (p.water || r.water) {
                // Lake interior – we don't want to draw the rivers here
                continue;
              } else if (edge.river != 0.0) {
                // River edge
                graphics.lineStyle(Math.sqrt(edge.river), colors.RIVER);
              } else if (edge.lava) {
                // Lava flow
                graphics.lineStyle(1, colors.LAVA);
              } else {
                // No edge
                continue;
              }
              
              graphics.moveTo(edge.path0[0].x, edge.path0[0].y);
              drawPathForwards(graphics, edge.path0);
              drawPathBackwards(graphics, edge.path1);
              graphics.lineStyle();
            }
        }
    }


    // Render the polygons so that each can be seen clearly
    public function renderDebugPolygons(graphics:Graphics, colors:Object):void {
      var p:Center, q:Corner, edge:Edge;

      for each (p in centers) {
          graphics.beginFill(interpolateColor(colors[p.biome] || 0, 0xdddddd, 0.2));
          for each (edge in p.edges) {
              if (edge.v0 && edge.v1) {
                graphics.moveTo(p.point.x, p.point.y);
                graphics.lineTo(edge.v0.point.x, edge.v0.point.y);
                if (edge.river) {
                  graphics.lineStyle(2, displayColors.RIVER, 1.0);
                } else {
                  graphics.lineStyle(1, 0x000000, 0.4);
                }
                graphics.lineTo(edge.v1.point.x, edge.v1.point.y);
                graphics.lineStyle();
              }
            }
          graphics.endFill();
          graphics.beginFill(p.water > 0 ? 0x00ffff : p.ocean? 0xff0000 : 0x000000, 0.7);
          graphics.drawCircle(p.point.x, p.point.y, 1.3);
          graphics.endFill();
          for each (q in p.corners) {
              graphics.beginFill(q.water? 0x0000ff : 0x009900);
              graphics.drawRect(q.point.x-0.7, q.point.y-0.7, 1.5, 1.5);
              graphics.endFill();
            }
        }
    }


    // Render the paths from each polygon to the ocean, showing watersheds
    public function renderWatersheds(graphics:Graphics):void {
      var q:Corner, r:Corner;

      for each (q in corners) {
          if (!q.ocean) {
            r = q.downslope;
            graphics.lineStyle(1.2, q.watershed == r.watershed? 0x00ffff : 0xff00ff,
                               0.1*Math.sqrt(q.watershed.watershed_size || 1));
            graphics.moveTo(q.point.x, q.point.y);
            graphics.lineTo(r.point.x, r.point.y);
            graphics.lineStyle();
          }
        }
      
      for each (q in corners) {
          for each (r in q.neighbors) {
              if (!q.ocean && !r.ocean && q.watershed != r.watershed && !q.coast && !r.coast) {
                var edge:Edge = lookupEdgeFromCorner(q, r);
                graphics.lineStyle(2.5, 0x000000, 0.05*Math.sqrt((q.watershed.watershed_size || 1) + (r.watershed.watershed_size || 1)));
                graphics.moveTo(edge.d0.point.x, edge.d0.point.y);
                graphics.lineTo(edge.midpoint.x, edge.midpoint.y);
                graphics.lineTo(edge.d1.point.x, edge.d1.point.y);
                graphics.lineStyle();
              }
            }
        }
    }
    

    private var lightVector:Vector3D = new Vector3D(-1, -1, 0);
    public function colorWithSlope(color:int, p:Center, q:Center, edge:Edge):int {
      var r:Corner = edge.v0;
      var s:Corner = edge.v1;
      if (!r || !s) {
        // Edge of the map
        return displayColors.OCEAN;
      } else if (p.water) {
        return color;
      }

      if (q != null && p.water == q.water) color = interpolateColor(color, displayColors[q.biome], 0.4);
      var colorLow:int = interpolateColor(color, 0x333333, 0.7);
      var colorHigh:int = interpolateColor(color, 0xffffff, 0.3);
      var A:Vector3D = new Vector3D(p.point.x, p.point.y, p.elevation);
      var B:Vector3D = new Vector3D(r.point.x, r.point.y, r.elevation);
      var C:Vector3D = new Vector3D(s.point.x, s.point.y, s.elevation);
      var normal:Vector3D = B.subtract(A).crossProduct(C.subtract(A));
      if (normal.z < 0) { normal.scaleBy(-1); }
      normal.normalize();
      var light:Number = 0.5 + 35*normal.dotProduct(lightVector);
      if (light < 0) light = 0;
      if (light > 1) light = 1;
      if (light < 0.5) return interpolateColor(colorLow, color, light*2);
      else return interpolateColor(color, colorHigh, light*2-1);
    }


    public function colorWithSmoothColors(color:int, p:Center, q:Center, edge:Edge):int {
      if (q != null && p.water == q.water) {
        color = interpolateColor(displayColors[p.biome], displayColors[q.biome], 0.25);
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
      LAVA: 0x20,
      SNOW: 0x30,
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
        renderPolygons(exportGraphics.graphics, exportOverrideColors, null, null);
        renderRoads(exportGraphics.graphics, exportOverrideColors);
        renderEdges(exportGraphics.graphics, exportOverrideColors);

        stage.quality = 'low';
        exportBitmap.draw(exportGraphics, m);
        stage.quality = 'best';

        // Mark the polygon centers in the export bitmap
        for each (var p:Center in centers) {
            if (!p.ocean) {
              var r:Point = new Point(Math.floor(p.point.x * 2048/SIZE),
                                    Math.floor(p.point.y * 2048/SIZE));
              exportBitmap.setPixel(r.x, r.y,
                                    exportBitmap.getPixel(r.x, r.y)
                                    | (p.road_connections?
                                       exportOverrideColors.POLYGON_CENTER_SAFE
                                       : exportOverrideColors.POLYGON_CENTER));
            }
          }
        
        saveBitmapToArray();
      } else if (layer == 'elevation') {
        renderPolygons(exportGraphics.graphics, exportElevationColors, 'elevation', null);
        exportBitmap.draw(exportGraphics, m);
        saveBitmapToArray();
      } else if (layer == 'moisture') {
        renderPolygons(exportGraphics.graphics, exportMoistureColors, 'moisture', null);
        exportBitmap.draw(exportGraphics, m);
        saveBitmapToArray();
      }
      return exportData;
    }


    // Make a button or label. If the callback is null, it's just a label.
    public function makeButton(label:String, x:int, y:int, width:int, callback:Function):TextField {
      var button:TextField = new TextField();
      var format:TextFormat = new TextFormat();
      format.font = "Arial";
      format.align = 'center';
      button.defaultTextFormat = format;
      button.text = label;
      button.selectable = false;
      button.x = x;
      button.y = y;
      button.width = width;
      button.height = 20;
      if (callback != null) {
        button.background = true;
        button.backgroundColor = 0xffffcc;
        button.addEventListener(MouseEvent.CLICK, callback);
      }
      return button;
    }

    
    public function addGenerateButtons():void {
      var y:int = 4;
      var islandShapeButton:TextField = makeButton("Island Shape:", 25, y, 150, null);

      var seedLabel:TextField = makeButton("Shape #", 25, y+22, 50, null);
      
      islandSeedInput = makeButton("67131", 75, y+22, 44, null);
      islandSeedInput.background = true;
      islandSeedInput.backgroundColor = 0xccddcc;
      islandSeedInput.selectable = true;
      islandSeedInput.type = TextFieldType.INPUT;
      islandSeedInput.addEventListener(KeyboardEvent.KEY_UP, function (e:KeyboardEvent):void {
          if (e.keyCode == 13) {
            newIsland(islandType);
            go();
          }
        });

      function markActiveIslandShape(type:String):void {
        mapTypes[islandType].backgroundColor = 0xffffcc;
        mapTypes[type].backgroundColor = 0xffff00;
      }
      
      function switcher(type:String):Function {
        return function(e:Event):void {
          markActiveIslandShape(type);
          newIsland(type);
          go();
        }
      }
      
      var mapTypes:Object = {
        'Radial': makeButton("Radial", 23, y+44, 40, switcher('Radial')),
        'Perlin': makeButton("Perlin", 65, y+44, 35, switcher('Perlin')),
        'Square': makeButton("Square", 102, y+44, 44, switcher('Square')),
        'Blob': makeButton("Blob", 148, y+44, 29, switcher('Blob'))
      };
      markActiveIslandShape(islandType);
      
      controls.addChild(islandShapeButton);
      controls.addChild(seedLabel);
      controls.addChild(islandSeedInput);
      controls.addChild(makeButton("Random", 121, y+22, 56,
                                   function (e:Event):void {
                                     islandSeedInput.text = (Math.random()*100000).toFixed(0);
                                     newIsland(islandType);
                                     go();
                                   }));
      controls.addChild(mapTypes.Radial);
      controls.addChild(mapTypes.Perlin);
      controls.addChild(mapTypes.Square);
      controls.addChild(mapTypes.Blob);
      
      controls.addChild(makeButton("Map #", 35, y+66, 40, null));
      mapSeedOutput = makeButton("", 75, y+66, 75, null);
      controls.addChild(mapSeedOutput);
    }

    
    public function addViewButtons():void {
      var y:int = 150;

      function markViewButton(mode:String):void {
        views[mapMode].backgroundColor = 0xffffcc;
        views[mode].backgroundColor = 0xffff00;
      }
      function switcher(mode:String):Function {
        return function(e:Event):void {
          markViewButton(mode);
          mapMode = mode;
          drawMap();
        }
      }
      
      var views:Object = {
        'biome': makeButton("Biomes", 25, y+22, 74, switcher('biome')),
        'smooth': makeButton("Smooth", 101, y+22, 74, switcher('smooth')),
        'slopes': makeButton("2D slopes", 25, y+44, 74, switcher('slopes')),
        '3d': makeButton("3D slopes", 101, y+44, 74, switcher('3d')),
        'elevation': makeButton("Elevation", 25, y+66, 74, switcher('elevation')),
        'moisture': makeButton("Moisture", 101, y+66, 74, switcher('moisture')),
        'polygons': makeButton("Polygons", 25, y+88, 74, switcher('polygons')),
        'watersheds': makeButton("Watersheds", 101, y+88, 74, switcher('watersheds'))
      };

      markViewButton(mapMode);
      
      controls.addChild(makeButton("View:", 50, y, 100, null));
      
      controls.addChild(views.biome);
      controls.addChild(views.smooth);
      controls.addChild(views.slopes);
      controls.addChild(views['3d']);
      controls.addChild(views.elevation);
      controls.addChild(views.moisture);
      controls.addChild(views.polygons);
      controls.addChild(views.watersheds);
    }

               
    public function addExportButtons():void {
      controls.addChild(makeButton("Export Bitmaps:", 25, 350, 150, null));
               
      controls.addChild(makeButton("Elevation", 50, 372, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('elevation'), 'elevation.data');
                            e.stopPropagation();
                          }));
      controls.addChild(makeButton("Moisture", 50, 394, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('moisture'), 'moisture.data');
                            e.stopPropagation();
                          }));
      controls.addChild(makeButton("Overrides", 50, 416, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('overrides'), 'overrides.data');
                            e.stopPropagation();
                          }));
    }
    
  }
  
}


// Data structures to represent the graph
class Center {
  public var index:int;
  
  public var point:Point;
  public var ocean:Boolean;
  public var water:int;
  public var coast:Boolean;
  public var border:Boolean;
  public var biome:String;
  public var elevation:Number;
  public var moisture:Number;
  public var edges:Vector.<Edge>;
  public var neighbors:Vector.<Center>;
  public var corners:Vector.<Corner>;
  public var contour:int;
  
  public var road_connections:int;  // should be Vector.<Corner>
};

class Corner {
  public var index:int;
  
  public var point:Point;
  public var ocean:Boolean;
  public var water:Boolean;
  public var coast:Boolean;
  public var border:Boolean;
  public var elevation:Number;
  public var moisture:Number;
  public var edges:Vector.<Edge>;
  public var neighbors:Vector.<Corner>;
  public var corners:Vector.<Center>;
  public var contour:int;
  
  public var river:int;
  public var downslope:Corner;
  public var watershed:Corner;
  public var watershed_size:int;
};

class Edge {
  public var index:int;
  public var v0:Corner, v1:Corner;
  public var d0:Center, d1:Center;
  public var path0:Vector.<Point>, path1:Vector.<Point>;
  public var midpoint:Point;
  public var river:Number;
  public var road:Boolean;
  public var lava:Boolean;
};

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
