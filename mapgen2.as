// Display the voronoi graph produced in voronoi_set.as
// Author: amitp@cs.stanford.edu
// License: MIT

package {
  import graph.*;
  import flash.geom.*;
  import flash.display.*;
  import flash.events.*;
  import flash.text.*;
  import flash.utils.ByteArray;
  import flash.utils.getTimer;
  import flash.utils.Timer;
  import flash.net.FileReference;
  import flash.system.System;
  import de.polygonal.math.PM_PRNG;

  [SWF(width="800", height="600")]
  public class mapgen2 extends Sprite {
    static public var SIZE:int = 600;
    static public var NOISY_LINE_TRADEOFF:Number = 0.5;  // low: jagged vedge; high: jagged dedge
    
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
      ROAD1: 0x442211,
      ROAD2: 0x553322,
      ROAD3: 0x664433,
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
    static public var islandSeedInitial:int = 85882;
    
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
    
    // These store 3d rendering data
    private var rotationAnimation:Number = 0.0;
    private var triangles3d:Array = [];
    private var graphicsData:Vector.<IGraphicsData>;
    
    // The map data
    public var map:voronoi_set;


    public function mapgen2() {
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

      map = new voronoi_set(SIZE);
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
      map.newIsland(type, seed);
    }

    
    public function reset():void {
      // Reset the 3d triangle data
      triangles3d = [];
      
      map.reset();
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
      mapSeedOutput.text = map.mapRandom.seed.toString();
      map.go();

      // Render the polygons first, including polygon edges
      // (coastline, lakeshores), then other edges (rivers, lava).
      var t:Number = getTimer();
      drawMap();
      Debug.trace("TIME for rendering:", getTimer()-t);
    }


    // Show some information about the maps
    private static var _biomeMap:Array =
      ['BEACH', 'LAKE', 'ICE', 'MARSH', 'SNOW', 'TUNDRA', 'BARE', 'SCORCHED',
       'TAIGA', 'SHRUBLAND', 'TEMPERATE_DESERT', 'TEMPERATE_RAIN_FOREST',
       'TEMPERATE_DECIDUOUS_FOREST', 'GRASSLAND', 'SUBTROPICAL_DESERT',
       'TROPICAL_RAIN_FOREST', 'TROPICAL_SEASONAL_FOREST'];
    public function drawHistograms():void {
      // There are pairs of functions for each chart. The bucket
      // function maps the polygon Center to a small int, and the
      // color function maps the int to a color.
      function landTypeBucket(p:Center):int {
        if (p.ocean) return 1;
        else if (p.coast) return 2;
        else if (p.water) return 3;
        else return 4;
      }
      function landTypeColor(bucket:int):uint {
        if (bucket == 1) return displayColors.OCEAN;
        else if (bucket == 2) return displayColors.BEACH;
        else if (bucket == 3) return displayColors.LAKE;
        else return displayColors.TEMPERATE_DECIDUOUS_FOREST;
      }
      function elevationBucket(p:Center):int {
        if (p.ocean) return -1;
        else return Math.floor(p.elevation*10);
      }
      function elevationColor(bucket:int):uint {
        return interpolateColor(displayColors.TEMPERATE_DECIDUOUS_FOREST,
                                displayColors.GRASSLAND, bucket*0.1);
      }
      function moistureBucket(p:Center):int {
        if (p.water) return -1;
        else return Math.floor(p.moisture*10);
      }
      function moistureColor(bucket:int):uint {
        return interpolateColor(displayColors.BEACH, displayColors.RIVER, bucket*0.1);
      }
      function biomeBucket(p:Center):int {
        return _biomeMap.indexOf(p.biome);
      }
      function biomeColor(bucket:int):uint {
        return displayColors[_biomeMap[bucket]];
      }

      function computeHistogram(bucketFn:Function):Array {
        var p:Center, histogram:Array, bucket:int;
        histogram = [];
        for each (p in map.centers) {
            bucket = bucketFn(p);
            if (bucket >= 0) histogram[bucket] = (histogram[bucket] || 0) + 1;
          }
        return histogram;
      }
      
      function drawHistogram(x:Number, y:Number, bucketFn:Function, colorFn:Function,
                             width:Number, height:Number):void {
        var scale:Number, i:int;
        var histogram:Array = computeHistogram(bucketFn);
        
        scale = 0.0;
        for (i = 0; i < histogram.length; i++) {
          scale = Math.max(scale, histogram[i] || 0);
        }
        for (i = 0; i < histogram.length; i++) {
          if (histogram[i]) {
            graphics.beginFill(colorFn(i));
            graphics.drawRect(SIZE+x+i*width/histogram.length, y+height,
                              Math.max(0, width/histogram.length-1), -height*histogram[i]/scale);
            graphics.endFill();
          }
        }
      }

      function drawDistribution(x:Number, y:Number, bucketFn:Function, colorFn:Function,
                                width:Number, height:Number):void {
        var scale:Number, i:int, x:Number, w:Number;
        var histogram:Array = computeHistogram(bucketFn);
      
        scale = 0.0;
        for (i = 0; i < histogram.length; i++) {
          scale += histogram[i] || 0.0;
        }
        for (i = 0; i < histogram.length; i++) {
          if (histogram[i]) {
            graphics.beginFill(colorFn(i));
            w = histogram[i]/scale*width;
            graphics.drawRect(SIZE+x, y, Math.max(0, w-1), height);
            x += w;
            graphics.endFill();
          }
        }
      }

      var x:Number = 23, y:Number = 140, width:Number = 154;
      drawDistribution(x, y, landTypeBucket, landTypeColor, width, 20);
      drawDistribution(x, y+25, biomeBucket, biomeColor, width, 20);

      drawHistogram(x, y+55, elevationBucket, elevationColor, width, 30);
      drawHistogram(x, y+95, moistureBucket, moistureColor, width, 20);
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
      
      drawHistograms();
      
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
        for each (p in map.centers) {
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
      
      for each (p in map.centers) {
          for each (r in p.neighbors) {
              var edge:Edge = map.lookupEdgeFromCenter(p, r);
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
      
      for each (p in map.centers) {
          if (p.road_connections == 2) {
            // Regular road: draw a spline from one edge to the other.
            edges = p.edges;
            for (i = 0; i < edges.length; i++) {
              edge1 = edges[i];
              if (edge1.road > 0) {
                for (j = i+1; j < edges.length; j++) {
                  edge2 = edges[j];
                  if (edge2.road > 0) {
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
                    graphics.lineStyle(1.1, colors['ROAD'+edge1.road]);
                    graphics.moveTo(edge1.midpoint.x, edge1.midpoint.y);
                    graphics.curveTo(A.x, A.y, C.x, C.y);
                    graphics.lineStyle(1.1, colors['ROAD'+edge2.road]);
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
                if (edge1.road > 0) {
                  d = 0.25*edge1.midpoint.subtract(p.point).length;
                  A = normalTowards(edge1, p.point, d).add(edge1.midpoint);
                  graphics.lineStyle(1.4, colors['ROAD'+edge1.road]);
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

      for each (p in map.centers) {
          for each (r in p.neighbors) {
              edge = map.lookupEdgeFromCenter(p, r);
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

      for each (p in map.centers) {
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

      for each (q in map.corners) {
          if (!q.ocean) {
            r = q.downslope;
            graphics.lineStyle(1.2, q.watershed == r.watershed? 0x00ffff : 0xff00ff,
                               0.1*Math.sqrt(q.watershed.watershed_size || 1));
            graphics.moveTo(q.point.x, q.point.y);
            graphics.lineTo(r.point.x, r.point.y);
            graphics.lineStyle();
          }
        }
      
      for each (q in map.corners) {
          for each (r in q.neighbors) {
              if (!q.ocean && !r.ocean && q.watershed != r.watershed && !q.coast && !r.coast) {
                var edge:Edge = map.lookupEdgeFromCorner(q, r);
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
         0x80:ocean shore, 0x90,0xa0,0xb0:road.  These are ORed with 0x01:
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
      ROAD1: 0x90,
      ROAD2: 0xa0,
      ROAD3: 0xb0
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
        for each (var p:Center in map.centers) {
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
      
      islandSeedInput = makeButton(islandSeedInitial.toString(), 75, y+22, 44, null);
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
      var y:int = 300;

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
      
      controls.addChild(makeButton("Distribution:", 50, 120, 100, null));
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
      var y:Number = 450;
      controls.addChild(makeButton("Export Bitmaps:", 25, y, 150, null));
               
      controls.addChild(makeButton("Elevation", 50, y+22, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('elevation'), 'elevation.data');
                            e.stopPropagation();
                          }));
      controls.addChild(makeButton("Moisture", 50, y+44, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('moisture'), 'moisture.data');
                            e.stopPropagation();
                          }));
      controls.addChild(makeButton("Overrides", 50, y+66, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('overrides'), 'overrides.data');
                            e.stopPropagation();
                          }));
    }
    
  }
  
}
