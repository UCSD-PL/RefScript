

/*@  predicate non_zero(b) = (b /= (lit "#x00000000" (BitVec (Size32 obj)))) */

enum SymbolFlags {
  Import             = 0x00400000,  // Import
  Instantiated       = 0x00800000,  // Instantiated symbol
  Merged             = 0x01000000,  // Merged symbol (created during program binding)
  Transient          = 0x02000000,  // Transient symbol (created during type check)   
  Prototype          = 0x04000000,  // Symbol for the prototype property (without source code representation)
}



interface Symbol {

  /*@ flags : [Immutable] { v: bitvector32 | [(non_zero(bvand(v, lit "#x02000000" (BitVec (Size32 obj))))) <=>  extends_interface(this,"TransientSymbol");
                                              (non_zero(bvand(v, lit "#x00400000" (BitVec (Size32 obj))))) <=>  extends_interface(this,"ImportSymbol");
                                              (non_zero(bvand(v, lit "#x00800000" (BitVec (Size32 obj))))) <=>  extends_interface(this,"MergedSymbol");
                                              (non_zero(bvand(v, lit "#x04000001" (BitVec (Size32 obj))))) <=>  extends_interface(this,"PrototypeSymbol")] } */
  flags: SymbolFlags;

  name: string; 

}

interface TransientSymbol extends Symbol { }
interface ImportSymbol extends Symbol { }

/*@ getSymbolLinks :: (symbol: Symbol<Immutable>) => { void | 0 < 1 } */
function getSymbolLinks(symbol: Symbol): void {

  if (symbol.flags & SymbolFlags.Merged) {

    var ts = <ImportSymbol>symbol;

  }

}

