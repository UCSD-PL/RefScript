/*@ ab :: (number) => {number | v >= 0} */
function ab(x){
  var r = x;
  if (x > 0) {
    r = x;
  } else {
    r = (0 - x);
  }
  return r;
}
