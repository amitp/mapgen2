// Draw a fractal quadrilateral drainage basin
// Author: amitp@cs.stanford.edu
// License: MIT

/*

  Recursive approach: given A-B-C-D, we split horizontally (q) and
  vertically (p) and create two quadrilaterals A-G-H-E and G-B-F-H.
  
  A  ----- G ----- B
  |          |        |
  E ----- H ----- F
  |                   |
  D -------------C

  The river goes from E-H to D-C and H-F to D-C.
  
*/

package {
  import flash.geom.*;
  import flash.filters.*;
  import flash.display.*;
  import flash.events.*;
  
  public class quadrilateral_drainage_basin extends Sprite {
    public var river:Shape = new Shape();
    
    public function quadrilateral_drainage_basin() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      river.filters = [new GlowFilter(0x000000, 0.5, 2.0, 2.0)];
      addChild(river);
      go();

      stage.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { go(); } );
    }

    public function go():void {
      river.graphics.clear();
      graphics.clear();
      graphics.beginFill(0x999999);
      graphics.drawRect(-1000, -1000, 2000, 2000);
      graphics.endFill();

      if (false) {
        // Draw one large quad
        drawQuad(new Vector3D(100, 10, 10), new Vector3D(400, 10, 10),
                 new Vector3D(600, 300, 0), new Vector3D(10, 400, 0),
                 50.0);
      } else {
        // Draw a bunch of quads
        var P:Array = [[100, 20], [200, 200], [160, 300], [200, 500],
                       [400, 80], [480, 220], [540, 280], [520, 430],
                       [540, 30], [600, 250], [660, 370], [580, 490],
                       [300, 25], [300, 550]];
        function draw(A:Array, B:Array, C:Array, D:Array):void {
          var aV:Vector3D = new Vector3D(A[0], A[1], 1);
          var bV:Vector3D = new Vector3D(B[0], B[1], 1);
          var cV:Vector3D = new Vector3D(C[0], C[1], 0);
          var dV:Vector3D = new Vector3D(D[0], D[1], 0);
          var normal:Vector3D = aV.subtract(cV).crossProduct(bV.subtract(dV));
          normal.normalize();
          var volume:Number = 0.0003 * areaOfQuad(aV, bV, cV, dV);
          if (normal.x > 0) volume *= 0.5;
          drawQuad(aV, bV, cV, dV, volume);
        }
        draw(P[4], P[5], P[1], P[0]);
        draw(P[5], P[6], P[2], P[1]);
        draw(P[6], P[7], P[3], P[2]);
        draw(P[5], P[4], P[8], P[9]);
        draw(P[6], P[5], P[9], P[10]);
        draw(P[7], P[6], P[10], P[11]);
        
        // Coastlines are drawn from midpoint to midpoint
        function drawCoast(i:int, j:int, k:int):void {
          var pV:Vector3D = interpolate(new Vector3D(P[i][0], P[i][1]), new Vector3D(P[j][0], P[j][1]), 0.5);
          var qV:Vector3D = new Vector3D(P[j][0], P[j][1]);
          var rV:Vector3D = interpolate(new Vector3D(P[j][0], P[j][1]), new Vector3D(P[k][0], P[k][1]), 0.5);
          drawRiver(graphics, pV, qV, 1, 1, 0x000000, (i == 0 && j == 1));
          drawRiver(graphics, qV, rV, 1, 1, 0x000000, false);
        }
        graphics.beginFill(0xffffff, 0.7);
        drawCoast(0, 1, 2); drawCoast(1, 2, 3);
        drawCoast(2, 3, 13); drawCoast(3, 13, 11);
        drawCoast(13, 11, 10); drawCoast(11, 10, 9);
        drawCoast(10, 9, 8); drawCoast(9, 8, 12);
        drawCoast(8, 12, 0); drawCoast(12, 0, 1);
        graphics.endFill();
      }
    }

    
    // Area of the planar projection of the quadrilateral down to z=0.
    // Used for rainfall estimate. The area of a quadrilateral is half
    // the cross product of the diagonals.
    public function areaOfQuad(A:Vector3D, B:Vector3D, C:Vector3D, D:Vector3D):Number {
      // NOTE: if we wanted to take into account the z value, use
      // 0.5 * AC.crossProduct(BD).length
      var AC:Vector3D = A.subtract(C);
      var BD:Vector3D = B.subtract(D);
      return 0.5 * Math.abs(AC.x * BD.y - BD.x * AC.y);
    }

    
    // TODO: volume should be based on the moisture level times the area of the quad
    public function drawQuad(A:Vector3D, B:Vector3D, C:Vector3D, D:Vector3D, volume:Number):void {
      // Draw the quadrilateral
      var lightingVector:Vector3D = D.subtract(C);
      lightingVector.normalize();
      var lighting:Number = 1.0 + lightingVector.dotProduct(new Vector3D(-0.3, -0.3, -0.6));
      lighting *= 0.6;
      if (lighting < 0.2) lighting = 0.2;
      if (lighting > 1.0) lighting = 1.0;
      lighting = 0.9;
      var gray:int = 255*lighting;
      graphics.beginFill((int(gray*0.8) << 16) | (gray << 8) | (gray>>1));
      graphics.lineStyle(1, 0x000000, 0.1);
      graphics.moveTo(A.x, A.y);
      graphics.lineTo(B.x, B.y);
      graphics.lineTo(C.x, C.y);
      graphics.lineTo(D.x, D.y);
      graphics.endFill();
      graphics.lineStyle();

      if (A.subtract(D).length < 5 || B.subtract(C).length < 5) return;

      // Subdivide the quadrilateral
      var p:Number = random(0.5, 0.7);  // vertical (along A-D and B-C)
      var q:Number = random(0.1, 0.9);  // horizontal (along A-B and D-C)

      // Midpoints
      var E:Vector3D = interpolate(A, D, p);
      var F:Vector3D = interpolate(B, C, p);
      var G:Vector3D = interpolate(A, B, q);

      // Central point starts out between E and F but doesn't have to be exact
      var H:Vector3D = interpolate(E, F, q);
      H = interpolate(H, G, random(-0.2, 0.4));

      // These are the river locations along edges. Right now they're
      // all midpoints but we could change that, if we pass the
      // position along in the recursive call.
      var DC:Vector3D = interpolate(D, C, 0.5);
      var DCH:Vector3D = interpolate(DC, interpolate(E, F, random(0.3, 0.7)), random(0.3, 0.7));
      var EH:Vector3D = interpolate(E, H, 0.5);
      var HF:Vector3D = interpolate(H, F, 0.5);

      // Adjust elevations
      G.z += 0.5;
      H.z = DC.z;

      // River widths. The width is the square root of the volume. We
      // assume the volume gets divided non-uniformly between the two
      // channels, based on q (the larger side is more likely to have
      // the larger tributary). Also, the lower portion of the
      // quadrilateral contributes water, based on p, so the two
      // tributaries don't add up to the full volume.
      var v0:Number = volume * p; // random(0.5, 1.0);  // how much comes from tributaries
      var volumeFromLeft:Number = q * random(1, 2) / random(1, 2);
      var v1:Number = v0 * volumeFromLeft;
      var v2:Number = v0 - v1;

      // Draw the river, plus its two tributaries
      drawRiver(river.graphics, DC, DCH, volume, v0, 0x0000ff);
      drawRiver(river.graphics, DCH, EH, v0, v1, 0x0000ff);
      drawRiver(river.graphics, DCH, HF, v0, v2, 0x0000ff);

      // Recursively divide the river
      drawQuad(A, G, H, E, v1);
      drawQuad(G, B, F, H, v2);
    }

    // Draw the river from p to q, volume u to v, and return its length
    public function drawRiver(g:Graphics, p:Vector3D, q:Vector3D, u:Number, v:Number, color:int, first:Boolean=true):Number {
      if (u < 0.25 || v < 0.25) {
        return p.subtract(q).length;
      } else if (p.subtract(q).length < 4) {
        g.lineStyle(Math.sqrt(0.5*(u+v)), color);
        if (first) g.moveTo(p.x, p.y);
        g.lineTo(q.x, q.y);
        g.lineStyle();
        return p.subtract(q).length;
      } else {
        // Subdivide and randomly move the midpoint
        var r:Vector3D = interpolate(p, q, random(0.3, 0.7));
        var perp:Vector3D = p.subtract(q).crossProduct(new Vector3D(0, 0, 1));
        perp.scaleBy(random(-0.25, +0.25));
        r.incrementBy(perp);
        return drawRiver(g, p, r, u, 0.5*(u+v), color, first)
          + drawRiver(g, r, q, 0.5*(u+v), v, color, false);
      }
    }


    // Convenience: random number in a range
    public static function random(low:Number, high:Number):Number {
      return low + (high-low) * Math.random();
    }


    // Interpolate between two points
    public function interpolate(p:Vector3D, q:Vector3D, f:Number):Vector3D {
      return new Vector3D(p.x*(1-f) + q.x*f, p.y*(1-f) + q.y*f, p.z*(1-f) + q.z*f);
    }

    
  }
}
