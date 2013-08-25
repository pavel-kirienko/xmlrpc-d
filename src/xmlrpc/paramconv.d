/*
 * XMLRPC parameter type converter
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.paramconv;

import xmlrpc.data;
import std.variant : Variant;
import std.range : isForwardRange;
import std.conv : to;
import std.traits : isAssociativeArray, isImplicitlyConvertible;

Variant[] paramsToVariantArray(Args...)(Args args)
{
    Variant[] result;
    foreach (a; args)
        result ~= paramToVariant(a);
    return result;
}

private
{
    Variant paramToVariant(Arg)(Arg arg)
    {
        static if (is(Arg : Variant))
        {
            return arg;
        }
        else static if (isForwardRange!Arg && !isImplicitlyConvertible!(Arg, const(char[])))
        {
            Variant[] array;
            foreach (a; arg)
                array ~= paramToVariant(a);
            return Variant(array);
        }
        else static if (isAssociativeArray!Arg)
        {
            static assert(isImplicitlyConvertible!(KeyType!Arg, const(char[])) || is(KeyType!Arg == Variant),
                          "Associative array key type must be string, implicitly convertible to string, or Variant");
            Variant[string] hash;
            foreach (key, rawValue; arg)
            {
                Variant value = paramToVariant(rawValue);
//                if (value.convertsTo!string)
//                {
//                    /*
//                     * HACK HACK HACK HACK
//                     * Current implementation of the Variant type will throw if this conversion is not performed
//                     */
//                    char[] mutableString = cast(char[])value.get!string;
//                    hash[to!string(key)] = mutableString;
//                }
//                else
                {
                    hash[to!string(key)] = value;
                }
            }
            return Variant(hash);
        }
        else
        {
            return Variant(arg);
        }
    }
    
    // http://forum.dlang.org/thread/mailman.753.1327358664.16222.digitalmars-d-learn@puremagic.com
    template KeyType(AA) if (isAssociativeArray!AA)
    {
       static if (is(AA V : V[K], K))
       {
           alias K KeyType;
       }
    }
}


version (xmlrpc_unittest) unittest
{
    import std.stdio;
    import std.exception;
    
    /*
     * Primitives
     */
    assert(paramToVariant(123) == 123);
    
    Variant converted = paramToVariant(["test": [456, 789]]);
    assert(converted["test"][0] == 456);
    assert(converted["test"][1] == 789);
    
    converted = paramToVariant(["test": ["nested": "string value"]]);
    //assert(getString(converted["test"]["nested"]) == "string value");
    assert(converted["test"]["nested"] == "string value");
    
    /*
     * Make sure that Variant types passed with no conversion, otherwise the
     * assoc. array with integer key would be illegal
     */
    converted = paramToVariant(["test": [Variant(456), Variant([123:456])]]);
    assert(converted["test"][0] == 456);
    assert(converted["test"][1][123] == 456);
    
    /*
     * Associative array key type checking
     */
    assert(is(typeof(paramToVariant(["test": ["hello":456]]))));       // OK: String key
    assertNotThrown(paramToVariant([Variant("hello"):456]));           // OK: Variant key is convertible to string
    assertNotThrown(paramToVariant([Variant(123456):456]));            // OK: Variant is not convertible to string
    assert(!is(typeof(paramToVariant([123:456]))));                    // Fail: Integer key
    
    /*
     * Group conversions
     */
    Variant[] va = paramsToVariantArray("string", 123, [465, 789], Variant("variant"), ["key": "value"]);
    //writeln(to!string(va));
    assert(to!string(va) == `[string, 123, [465, 789], variant, ["key":value]]`);
}
