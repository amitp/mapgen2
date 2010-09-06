package graph {
  import flash.geom.Point;
  
  public class Edge {
    public var index:int;
    public var d0:Center, d1:Center;  // Delaunay edge
    public var v0:Corner, v1:Corner;  // Voronoi edge
    public var midpoint:Point;  // halfway between v0,v1
    public var river:int;  // volume of water, or 0
  };
}
