
// posint get translated to number before being passed to RSC

/*@ foo :: <V extends posint, W extends number>(x: W, y: V) => W */
export function foo<V extends posint, W extends number>(x: W, y: V): W {
    return x;
}

assert(foo(-1, -2) === -1);
