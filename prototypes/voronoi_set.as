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
  import com.nodename.geom.Circle;
  import com.nodename.geom.LineSegment;
  import com.nodename.Delaunay.Edge;
  import com.nodename.Delaunay.Voronoi;
  
  public class voronoi_set extends Sprite {
    static public var NUM_POINTS:int = 2000;
    static public var SIZE:int = 600;
    static public var ISLAND_FACTOR:Number = 1.1;  // 1.0 means no small islands; 2.0 leads to a lot

    static public var displayColors:Object = {
      OCEAN: 0x555599,
      COAST: 0x333377,
      LAKESHORE: 0x225588,
      LAKE: 0x336699,
      RIVER: 0x336699,
      MARSH: 0x226677,
      ICE: 0x99ffff,
      SCORCHED: 0x444433,
      BEACH: 0xb0b099,
      LAVA: 0xcc3333,
      SNOW: 0xffffff,
      SAVANNAH: 0xaacc88,
      GRASSLANDS: 0x99aa55,
      DRY_FOREST: 0x77aa55,
      RAIN_FOREST: 0x559955,
      SWAMP: 0x558866
    };

    public function voronoi_set() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      addChild(new Debug(this));

      stage.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { go(); } );

      addExportButtons();
      go();
    }

    // Random parameters governing the overall shape of the island
    public var island:Object = {
      bumps: int(1 + Math.random()*6),
      startAngle: Math.random() * 2*Math.PI,
      dipAngle: Math.random() * 2*Math.PI,
      dipWidth: 0.2 + Math.random()*0.5
    };

    public function go():void {
      graphics.clear();
      graphics.beginFill(0x555599);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      var i:int, j:int, t:Number;

      // Generate random points and assign them to be on the island or
      // in the water. Some water points are inland lakes; others are
      // ocean. We'll determine ocean later by looking at what's
      // connected to ocean.
      t = getTimer();
      var points:Vector.<Point> = new Vector.<Point>();
      var attr:Dictionary = new Dictionary();
      for (i = 0; i < NUM_POINTS; i++) {
        p = new Point(10 + (SIZE-20)*Math.random(), 10 + (SIZE-20)*Math.random());

        points.push(p);
        attr[p] = {
          ocean: false,
          coast: false,
          water: !inside(island, p)
        };
      }
      Debug.trace("TIME for random points:", getTimer()-t);

      t = getTimer();
      var voronoi:Voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));
      Debug.trace("TIME for voronoi:", getTimer()-t);

      // Create a graph structure from the voronoi edge list
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
            attr[p].elevation = 0;
            queue.push(p);
          }
        }
      Debug.trace("TIME for initial queue:", getTimer()-t);
      t = getTimer();
      while (queue.length > 0) {
        p = queue.shift();

        for each (q in attr[p].neighbors) {
            var newElevation:Number = 0.01 + attr[p].elevation;
            var changed:Boolean = false;
            if (!attr[q].water && !attr[p].water) {
              newElevation += 1 + Math.random();
            }
            if (attr[q].elevation == null || newElevation < attr[q].elevation) {
              attr[q].elevation = newElevation;
              changed = true;
            }
            if (attr[p].ocean && attr[q].water && !attr[q].ocean) {
              // Oceans are all connected, but some bodies of water
              // are not connected to oceans.
              attr[q].ocean = true;
              changed = true;
            }
            if (attr[p].ocean && !attr[q].ocean && !attr[q].coast) {
              // Coasts are land, but connected to oceans
              attr[q].coast = true;
              changed = true;
            }
            if (changed) {
              queue.push(q);
            }
          }
      }
      Debug.trace("TIME for elevation queue processing:", getTimer()-t);


      // Rescale elevations so that the highest is 10
      t = getTimer();
      var maxElevation:Number = 0.0;
      for each (p in points) {
          if (attr[p].elevation > maxElevation) {
            maxElevation = attr[p].elevation;
          }
        }
      for each (p in points) {
          attr[p].elevation = attr[p].elevation * 10 / maxElevation;
        }
      Debug.trace("TIME for elevation rescaling:", getTimer()-t);


      // Choose polygon biomes based on elevation, water, ocean
      t = getTimer();
      for each (p in points) {
          if (attr[p].ocean) {
            attr[p].biome = 'OCEAN';
          } else if (attr[p].water) {
            attr[p].biome = 'LAKE';
            if (attr[p].elevation < 0.1) attr[p].biome = 'MARSH';
            if (attr[p].elevation > 7) attr[p].biome = 'ICE';
            if (attr[p].elevation > 9) attr[p].biome = 'SCORCHED';
          } else if (attr[p].coast) {
            attr[p].biome = 'BEACH';
          } else if (attr[p].elevation > 9.9) {
            attr[p].biome = 'LAVA';
          } else if (attr[p].elevation > 9) {
            attr[p].biome = 'SCORCHED';
          } else if (attr[p].elevation > 8) {
            attr[p].biome = 'SNOW';
          } else if (attr[p].elevation > 7) {
            attr[p].biome = 'SAVANNAH'; 
          } else if (attr[p].elevation > 6) {
            attr[p].biome = 'GRASSLANDS';
          } else if (attr[p].elevation > 4) {
            attr[p].biome = 'DRY_FOREST';
          }  else if (attr[p].elevation > 0) {
            attr[p].biome = 'RAIN_FOREST';
          } else {
            attr[p].biome = 'SWAMP';
          }
        }
      Debug.trace("TIME for terrain assignment:", getTimer()-t);
                              
      // Determine downslope paths
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

      
      // Create rivers. Pick a random point, then move downslope
      t = getTimer();
      for (i = 0; i < SIZE/2; i++) {
        p = points[int(Math.random() * NUM_POINTS)];
        if (attr[p].water || attr[p].elevation < 3 || attr[p].elevation > 9) continue;
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

      // For all edges between polygons, build a noisy line path that
      // we can reuse while drawing both polygons connected to that edge
      t = getTimer();
      buildNoisyEdges(points, attr);
      Debug.trace("TIME for noisy edge construction:", getTimer()-t);

      var p:Point, q:Point, r:Point, s:Point;

      t = getTimer();
      renderPolygons(graphics, points, displayColors, attr, true, null, null);
      Debug.trace("TIME for polygon rendering:", getTimer()-t);
      t = getTimer();
      renderRivers(graphics, points, displayColors, voronoi, attr);
      Debug.trace("TIME for edge rendering:", getTimer()-t);

      t = getTimer();
      setupExport(points, voronoi, attr);
      Debug.trace("TIME for export setup:", getTimer()-t);
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
                var f:Number = 0.6;  // low: jagged vedge; high: jagged dedge
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
    public function renderPolygons(graphics:Graphics, points:Vector.<Point>, colors:Object, attr:Dictionary, texturedFills:Boolean):void {
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
              if (texturedFills) {
                graphics.beginBitmapFill(getBitmapTexture(colors[attr[p].biome]));
              } else {
                graphics.beginFill(colors[attr[p].biome]);
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
              && (attr[dedge.p0].elevation > 9 || attr[dedge.p1].elevation > 9)) {
            noisy_line.drawLineP(graphics, vedge.p0, p, midpoint, r, {color: colors.LAVA, width: 0.5*(attr[dedge.p0].elevation - 7), minLength: 1});
            noisy_line.drawLineP(graphics, midpoint, q, vedge.p1, s, {color: colors.LAVA, width: 0.5*(attr[dedge.p1].elevation - 7), minLength: 1});
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
      OCEAN: 0x00ff50,
      COAST: 0x00ff80,
      LAKE: 0x55ff60,
      LAKESHORE: 0x55ff70,
      RIVER: 0x55ff10,
      MARSH: 0x33ff10,
      ICE: 0xeeff40,
      SCORCHED: 0xdd0000,
      BEACH: 0x034400,
      LAVA: 0xee0020,
      SNOW: 0xeeff30,
      SAVANNAH: 0xcc2200,
      GRASSLANDS: 0x994400,
      DRY_FOREST: 0x666600,
      RAIN_FOREST: 0x448800,
      SWAMP: 0x33ff00
    };

    // These are empty when we make a map, and filled in on export
    public var altitude:ByteArray = new ByteArray();
    public var moisture:ByteArray = new ByteArray();
    public var override:ByteArray = new ByteArray();
    // This function fills in the above three arrays
    public var fillExportBitmaps:Function;
    
    public function setupExport(points:Vector.<Point>, voronoi:Voronoi, attr:Dictionary):void {
      var export:BitmapData = new BitmapData(2048, 2048);
      var exportGraphics:Shape = new Shape();
      altitude.clear();
      moisture.clear();
      override.clear();
      
      fillExportBitmaps = function():void {
        if (altitude.length == 0) {
          renderPolygons(exportGraphics.graphics, points, exportColors, attr, false);
          renderRivers(exportGraphics.graphics, points, exportColors, voronoi, attr);
          var m:Matrix = new Matrix();
          m.scale(2048.0 / SIZE, 2048.0 / SIZE);
          stage.quality = 'low';
          export.draw(exportGraphics, m);
          stage.quality = 'best';
          for (var x:int = 0; x < 2048; x++) {
            for (var y:int = 0; y < 2048; y++) {
              var color:uint = export.getPixel(x, y);
              altitude.writeByte((color >> 16) & 0xff);
              moisture.writeByte((color >> 8) & 0xff);
              override.writeByte(color & 0xff);
            }
          }
        }
      }
    }

    public function addExportButtons():void {
      function makeButton(label:String, x:int, y:int, callback:Function):TextField {
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

      addChild(makeButton("altitude", 650, 50,
                          function (e:Event):void {
                            fillExportBitmaps();
                            new FileReference().save(altitude);
                            e.stopPropagation();
                          }));
      addChild(makeButton("moisture", 650, 80,
                          function (e:Event):void {
                            fillExportBitmaps();
                            new FileReference().save(moisture);
                            e.stopPropagation();
                          }));
      addChild(makeButton("overrides", 650, 110,
                          function (e:Event):void {
                            fillExportBitmaps();
                            new FileReference().save(override);
                            e.stopPropagation();
                          }));
    }
    
  }
  
}
