package graph {
  import flash.geom.Point;
  
  public class Center {
    public var index:int;
  
    public var point:Point;
    public var ocean:Boolean;
    public var water:int;
    public var coast:Boolean;
    public var border:Boolean;
    public var biome:String;
    public var elevation:Number;
    public var moisture:Number;
    public var edges:Vector.<Edge>;
    public var neighbors:Vector.<Center>;
    public var corners:Vector.<Corner>;
    public var contour:int;
  
    public var road_connections:int;  // should be Vector.<Corner>
  };
}
