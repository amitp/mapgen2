// Draw a fractal noisy line inside a quad boundary
// Author: amitp@cs.stanford.edu
// License: MIT

/*

  Recursive approach: given A-B-C-D, we split horizontally (q) and
  vertically (p).
  
  A  ----- G ----- B
  |          |        |
  E ----- H ----- F
  |          I        |
  D ------I------C

  To draw a line from A to C, we pick H somewhere in the quad, then
  recursively draw a noisy line from A to H inside A-G-H-E and from
  H to C inside H-F-C-I.
  
*/

package {
  import flash.geom.*;
  import flash.display.*;
  import flash.events.*;
  
  public class noisy_line extends Sprite {
    public function noisy_line() {
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

      drawLine(graphics,
               new Vector3D(0, 0), new Vector3D(300, 0),
               new Vector3D(300, 200), new Vector3D(0, 200));
      drawLine(graphics,
               new Vector3D(300, 200), new Vector3D(600, 200),
               new Vector3D(600, 400), new Vector3D(300, 400));
    }


    public static function drawLineP(g:Graphics, A:Point, B:Point, C:Point, D:Point, style:Object):Number {
      return drawLine(g, new Vector3D(A.x, A.y), new Vector3D(B.x, B.y), new Vector3D(C.x, C.y), new Vector3D(D.x, D.y), style);
    }

    
    public static function drawLine(g:Graphics, A:Vector3D, B:Vector3D, C:Vector3D, D:Vector3D, style:Object=null):Number {
      if (!style) style = {};
      
      // Draw the quadrilateral
      if (style.debug) {
        g.beginFill(0xccccbb, 0.1);
        g.lineStyle(1, 0x000000, 0.1);
        g.moveTo(A.x, A.y);
        g.lineTo(B.x, B.y);
        g.lineTo(C.x, C.y);
        g.lineTo(D.x, D.y);
        g.endFill();
        g.lineStyle();
      }

      var minLength:Number = style.minLength != null? style.minLength : 3;
      if (A.subtract(C).length < minLength || B.subtract(D).length < minLength) {
        g.lineStyle(style.width != null? style.width:1,
                    style.color != null? style.color:0x000000,
                    style.alpha != null? style.alpha:1.0);
        g.moveTo(A.x, A.y);
        g.lineTo(C.x, C.y);
        return A.subtract(C).length;
      }

      // Subdivide the quadrilateral
      var p:Number = random(0.1, 0.9);  // vertical (along A-D and B-C)
      var q:Number = random(0.3, 0.7);  // horizontal (along A-B and D-C)

      // Midpoints
      var E:Vector3D = interpolate(A, D, p);
      var F:Vector3D = interpolate(B, C, p);
      var G:Vector3D = interpolate(A, B, q);
      var I:Vector3D = interpolate(D, C, q);

      // Central point
      var H:Vector3D = interpolate(E, F, q);

      // Divide the quad into subquads, but meet at H
      var s:Number = random(-0.4, 0.4);
      var t:Number = random(-0.4, 0.4);
      
      return drawLine(g, A, interpolate(G, B, s), H, interpolate(E, D, t), style)
        + drawLine(g, H, interpolate(F, C, s), C, interpolate(I, D, t), style);
    }

    // Convenience: random number in a range
    public static function random(low:Number, high:Number):Number {
      return low + (high-low) * Math.random();
    }


    // Interpolate between two points
    public static function interpolate(p:Vector3D, q:Vector3D, f:Number):Vector3D {
      return new Vector3D(p.x*(1-f) + q.x*f, p.y*(1-f) + q.y*f, p.z*(1-f) + q.z*f);
    }

    
  }
}
