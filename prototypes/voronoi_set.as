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
      
      go();

      stage.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { go(); } );
    }

    public function go():void {
      graphics.clear();
      graphics.beginFill(0x999999);
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

      // Determine the elevations, oceans, and colors
      var queue:Array = [];
      for each (p in points) {
          // Work around a bug in Voronoi.as: we need to call region()
          // on everything before we're allowed to call
          // neighborSitesForSite().
          /* result ignored */ voronoi.region(p);

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

        // Determine the color of this polygon
        if (attr[p].ocean) {
          attr[p].color = 0x555599;
        } else if (attr[p].water) {
          attr[p].color = 0x336699;
          if (attr[p].elevation == 0) attr[p].color = 0x000099; /* swamp? */
          if (attr[p].elevation > 7) attr[p].color = 0x99ffff; /* ice */
        } else if (attr[p].coast) {
          attr[p].color = 0xb0b099;  // beach
        } else if (attr[p].elevation > 9) {
          attr[p].color = 0xcc5555;  // lava
        } else if (attr[p].elevation > 7) {
          attr[p].color = 0xeeeeee;  // ice
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
        
        var neighbors:Vector.<Point> = voronoi.neighborSitesForSite(p);
        for each (q in neighbors) {
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

      // Determine downslope paths
      for each (p in points) {
          neighbors = voronoi.neighborSitesForSite(p);
          r = p;
          for each (q in neighbors) {
              if (attr[q].elevation <= attr[r].elevation) {
                r = q;
              }
            }
          attr[p].downslope = r;
        }

      
      // Create rivers. Pick a random point, then move downslope
      for (i = 0; i < SIZE; i++) {
        p = points[int(Math.random() * NUM_POINTS)];
        if (attr[p].elevation < 6 || attr[p].elevation > 9) continue;
        while (!attr[p].ocean) {
          if (attr[p].river == null) attr[p].river = 0;
          attr[p].river = attr[p].river + 1;
          if (attr[p].downslope == p) break;
          p = attr[p].downslope;
        }
      }

      
      // Draw the polygons. TODO: we're drawing them with the original
      // edges, but we really want to draw them with the noisy
      // edges. Need to figure out how to record noisy edge path so
      // that we can find it again indexed by polygon, not by edge.
      for (i = 0; i < NUM_POINTS; i++) {
        var region:Vector.<Point> = voronoi.region(points[i]);

        graphics.beginFill(attr[points[i]].color);
        graphics.moveTo(region[region.length-1].x, region[region.length-1].y);
        for (j = 0; j < region.length; j++) {
          graphics.lineTo(region[j].x, region[j].y);
        }
        graphics.endFill();
        graphics.lineStyle();
        
        if (attr[points[i]].ocean) {
          // For oceans we also draw the point that generated the polygon
          graphics.beginFill(0x000000, 0.1);
          graphics.drawCircle(points[i].x, points[i].y, 2);
          graphics.endFill();
        }
      }

      
      // Draw noisy Voronoi edges and Delaunay edges
      var edges:Vector.<Edge> = voronoi.edges();
      for (i = 0; i < edges.length; i++) {
        var dedge:LineSegment = edges[i].delaunayLine();
        var vedge:LineSegment = edges[i].voronoiEdge();
        if (vedge.p0 && vedge.p1 &&
            (!attr[dedge.p0].ocean || !attr[dedge.p1].ocean)) {
          var midpoint:Point = Point.interpolate(vedge.p0, vedge.p1, 0.5);
          var alpha:Number = 0.03;

          if (attr[dedge.p0].ocean != attr[dedge.p1].ocean) {
            // One side is ocean and the other side is land -- coastline
            alpha = 1.0;
          } else if (attr[dedge.p0].color != attr[dedge.p1].color) {
            // Terrain boundary -- emphasize a bit
            alpha = 0.1;
          }

          var f:Number = 0.6;  // low: jagged vedge; high: jagged dedge
          var p:Point = Point.interpolate(vedge.p0, dedge.p0, f);
          var q:Point = Point.interpolate(vedge.p0, dedge.p1, f);
          var r:Point = Point.interpolate(vedge.p1, dedge.p0, f);
          var s:Point = Point.interpolate(vedge.p1, dedge.p1, f);
          drawNoisyLine(vedge.p0, midpoint, p, q, {color: 0x000000, alpha: alpha, width: 0, minLength:2});
          drawNoisyLine(midpoint, vedge.p1, r, s, {color: 0x000000, alpha: alpha, width: 0, minLength:2});
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

    
    // Draw a noisy line from p to q, enclosed by the boundary points
    // a and b.  Points p-a-q-b form a quadrilateral, and the noisy
    // line will be inside of it.
    public function drawNoisyLine(p:Point, q:Point, a:Point, b:Point, style:Object=null):void {
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
  }
}
