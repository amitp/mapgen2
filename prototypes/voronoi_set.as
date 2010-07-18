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
  
  public class voronoi_set extends Sprite {
    static public var NUM_POINTS:int = 2000;
    static public var SIZE:int = 600;
    static public var ISLAND_FACTOR:Number = 1.1;  // 1.0 means no small islands; 2.0 leads to a lot
    static public var NOISY_LINE_TRADEOFF:Number = 0.6;  // low: jagged vedge; high: jagged dedge
    
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
      SWAMP: 0x44524c
    };

    public var islandRandom:PM_PRNG = new PM_PRNG(487);
    public var mapRandom:PM_PRNG = new PM_PRNG(487);

    // These store the graph data
    public var voronoi:Voronoi;
    public var points:Vector.<Point>;
    public var attr:Dictionary;

    // These are empty when we make a map, and filled in on export
    public var exportAltitude:ByteArray = new ByteArray();
    public var exportMoisture:ByteArray = new ByteArray();
    public var exportOverride:ByteArray = new ByteArray();
    
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

    public function go():void {
      graphics.clear();
      graphics.beginFill(0x555599);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      var i:int, j:int, t:Number;
      var p:Point, q:Point, r:Point, s:Point;
      var t0:Number = getTimer();

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
      if (voronoi) {
        voronoi.dispose();
        voronoi = null;
      }

      // Clear the previous graph data. We'll reuse attr and points
      // when we can, but there's no easy way to reuse the Voronoi
      // object, so we'll allocate a new one.
      if (!attr) attr = new Dictionary(true);
      if (!points) points = new Vector.<Point>();
      
      // Clear the previous export bitmap data
      exportAltitude.clear();
      exportMoisture.clear();
      exportOverride.clear();

      System.gc();
      Debug.trace("MEMORY BEFORE:", System.totalMemory);

      
      // Generate random points and assign them to be on the island or
      // in the water. Some water points are inland lakes; others are
      // ocean. We'll determine ocean later by looking at what's
      // connected to ocean.
      t = getTimer();
      for (i = 0; i < NUM_POINTS; i++) {
        p = new Point(mapRandom.nextDoubleRange(10, SIZE-10),
                      mapRandom.nextDoubleRange(10, SIZE-10));
        points.push(p);
        attr[p] = {
          ocean: false,
          coast: false,
          water: !inside(island, p)
        };
      }
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
      // to the edge, and a map from these four points to the points
      // they connect to.
      t = getTimer();
      for each (p in points) {
          // Workaround for Voronoi lib bug: we need to call region()
          // before Edges or neighboringSites are available
          voronoi.region(p);
        }
      Debug.trace("TIME for region workaround:", getTimer()-t);
      t = getTimer();
      buildGraph(voronoi, attr);
      Debug.trace("TIME for buildGraph:", getTimer()-t);
      

      // Determine the elevations and oceans. By construction, we have
      // no local minima. This is important for the downslope vectors
      // later, which are used in the river construction
      // algorithm. Also by construction, inlets/bays push low
      // elevation areas inland, which means many rivers end up
      // flowing out through them. Also by construction, lakes often
      // end up on river paths because they don't raise the elevation
      // as much as other terrain does. TODO: there are points that
      // aren't being reached from this loop. Why?? We probably need
      // to force the edges of the map to be ocean, altitude 0.
      t = getTimer();
      var queue:Array = [];
      for each (p in points) {
          // Start with a seed ocean in the upper left, and let it
          // spread through anything already marked as ocean
          if (p.x < 50 && p.y < 50) {
            attr[p].water = true;
            attr[p].ocean = true;
            attr[p].elevation = 0.0;
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
            // Every step up is epsilon, unless it's over land, in
            // which case it's 1. The number doesn't matter because
            // we'll rescale the elevations later.
            var newElevation:Number = 0.01 + attr[p].elevation;
            if (!attr[q].water && !attr[p].water) {
              newElevation += 1;
            }
            // If anything has changed, we'll add this point to the
            // queue so that we can process its neighbors too.
            var changed:Boolean = false;
            if (attr[q].elevation == null || newElevation < attr[q].elevation) {
              attr[q].elevation = newElevation;
              changed = true;
            }
            if (attr[p].ocean && attr[q].water && !attr[q].ocean) {
              // The coastline algorithm marks water/land. The oceans
              // are the water areas connected to the initial ocean
              // seed; all other water areas will be treated as lakes. 
              attr[q].ocean = true;
              changed = true;
            }
            if (attr[p].ocean && !attr[q].ocean && !attr[q].coast) {
              // Coastal areas are land polygons with an ocean neighbor
              attr[q].coast = true;
              changed = true;
            }
            if (changed) {
              queue.push(q);
            }
          }
      }
      Debug.trace("TIME for elevation queue processing:", getTimer()-t);


      // Determine downslope paths. NOTE: we do this before calling
      // redistributeElevations because there's no guarantee that the
      // resulting elevations will have proper downslope paths. TODO:
      // redistributeElevations should be order-preserving.
      t = getTimer();
      for each (p in points) {
          r = p;
          for each (q in attr[p].neighbors) {
              if (attr[q].elevation <= attr[r].elevation) {
                r = q;
              }
            }
          attr[p].downslope = r;
        }
      Debug.trace("TIME for downslope paths:", getTimer()-t);

      
      // Rescale elevations so that the highest is 1.0, and they're
      // distributed well. We want lower elevations to be more common
      // than higher elevations, in proportions approximately matching
      // concentric rings. That is, the lowest elevation is the
      // largest ring around the island, and therefore should more
      // land area than the highest elevation, which is the very
      // center of a perfectly circular island.
      t = getTimer();

      var landPoints:Vector.<Point> = new Vector.<Point>();  // only non-ocean
      for each (p in points) {
          if (!attr[p].ocean) landPoints.push(p);
        }
      redistributeElevations(landPoints, attr);
      redistributeElevations(landPoints, attr);
      redistributeElevations(landPoints, attr);
      Debug.trace("TIME for elevation rescaling:", getTimer()-t);
      

      // Create rivers. Pick a random point, then move downslope
      t = getTimer();
      for (i = 0; i < SIZE/2; i++) {
        p = points[mapRandom.nextIntRange(0, NUM_POINTS-1)];
        if (attr[p].water || attr[p].elevation < 0.3 || attr[p].elevation > 0.9) continue;
        // Bias rivers to go west: if (attr[p].downslope.x > p.x) continue;
        while (!attr[p].ocean) {
          if (attr[p].river == null) attr[p].river = 0;
          attr[p].river = attr[p].river + 1;
          if (p == attr[p].downslope) {
            Debug.trace("Downslope failed", attr[p].elevation);
            break;
          }
          p = attr[p].downslope;
        }
      }
      Debug.trace("TIME for river paths:", getTimer()-t);

      
      // Calculate moisture. Rivers and lakes get high moisture, and
      // moisture drops off from there. Oceans get high moisture but
      // moisture does not propagate from oceans (we set it at the
      // end, after propagation). TODO: the parameters (1.5, 0.2, 0.9)
      // are tuned for NUM_POINTS = 2000, and it's not clear how they
      // should be adjusted for other scales.
      t = getTimer();
      queue = [];
      for each (p in points) {
          if ((attr[p].water || attr[p].river) && !attr[p].ocean) {
            attr[p].moisture = attr[p].river? Math.min(1.5, (0.2 * attr[p].river)) : 1.0;
            queue.push(p);
          } else {
            attr[p].moisture = 0.0;
          }
        }
      while (queue.length > 0) {
        p = queue.shift();

        for each (q in attr[p].neighbors) {
            var newMoisture:Number = attr[p].moisture * 0.80;
            if (newMoisture > attr[q].moisture) {
              attr[q].moisture = newMoisture;
              queue.push(q);
            }
          }
      }
      for each (p in points) {
          if (attr[p].ocean) attr[p].moisture = 0.8;
        }
      Debug.trace("TIME for moisture calculation:", getTimer()-t);

      
      // Choose polygon biomes based on elevation, water, ocean
      t = getTimer();
      assignTerrains(points, attr);
      Debug.trace("TIME for terrain assignment:", getTimer()-t);

      
      // For all edges between polygons, build a noisy line path that
      // we can reuse while drawing both polygons connected to that
      // edge. The noisy lines are constructed in two sections, going
      // from the vertex to the midpoint. We don't construct the noisy
      // lines from the polygon centers to the midpoints, because
      // they're not needed for polygon filling.
      t = getTimer();
      buildNoisyEdges(points, attr);
      Debug.trace("TIME for noisy edge construction:", getTimer()-t);


      // Render the polygons first, then select edges (rivers, lava,
      // coastline, lakeshores) 
      t = getTimer();
      renderPolygons(graphics, points, displayColors, attr, true, null, null);
      renderRivers(graphics, points, displayColors, voronoi, attr);
      Debug.trace("TIME for rendering:", getTimer()-t);


      Debug.trace("MEMORY AFTER:", System.totalMemory, " TIME taken:", getTimer()-t0,"ms");
    }


    // Build graph data structure in the 'attr' objects, based on
    // information in the Voronoi results: attr[point].neighbors will
    // be a list of neighboring points of the same type (corner or
    // center); attr[point].edges will be a list of edges that include
    // that point. Each edge connects to four points: the Voronoi edge
    // attr[edge].{v0,v1} and its dual Delaunay triangle edge
    // attr[edge].{d0,d1}.  For boundary polygons, the Delaunay edge
    // will have one null point, and the Voronoi edge may be null.
    public function buildGraph(voronoi:Voronoi, attr:Dictionary):void {
      var edges:Vector.<Edge> = voronoi.edges();
      for each (var edge:Edge in edges) {
          var dedge:LineSegment = edge.delaunayLine();
          var vedge:LineSegment = edge.voronoiEdge();

          // Per point attributes: neighbors and edges
          for each (var point:Point in [dedge.p0, dedge.p1, vedge.p0, vedge.p1]) {
              if (point == null) { continue; }
              if (attr[point] == null) attr[point] = {};
              if (attr[point].edges == null) attr[point].edges = new Vector.<Edge>();
              if (attr[point].neighbors == null) attr[point].neighbors = new Vector.<Point>();
              attr[point].edges.push(edge);
            }
          if (dedge.p0 != null && dedge.p1 != null) {
            attr[dedge.p0].neighbors.push(dedge.p1);
            attr[dedge.p1].neighbors.push(dedge.p0);
          }
          if (vedge.p0 != null && vedge.p1 != null) {
            attr[vedge.p0].neighbors.push(vedge.p1);
            attr[vedge.p1].neighbors.push(vedge.p0);
          }
          
          // Per edge attributes
          attr[edge] = {};
          attr[edge].v0 = vedge.p0;
          attr[edge].v1 = vedge.p1;
          attr[edge].d0 = dedge.p0;
          attr[edge].d1 = dedge.p1;
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
    public function redistributeElevations(points:Vector.<Point>, attr:Dictionary):void {
      var maxElevation:int = 10;
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
      for each (p in points) {
          x = attr[p].elevation;
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
          attr[p].elevation = x/maxElevation;
        }
    }

    
    // Assign a terrain type to each polygon. If it has
    // ocean/coast/water, then that's the terrain type; otherwise it
    // depends on low/high elevation and low/medium/high moisture.
    public function assignTerrains(points:Vector.<Point>, attr:Dictionary):void {
      for each (var p:Point in points) {
          var A:Object = attr[p];
          if (A.ocean) {
            A.biome = 'OCEAN';
          } else if (A.water) {
            A.biome = 'LAKE';
            if (A.elevation < 0.1) A.biome = 'MARSH';
            if (A.elevation > 0.7) A.biome = 'ICE';
          } else if (A.coast) {
            A.biome = 'BEACH';
          } else if (A.elevation > 0.85) {
            if (A.moisture > 0.5) A.biome = 'SNOW';
            else if (A.moisture > 0.3) A.biome = 'BARE'; 
            else A.biome = 'SCORCHED';
          } else if (A.elevation > 0.2) {
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
                var midpoint:Point = Point.interpolate(attr[edge].v0, attr[edge].v1, 0.5);
                var p:Point = Point.interpolate(attr[edge].v0, attr[edge].d0, f);
                var q:Point = Point.interpolate(attr[edge].v0, attr[edge].d1, f);
                var r:Point = Point.interpolate(attr[edge].v1, attr[edge].d0, f);
                var s:Point = Point.interpolate(attr[edge].v1, attr[edge].d1, f);

                var minLength:int = 4;
                if (attr[attr[edge].d0].water != attr[attr[edge].d1].water) minLength = 2;
                if (attr[attr[edge].d0].ocean && attr[attr[edge].d1].ocean) minLength = 100;
                
                attr[edge].path0 = noisy_line.buildLineSegments(attr[edge].v0, p, midpoint, q, minLength);
                attr[edge].path1 = noisy_line.buildLineSegments(attr[edge].v1, s, midpoint, r, minLength);
                _count++;
              }
            }
        }
    }
    

    // Look up a Voronoi Edge object given two adjacent Voronoi polygons
    public function lookupEdge(p:Point, q:Point, attr:Dictionary):Edge {
      for each (var edge:Edge in attr[p].edges) {
          if (attr[edge].d0 == q || attr[edge].d1 == q) return edge;
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


    // Render the polygons
    public function renderPolygons(graphics:Graphics, points:Vector.<Point>, colors:Object, attr:Dictionary, texturedFills:Boolean, altitudeFunction:Function, moistureFunction:Function):void {
      var p:Point, q:Point;

      // My Voronoi polygon rendering doesn't handle the boundary
      // polygons, so I just fill everything with ocean first.
      graphics.beginFill(colors.OCEAN);
      graphics.drawRect(0, 0, SIZE, SIZE);
      graphics.endFill();
      
      for each (p in points) {
          function drawPathForwards(path:Vector.<Point>):void {
            for (var i:int = 0; i < path.length; i++) {
              graphics.lineTo(path[i].x, path[i].y);
            }
          }
          function drawPathBackwards(path:Vector.<Point>):void {
            for (var i:int = path.length-1; i >= 0; i--) {
              graphics.lineTo(path[i].x, path[i].y);
            }
          }
          for each (q in attr[p].neighbors) {
              var color:int = colors[attr[p].biome];
              if (altitudeFunction != null) {
                color = (altitudeFunction(p, q, attr) << 16) | (color & 0x00ffff);
              }
              if (moistureFunction != null) {
                color = (moistureFunction(p, q, attr) << 8) | (color & 0xff00ff);
              }
              /* HACK: draw moisture level
              color = int(255*(0.667*attr[p].moisture+0.333*attr[q].elevation));
              if (color > 255) color = 255;
              color = color | 0x777700;
*/
              /* HACK: draw altitude level
                 color = int(255*(0.667*attr[p].elevation+0.333*attr[q].elevation));
                 if (color > 255) color = 255;
                 color = (color << 8) | (color << 16) | 0x77;
*/
                   
              if (texturedFills) {
                graphics.beginBitmapFill(getBitmapTexture(color));
              } else {
                graphics.beginFill(color);
              }
              graphics.moveTo(p.x, p.y);
              var edge:Edge = lookupEdge(p, q, attr);
              if (attr[edge].path0 == null || attr[edge].path1 == null) {
                continue;
                Debug.trace("NULL PATH", attr[edge].d0 == p, attr[edge].d0 == q);
              }
              graphics.lineTo(attr[edge].path0[0].x, attr[edge].path0[0].y);
              if (attr[p].ocean != attr[q].ocean) {
                // One side is ocean and the other side is land -- coastline
                graphics.lineStyle(2, colors.COAST);
              } else if (attr[p].water != attr[q].water) {
                // Lake boundary
                graphics.lineStyle(1, colors.LAKESHORE);
              }
              
              drawPathForwards(attr[edge].path0);
              drawPathBackwards(attr[edge].path1);
              graphics.lineStyle();
              graphics.lineTo(p.x, p.y);
              graphics.endFill();
            }
        }
    }
    

    // Render rivers. TODO: refactor to share code with buildNoisyEdges()
    public function renderRivers(graphics:Graphics, points:Vector.<Point>, colors:Object, voronoi:Voronoi, attr:Dictionary):void {
      var edges:Vector.<Edge> = voronoi.edges();
      for (var i:int = 0; i < edges.length; i++) {
        var dedge:LineSegment = edges[i].delaunayLine();
        var vedge:LineSegment = edges[i].voronoiEdge();
        if (vedge.p0 && vedge.p1 &&
            (!attr[dedge.p0].ocean || !attr[dedge.p1].ocean)) {
          var midpoint:Point = Point.interpolate(vedge.p0, vedge.p1, 0.5);
          var alpha:Number = 0.03;

          var f:Number = 0.6;  // low: jagged vedge; high: jagged dedge
          var p:Point = Point.interpolate(vedge.p0, dedge.p0, f);
          var q:Point = Point.interpolate(vedge.p0, dedge.p1, f);
          var r:Point = Point.interpolate(vedge.p1, dedge.p0, f);
          var s:Point = Point.interpolate(vedge.p1, dedge.p1, f);

          // Water river
          if ((attr[dedge.p0].downslope == dedge.p1 || attr[dedge.p1].downslope == dedge.p0)
              && ((attr[dedge.p0].water || attr[dedge.p0].river)
                  && (attr[dedge.p1].water || attr[dedge.p1].river))) {
            if (attr[dedge.p0].river && !attr[dedge.p0].water) {
              noisy_line.drawLineP(graphics, dedge.p0, p, midpoint, r, {color: colors.RIVER, width: Math.sqrt(attr[dedge.p0].river), minLength: 2});
            }
            if (attr[dedge.p1].river && !attr[dedge.p1].water) {
              noisy_line.drawLineP(graphics, midpoint, q, dedge.p1, s, {color: colors.RIVER, width: Math.sqrt(attr[dedge.p1].river), minLength: 2});
            }
          }

          // Lava flow
          if (!attr[dedge.p0].water && !attr[dedge.p1].water
              && !attr[dedge.p0].river && !attr[dedge.p1].river
              && (attr[dedge.p0].elevation > 0.9 || attr[dedge.p1].elevation > 0.9)
              && (attr[dedge.p0].moisture < 0.5 && attr[dedge.p1].moisture < 0.5)
              && mapRandom.nextIntRange(0, 2) == 0) {
            noisy_line.drawLineP(graphics, vedge.p0, p, midpoint, r, {color: colors.LAVA, width: 5*(attr[dedge.p0].elevation - 0.7), minLength: 1});
            noisy_line.drawLineP(graphics, midpoint, q, vedge.p1, s, {color: colors.LAVA, width: 5*(attr[dedge.p1].elevation - 0.7), minLength: 1});
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


    //////////////////////////////////////////////////////////////////////
    // The following code is used to export the maps to disk

    // We export altitude, moisture, and an override byte. We "paint"
    // these three by using RGB values and the standard paint
    // routines.  The exportColors have R, G, B, set to be the
    // altitude, moisture, and override code.
    static public var exportColors:Object = {
      /* override codes are 0:none, 0x10:river water, 0x20:lava, 0x30:snow,
         0x40:ice, 0x50:ocean, 0x60:lake, 0x70:lake shore, 0x80:ocean shore */
      // TODO: we only use the override code; remove the rest
      OCEAN: 0x00ff50,
      COAST: 0x00ff80,
      LAKE: 0x55ff60,
      LAKESHORE: 0x55ff70,
      RIVER: 0x55ff10,
      MARSH: 0x33ff10,
      ICE: 0xeeff40,
      SCORCHED: 0xdd0000,
      BEACH: 0x034400,
      BARE: 0xee0000,
      LAVA: 0xee0020,
      SNOW: 0xeeff30,
      DESERT: 0x990000,
      SAVANNAH: 0x992200,
      GRASSLANDS: 0x994400,
      DRY_FOREST: 0x666600,
      RAIN_FOREST: 0x448800,
      SWAMP: 0x33ff00
    };

    
    // This function draws to a bitmap and copies that data into the
    // three export byte arrays
    public function fillExportBitmaps():void {
      if (exportAltitude.length == 0) {
        var export:BitmapData = new BitmapData(2048, 2048);
        var exportGraphics:Shape = new Shape();
        renderPolygons(exportGraphics.graphics, points, exportColors, attr, false, exportAltitudeFunction, exportMoistureFunction);
        renderRivers(exportGraphics.graphics, points, exportColors, voronoi, attr);
        var m:Matrix = new Matrix();
        m.scale(2048.0 / SIZE, 2048.0 / SIZE);
        stage.quality = 'low';
        export.draw(exportGraphics, m);
        stage.quality = 'best';
        for (var x:int = 0; x < 2048; x++) {
          for (var y:int = 0; y < 2048; y++) {
            var color:uint = export.getPixel(x, y);
            exportAltitude.writeByte((color >> 16) & 0xff);
            exportMoisture.writeByte((color >> 8) & 0xff);
            exportOverride.writeByte(color & 0xff);
          }
        }
      }
    }

    public function exportAltitudeFunction(p:Point, q:Point, attr:Dictionary):int {
      var elevation:Number = (0.667 * attr[p].elevation + 0.333 * attr[q].elevation);
      var c:int = 255 * elevation;
      if (attr[p].biome == 'BEACH') c = 3;
      else if (attr[p].ocean) c = 0;
      else c += 6;
      if (c < 0) c = 0;
      if (c > 255) c = 255;
      return c;
    }


    public function exportMoistureFunction(p:Point, q:Point, attr:Dictionary):int {
      var moisture:Number = (0.667 * attr[p].moisture + 0.333 * attr[q].moisture);
      var c:int = 255 * moisture;
      if (c < 0) c = 0;
      if (c > 255) c = 255;
      return c;
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
    }

               
    public function addExportButtons():void {
      addChild(makeButton("export elevation", 650, 150,
                          function (e:Event):void {
                            fillExportBitmaps();
                            new FileReference().save(exportAltitude);
                            e.stopPropagation();
                          }));
      addChild(makeButton("export moisture", 650, 180,
                          function (e:Event):void {
                            fillExportBitmaps();
                            new FileReference().save(exportMoisture);
                            e.stopPropagation();
                          }));
      addChild(makeButton("export overrides", 650, 210,
                          function (e:Event):void {
                            fillExportBitmaps();
                            new FileReference().save(exportOverride);
                            e.stopPropagation();
                          }));
    }
    
  }
  
}
