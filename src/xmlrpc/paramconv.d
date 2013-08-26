/*
 * XMLRPC parameter type converter
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.paramconv;

import xmlrpc.data;
import std.variant : Variant;
import std.range : isForwardRange;
import std.conv : to;
import std.traits : isAssociativeArray, isImplicitlyConvertible, KeyType, isSomeString, isScalarType, Unqual;

Variant[] paramsToVariantArray(Args...)(Args args)
{
    Variant[] result;
    foreach (a; args)
        result ~= paramToVariant(a);
    return result;
}

private Variant paramToVariant(Arg)(Arg arg)
{
    static if (isImplicitlyConvertible!(Arg, Variant))
    {
        return arg;
    }
    else static if (isSomeString!Arg || isImplicitlyConvertible!(Arg, const(string)))
    {
        return Variant(to!string(arg));     // NOTE: 'wstring', 'dstring' are converted to 'string'
    }
    else static if (isForwardRange!Arg)     // Order matters because strings are forward ranges too.
    {
        Variant[] array;
        foreach (a; arg)
            array ~= paramToVariant(a);
        return Variant(array);
    }
    else static if (isAssociativeArray!Arg)
    {
        static assert(isSomeString!(KeyType!Arg) ||
                      isImplicitlyConvertible!(KeyType!Arg, const(string)) ||
                      is(KeyType!Arg == Variant),
                      "Associative array key type must be string, implicitly convertible to string, or Variant");
        Variant[string] hash;
        foreach (key, rawValue; arg)
        {
            Variant value = paramToVariant(rawValue);
            hash[to!string(key)] = value;              // NOTE: Any Variant will be silently turned into string
        }
        return Variant(hash);
    }
    else static if (isScalarType!Arg)                  // NOTE: Get rid of type qualifiers
    {
        return Variant(cast(Unqual!Arg)arg);
    }
    else
    {
        return Variant(arg);
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
    
    Variant converted = paramToVariant(["test": [cast(immutable)456, cast(const)789]]);
    assert(converted["test"][0].type() == typeid(int));
    assert(converted["test"][0] == 456);
    assert(converted["test"][1] == 789);
    
    converted = paramToVariant(["test": ["nested"w: "string value"d]]);
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
    assert(to!string(va) == `[string, 123, [465, 789], variant, ["key":value]]`);
}
