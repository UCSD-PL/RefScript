/*@ hop :: (list [{v:int| 0 <= v}]) => list [{v:int| 0 < v}] */
function hop(xs){
  var t = tail(xs);
  return t;
}

