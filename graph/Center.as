package graph {
  import flash.geom.Point;
  
  public class Center {
    public var index:int;
  
    public var point:Point;
    public var water:Boolean;  // lake or ocean
    public var ocean:Boolean;
    public var coast:Boolean;
    public var border:Boolean;
    public var biome:String;
    public var elevation:Number;
    public var moisture:Number;
    public var borders:Vector.<Edge>;
    public var neighbors:Vector.<Center>;
    public var corners:Vector.<Corner>;
  };
}
