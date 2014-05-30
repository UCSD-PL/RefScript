

/*@ myPlusOk :: /\ (x: number, y: number) => { number | v = x + y }  
                /\ (x: number + string, y: number + string) => string */
function myPlusOk(x, y){
    return myPlusOk(x,y);
}

/*@ num_num :: (a:number, b:number) => {number | v = a + b } */
function num_num(a:number, b:number):number{
	var d :number= myPlusOk(a, b);
	return d; 
}

/*@ str_str :: (string) => {string | true } */
function str_str(a:string):string{
	var b :string= "dog";
	return  myPlusOk(a, b); 
}

/*@ num_str :: (number) => {string | true } */
function num_str(a:number):string{
	var b :string= "dog";
	return myPlusOk(a, b); 
}
