// Display the voronoi graph produced in Map.as
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

  [SWF(width="800", height="600", frameRate=60)]
  public class mapgen2 extends Sprite {
    static public var SIZE:int = 600;
    
    static public var displayColors:Object = {
      // Features
      OCEAN: 0x44447a,
      COAST: 0x33335a,
      LAKESHORE: 0x225588,
      LAKE: 0x336699,
      RIVER: 0x225588,
      MARSH: 0x2f6666,
      ICE: 0x99ffff,
      BEACH: 0xa09077,
      ROAD1: 0x442211,
      ROAD2: 0x553322,
      ROAD3: 0x664433,
      BRIDGE: 0x686860,
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
    static public var islandSeedInitial:String = "85882-1";
    
    // GUI for controlling the map generation and view
    public var controls:Sprite = new Sprite();
    public var islandSeedInput:TextField;
    public var statusBar:TextField;

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
    public var map:Map;
    public var roads:Roads;
    public var lava:Lava;
    public var watersheds:Watersheds;
    public var noisyEdges:NoisyEdges;


    public function mapgen2() {
      stage.scaleMode = 'noScale';
      stage.align = 'TL';

      addChild(noiseLayer);
      noiseLayer.bitmapData.noise(555, 128-10, 128+10, 7, true);
      noiseLayer.blendMode = BlendMode.HARDLIGHT;

      controls.x = SIZE;
      addChild(controls);

      addExportButtons();
      addViewButtons();
      addGenerateButtons();
      addMiscLabels();

      map = new Map(SIZE);
      go(islandType);
      
      render3dTimer.addEventListener(TimerEvent.TIMER, function (e:TimerEvent):void {
          // TODO: don't draw this while the map is being built
          drawMap(mapMode);
        });
    }

    
    // Random parameters governing the overall shape of the island
    public function newIsland(type:String):void {
      var seed:int = 0, variant:int = 0;
      var t:Number = getTimer();
      
      if (islandSeedInput.text.length == 0) {
        islandSeedInput.text = (Math.random()*100000).toFixed(0);
      }
      
      var match:Object = /\s*(\d+)(?:\-(\d+))\s*$/.exec(islandSeedInput.text);
      if (match != null) {
        // It's of the format SHAPE-VARIANT
        seed = parseInt(match[1]);
        variant = parseInt(match[2] || "0");
      }
      if (seed == 0) {
        // Convert the string into a number. This is a cheesy way to
        // do it but it doesn't matter. It just allows people to use
        // words as seeds.
        for (var i:int = 0; i < islandSeedInput.text.length; i++) {
          seed = (seed << 4) | islandSeedInput.text.charCodeAt(i);
        }
        seed %= 100000;
        variant = 1+Math.floor(9*Math.random());
      }
      islandType = type;
      map.newIsland(type, seed, variant);
    }

    
    public function graphicsReset():void {
      triangles3d = [];
      graphics.clear();
      graphics.beginFill(displayColors.OCEAN);
      graphics.drawRect(0, 0, SIZE, 2000);
      graphics.endFill();
      graphics.beginFill(0xbbbbaa);
      graphics.drawRect(SIZE, 0, 2000, 2000);
      graphics.endFill();
    }

    
    public function go(type:String):void {
      cancelCommands();

      roads = new Roads();
      lava = new Lava();
      watersheds = new Watersheds();
      noisyEdges = new NoisyEdges();
      
      commandExecute("Shaping map...",
                     function():void {
                       newIsland(type);
                     });
      
      commandExecute("Placing points...",
                     function():void {
                       map.go(0, 1);
                       drawMap('polygons');
                     });

      commandExecute("Improving points...",
                     function():void {
                       map.go(1, 2);
                       drawMap('polygons');
                     });
      
      commandExecute("Building graph...",
                     function():void {
                       map.go(2, 3);
                       map.assignBiomes();
                       drawMap('polygons');
                     });
      
      commandExecute("Features...",
                     function():void {
                       map.go(3, 6);
                       map.assignBiomes();
                       drawMap('polygons');
                     });

      commandExecute("Edges...",
                     function():void {
                       roads.createRoads(map);
                       lava.createLava(map, map.mapRandom.nextDouble);
                       watersheds.createWatersheds(map);
                       noisyEdges.buildNoisyEdges(map, lava, map.mapRandom);
                       drawMap(mapMode);
                     });
    }


    // Command queue is processed on ENTER_FRAME. If it's empty,
    // remove the handler.
    private var _guiQueue:Array = [];
    private function _onEnterFrame(e:Event):void {
      (_guiQueue.shift()[1])();
      if (_guiQueue.length == 0) {
        stage.removeEventListener(Event.ENTER_FRAME, _onEnterFrame);
        statusBar.text = "";
      } else {
        statusBar.text = _guiQueue[0][0];
      }
    }

    public function cancelCommands():void {
      if (_guiQueue.length != 0) {
        stage.removeEventListener(Event.ENTER_FRAME, _onEnterFrame);
        statusBar.text = "";
        _guiQueue = [];
      }
    }

    public function commandExecute(status:String, command:Function):void {
      if (_guiQueue.length == 0) {
        statusBar.text = status;
        stage.addEventListener(Event.ENTER_FRAME, _onEnterFrame);
      }
      _guiQueue.push([status, command]);
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
                                          colors:Array, fillFunction:Function):void {
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
        // be trusted.  NOTE: only works for 1, 2, 3 colors in the array
        var color:uint = colors[0];
        if (colors.length == 2) {
          color = interpolateColor(colors[0], colors[1], V.z);
        } else if (colors.length == 3) {
          if (V.z < 0.5) {
            color = interpolateColor(colors[0], colors[1], V.z*2);
          } else {
            color = interpolateColor(colors[1], colors[2], V.z*2-1);
          }
        }
        graphics.beginFill(color);
      } else {
        // The gradient box is weird to set up, so we let Flash set up
        // a basic matrix and then we alter it:
        m.createGradientBox(1, 1, 0, 0, 0);
        m.translate(-0.5, -0.5);
        m.scale((1/G.length), (1/G.length));
        m.rotate(Math.atan2(G.y, G.x));
        m.translate(C.x, C.y);
        var alphas:Array = colors.map(function (_:*, index:int, A:Array):Number { return 1.0; });
        var spread:Array = colors.map(function (_:*, index:int, A:Array):int { return 255*index/(A.length-1); });
        graphics.beginGradientFill(GradientType.LINEAR, colors, alphas, spread, m, SpreadMethod.PAD);
      }
      fillFunction();
      graphics.endFill();
    }
    

    // Draw the map in the current map mode
    public function drawMap(mode:String):void {
      graphicsReset();
      noiseLayer.visible = true;
      
      drawHistograms();
      
      if (mode == '3d') {
        if (!render3dTimer.running) render3dTimer.start();
        noiseLayer.visible = false;
        render3dPolygons(graphics, displayColors, colorWithSlope);
        return;
      } else if (mode == 'polygons') {
        noiseLayer.visible = false;
        renderDebugPolygons(graphics, displayColors);
      } else if (mode == 'watersheds') {
        noiseLayer.visible = false;
        renderDebugPolygons(graphics, displayColors);
        renderWatersheds(graphics);
        return;
      } else if (mode == 'biome') {
        renderPolygons(graphics, displayColors, null, null);
      } else if (mode == 'slopes') {
        renderPolygons(graphics, displayColors, null, colorWithSlope);
      } else if (mode == 'smooth') {
        renderPolygons(graphics, displayColors, null, colorWithSmoothColors);
      } else if (mode == 'elevation') {
        renderPolygons(graphics, elevationGradientColors, 'elevation', null);
      } else if (mode == 'moisture') {
        renderPolygons(graphics, moistureGradientColors, 'moisture', null);
      }

      if (render3dTimer.running) render3dTimer.stop();

      if (mode != 'slopes' && mode != 'moisture') {
        renderRoads(graphics, displayColors);
      }
      if (mode != 'polygons') {
        renderEdges(graphics, displayColors);
      }
      if (mode != 'slopes' && mode != 'moisture') {
        renderBridges(graphics, displayColors);
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
            for each (edge in p.borders) {
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
                var path:Vector.<Point> = noisyEdges.path0[edge.index];
                graphics.moveTo(p.point.x, p.point.y);
                graphics.lineTo(path[0].x, path[0].y);
                drawPathForwards(graphics, path);
                graphics.lineTo(p.point.x, p.point.y);
              }

              function drawPath1():void {
                var path:Vector.<Point> = noisyEdges.path1[edge.index];
                graphics.moveTo(p.point.x, p.point.y);
                graphics.lineTo(path[0].x, path[0].y);
                drawPathForwards(graphics, path);
                graphics.lineTo(p.point.x, p.point.y);
              }

              if (noisyEdges.path0[edge.index] == null
                  || noisyEdges.path1[edge.index] == null) {
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
                   [colors.GRADIENT_LOW, colors.GRADIENT_HIGH], drawPath0);
                drawGradientTriangle
                  (graphics,
                   new Vector3D(p.point.x, p.point.y, p[gradientFillProperty]),
                   new Vector3D(midpoint.x, midpoint.y, midpointAttr),
                   new Vector3D(corner1.point.x, corner1.point.y, corner1[gradientFillProperty]),
                   [colors.GRADIENT_LOW, colors.GRADIENT_HIGH], drawPath1);
              } else {
                graphics.beginFill(color);
                drawPath0();
                drawPath1();
                graphics.endFill();
              }
            }
        }
    }


    // Render bridges across every narrow river edge. Bridges are
    // straight line segments perpendicular to the edge. Bridges are
    // drawn after rivers. TODO: sometimes the bridges aren't long
    // enough to cross the entire noisy line river. TODO: bridges
    // don't line up with curved road segments when there are
    // roads. It might be worth making a shader that draws the bridge
    // only when there's water underneath.
    public function renderBridges(graphics:Graphics, colors:Object):void {
      var edge:Edge;

      for each (edge in map.edges) {
          if (edge.river > 0 && edge.river < 4
              && !edge.d0.water && !edge.d1.water
              && (edge.d0.elevation > 0.05 || edge.d1.elevation > 0.05)) {
            var n:Point = new Point(-(edge.v1.point.y - edge.v0.point.y), edge.v1.point.x - edge.v0.point.x);
            n.normalize(0.25 + (roads.road[edge.index]? 0.5 : 0) + 0.75*Math.sqrt(edge.river));
            graphics.lineStyle(1.1, colors.BRIDGE, 1.0, false, LineScaleMode.NORMAL, CapsStyle.SQUARE);
            graphics.moveTo(edge.midpoint.x - n.x, edge.midpoint.y - n.y);
            graphics.lineTo(edge.midpoint.x + n.x, edge.midpoint.y + n.y);
            graphics.lineStyle();
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
          if (roads.roadConnections[p.index]) {
            if (roads.roadConnections[p.index].length == 2) {
              // Regular road: draw a spline from one edge to the other.
              edges = p.borders;
              for (i = 0; i < edges.length; i++) {
                edge1 = edges[i];
                if (roads.road[edge1.index] > 0) {
                  for (j = i+1; j < edges.length; j++) {
                    edge2 = edges[j];
                    if (roads.road[edge2.index] > 0) {
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
                      graphics.lineStyle(1.1, colors['ROAD'+roads.road[edge1.index]]);
                      graphics.moveTo(edge1.midpoint.x, edge1.midpoint.y);
                      graphics.curveTo(A.x, A.y, C.x, C.y);
                      graphics.lineStyle(1.1, colors['ROAD'+roads.road[edge2.index]]);
                      graphics.curveTo(B.x, B.y, edge2.midpoint.x, edge2.midpoint.y);
                      graphics.lineStyle();
                    }
                  }
                }
              }
            } else {
              // Intersection or dead end: draw a road spline from
              // each edge to the center
              for each (edge1 in p.borders) {
                  if (roads.road[edge1.index] > 0) {
                    d = 0.25*edge1.midpoint.subtract(p.point).length;
                    A = normalTowards(edge1, p.point, d).add(edge1.midpoint);
                    graphics.lineStyle(1.4, colors['ROAD'+roads.road[edge1.index]]);
                    graphics.moveTo(edge1.midpoint.x, edge1.midpoint.y);
                    graphics.curveTo(A.x, A.y, p.point.x, p.point.y);
                    graphics.lineStyle();
                  }
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
              if (noisyEdges.path0[edge.index] == null
                  || noisyEdges.path1[edge.index] == null) {
                // It's at the edge of the map
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
              } else if (lava.lava[edge.index]) {
                // Lava flow
                graphics.lineStyle(1, colors.LAVA);
              } else if (edge.river > 0) {
                // River edge
                graphics.lineStyle(Math.sqrt(edge.river), colors.RIVER);
              } else {
                // No edge
                continue;
              }
              
              graphics.moveTo(noisyEdges.path0[edge.index][0].x,
                              noisyEdges.path0[edge.index][0].y);
              drawPathForwards(graphics, noisyEdges.path0[edge.index]);
              drawPathBackwards(graphics, noisyEdges.path1[edge.index]);
              graphics.lineStyle();
            }
        }
    }


    // Render the polygons so that each can be seen clearly
    public function renderDebugPolygons(graphics:Graphics, colors:Object):void {
      var p:Center, q:Corner, edge:Edge, point:Point, color:int;

      if (map.centers.length == 0) {
        // We're still constructing the map so we may have some points
        graphics.beginFill(0xdddddd);
        graphics.drawRect(0, 0, SIZE, SIZE);
        graphics.endFill();
        for each (point in map.points) {
            graphics.beginFill(0x000000);
            graphics.drawCircle(point.x, point.y, 1.3);
            graphics.endFill();
          }
      }
      
      for each (p in map.centers) {
          color = colors[p.biome] || (p.ocean? colors.OCEAN : p.water? colors.RIVER : 0xffffff);
          graphics.beginFill(interpolateColor(color, 0xdddddd, 0.2));
          for each (edge in p.borders) {
              if (edge.v0 && edge.v1) {
                graphics.moveTo(p.point.x, p.point.y);
                graphics.lineTo(edge.v0.point.x, edge.v0.point.y);
                if (edge.river > 0) {
                  graphics.lineStyle(2, displayColors.RIVER, 1.0);
                } else {
                  graphics.lineStyle(0, 0x000000, 0.4);
                }
                graphics.lineTo(edge.v1.point.x, edge.v1.point.y);
                graphics.lineStyle();
              }
            }
          graphics.endFill();
          graphics.beginFill(p.water > 0 ? 0x003333 : 0x000000, 0.7);
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
      var edge:Edge, w0:int, w1:int;

      for each (edge in map.edges) {
          if (edge.d0 && edge.d1 && edge.v0 && edge.v1
              && !edge.d0.ocean && !edge.d1.ocean) {
            w0 = watersheds.watersheds[edge.d0.index];
            w1 = watersheds.watersheds[edge.d1.index];
            if (w0 != w1) {
              graphics.lineStyle(3.5, 0x000000, 0.1*Math.sqrt((map.corners[w0].watershed_size || 1) + (map.corners[w1].watershed.watershed_size || 1)));
              graphics.moveTo(edge.v0.point.x, edge.v0.point.y);
              graphics.lineTo(edge.v1.point.x, edge.v1.point.y);
              graphics.lineStyle();
            }
          }
        }

      for each (edge in map.edges) {
          if (edge.river) {
            graphics.lineStyle(1.0, 0x6699ff);
            graphics.moveTo(edge.v0.point.x, edge.v0.point.y);
            graphics.lineTo(edge.v1.point.x, edge.v1.point.y);
            graphics.lineStyle();
          }
        }
    }
    

    private var lightVector:Vector3D = new Vector3D(-1, -1, 0);
    public function calculateLighting(p:Center, r:Corner, s:Corner):Number {
      var A:Vector3D = new Vector3D(p.point.x, p.point.y, p.elevation);
      var B:Vector3D = new Vector3D(r.point.x, r.point.y, r.elevation);
      var C:Vector3D = new Vector3D(s.point.x, s.point.y, s.elevation);
      var normal:Vector3D = B.subtract(A).crossProduct(C.subtract(A));
      if (normal.z < 0) { normal.scaleBy(-1); }
      normal.normalize();
      var light:Number = 0.5 + 35*normal.dotProduct(lightVector);
      if (light < 0) light = 0;
      if (light > 1) light = 1;
      return light;
    }
    
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
      var light:Number = calculateLighting(p, r, s);
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
         0x80:ocean shore, 0x90,0xa0,0xb0:road, 0xc0:bridge.  These
         are ORed with 0x01: polygon center, 0x02: safe polygon
         center. */
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
      ROAD3: 0xb0,
      BRIDGE: 0xc0
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
        renderBridges(exportGraphics.graphics, exportOverrideColors);

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
                                    | (roads.roadConnections[p]?
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


    // Export the graph data as XML (slow)
    public function exportPolygons():XML {
      var p:Center, q:Corner, r:Center, s:Corner, edge:Edge;
      var top:XML =
        <map
          shape={islandSeedInput.text}
          type={islandType}
          size={Map.NUM_POINTS}>
          <generator
             url="http://www-cs-students.stanford.edu/~amitp/game-programming/polygon-map-generation/"
             timestamp={new Date().toUTCString()} />
        </map>;
      var dnodes:XML = <centers/>;
      var edges:XML = <edges/>;
      var vnodes:XML = <corners/>;
      var borders:XML, neighbors:XML, corners:XML;
      var touches:XML, protrudes:XML, adjacent:XML;
      var edgeNode:XML;

      for each (p in map.centers) {
          borders = <borders/>;
          neighbors = <neighbors/>;
          corners = <corners/>;

          for each (r in p.neighbors) {
              neighbors.appendChild(<center id={r.index}/>);
            }
          for each (edge in p.borders) {
              borders.appendChild(<edge id={edge.index}/>);
            }
          for each (q in p.corners) {
              corners.appendChild(<corner id={q.index}/>);
            }
          
          dnodes.appendChild
            (<center id={p.index}
                     x={p.point.x} y={p.point.y}
                     water={p.water} ocean={p.ocean}
                     coast={p.coast} border={p.border}
                     biome={p.biome}
                     elevation={p.elevation} moisture={p.moisture}>
               {neighbors}
               {borders}
               {corners}
             </center>);
        }

      for each (edge in map.edges) {
          edgeNode =
            <edge id={edge.index} river={edge.river}/>;
          if (edge.midpoint != null) {
            edgeNode.@x = edge.midpoint.x;
            edgeNode.@y = edge.midpoint.y;
          }
          if (edge.d0 != null) edgeNode.@center0 = edge.d0.index;
          if (edge.d1 != null) edgeNode.@center1 = edge.d1.index;
          if (edge.v0 != null) edgeNode.@corner0 = edge.v0.index;
          if (edge.v1 != null) edgeNode.@corner1 = edge.v1.index;
          edges.appendChild(edgeNode);
        }
      
      for each (q in map.corners) {
          touches = <touches/>;
          protrudes = <protrudes/>;
          adjacent = <adjacent/>;

          for each (p in q.touches) {
              touches.appendChild(<center id={p.index}/>);
            }
          for each (edge in q.protrudes) {
              protrudes.appendChild(<edge id={edge.index}/>);
            }
          for each (s in q.adjacent) {
              corners.appendChild(<corner id={s.index}/>);
            }
          
          vnodes.appendChild
            (<corner id={q.index}
                     x={q.point.x} y={q.point.y}
                     water={q.water} ocean={q.ocean}
                     coast={q.coast} border={q.border}
                     elevation={q.elevation} moisture={q.moisture}
                     river={q.river} downslope={q.downslope?q.downslope.index:-1}>
               {touches}
               {protrudes}
               {adjacent}
             </corner>);
        }

      top.appendChild(dnodes);
      top.appendChild(edges);
      top.appendChild(vnodes);
      return top;
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

      var seedLabel:TextField = makeButton("Shape #", 20, y+22, 50, null);
      
      islandSeedInput = makeButton(islandSeedInitial, 70, y+22, 54, null);
      islandSeedInput.background = true;
      islandSeedInput.backgroundColor = 0xccddcc;
      islandSeedInput.selectable = true;
      islandSeedInput.type = TextFieldType.INPUT;
      islandSeedInput.addEventListener(KeyboardEvent.KEY_UP, function (e:KeyboardEvent):void {
          if (e.keyCode == 13) {
            go(islandType);
          }
        });

      function markActiveIslandShape(type:String):void {
        mapTypes[islandType].backgroundColor = 0xffffcc;
        mapTypes[type].backgroundColor = 0xffff00;
      }
      
      function switcher(type:String):Function {
        return function(e:Event):void {
          markActiveIslandShape(type);
          go(type);
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
      controls.addChild(makeButton("Random", 125, y+22, 56,
                                   function (e:Event):void {
                                     islandSeedInput.text =
                                       ( (Math.random()*100000).toFixed(0)
                                         + "-"
                                         + (1 + Math.floor(9*Math.random())).toFixed(0) );
                                     go(islandType);
                                   }));
      controls.addChild(mapTypes.Radial);
      controls.addChild(mapTypes.Perlin);
      controls.addChild(mapTypes.Square);
      controls.addChild(mapTypes.Blob);
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
          drawMap(mapMode);
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


    public function addMiscLabels():void {
      controls.addChild(makeButton("Distribution:", 50, 120, 100, null));
      statusBar = makeButton("", SIZE/2-50, 10, 100, null);
      addChild(statusBar);
    }

               
    public function addExportButtons():void {
      var y:Number = 450;
      controls.addChild(makeButton("Export Bitmaps:", 25, y, 150, null));
               
      controls.addChild(makeButton("Elevation", 50, y+22, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('elevation'), 'elevation.data');
                          }));
      controls.addChild(makeButton("Moisture", 50, y+44, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('moisture'), 'moisture.data');
                          }));
      controls.addChild(makeButton("Overrides", 50, y+66, 100,
                          function (e:Event):void {
                            new FileReference().save(makeExport('overrides'), 'overrides.data');
                          }));

      controls.addChild(makeButton("Export Polygons (slow)", 25, y+100, 150,
                          function (e:Event):void {
                            new FileReference().save(exportPolygons().toString(), 'map.xml');
                          }));
    }
    
  }
  
}
