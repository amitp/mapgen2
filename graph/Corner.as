package graph {
  import flash.geom.Point;
  
  public class Corner {
    public var index:int;
  
    public var point:Point;
    public var ocean:Boolean;
    public var water:Boolean;
    public var coast:Boolean;
    public var border:Boolean;
    public var elevation:Number;
    public var moisture:Number;
    public var edges:Vector.<Edge>;
    public var neighbors:Vector.<Corner>;
    public var corners:Vector.<Center>;
    public var contour:int;
  
    public var river:int;
    public var downslope:Corner;
    public var watershed:Corner;
    public var watershed_size:int;
  };
}
