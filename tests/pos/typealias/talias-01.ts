/*@ ab :: (number) => #Nat */
function ab(x:number): number {
  if (x > 0){
    return x;
  }
  return (0 - x);
}
