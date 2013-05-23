/*@ idt :: forall A. (A) => A */
function idt(x) { return x;}


/*@ idbool :: (boolean) => boolean */
function idbool(x) { return idt(x); }

/*@ main :: ({x:int|true}, boolean) => {v:int|v = x} */
function main(x, y){
  var yr = idt(y);
  var xr = idt(x);
  var z  = 0;
  if (yr) {
    z = 10;
    return xr;
  }
  return xr + z;
}
 

