
/*@ abs :: (x:number) => {v:number | v >= x} */ 
function abs(x){
  var res /*@  number */  = 0;
  if (x > 0) {
    res = x;
  } else {
    res = -x;
  };
  assert(res >= 0);
  return res;
}
