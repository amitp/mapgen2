// Make a map out of a delaunay graph
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.events.*;
  import com.indiemaps.delaunay.*;
  
  public class delaunay_set extends Sprite {
    public function delaunay_set() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      go();

      stage.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { go(); } );
    }

    public function go():void {
      graphics.clear();
      graphics.beginFill(0x999999);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      // TODO: build voronoi data structure (NOTE: decided to switch
      // to a Voronoi library instead)

      // TODO: if a node has only one neighbor with same
      // inside/outside status, then change its status. This will
      // remove impossible areas.
      
      var i:int;
      var pxyz:Array = [];

      var tiles:Array = [];
      for (i = 0; i < 600; i++) {
        var xyz:XYZ = new XYZ(600*Math.random(), 500*Math.random(), 0);
        pxyz.push(xyz);
        if (inside(xyz)) {
          graphics.beginFill(0x009900);
        } else {
          graphics.beginFill(0x7777cc);
        }
        graphics.drawCircle(xyz.x, xyz.y, 5);
        graphics.endFill();
      }

      var triangles:Array = Delaunay.triangulate(pxyz);

      drawOld(pxyz, triangles);

          /*
      for each (var tri:ITriangle in triangles) {
          var circle:XYZ = new XYZ();
          Delaunay.CircumCircle(0, 0, pxyz[tri.p1].x, pxyz[tri.p1].y, pxyz[tri.p2].x, pxyz[tri.p2].y, pxyz[tri.p3].x, pxyz[tri.p3].y, circle);
          graphics.beginFill(0xff0000);
          graphics.drawCircle(circle.x, circle.y, 3);
          graphics.endFill();
          graphics.lineStyle(1, 0x000000, 0.2);
          graphics.drawCircle(circle.x, circle.y, circle.z);
          graphics.lineStyle();
        }
          */
    }

    public function drawOld(pxyz:Array, triangles:Array):void {
      for each (var tri:ITriangle in triangles) {
          function D(p1:int, p2:int, p3:int):void {
            var i1:Boolean = inside(pxyz[p1]);
            var i2:Boolean = inside(pxyz[p2]);
            var i3:Boolean = inside(pxyz[p3]);
            if (!i1 && !i2 && i3 && p1 > p2) {
              var p:int = p1;
              p1 = p2;
              p2 = p;
            }
            if (p1 < p2) {
              var color:int = 0x666600;
              if (i1&&i2) color = 0x007700;
              else if (!i1 && !i2 && i3) color = 0x000000;
              else if (!i1 && !i2) color = 0x6666cc;
              drawNoisyLine(pxyz[p1], pxyz[p2], {color: color, minLength:500, alpha:1, width:1});
              graphics.lineStyle();
            }
          }
          D(tri.p1, tri.p2, tri.p3);
          D(tri.p2, tri.p3, tri.p1);
          D(tri.p3, tri.p1, tri.p2);
        }
    }

    public function drawNoisyLine(p:XYZ, q:XYZ, style:Object=null):void {
      // TODO: don't use perp; use voronoi centers
      var pv:Vector3D = new Vector3D(p.x, p.y);
      var qv:Vector3D = new Vector3D(q.x, q.y);
      var p2q:Vector3D = qv.subtract(pv);
      var perp:Vector3D = new Vector3D(0.4*p2q.y, -0.4*p2q.x);
      var pq:Vector3D = new Vector3D(0.5*(p.x+q.x), 0.5*(p.y+q.y));
      noisy_line.drawLine(graphics, pv, pq.add(perp), qv, pq.subtract(perp), style);
      graphics.lineStyle();
    }
    
    public function inside(xyz:XYZ):Boolean {
      var angle:Number = Math.atan2(xyz.y-250, xyz.x-300);
      var length:Number = new Point(xyz.x-300, xyz.y-250).length;
      var r1:Number = 150 - 30*Math.sin(5*angle);
      var r2:Number = 150 - 70*Math.sin(5*angle + 0.5);
      if (0.1 < angle && angle < 1.2) r1 = r2 = 30;
      return  (length < r1 || (length >= r1 && length < r2));
    }
      
    public static function coordinateToPoint(i:int, j:int):Point {
      return new Point(20 + 50*i + 25*j + 3.7*(i % 3) + 2.5*(j % 4), 10 + 50*j + 3.7*(j % 3) + 2.5*(i % 4));
    }
  }
}
