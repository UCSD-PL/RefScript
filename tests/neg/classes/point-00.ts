
class Point {

  /*@ x : number */
  public x : number;

  /*@ y : number */
  public y : number;

}


class ColorPoint extends Point {
  
  /*@ c : string */
  public c : string; 

}

class RedPoint extends ColorPoint {

  /*@ c : { string | v = "red" } */
  public c : string = "red";

}

/*@ a :: #RedPoint[#Mutable] */
var a : RedPoint = { x: 1, y: 2, c: "blue" };

