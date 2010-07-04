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
      
      var island:Object = {
        bumps: int(1 + Math.random()*6),
        startAngle: Math.random() * 2*Math.PI,
        dipAngle: Math.random() * 2*Math.PI,
        dipWidth: 0.2 + Math.random()*0.5
      };
    
      var points:Vector.<Point> = new Vector.<Point>();
      var colors:Vector.<uint> = new Vector.<uint>();
      var pointToColor:Dictionary = new Dictionary();
      for (i = 0; i < NUM_POINTS; i++) {
        var p:Point = new Point(10 + (SIZE-20)*Math.random(), 10 + (SIZE-20)*Math.random());

        points.push(p);
        if (inside(island, p)) {
          colors.push(0x009900);
        } else {
          colors.push(0x000099);
        }
        pointToColor[p] = colors[i];

        if (colors[i] == 0x000099) {
          graphics.beginFill(colors[i], colors[i] == 0x000099? 0.2 : 0.0);
          graphics.drawCircle(p.x, p.y, 2.5);
          graphics.endFill();
        }
      }

      var voronoi:Voronoi = new Voronoi(points, null, new Rectangle(0, 0, SIZE, SIZE));

      for (i = 0; i < NUM_POINTS; i++) {
        var region:Vector.<Point> = voronoi.region(points[i]);
        graphics.beginFill(colors[i], 0.4);
        graphics.moveTo(region[region.length-1].x, region[region.length-1].y);
        // graphics.lineStyle(1, 0x000000, 0.2);
        for (j = 0; j < region.length; j++) {
          graphics.lineTo(region[j].x, region[j].y);
        }
        graphics.endFill();
        graphics.lineStyle();

        // NOTE: neighbors.length is not always region.length, for
        // reasons I don't understand. Could be boundary issues.
      }

      var edges:Vector.<Edge> = voronoi.edges();
      for (i = 0; i < edges.length; i++) {
        var dedge:LineSegment = edges[i].delaunayLine();
        var vedge:LineSegment = edges[i].voronoiEdge();
        if (vedge.p0 && vedge.p1 &&
            ((pointToColor[dedge.p0] != 0x000099) || (pointToColor[dedge.p1] != 0x000099))) {
          var midpoint:Point = Point.interpolate(vedge.p0, vedge.p1, 0.5);
          var alpha:Number = 0.2;

          if ((pointToColor[dedge.p0] == 0x000099) != (pointToColor[dedge.p1] == 0x000099)) {
            // One side is ocean and the other side is land -- coastline
            alpha = 1.0;
          }

          var f:Number = 0.6;  // low: jagged vedge; high: jagged dedge
          var p:Point = Point.interpolate(vedge.p0, dedge.p0, f);
          var q:Point = Point.interpolate(vedge.p0, dedge.p1, f);
          var r:Point = Point.interpolate(vedge.p1, dedge.p0, f);
          var s:Point = Point.interpolate(vedge.p1, dedge.p1, f);
          drawNoisyLine(vedge.p0, midpoint, p, q, {color: 0x000000, alpha: alpha, width: 0, minLength:1});
          drawNoisyLine(midpoint, vedge.p1, r, s, {color: 0x000000, alpha: alpha, width: 0, minLength:1});
          if (pointToColor[dedge.p0] != 0x000099) {
            drawNoisyLine(dedge.p0, midpoint, p, r, {color: 0xffffff, alpha: 0.2, width: 0, minLength: 1});
          }
          if (pointToColor[dedge.p1] != 0x000099) {
            drawNoisyLine(midpoint, dedge.p1, q, s, {color: 0xffffff, alpha: 0.2, width: 0, minLength: 1});
          }
        }
      }
      
      graphics.lineStyle();

    }

    public function drawNoisyLine(p:Point, q:Point, a:Point, b:Point, style:Object=null):void {
      noisy_line.drawLineP(graphics, p, a, q, b, style);
    }

    public function inside(island:Object, p:Point):Boolean {
      var q:Point = new Point(p.x-SIZE/2, p.y-SIZE/2);  // normalize to center of island
      var angle:Number = Math.atan2(q.y, q.x);
      var length:Number = 0.5 * (Math.max(Math.abs(q.x), Math.abs(q.y)) + q.length);
      var r1:Number = SIZE*(0.25 + 0.1*Math.sin(island.startAngle + island.bumps*angle + Math.cos((island.bumps+3)*angle)));
      var r2:Number = SIZE*(0.30 - 0.1*Math.sin(island.startAngle + island.bumps*angle - Math.sin((island.bumps+2)*angle)));
      if (Math.abs(angle - island.dipAngle) < island.dipWidth
          || Math.abs(angle - island.dipAngle + 2*Math.PI) < island.dipWidth
          || Math.abs(angle - island.dipAngle - 2*Math.PI) < island.dipWidth) {
        r1 = r2 = 50;
      }
      return  (length < r1 || (length > r1*ISLAND_FACTOR && length < r2));
    }
  }
}
