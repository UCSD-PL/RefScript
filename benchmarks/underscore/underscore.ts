// Based on:
// //     Underscore.js 1.6.0
// //     http://underscorejs.org
// //     (c) 2009-2014 Jeremy Ashkenas, DocumentCloud and Investigative Reporters & Editors
// //     Underscore may be freely distributed under the MIT license.

///<reference path='.\underscore3.d.ts' />

//TODO: restore 'guard' internal params to several functions

module _Implementation {

                    //   // Baseline setup
                    //   // --------------

                    //   // Establish the root object, `window` in the browser, or `exports` on the server.
                    //   var root = this;

                    //   // Save the previous value of the `_` variable.
                    //   var previousUnderscore = root._;

  // Establish the object that gets returned to break out of a loop iteration.
  var breaker = {};

  // Save bytes in the minified (but not gzipped) version:
  var ArrayProto = Array.prototype, ObjProto = Object.prototype, FuncProto = Function.prototype;

  // Create quick reference variables for speed access to core prototypes.
  var
    push             = ArrayProto.push,
    slice            = ArrayProto.slice,
    concat           = ArrayProto.concat,
    toString         = ObjProto.toString, //TODO: why will it compile without this line?
    hasOwnProperty   = ObjProto.hasOwnProperty;

  // All **ECMAScript 5** native function implementations that we hope to use
  // are declared here.
  var
                    //     nativeIsArray      = Array.isArray,
    nativeKeys         = Object.keys;
                    //     nativeBind         = FuncProto.bind;

                    //   // Create a safe reference to the Underscore object for use below.
                    //   var _ = function(obj) {
                    //     if (obj instanceof _) return obj;
                    //     if (!(this instanceof _)) return new _(obj);
                    //     this._wrapped = obj;
                    //   };

                    //   // Export the Underscore object for **Node.js**, with
                    //   // backwards-compatibility for the old `require()` API. If we're in
                    //   // the browser, add `_` as a global object via a string identifier,
                    //   // for Closure Compiler "advanced" mode.
                    //   if (typeof exports !== 'undefined') {
                    //     if (typeof module !== 'undefined' && module.exports) {
                    //       exports = module.exports = _;
                    //     }
                    //     exports._ = _;
                    //   } else {
                    //     root._ = _;
                    //   }

                    //   // Current version.
                    //   _.VERSION = '1.6.0';

  var reduceError = 'Reduce of empty array with no initial value';

  class Underscore implements UnderscoreStatic {

    // Internal Functions
    // --------------------
    
    // Generates lookup iterators.
    private lookupIterator1<T, TResult>(func: (x: T) => TResult, context: any, argCount?: any): (x: T) => TResult {
      if (func == null) return this.identity;
      return this.createCallback1(func, context);
    }

    private lookupIterator<T, TResult>(func: _.ListIterator<T, TResult>, context: any): _.ListIterator<T, TResult> {
      if (func == null) return this.identity;
      return this.createCallback(func, context);
    }

    private lookupIteratorM<T, TResult>(func: _.MemoIterator<T, TResult>, context: any): _.MemoIterator<T, TResult> {
      if (func == null) return this.identity;
      return this.createCallbackM(func, context);
    }

    // Creates a callback bound to its context if supplied
    private createCallback1<T, TResult>(func: (x: T) => TResult, context: any): (x: T) => TResult {
      if (context === void 0) return func;
      return function(value) {
          return func.call(context, value);
      };
    }

                    //       case 2: return function(value, other) {
                    //         return func.call(context, value, other);
                    //       };

    private createCallback<T, TResult>(func: _.ListIterator<T, TResult>, context: any): _.ListIterator<T, TResult> {
      if (context === void 0) return func;   
      return function(value, index, collection) {
        return func.call(context, value, index, collection);
      };
    }

    private createCallbackM<T, TResult>(func: _.MemoIterator<T, TResult>, context: any): _.MemoIterator<T, TResult> {
      if (context === void 0) return func;
      return function(accumulator, value, index, collection) {
          return func.call(context, accumulator, value, index, collection);
      };
    }
                    //     return function() {
                    //       return func.apply(context, arguments);
                    //     };

    // Collection Functions
    // --------------------

    // The cornerstone, an `each` implementation, aka `forEach`.
    // Handles raw objects in addition to array-likes. Treats all
    // sparse array-likes as if they were dense.
    public each<T>(obj: _.List<T>, iterator: _.ListIterator<T, any>, context?: any): _.List<T> {
      var i, length;
      if (obj == null) return obj;
      iterator = this.createCallback(iterator, context);
      if (obj.length === +obj.length) {
        for (i = 0, length = obj.length; i < length; i++) {
          if (iterator(obj[i], i, obj) === breaker) break;
        }
      }
      // else {
      //   var keys = _.keys(obj);
      //   for (i = 0, length = keys.length; i < length; i++) {
      //     if (iterator(obj[keys[i]], keys[i], obj) === breaker) break;
      //   }
      // }
      return obj;
    }

    public forEach<T>(obj: _.List<T>, iterator: _.ListIterator<T, any>, context?: any): _.List<T> {
      return this.each(obj, iterator, context);
    }


    // Return the results of applying the iterator to each element.
    public map<T, TResult>(obj: _.List<T>, iterator: _.ListIterator<T, TResult>, context?: any): TResult[] {
      var results = [];
      if (obj == null) return results;
      iterator = this.lookupIterator(iterator, context);
      this.each(obj, function(value, index, list) {
        results.push(iterator(value, index, list));
      });
      return results;
    }

    public collect<T, TResult>(obj: _.List<T>, iterator: _.ListIterator<T, TResult>, context?: any): TResult[] {
      return this.map(obj, iterator, context);
    }

    // **Reduce** builds up a single result from a list of values, aka `inject`,
    // or `foldl`.
    public reduce<T, TResult>(obj: _.List<T>, iterator: _.MemoIterator<T, TResult>, memo: TResult, context?: any): TResult;
    public reduce<T>(obj: _.List<T>, iterator: _.MemoIterator<T, T>, memo?: T, context?: any): T;
    public reduce<T>(obj: _.List<T>, iterator: any, memo?: any, context?: any): any {
      var initial = arguments.length > 2;
      if (obj == null) obj = [];
      iterator = this.createCallbackM(iterator, context);
      this.each(obj, function(value:T, index:number, list:_.List<T>) {
        if (!initial) {
          memo = value;
          initial = true;
        } else {
          memo = iterator(memo, value, index, list);
        }
      });
      if (!initial) throw TypeError(reduceError);
      return memo;
    }

    public inject<T, TResult>(obj: _.List<T>, iterator: _.MemoIterator<T, TResult>, memo: TResult, context?: any): TResult;
    public inject<T>(obj: _.List<T>, iterator: _.MemoIterator<T, T>, memo?: T, context?: any): T;
    public inject<T>(obj: _.List<T>, iterator: any, memo?: any, context?: any): any {
      return this.reduce(obj, iterator, memo, context);
    }

    public foldl<T, TResult>(obj: _.List<T>, iterator: _.MemoIterator<T, TResult>, memo: TResult, context?: any): TResult;
    public foldl<T>(obj: _.List<T>, iterator: _.MemoIterator<T, T>, memo?: T, context?: any): T;
    public foldl<T>(obj: _.List<T>, iterator: any, memo?: any, context?: any): any {
      return this.reduce(obj, iterator, memo, context);
    }


    // The right-associative version of reduce, also known as `foldr`.
    public reduceRight<T, TResult>(obj: _.List<T>, iterator: _.MemoIterator<T, TResult>, memo: TResult, context?: any): TResult;
    public reduceRight<T>(obj: _.List<T>, iterator: _.MemoIterator<T, T>, memo?: T, context?: any): T;
    public reduceRight<T>(obj: _.List<T>, iterator: any, memo?: any, context?: any): any {
      var initial = arguments.length > 2;
      if (obj == null) obj = [];
      var length = obj.length;
      iterator = this.createCallbackM(iterator, context);
      // if (length !== +length) {
      //   var keys = this.keys(obj);
      //   length = keys.length;
      // }
      this.each(obj, function(value, index, list) {
        //index = keys ? keys[--length] : --length;
        index = --length;
        if (!initial) {
          memo = obj[index];
          initial = true;
        } else {
          memo = iterator(memo, obj[index], index, list);
        }
      });
      if (!initial) throw TypeError(reduceError);
      return memo;
    }

    public foldr<T, TResult>(obj: _.List<T>, iterator: _.MemoIterator<T, TResult>, memo: TResult, context?: any): TResult;
    public foldr<T>(obj: _.List<T>, iterator: _.MemoIterator<T, T>, memo?: T, context?: any): T;
    public foldr<T>(obj: _.List<T>, iterator: any, memo?: any, context?: any): any {
      return this.reduceRight(obj, iterator, memo, context);
    }

    // Return the first value which passes a truth test. Aliased as `detect`.
    public find<T>(list: _.List<T>, predicate: _.ListIterator<T, boolean>, context?: any): T {
    //public find<T>(object: _.Dictionary<T>, predicate: _.ObjectIterator<T, boolean>, context?: any): T;
    //public find<T>(obj: any, predicate: any, context?: any): T {
      var result;
      predicate = this.lookupIterator(predicate, context);
      this.some(list, function(value, index, list) {
        if (predicate(value, index, list)) {
          result = value;
          return true;
        }
      });
      return result;
    }

    public detect<T>(list: _.List<T>, predicate: _.ListIterator<T, boolean>, context?: any): T {
      return this.find(list, predicate, context);
    }

    // Return all the elements that pass a truth test.
    // Aliased as `select`.
    public filter<T>(list: _.List<T>, predicate: _.ListIterator<T, boolean>, context?: any): T[] {
      var results = [];
      if (list == null) return results;
      predicate = this.lookupIterator(predicate, context);
      this.each(list, function(value, index, list) {
        if (predicate(value, index, list)) results.push(value);
      });
      return results;
    }

    public select<T>(list: _.List<T>, predicate: _.ListIterator<T, boolean>, context?: any): T[] {
      return this.filter(list, predicate, context);
    }

    // Return all the elements for which a truth test fails.
    // TODO: is the 'context' arg I added to lookupIterator here correct?
    public reject<T>(list: _.List<T>, predicate: _.ListIterator<T, boolean>, context?: any): T[] {
      return this.filter(list, this.negate(this.lookupIterator(predicate, context)), context);
    }

    // Determine whether all of the elements match a truth test.
    // Aliased as `all`.
    public every<T>(list: _.List<T>, predicate?: _.ListIterator<T, boolean>, context?: any): boolean {
      var result = true;
      if (list == null) return result;
      predicate = this.lookupIterator(predicate, context);
      this.each(list, function(value, index, list) {
        result = predicate(value, index, list);
        if (!result) return breaker;
      });
      return !!result;
    }

    public all<T>(list: _.List<T>, predicate?: _.ListIterator<T, boolean>, context?: any): boolean {
      return this.every(list, predicate, context);
    }

    // Determine if at least one element in the object matches a truth test.
    // Aliased as `any`.
    public some<T>(list: _.List<T>, predicate?: _.ListIterator<T, boolean>, context?: any): boolean {
      var result = false;
      if (list == null) return result;
      predicate = this.lookupIterator(predicate, context);
      this.each(list, function(value, index, list) {
        result = predicate(value, index, list);
        if (result) return breaker;
      });
      return !!result;
    }

    public any<T>(list: _.List<T>, predicate?: _.ListIterator<T, boolean>, context?: any): boolean {
      return this.some(list, predicate, context);
    }


    // Determine if the array or object contains a given value (using `===`).
    // Aliased as `include`.
    public contains<T>(obj: _.List<T>, value: T): boolean {
      if (obj == null) return false;
      //if (obj.length !== +obj.length) obj = this.values(obj);
      return this.indexOf(obj, value) >= 0;
    }

    public include<T>(obj: _.List<T>, value: T): boolean {
      return this.contains(obj, value);
    }

    // Invoke a method (with arguments) on every item in a collection.
    public invoke<T extends {}>(list: _.List<T>, method: any, ...args: any[]): any {
      var isFunc = this.isFunction(method);
      return this.map(list, function(value) {
        return (isFunc ? method : value[method]).apply(value, args);
      });
    }

    // Convenience version of a common use case of `map`: fetching a property.
    public pluck<T extends {}>(list: _.List<T>, propertyName: string): any[] {
      return this.map(list, this.property(propertyName));
    }

    // Convenience version of a common use case of `filter`: selecting only objects
    // containing specific `key:value` pairs.
    public where<T>(list: _.List<T>, attrs: any): T[] {
      return this.filter(list, this.matches(attrs));
    }

    // Convenience version of a common use case of `find`: getting the first object
    // containing specific `key:value` pairs.
    public findWhere<T>(list: _.List<T>, attrs: any): T {
      return this.find(list, this.matches(attrs));
    }

    // Return the maximum element (or element-based computation).
    public max(list: _.List<number>): number;
    public max<T>(list: _.List<T>, iterator?: _.ListIterator<T, number>, context?: any): T;
    public max<T>(obj: _.List<any>, iterator?: _.ListIterator<T, number>, context?: any): any {
      var result = -Infinity, lastComputed = -Infinity,
          value, computed;
      if (!iterator && this.isArray(obj)) {
        for (var i = 0, length = obj.length; i < length; i++) {
          value = obj[i];
          if (value > result) {
            result = value;
          }
        }
      } else {
        iterator = this.lookupIterator(iterator, context);
        this.each(obj, function(value, index, list) {
          computed = iterator(value, index, list);
          if (computed > lastComputed || computed === -Infinity && result === -Infinity) {
            result = value;
            lastComputed = computed;
          }
        });
      }
      return result;
    }

    // Return the minimum element (or element-based computation).
    public min(list: _.List<number>): number;
    public min<T>(list: _.List<T>, iterator?: _.ListIterator<T, number>, context?: any): T;
    public min<T>(obj: _.List<any>, iterator?: _.ListIterator<T, number>, context?: any): any {
      var result = Infinity, lastComputed = Infinity,
        value, computed;
      if (!iterator && this.isArray(obj)) {
        for (var i = 0, length = obj.length; i < length; i++) {
          value = obj[i];
          if (value < result) {
            result = value;
          }
        }
      } else {
        iterator = this.lookupIterator(iterator, context);
        this.each(obj, function(value, index, list) {
          computed = iterator(value, index, list);
          if (computed < lastComputed || computed === Infinity && result === Infinity) {
            result = value;
            lastComputed = computed;
          }
        });
      }
      return result;
    }

    // Shuffle an array, using the modern version of the
    // [Fisher-Yates shuffle](http://en.wikipedia.org/wiki/Fisher–Yates_shuffle).
    public shuffle<T>(obj: _.List<T>): T[] {
      var rand;
      var index = 0;
      var shuffled = [];
      this.each(obj, function(value) {
        rand = this.random(index++);
        shuffled[index - 1] = shuffled[rand];
        shuffled[rand] = value;
      });
      return shuffled;
    }

    // Sample **n** random values from a collection.
    // If **n** is not specified, returns a single random element.
    // The internal `guard` argument allows it to work with `map`.
    public sample<T>(obj: _.List<T>, n: number): T[];
    public sample<T>(obj: _.List<T>): T;
    public sample<T>(obj: _.List<T>, n?: number): any {
      if (n == null) {
        //if (obj.length !== +obj.length) obj = this.values(obj);
        return obj[this.random(obj.length - 1)];
      }
      return this.shuffle(obj).slice(0, Math.max(0, n));
    }

    // Sort the object's values by a criterion produced by an iterator.
    public sortBy<T>(list: _.List<T>, iterator?: _.ListIterator<T, any>, context?: any): T[];
    public sortBy<T>(list: _.List<T>, iterator: string, context?: any): T[];
    public sortBy<T>(list: _.List<T>, iterator?: any, context?: any): T[] {
      iterator = this.lookupIterator(iterator, context);
      return this.pluck(this.map(list, function(value, index, list) {
        return {
          value: value,
          index: index,
          criteria: iterator(value, index, list)
        };
      }).sort(function(left, right) {
        var a = left.criteria;
        var b = right.criteria;
        if (a !== b) {
          if (a > b || a === void 0) return 1;
          if (a < b || b === void 0) return -1;
        }
        return left.index - right.index;
      }), 'value');
    }

    // An internal function used for aggregate "group by" operations.
    private group<T>(behavior) {
      return function(obj, iterator, context) {
        var result: _.Dictionary<T> = {};
        iterator = this.lookupIterator(iterator, context);
        this.each(obj, function(value, index) {
          var key = iterator(value, index, obj);
          behavior(result, value, key);
        });
        return result;
      };
    }

    // Groups the object's values by a criterion. Pass either a string attribute
    // to group by, or a function that returns the criterion.
    public groupBy<T>(list: _.List<T>, iterator?: _.ListIterator<T, any>, context?: any): _.Dictionary<T[]> {
      return this.group<T[]>(function(result, value, key) { if (this.has(result, key)) result[key].push(value); else result[key] = [value]; })(list, iterator, context);
    }

    // Indexes the object's values by a criterion, similar to `groupBy`, but for
    // when you know that your index values will be unique.
    public indexBy<T>(list: _.List<T>, iterator: _.ListIterator<T, any>, context?: any): _.Dictionary<T> {
      return this.group<T>(function(result, value, key) { result[key] = value; })(list, iterator, context);
    }

    // Counts instances of an object that group by a certain criterion. Pass
    // either a string attribute to count by, or a function that returns the
    // criterion.
    public countBy<T>(list: _.List<T>, iterator?: _.ListIterator<T, any>, context?: any): _.Dictionary<number> {
      return this.group<number>(function(result, value, key) { if (this.has(result, key)) result[key]++; else result[key] = 1; })(list, iterator, context);
    }

    // TODO: formerly not restricted to comparing numbers; needs Comparable interface?
    // TODO: does this match the .d.ts file? if not, why is it compiling?
    // Use a comparator function to figure out the smallest index at which
    // an object should be inserted so as to maintain order. Uses binary search.
    public sortedIndex(list: _.List<number>, value: number, iterator?: (x: number) => number, context?: any): number;
    public sortedIndex<T>(list: _.List<T>, value: T, iterator: (x: T) => number, context?: any): number;
    public sortedIndex(list: _.List<any>, value: any, iterator?: (x: any) => number, context?: any): number {
      iterator = this.lookupIterator1(iterator, context);
      var processedValue = iterator(value);
      var low = 0, high = list.length;
      while (low < high) {
        var mid = (low + high) >>> 1;
        if (iterator(list[mid]) < processedValue) low = mid + 1; else high = mid;
      }
      return low;
    }

    // Safely create a real, live array from anything iterable.
    public toArray<T>(list: _.List<T>): T[];
    public toArray<T>(dict: _.Dictionary<T>): T[];
    public toArray<T>(obj: any): T[] {
      if (!obj) return [];
      if (this.isArray(obj)) return slice.call(obj);
      if (obj.length === +obj.length) return this.map<T, T>(obj, this.identity);
      return this.values(obj);
    }

    // Return the number of elements in an object.
    public size<T>(list: _.List<T>): number;
    public size<T>(dict: _.Dictionary<T>): number;
    public size<T>(obj: any): number {
      if (obj == null) return 0;
      return obj.length === +obj.length ? obj.length : this.keys(obj).length;
    }

    // Split a collection into two arrays: one whose elements all satisfy the given
    // predicate, and one whose elements all do not satisfy the predicate.
    partition<T>(array: Array<T>, predicate: _.ListIterator<T, boolean>, context?: any): T[][] {
      predicate = this.lookupIterator(predicate, context);
      var pass = [], fail = [];
      this.each(array, function(value, key, obj) {
        (predicate(value, key, obj) ? pass : fail).push(value);
      });
      return [pass, fail];
    }

    // Array Functions
    // ---------------

    // Get the first element of an array. Passing **n** will return the first N
    // values in the array. Aliased as `head` and `take`. The **guard** check
    // allows it to work with `_.map`.
    public first<T>(array: _.List<T>): T;
    public first<T>(array: _.List<T>, n: number): T[];
    public first<T>(array: _.List<T>, n?: number): any {
      if (array == null) return void 0;
      if (n == null) return array[0];
      if (n < 0) return [];
      return slice.call(array, 0, n);
    }

    public head<T>(array: _.List<T>): T;
    public head<T>(array: _.List<T>, n: number): T[];
    public head<T>(array: _.List<T>, n?: number): any {
      return this.first(array, n);
    }

    public take<T>(array: _.List<T>): T;
    public take<T>(array: _.List<T>, n: number): T[];
    public take<T>(array: _.List<T>, n?: number): any {
      return this.first(array, n);
    }

    // Returns everything but the last entry of the array. Especially useful on
    // the arguments object. Passing **n** will return all the values in
    // the array, excluding the last N. The **guard** check allows it to work with
    // `_.map`.
    public initial<T>(array: _.List<T>, n?: number): T[] {
      if (n == null) n = 1;
      return slice.call(array, 0, Math.max(0, array.length - n));
    }

    // Get the last element of an array. Passing **n** will return the last N
    // values in the array. The **guard** check allows it to work with `_.map`.
    public last<T>(array: _.List<T>): T;
    public last<T>(array: _.List<T>, n: number): T[];
    public last<T>(array: _.List<T>, n?: number): any {
      if (array == null) return void 0;
      if (n == null) return array[array.length - 1];
      return slice.call(array, Math.max(array.length - n, 0));
    }

    // Returns everything but the first entry of the array. Aliased as `tail` and `drop`.
    // Especially useful on the arguments object. Passing an **n** will return
    // the rest N values in the array. The **guard**
    // check allows it to work with `_.map`.
    public rest<T>(array: _.List<T>, n?: number): T[] {
      if (n == null) n = 1;
      return slice.call(array, n);
    }

    public tail<T>(array: _.List<T>, n?: number): T[] {
      return this.rest(array, n);
    }

    public drop<T>(array: _.List<T>, n?: number): T[] {
      return this.rest(array, n);
    }

    // Trim out all falsy values from an array.
    public compact<T>(array: _.List<T>): T[] {
      return this.filter(array, this.identity);
    }

    // Internal implementation of a recursive `flatten` function.
    private flattenInternal(input: _.List<any>, shallow: boolean, strict: boolean, output: any[]): any[] {
      if (shallow && this.every(input, this.isArray)) {
        return concat.apply(output, input);
      }
      for (var i = 0, length = input.length; i < length; i++) {
        var value = input[i];
        if (!this.isArray(value) && !this.isArguments(value)) {
          if (!strict) output.push(value);
        } else if (shallow) {
          push.apply(output, value);
        } else {
          this.flattenInternal(value, shallow, strict, output);
        }
      }
      return output;
    }

    // Flatten out an array, either recursively (by default), or just one level.
    public flatten(array: _.List<any>, shallow?: boolean): any[] {
      return this.flattenInternal(array, shallow, false, []);
    }

    // Return a version of the array that does not contain the specified value(s).
    public without<T>(array: _.List<T>, ...values: T[]): T[] {
      return this.difference(array, values);
    }

    // Produce a duplicate-free version of the array. If the array has already
    // been sorted, you have the option of using a faster algorithm.
    // Aliased as `unique`.
    // _.uniq = _.unique = function(array, isSorted, iterator, context) {
    public uniq<T, TSort>(array: _.List<T>, isSorted?: boolean, iterator?: _.ListIterator<T, TSort>, context?: any): T[];
    public uniq<T, TSort>(array: _.List<T>, iterator?: _.ListIterator<T, TSort>, context?: any): T[];
    public uniq<T, TSort>(array: _.List<T>, isSorted?: any, iterator?: any, context?: any): T[] {
      if (array == null) return [];
      if (this.isFunction(isSorted)) { // Turn a call of second overload into a call of first
        return this.uniq(array, false, isSorted, iterator);
      }
      if (iterator) iterator = this.lookupIterator(iterator, context);
      var result = [];
      var prev = null
      var seen = [];
      for (var i = 0, length = array.length; i < length; i++) {
        var value = array[i];
        if (iterator) value = iterator(value, i, array);
        if (isSorted ? !i || prev !== value : !this.contains(seen, value)) {
          if (isSorted) prev = value;
          else seen.push(value);
          result.push(array[i]);
        }
      }
      return result;
    }

    public unique<T, TSort>(array: _.List<T>, isSorted?: boolean, iterator?: _.ListIterator<T, TSort>, context?: any): T[];
    public unique<T, TSort>(array: _.List<T>, iterator?: _.ListIterator<T, TSort>, context?: any): T[];
    public unique<T, TSort>(array: _.List<T>, isSorted?: any, iterator?: any, context?: any): T[] {
      return this.uniq(array, isSorted, iterator, context);
    }

    // Produce an array that contains the union: each distinct element from all of
    // the passed-in arrays.
    public union<T>(...arrays: _.List<T>[]): T[] {
      return this.uniq(this.flattenInternal(arrays, true, true, []));
    }

    // Produce an array that contains every item shared between all the
    // passed-in arrays.
    public intersection<T>(...arrays: _.List<T>[]): T[] {
      if (arrays == null) return [];
      var result = [];
      var argsLength = arguments.length;
      for (var i = 0, length = arrays.length; i < length; i++) {
        var item = arrays[i];
        if (this.contains(result, item)) continue;
        for (var j = 1; j < argsLength; j++) {
          if (!this.contains(arguments[j], item)) break;
        }
        if (j === argsLength) result.push(item);
      }
      return result;
    }

    // Take the difference between one array and a number of other arrays.
    // Only the elements present in just the first array will remain.
    public difference<T>(array: _.List<T>, ...others: _.List<T>[]): T[] {
      var rest = this.flattenInternal(others, true, true, []);
      return this.filter(array, function(value) {
        return !this.contains(rest, value);
      });
    }

                    //   // Zip together multiple lists into a single array -- elements that share
                    //   // an index go together.
                    //   _.zip = function(array) {
                    //     if (array == null) return [];
                    //     var length = _.max(arguments, 'length').length;
                    //     var results = Array(length);
                    //     for (var i = 0; i < length; i++) {
                    //       results[i] = _.pluck(arguments, i);
                    //     }
                    //     return results;
                    //   };

    // Converts lists into objects. Pass either a single array of `[key, value]`
    // pairs, or two parallel arrays of the same length -- one of keys, and one of
    // the corresponding values.
    public object(...keyValuePairs: any[][]): {};
    public object(list: _.List<string>, values: _.List<any>): {};
    public object(list: any, values?: _.List<any>): {} {
      if (list == null) return {};
      var result = {};
      for (var i = 0, length = list.length; i < length; i++) {
        if (values) {
          result[list[i]] = values[i];
        } else {
          result[list[i][0]] = list[i][1];
        }
      }
      return result;
    }

    // Return the position of the first occurrence of an item in an array,
    // or -1 if the item is not included in the array.
    // If the array is large and already in sort order, pass `true`
    // for **isSorted** to use binary search.
    public indexOf(array: _.List<number>, value: number, isSorted?: boolean): number;
    public indexOf<T>(array: _.List<T>, value: T, startFrom?: number): number;
    public indexOf(array: any, value: any, arg?: any): number {
      if (array == null) return -1;
      var i = 0, length = array.length;
      if (arg) {
        if (typeof arg == 'number') {
          i = arg < 0 ? Math.max(0, length + arg) : arg;
        } else {
          i = this.sortedIndex(array, value);
          return array[i] === value ? i : -1;
        }
      }
      for (; i < length; i++) if (array[i] === value) return i;
      return -1;
    }

    public lastIndexOf<T>(array: _.List<T>, value: T, from?: number): number {
      if (array == null) return -1;
      var i = from == null ? array.length : from;
      while (i--) if (array[i] === value) return i;
      return -1;
    }

    // Generate an integer Array containing an arithmetic progression. A port of
    // the native Python `range()` function. See
    // [the Python documentation](http://docs.python.org/library/functions.html#range).
    public range(start: number, stop?: number, step?: number): number[] {
      if (arguments.length == 1) {
        stop = start;
        start = 0;
      }
      step = arguments[2] || 1;

      var length = Math.max(Math.ceil((stop - start) / step), 0);
      var idx = 0;
      var range = Array(length);

      while (idx < length) {
        range[idx++] = start;
        start += step;
      }

      return range;
    }

                    //   // Function (ahem) Functions
                    //   // ------------------

                    //   // Reusable constructor function for prototype setting.
                    //   var Ctor = function(){};

                    //   // Create a function bound to a given object (assigning `this`, and arguments,
                    //   // optionally). Delegates to **ECMAScript 5**'s native `Function.bind` if
                    //   // available.
                    //   _.bind = function(func, context) {
                    //     var args, bound;
                    //     if (nativeBind && func.bind === nativeBind) return nativeBind.apply(func, slice.call(arguments, 1));
                    //     if (!_.isFunction(func)) throw TypeError('Bind must be called on a function');
                    //     args = slice.call(arguments, 2);
                    //     bound = function() {
                    //       if (!(this instanceof bound)) return func.apply(context, args.concat(slice.call(arguments)));
                    //       Ctor.prototype = func.prototype;
                    //       var self = new Ctor;
                    //       Ctor.prototype = null;
                    //       var result = func.apply(self, args.concat(slice.call(arguments)));
                    //       if (Object(result) === result) return result;
                    //       return self;
                    //     };
                    //     return bound;
                    //   };

                    //   // Partially apply a function by creating a version that has had some of its
                    //   // arguments pre-filled, without changing its dynamic `this` context. _ acts
                    //   // as a placeholder, allowing any combination of arguments to be pre-filled.
                    //   _.partial = function(func) {
                    //     var boundArgs = slice.call(arguments, 1);
                    //     return function() {
                    //       var position = 0;
                    //       var args = boundArgs.slice();
                    //       for (var i = 0, length = args.length; i < length; i++) {
                    //         if (args[i] === _) args[i] = arguments[position++];
                    //       }
                    //       while (position < arguments.length) args.push(arguments[position++]);
                    //       return func.apply(this, args);
                    //     };
                    //   };

                    //   // Bind a number of an object's methods to that object. Remaining arguments
                    //   // are the method names to be bound. Useful for ensuring that all callbacks
                    //   // defined on an object belong to it.
                    //   _.bindAll = function(obj) {
                    //     var i = 1, length = arguments.length, key;
                    //     if (length <= 1) throw Error('bindAll must be passed function names');
                    //     for (; i < length; i++) {
                    //       key = arguments[i];
                    //       obj[key] = _.bind(obj[key], obj);
                    //     }
                    //     return obj;
                    //   };

    // Memoize an expensive function by storing its results.
    public memoize(func: Function, hashFn?: (...args: any[]) => string): Function {
      var memoize:any = function(key) { //TODO: how to say that memoize is a Function with a named member var?
        var cache = memoize.cache;
        var address = hashFn ? hashFn.apply(this, arguments) : key;
        if (!this.has(cache, address)) cache[address] = func.apply(this, arguments);
        return cache[key];
      };
      memoize.cache = {};
      return memoize;
    }

    // Delays a function for the given number of milliseconds, and then calls
    // it with the arguments supplied.
    public delay(func: Function, wait: number, ...args: any[]): any {
      var slicedArgs = slice.call(args, 2);
      return setTimeout(function(){
        return func.apply(null, slicedArgs);
      }, wait);
    }

                    //   // Defers a function, scheduling it to run after the current call stack has
                    //   // cleared.
                    //   _.defer = function(func) {
                    //     return _.delay.apply(_, [func, 1].concat(slice.call(arguments, 1)));
                    //   };

                    //   // Returns a function, that, when invoked, will only be triggered at most once
                    //   // during a given window of time. Normally, the throttled function will run
                    //   // as much as it can, without ever going more than once per `wait` duration;
                    //   // but if you'd like to disable the execution on the leading edge, pass
                    //   // `{leading: false}`. To disable execution on the trailing edge, ditto.
                    //   _.throttle = function(func, wait, options) {
                    //     var context, args, result;
                    //     var timeout = null;
                    //     var previous = 0;
                    //     if (!options) options = {};
                    //     var later = function() {
                    //       previous = options.leading === false ? 0 : _.now();
                    //       timeout = null;
                    //       result = func.apply(context, args);
                    //       if (!timeout) context = args = null;
                    //     };
                    //     return function() {
                    //       var now = _.now();
                    //       if (!previous && options.leading === false) previous = now;
                    //       var remaining = wait - (now - previous);
                    //       context = this;
                    //       args = arguments;
                    //       if (remaining <= 0 || remaining > wait) {
                    //         clearTimeout(timeout);
                    //         timeout = null;
                    //         previous = now;
                    //         result = func.apply(context, args);
                    //         if (!timeout) context = args = null;
                    //       } else if (!timeout && options.trailing !== false) {
                    //         timeout = setTimeout(later, remaining);
                    //       }
                    //       return result;
                    //     };
                    //   };

                    //   // Returns a function, that, as long as it continues to be invoked, will not
                    //   // be triggered. The function will be called after it stops being called for
                    //   // N milliseconds. If `immediate` is passed, trigger the function on the
                    //   // leading edge, instead of the trailing.
                    //   _.debounce = function(func, wait, immediate) {
                    //     var timeout, args, context, timestamp, result;

                    //     var later = function() {
                    //       var last = _.now() - timestamp;

                    //       if (last < wait && last > 0) {
                    //         timeout = setTimeout(later, wait - last);
                    //       } else {
                    //         timeout = null;
                    //         if (!immediate) {
                    //           result = func.apply(context, args);
                    //           if (!timeout) context = args = null;
                    //         }
                    //       }
                    //     };

                    //     return function() {
                    //       context = this;
                    //       args = arguments;
                    //       timestamp = _.now();
                    //       var callNow = immediate && !timeout;
                    //       if (!timeout) timeout = setTimeout(later, wait);
                    //       if (callNow) {
                    //         result = func.apply(context, args);
                    //         context = args = null;
                    //       }

                    //       return result;
                    //     };
                    //   };

                    //   // Returns a function that will be executed at most one time, no matter how
                    //   // often you call it. Useful for lazy initialization.
                    //   _.once = function(func) {
                    //     var ran = false, memo;
                    //     return function() {
                    //       if (ran) return memo;
                    //       ran = true;
                    //       memo = func.apply(this, arguments);
                    //       func = null;
                    //       return memo;
                    //     };
                    //   };

                    //   // Returns the first function passed as an argument to the second,
                    //   // allowing you to adjust arguments, run code before and after, and
                    //   // conditionally execute the original function.
                    //   _.wrap = function(func, wrapper) {
                    //     return _.partial(wrapper, func);
                    //   };

    // Returns a negated version of the passed-in predicate.
    public negate<T>(predicate: _.ListIterator<T, boolean>): _.ListIterator<T, boolean> {
      return function(value: T, index: number, list: _.List<T>) {
        return !predicate.call(this, value, index, list);
      };
    }

    // Returns a function that is the composition of a list of functions, each
    // consuming the return value of the function that follows.
    public compose(...functions: Function[]): Function {
      var funcs = functions;
      return function() {
        var args = functions;
        for (var i = funcs.length - 1; i >= 0; i--) {
          args = [funcs[i].apply(this, args)];
        }
        return args[0];
      };
    }

                    //   // Returns a function that will only be executed after being called N times.
                    //   _.after = function(times, func) {
                    //     return function() {
                    //       if (--times < 1) {
                    //         return func.apply(this, arguments);
                    //       }
                    //     };
                    //   };

                    //   // Object Functions
                    //   // ----------------

    // Retrieve the names of an object's properties.
    // Delegates to **ECMAScript 5**'s native `Object.keys`
    public keys(obj: any): string[] {
      if (!this.isObject(obj)) return [];
      if (nativeKeys) return nativeKeys(obj);
      var keys = [];
      for (var key in obj) if (this.has(obj, key)) keys.push(key);
      return keys;
    }

    // Retrieve the values of an object's properties.
    public values(obj: any): any[] {
      var keys = this.keys(obj);
      var length = keys.length;
      var values = Array(length);
      for (var i = 0; i < length; i++) {
        values[i] = obj[keys[i]];
      }
      return values;
    }

    // Convert an object into a list of `[key, value]` pairs.
    public pairs(obj: any): any[][] {
      var keys = this.keys(obj);
      var length = keys.length;
      var pairs = Array(length);
      for (var i = 0; i < length; i++) {
        pairs[i] = [keys[i], obj[keys[i]]];
      }
      return pairs;
    }

    // Invert the keys and values of an object. The values must be serializable.
    public invert(obj: any): any {
      var result = {};
      var keys = this.keys(obj);
      for (var i = 0, length = keys.length; i < length; i++) {
        result[obj[keys[i]]] = keys[i];
      }
      return result;
    }

    // Return a sorted list of the function names available on the object.
    // Aliased as `methods`
    public functions(obj: any): string[] {
      var names = [];
      for (var key in obj) {
        if (this.isFunction(obj[key])) names.push(key);
      }
      return names.sort();
    }

    public methods(obj: any): string[] {
      return this.functions(obj);
    }

    // Extend a given object with all the properties in passed-in object(s).
    public extend(obj: any, ...sources: any[]): any {
      if (!this.isObject(obj)) return obj;
      var source, prop;
      for (var i = 1, length = sources.length; i < length; i++) {
        source = sources[i];
        for (prop in source) {
          obj[prop] = source[prop];
        }
      }
      return obj;
    }

                    //   // Return a copy of the object only containing the whitelisted properties.
                    //   _.pick = function(obj, iterator, context) {
                    //     var result = {}, key;
                    //     if (obj == null) return result;
                    //     if (_.isFunction(iterator)) {
                    //       iterator = createCallback(iterator, context);
                    //       for (key in obj) {
                    //         var value = obj[key];
                    //         if (iterator(value, key, obj)) result[key] = value;
                    //       }
                    //     } else {
                    //       var keys = concat.apply([], slice.call(arguments, 1));
                    //       obj = Object(obj);
                    //       for (var i = 0, length = keys.length; i < length; i++) {
                    //         key = keys[i];
                    //         if (key in obj) result[key] = obj[key];
                    //       }
                    //     }
                    //     return result;
                    //   };

                    //    // Return a copy of the object without the blacklisted properties.
                    //   _.omit = function(obj, iterator, context) {
                    //     if (_.isFunction(iterator)) {
                    //       iterator = _.negate(iterator);
                    //     } else {
                    //       var keys = _.map(concat.apply([], slice.call(arguments, 1)), String);
                    //       iterator = function(value, key) {
                    //         return !_.contains(keys, key);
                    //       };
                    //     }
                    //     return _.pick(obj, iterator, context);
                    //   };

    // Fill in a given object with default properties.
    public defaults(obj: any, ...defaults: any[]): any {
      if (!this.isObject(obj)) return obj;
      for (var i = 1, length = defaults.length; i < length; i++) {
        var source = defaults[i];
        for (var prop in source) {
          if (obj[prop] === void 0) obj[prop] = source[prop];
        }
      }
      return obj;
    }

                    //   // Create a (shallow-cloned) duplicate of an object.
                    //   _.clone = function(obj) {
                    //     if (!_.isObject(obj)) return obj;
                    //     return _.isArray(obj) ? obj.slice() : _.extend({}, obj);
                    //   };

    // Invokes interceptor with the obj, and then returns obj.
    // The primary purpose of this method is to "tap into" a method chain, in
    // order to perform operations on intermediate results within the chain.
    public tap<T>(obj: T, interceptor: Function): T {
      interceptor(obj);
      return obj;
    }

    // Internal recursive comparison function for `isEqual`.
    private eq(a, b, aStack, bStack): boolean {
      // Identical objects are equal. `0 === -0`, but they aren't identical.
      // See the [Harmony `egal` proposal](http://wiki.ecmascript.org/doku.php?id=harmony:egal).
      if (a === b) return a !== 0 || 1 / a === 1 / b;
      // A strict comparison is necessary because `null == undefined`.
      if (a == null || b == null) return a === b;
                    // // Unwrap any wrapped objects.
                    // if (a instanceof _) a = a._wrapped;
                    // if (b instanceof _) b = b._wrapped;
      // Compare `[[Class]]` names.
      var className = toString.call(a);
      if (className !== toString.call(b)) return false;
      switch (className) {
        // Strings, numbers, regular expressions, dates, and booleans are compared by value.
        case '[object RegExp]':
        // RegExps are coerced to strings for comparison (Note: '' + /a/i === '/a/i')
        case '[object String]':
          // Primitives and their corresponding object wrappers are equivalent; thus, `"5"` is
          // equivalent to `new String("5")`.
          return '' + a === '' + b;
        case '[object Number]':
          // `NaN`s are equivalent, but non-reflexive.
          // Object(NaN) is equivalent to NaN
          if (a != +a) return b != +b;
          // An `egal` comparison is performed for other numeric values.
          return a == 0 ? 1 / a == 1 / b : a == +b;
        case '[object Date]':
        case '[object Boolean]':
          // Coerce dates and booleans to numeric primitive values. Dates are compared by their
          // millisecond representations. Note that invalid dates with millisecond representations
          // of `NaN` are not equivalent.
          return +a === +b;
      }
      if (typeof a != 'object' || typeof b != 'object') return false;
      // Assume equality for cyclic structures. The algorithm for detecting cyclic
      // structures is adapted from ES 5.1 section 15.12.3, abstract operation `JO`.
      var length = aStack.length;
      while (length--) {
        // Linear search. Performance is inversely proportional to the number of
        // unique nested structures.
        if (aStack[length] === a) return bStack[length] === b;
      }
      // Objects with different constructors are not equivalent, but `Object`s
      // from different frames are.
      var aCtor = a.constructor, bCtor = b.constructor;
      if (
        aCtor !== bCtor &&
        // Handle Object.create(x) cases
        'constructor' in a && 'constructor' in b &&
        !(this.isFunction(aCtor) && aCtor instanceof aCtor &&
          this.isFunction(bCtor) && bCtor instanceof bCtor)
      ) {
        return false;
      }
      // Add the first object to the stack of traversed objects.
      aStack.push(a);
      bStack.push(b);
      var size, result;
      // Recursively compare objects and arrays.
      if (className === '[object Array]') {
        // Compare array lengths to determine if a deep comparison is necessary.
        size = a.length;
        result = size === b.length;
        if (result) {
          // Deep compare the contents, ignoring non-numeric properties.
          while (size--) {
            if (!(result = this.eq(a[size], b[size], aStack, bStack))) break;
          }
        }
      } else {
        // Deep compare objects.
        var keys = this.keys(a), key;
        size = keys.length;
        // Ensure that both objects contain the same number of properties before comparing deep equality.
        result = this.keys(b).length == size;
        if (result) {
          while (size--) {
            // Deep compare each member
            key = keys[size];
            if (!(result = this.has(b, key) && this.eq(a[key], b[key], aStack, bStack))) break;
          }
        }
      }
      // Remove the first object from the stack of traversed objects.
      aStack.pop();
      bStack.pop();
      return result;
    }

    // Perform a deep comparison to check if two objects are equal.
    public isEqual(obj: any, other: any): boolean {
      return this.eq(obj, other, [], []);
    }

    // Is a given array, string, or object empty?
    // An "empty" object has no enumerable own-properties.
    public isEmpty(obj: any): boolean {
      if (obj == null) return true;
      if (this.isArray(obj) || this.isString(obj) || this.isArguments(obj)) return obj.length === 0;
      for (var key in obj) if (this.has(obj, key)) return false;
      return true;
    }

    // Is a given value a DOM element?
    public isElement(obj: any): boolean {
      return !!(obj && obj.nodeType === 1);
    }

    // Is a given value an array?
    public isArray(obj: any): boolean {
      return toString.call(obj) === '[object Array]'
    }
                    //   // Delegates to ECMA5's native Array.isArray
                    //   _.isArray = nativeIsArray || function(obj) {
                    //     return toString.call(obj) === '[object Array]';
                    //   };

    // Is a given variable an object?
    public isObject(obj: any): boolean {
      return obj === Object(obj);
    }

    // some isType methods
    public isArguments(obj: any): boolean { return toString.call(obj) === '[object Arguments]'; }
    public isFunction(obj: any): boolean { return toString.call(obj) === '[object Function]'; }
    public isString(obj: any): boolean { return toString.call(obj) === '[object String]'; }
    public isNumber(obj: any): boolean { return toString.call(obj) === '[object Number]'; }
    public isDate(obj: any): boolean { return toString.call(obj) === '[object Date]'; }
    public isRegExp(obj: any): boolean { return toString.call(obj) === '[object RegExp]'; }

                    //   // Define a fallback version of the method in browsers (ahem, IE), where
                    //   // there isn't any inspectable "Arguments" type.
                    //   if (!_.isArguments(arguments)) {
                    //     _.isArguments = function(obj) {
                    //       return _.has(obj, 'callee');
                    //     };
                    //   }

                    //   // Optimize `isFunction` if appropriate.
                    //   if (typeof /./ !== 'function') {
                    //     _.isFunction = function(obj) {
                    //       return typeof obj === 'function';
                    //     };
                    //   }

    // Is a given object a finite number?
    public isFinite(obj: any): boolean {
      return isFinite(obj) && !isNaN(parseFloat(obj));
    }

    // Is the given value `NaN`? (NaN is the only number which does not equal itself).
    public isNaN(obj: any): boolean {
      return this.isNumber(obj) && obj !== +obj;
    }

    // Is a given value a boolean?
    public isBoolean(obj: any): boolean {
      return obj === true || obj === false || toString.call(obj) === '[object Boolean]';
    }

    // Is a given value equal to null?
    public isNull(obj: any): boolean {
      return obj === null;
    }

    // Is a given variable undefined?
    public isUndefined(obj: any): boolean {
      return obj === void 0;
    }

    // Shortcut function for checking if an object has a given property directly
    // on itself (in other words, not on a prototype).
    public has(obj: any, key: string): boolean {
      return obj != null && hasOwnProperty.call(obj, key);
    }

                    //   // Utility Functions
                    //   // -----------------

                    //   // Run Underscore.js in *noConflict* mode, returning the `_` variable to its
                    //   // previous owner. Returns a reference to the Underscore object.
                    //   _.noConflict = function() {
                    //     root._ = previousUnderscore;
                    //     return this;
                    //   };

    // Keep the identity function around for default iterators.
    public identity<T>(value: T): T {
      return value;
    }

    public constant<T>(value: T): () => T {
      return function() {
        return value;
      };
    }

                    //   _.noop = function(){};

    public property(key: string): (object: Object) => any {
      return function(obj) {
        return obj[key];
      };
    }

    // Returns a predicate for checking whether an object has a given set of `key:value` pairs.
    public matches(attrs: any): _.ListIterator<any, boolean> {
      return function(obj) {
        if (obj == null) return this.isEmpty(attrs);
        if (obj === attrs) return true;
        for (var key in attrs) if (attrs[key] !== obj[key]) return false;
        return true;
      };
    }

    // Run a function **n** times.
    public times<TResult>(n: number, iterator: (n: number) => TResult, context?: any): TResult[] {
      var accum = Array(Math.max(0, n));
      iterator = this.createCallback1(iterator, context);
      for (var i = 0; i < n; i++) accum[i] = iterator(i);
      return accum;
    }

    // Return a random integer between min and max (inclusive).
    public random(min: number, max?: number): number {
      if (max == null) {
        max = min;
        min = 0;
      }
      return min + Math.floor(Math.random() * (max - min + 1));
    }

    // A (possibly faster) way to get the current timestamp as an integer.
    public now(): number {
      return Date.now() || new Date().getTime();
    }

                    //   // List of HTML entities for escaping.
                    //   var entityMap = {
                    //     escape: {
                    //       '&': '&amp;',
                    //       '<': '&lt;',
                    //       '>': '&gt;',
                    //       '"': '&quot;',
                    //       "'": '&#x27;'
                    //     }
                    //   };
                    //   entityMap.unescape = _.invert(entityMap.escape);

                    //   // Regexes containing the keys and values listed immediately above.
                    //   var entityRegexes = {
                    //     escape:   RegExp('[' + _.keys(entityMap.escape).join('') + ']', 'g'),
                    //     unescape: RegExp('(' + _.keys(entityMap.unescape).join('|') + ')', 'g')
                    //   };

                    //   // Functions for escaping and unescaping strings to/from HTML interpolation.
                    //   _.each(['escape', 'unescape'], function(method) {
                    //     _[method] = function(string) {
                    //       if (string == null) return '';
                    //       return ('' + string).replace(entityRegexes[method], function(match) {
                    //         return entityMap[method][match];
                    //       });
                    //     };
                    //   });

    // If the value of the named `property` is a function then invoke it with the
    // `object` as context; otherwise, return it.
    public result(object: any, property: string): any {
      if (object == null) return void 0;
      var value = object[property];
      return this.isFunction(value) ? object[property]() : value;
    }

                    //   // Generate a unique integer id (unique within the entire client session).
                    //   // Useful for temporary DOM ids.
                    //   var idCounter = 0;
                    //   _.uniqueId = function(prefix) {
                    //     var id = ++idCounter + '';
                    //     return prefix ? prefix + id : id;
                    //   };

                    //   // By default, Underscore uses ERB-style template delimiters, change the
                    //   // following template settings to use alternative delimiters.
                    //   _.templateSettings = {
                    //     evaluate    : /<%([\s\S]+?)%>/g,
                    //     interpolate : /<%=([\s\S]+?)%>/g,
                    //     escape      : /<%-([\s\S]+?)%>/g
                    //   };

                    //   // When customizing `templateSettings`, if you don't want to define an
                    //   // interpolation, evaluation or escaping regex, we need one that is
                    //   // guaranteed not to match.
                    //   var noMatch = /(.)^/;

                    //   // Certain characters need to be escaped so that they can be put into a
                    //   // string literal.
                    //   var escapes = {
                    //     "'":      "'",
                    //     '\\':     '\\',
                    //     '\r':     'r',
                    //     '\n':     'n',
                    //     '\u2028': 'u2028',
                    //     '\u2029': 'u2029'
                    //   };

                    //   var escaper = /\\|'|\r|\n|\u2028|\u2029/g;

                    //   var escapeChar = function(match) {
                    //     return '\\' + escapes[match];
                    //   };

                    //   // JavaScript micro-templating, similar to John Resig's implementation.
                    //   // Underscore templating handles arbitrary delimiters, preserves whitespace,
                    //   // and correctly escapes quotes within interpolated code.
                    //   _.template = function(text, data, settings) {
                    //     settings = _.defaults({}, settings, _.templateSettings);

                    //     // Combine delimiters into one regular expression via alternation.
                    //     var matcher = RegExp([
                    //       (settings.escape || noMatch).source,
                    //       (settings.interpolate || noMatch).source,
                    //       (settings.evaluate || noMatch).source
                    //     ].join('|') + '|$', 'g');

                    //     // Compile the template source, escaping string literals appropriately.
                    //     var index = 0;
                    //     var source = "__p+='";
                    //     text.replace(matcher, function(match, escape, interpolate, evaluate, offset) {
                    //       source += text.slice(index, offset).replace(escaper, escapeChar);
                    //       index = offset + match.length;

                    //       if (escape) {
                    //         source += "'+\n((__t=(" + escape + "))==null?'':_.escape(__t))+\n'";
                    //       } else if (interpolate) {
                    //         source += "'+\n((__t=(" + interpolate + "))==null?'':__t)+\n'";
                    //       } else if (evaluate) {
                    //         source += "';\n" + evaluate + "\n__p+='";
                    //       }

                    //       // Adobe VMs need the match returned to produce the correct offest.
                    //       return match;
                    //     });
                    //     source += "';\n";

                    //     // If a variable is not specified, place data values in local scope.
                    //     if (!settings.variable) source = 'with(obj||{}){\n' + source + '}\n';

                    //     source = "var __t,__p='',__j=Array.prototype.join," +
                    //       "print=function(){__p+=__j.call(arguments,'');};\n" +
                    //       source + 'return __p;\n';

                    //     try {
                    //       var render = Function(settings.variable || 'obj', '_', source);
                    //     } catch (e) {
                    //       e.source = source;
                    //       throw e;
                    //     }

                    //     if (data) return render(data, _);
                    //     var template = function(data) {
                    //       return render.call(this, data, _);
                    //     };

                    //     // Provide the compiled source as a convenience for precompilation.
                    //     var argument = settings.variable || 'obj';
                    //     template.source = 'function(' + argument + '){\n' + source + '}';

                    //     return template;
                    //   };

                    //   // Add a "chain" function. Start chaining a wrapped Underscore object.
                    //   _.chain = function(obj) {
                    //     var instance = _(obj);
                    //     instance._chain = true;
                    //     return instance;
                    //   };

                    //   // OOP
                    //   // ---------------
                    //   // If Underscore is called as a function, it returns a wrapped object that
                    //   // can be used OO-style. This wrapper holds altered versions of all the
                    //   // underscore functions. Wrapped objects may be chained.

                    //   // Helper function to continue chaining intermediate results.
                    //   var result = function(obj) {
                    //     return this._chain ? _(obj).chain() : obj;
                    //   };

                    //   // Add your own custom functions to the Underscore object.
                    //   _.mixin = function(obj) {
                    //     _.each(_.functions(obj), function(name) {
                    //       var func = _[name] = obj[name];
                    //       _.prototype[name] = function() {
                    //         var args = [this._wrapped];
                    //         push.apply(args, arguments);
                    //         return result.call(this, func.apply(_, args));
                    //       };
                    //     });
                    //   };

                    //   // Add all of the Underscore functions to the wrapper object.
                    //   _.mixin(_);

                    //   // Add all mutator Array functions to the wrapper.
                    //   _.each(['pop', 'push', 'reverse', 'shift', 'sort', 'splice', 'unshift'], function(name) {
                    //     var method = ArrayProto[name];
                    //     _.prototype[name] = function() {
                    //       var obj = this._wrapped;
                    //       method.apply(obj, arguments);
                    //       if ((name === 'shift' || name === 'splice') && obj.length === 0) delete obj[0];
                    //       return result.call(this, obj);
                    //     };
                    //   });

                    //   // Add all accessor Array functions to the wrapper.
                    //   _.each(['concat', 'join', 'slice'], function(name) {
                    //     var method = ArrayProto[name];
                    //     _.prototype[name] = function() {
                    //       return result.call(this, method.apply(this._wrapped, arguments));
                    //     };
                    //   });

                    //   // Extracts the result from a wrapped and chained object.
                    //   _.prototype.value = function() {
                    //     return this._wrapped;
                    //   };

                    //   // AMD registration happens at the end for compatibility with AMD loaders
                    //   // that may not enforce next-turn semantics on modules. Even though general
                    //   // practice for AMD registration is to be anonymous, underscore registers
                    //   // as a named module because, like jQuery, it is a base library that is
                    //   // popular enough to be bundled in a third party lib, but not be part of
                    //   // an AMD load request. Those cases could generate an error when an
                    //   // anonymous define() is called outside of a loader request.
                    //   if (typeof define === 'function' && define.amd) {
                    //     define('underscore', [], function() {
                    //       return _;
                    //     });
                    //   }
  }
}