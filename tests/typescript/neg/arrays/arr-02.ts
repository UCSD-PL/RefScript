/*@ index :: (a: #Array[#Immutable,number], i: {number|((v <= (len a)) && (v >= 0))}) => number */
function index(a, i) {
  return a[i];
}
