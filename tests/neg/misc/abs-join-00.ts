/*@ abs :: (number) => { number | 0 < 1 } */ 
function abs(x){
  var res = 0;
  if (x > 0) {
    res = x;
  } else {
    res = <any>(x > 99);
  };
  
  assert(res >= 0);
  return res;
}
