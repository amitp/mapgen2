// Make a map out of a voronoi graph
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.events.*;
  import flash.utils.Dictionary;
  import com.nodename.geom.Circle;
  import com.nodename.geom.LineSegment;
  import com.nodename.Delaunay.Edge;
  import com.nodename.Delaunay.Voronoi;
  
  public class voronoi_set extends Sprite {
    static public var NUM_POINTS:int = 2000;
    static public var SIZE:int = 600;
    static public var ISLAND_FACTOR:Number = 1.1;  // 1.0 means no small islands; 2.0 leads to a lot
    
    public function voronoi_set() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      addChild(new Debug(this));

      stage.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { go(); } );
      go();
    }

    public function go():void {
      graphics.clear();
      graphics.beginFill(0x555599);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      var i:int, j:int;

      // Random parameters governing the overall shape of the island
      var island:Object = {
        bumps: int(1 + Math.random()*6),
        startAngle: Math.random() * 2*Math.PI,
        dipAngle: Math.random() * 2*Math.PI,
        dipWidth: 0.2 + Math.random()*0.5
      };

      // Generate random points and assign them to be on the island or
      // in the water. Some water points are inland lakes; others are
      // ocean. We'll determine ocean later by looking at what's
      // connected to ocean.
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

      var voronoi:Voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));

      // Create a graph structure from the voronoi edge list
      for each (p in points) {
          // Workaround for Voronoi lib bug: we need to call region()
          // before Edges or neighboringSites are available
          voronoi.region(p);
        }
      buildGraph(voronoi, attr);
      
      // Determine the elevations, oceans, and colors. By
      // construction, we have no local minima. This is important for
      // the downslope vectors later, which are used in the river
      // construction algorithm. Also by construction, inlets/bays
      // push low elevation areas inland, which means many rivers end
      // up flowing out through them. Also by construction, lakes
      // often end up on river paths because they don't raise the
      // elevation as much as other terrain does. TODO: there are
      // rivers that are not reaching the sea, possibly because of
      // loops in the downslope graph; need to investigate. This may
      // be because neighboringSites considers corner matches and the
      // Edge list does not.  TODO: there are points that aren't being
      // reached from this loop. Why?? We probably need to force the
      // edges of the map to be ocean, altitude 0.
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
      while (queue.length > 0) {
        p = queue.shift();

        for each (q in attr[p].neighbors) {
            var newElevation:Number = 0.01 + attr[p].elevation;
            var changed:Boolean = false;
            if (!attr[q].water && !attr[p].water) {
              newElevation += 0.5 + Math.random();
              if (p.x > q.x && newElevation > 1) {
                // biased so that mountains are more common on one side
                newElevation += 4 + 2 * Math.random();
              }
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


      // Color the polygons based on elevation, water, ocean
      for each (p in points) {
          if (attr[p].ocean) {
            attr[p].color = 0x555599;
          } else if (attr[p].water) {
            attr[p].color = 0x336699;
            if (attr[p].elevation < 0.1) attr[p].color = 0x226677; /* swamp?? not sure */
            if (attr[p].elevation > 7) attr[p].color = 0x99ffff; /* ice */
            if (attr[p].elevation > 9) attr[p].color = 0x333333; /* scorched? */
          } else if (attr[p].coast) {
            attr[p].color = 0xb0b099;  // beach
          } else if (attr[p].elevation > 9) {
            attr[p].color = 0xcc3333;  // lava
          } else if (attr[p].elevation > 8.5) {
            attr[p].color = 0x666666;  // scorched
          } else if (attr[p].elevation > 7) {
            attr[p].color = 0xffffff;  // ice
          } else if (attr[p].elevation > 6) {
            attr[p].color = 0xaacc88;  // dry grasslands
          } else if (attr[p].elevation > 4.5) {
            attr[p].color = 0x99aa55;  // grasslands
          } else if (attr[p].elevation > 2.5) {
            attr[p].color = 0x77aa55;  // grasslands
          }  else if (attr[p].elevation > 0) {
            attr[p].color = 0x559955;  // wet grasslands
          } else {
            attr[p].color = 0x558866;  // swampy
          }
        }
                              
      // Determine downslope paths
      for each (p in points) {
          r = p;
          for each (q in attr[p].neighbors) {
              if (attr[q].elevation <= attr[r].elevation) {
                r = q;
              }
            }
          attr[p].downslope = r;
        }

      
      // Create rivers. Pick a random point, then move downslope
      for (i = 0; i < SIZE/3; i++) {
        p = points[int(Math.random() * NUM_POINTS)];
        if (attr[p].water || attr[p].elevation < 5 || attr[p].elevation > 9) continue;
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

      // For all edges between polygons, build a noisy line path that
      // we can reuse while drawing both polygons connected to that edge
      buildNoisyEdges(points, attr);

      // Draw the polygons.
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
              graphics.beginBitmapFill(getBitmapTexture(attr[p].color));
              graphics.moveTo(p.x, p.y);
              var edge:Edge = lookupEdge(p, q, attr);
              if (attr[edge].path0 == null || attr[edge].path1 == null) {
                continue;
                Debug.trace("NULL PATH", attr[edge].d0 == p, attr[edge].d0 == q);
              }
              graphics.lineTo(attr[edge].path0[0].x, attr[edge].path0[0].y);
              if (attr[p].ocean != attr[q].ocean) {
                // One side is ocean and the other side is land -- coastline
                graphics.lineStyle(1, 0x000000);
              } else if (attr[p].water != attr[q].water) {
                // Lake boundary
                graphics.lineStyle(1, 0x003366, 0.5);
              } else if (attr[p].color != attr[q].color) {
                // Terrain boundary -- emphasize a bit
                graphics.lineStyle(1, 0x000000, 0.05);
              }
              drawPathForwards(attr[edge].path0);
              drawPathBackwards(attr[edge].path1);
                graphics.lineStyle();
              graphics.lineTo(p.x, p.y);
              graphics.endFill();
            }
        }
      
      var p:Point, q:Point, r:Point, s:Point;

      // Draw rivers. TODO: refactor to share code with buildNoisyEdges()
      var edges:Vector.<Edge> = voronoi.edges();
      for (i = 0; i < edges.length; i++) {
        var dedge:LineSegment = edges[i].delaunayLine();
        var vedge:LineSegment = edges[i].voronoiEdge();
        if (vedge.p0 && vedge.p1 &&
            (!attr[dedge.p0].ocean || !attr[dedge.p1].ocean)) {
          var midpoint:Point = Point.interpolate(vedge.p0, vedge.p1, 0.5);
          var alpha:Number = 0.03;

          var f:Number = 0.6;  // low: jagged vedge; high: jagged dedge
          p = Point.interpolate(vedge.p0, dedge.p0, f);
          q = Point.interpolate(vedge.p0, dedge.p1, f);
          r = Point.interpolate(vedge.p1, dedge.p0, f);
          s = Point.interpolate(vedge.p1, dedge.p1, f);
          if ((attr[dedge.p0].downslope == dedge.p1 || attr[dedge.p1].downslope == dedge.p0)
              && ((attr[dedge.p0].water || attr[dedge.p0].river)
                  && (attr[dedge.p1].water || attr[dedge.p1].river))) {
            if (attr[dedge.p0].river && !attr[dedge.p0].water) {
              drawNoisyLine(dedge.p0, midpoint, p, r, {color: 0x336699, width: Math.sqrt(attr[dedge.p0].river), minLength: 2});
            }
            if (attr[dedge.p1].river && !attr[dedge.p1].water) {
              drawNoisyLine(midpoint, dedge.p1, q, s, {color: 0x336699, width: Math.sqrt(attr[dedge.p1].river), minLength: 2});
            }
          }
        }
      }
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

                attr[edge].path0 = noisy_line.buildLineSegments(attr[edge].v0, p, midpoint, q, 1);
                attr[edge].path1 = noisy_line.buildLineSegments(attr[edge].v1, s, midpoint, r, 1);
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

    
    // Draw a noisy line from p to q, enclosed by the boundary points
    // a and b.  Points p-a-q-b form a quadrilateral, and the noisy
    // line will be inside of it.
    public function drawNoisyLine(p:Point, q:Point, a:Point, b:Point, style:Object=null):void {
      // TODO: we actually want two line widths, one for p and one for q
      noisy_line.drawLineP(graphics, p, a, q, b, style);
      graphics.lineStyle();
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
  }
}
