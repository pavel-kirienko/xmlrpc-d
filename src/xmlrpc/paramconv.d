/*
 * XMLRPC parameter type converter
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.paramconv;

import xmlrpc.data;
import xmlrpc.error;
import std.string : format;
import std.exception : enforce;
import std.variant : Variant, VariantException;
import std.range : isForwardRange;
import std.conv : to, ConvException;
import std.typecons : Tuple;
import std.stdio : writeln;
import std.traits : isAssociativeArray, isArray, isImplicitlyConvertible, KeyType, ValueType, isSomeString,
                    isScalarType, Unqual;

@trusted:

class ParameterConversionException : XmlRpcException
{
    private this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}

package:

Variant[] paramsToVariantArray(Args...)(Args args)
{
    Variant[] result;
    foreach (a; args)
        result ~= paramToVariant(a);
    return result;
}

auto variantArrayToParams(Args...)(Variant[] variants)
{
    enforce(Args.length == variants.length,
        new ParameterConversionException(format("Wrong number of arguments: expected %s, got %s)",
                                                Args.length, variants.length)));
    
    static if (Args.length == 0)
        return;
    static if (Args.length == 1)  // Special case
        return variantToParam!(Args[0])(variants[0]);
    else
    {
        Tuple!(Args) returnValue;
        foreach (i, ref item; returnValue)
            item = variantToParam!(typeof(returnValue[i]))(variants[i]);
        return returnValue;
    }
}

private:

Arg variantToParam(Arg)(Variant var)
{
    static if (is(Arg : Variant))
    {
        return var;
    }
    else static if (isSomeString!Arg)
    {
        return to!Arg(var);
    }
    else static if (isArray!Arg)
    {
        Arg array;
        foreach (ref Variant item; var)
            array ~= variantToParam!(typeof(array[0]))(item);
        return array;
    }
    else static if (isAssociativeArray!Arg)
    {
        static assert(isImplicitlyConvertible!(KeyType!Arg, const(string)) ||
                      "Associative array key type must be implicitly convertible to string");
        Arg assocArray;
        // Intermediate array is required because iterating over the Variant(Value[Key]) is not possible
        auto intermediate = var.get!(Variant[string])();
        foreach (key, ref value; intermediate)
            assocArray[key] = variantToParam!(ValueType!Arg)(value);
        return assocArray;
    }
    else static if (is(typeof(var.coerce!Arg())))  // Try to coerce only if the type is coercible
    {
        return var.coerce!Arg();
    }
    else
    {
        return var.get!Arg();                      // Exact match is the last line of defence
    }
}

Variant paramToVariant(Arg)(Arg arg)
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
            hash[to!string(key)] = value;              // Any Variant turns into string
        }
        return Variant(hash);
    }
    else static if (isScalarType!Arg)                  // Get rid of type qualifiers
    {
        return Variant(to!(Unqual!Arg)(arg));
    }
    else
    {
        return Variant(arg);
    }
}

// From Variant[]
version (xmlrpc_unittest) unittest
{
    import std.exception;
    import std.datetime : DateTime;
    
    Variant[] vars = [Variant([Variant(123), Variant(456)])];
    auto p1 = variantArrayToParams!(int[])(vars);
    assert(p1 == [123, 456]);
    
    Variant[string] aa = ["abc": Variant(456)];
    vars = [Variant(aa)];
    auto p2 = variantArrayToParams!(int[string])(vars);
    assert(p2["abc"] == 456);
    
    // Multiple arguments, implicit string to float conversion
    aa = ["abc": Variant(456), "qwerty": Variant("123.456")];
    vars = [Variant(123), Variant("def"), Variant("789"), Variant(aa), Variant(DateTime(2020, 1, 17, 12, 34, 56))];
    auto p3 = variantArrayToParams!(int, string, float, real[string], DateTime)(vars);
    assert(p3[0] == 123);
    assert(p3[1] == "def");
    assert(p3[2] == 789);
    assert(p3[3]["abc"] == 456);
    assert(p3[3]["qwerty"] == 123.456);
    assert(p3[4] == DateTime(2020, 1, 17, 12, 34, 56));
    
    // Non-parseable strings
    vars = [Variant("nonparseable"), Variant("*+j")];
    assertThrown!ConvException(variantArrayToParams!(int, float)(vars));
    
    // Type mismatch
    assertThrown!ParameterConversionException(variantArrayToParams!(int)(vars));
    assertThrown!VariantException(variantArrayToParams!(int[string], float[])(vars));
    
    // Compilation failure
    static assert(!is(typeof(variantArrayToParams!(string[int])(vars)))); // AA key type
}

// To Variant[]
version (xmlrpc_unittest) unittest
{
    import std.exception;
    
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
