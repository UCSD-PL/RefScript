/*@ glob :: { number | v > 10 } */
var glob = 12;

var zoo = "moomp";

/*@ zog :: () => {void | true} */
function zog(){
  glob = 79;
}
