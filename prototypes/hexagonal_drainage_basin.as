// Draw a fractal hexagonal drainage basin
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import flash.geom.*;
  import flash.display.*;

  public class hexagonal_drainage_basin extends Sprite {

    public function hexagonal_drainage_basin() {
      graphics.beginFill(0x999999);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      drawHex(new Vector3D(300, 0),
              new Vector3D(500, 100),
              new Vector3D(500, 250),
              new Vector3D(300, 350),
              new Vector3D(100, 250),
              new Vector3D(100, 100));
    }

    public function drawHex(A:Vector3D, B:Vector3D, C:Vector3D, D:Vector3D, E:Vector3D, F:Vector3D):void {
      graphics.beginFill(0x00ff00);
      graphics.lineStyle(1, 0x000000, 0.1);
      graphics.moveTo(A.x, A.y);
      graphics.lineTo(B.x, B.y);
      graphics.lineTo(C.x, C.y);
      graphics.lineTo(D.x, D.y);
      graphics.lineTo(E.x, E.y);
      graphics.lineTo(F.x, F.y);
      graphics.endFill();
      graphics.lineStyle();

      var H:Vector3D = between([A, B, C, D, E, F]);
      if (H.subtract(D).length < 1) return;
      
      graphics.lineStyle(2, 0x0000ff);
      graphics.moveTo(D.x, D.y);
      graphics.lineTo(H.x, H.y);
      graphics.lineStyle();
      
      var J:Vector3D = between([A, H]);
      var K:Vector3D = between([E, H]);
      var L:Vector3D = between([H, C]);
      var M:Vector3D = between([A, F]);
      var N:Vector3D = between([F, E]);
      var P:Vector3D = between([A, B]);
      var Q:Vector3D = between([B, C]);

      drawHex(F, M, J, H, K, N);
      drawHex(B, Q, L, H, J, P);
    }

    public function between(points:Array):Vector3D {
      var result:Vector3D = new Vector3D();
      var weight:Number = 0.0;
      for each (var p:Vector3D in points) {
          var w:Number = Math.random() + 0.5;
          result.x += p.x * w;
          result.y += p.y * w;
          result.z += p.z * w;
          weight += w;
        }
      result.scaleBy(1.0/weight);
      return result;
    }
  }
}
