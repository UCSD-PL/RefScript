
/*@ qualif Bot(v:a,s:string): hasProperty(v,s) */
/*@ qualif Bot(v:a,s:string): enumProp(v,s) */

/*@ values :: (map: [Immutable]{[k:string]: { number | v >= 0 }}) => MArray<{ number | v > 0 }> */
function values(map:{[k:string]: number}): number[] {

  var values = [];
  
  for (var key in map) {
    values.push(map[key]);
  }
  
  return values;
};
