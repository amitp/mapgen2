package graph {
  import flash.geom.Point;
  
  public class Edge {
    public var index:int;
    public var v0:Corner, v1:Corner;
    public var d0:Center, d1:Center;
    public var midpoint:Point;
    public var river:int;
  };
}
