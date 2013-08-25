/*
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.data;

import xmlrpc.exception;
import std.variant : Variant;
import std.functional : reduce;
import std.conv : to;
import std.string : format;

alias Variant[] XmlRpcArray;
alias Variant[string] XmlRpcStruct;

struct MethodCallData
{
    string name;
    Variant[] params;
    
    string toString()
    {
        return name ~ "(" ~ prettyParams(params) ~ ")";
    }
}

struct MethodResponseData
{
    bool fault;
    Variant[] params;
    
    string toString()
    {
        return (fault ? "FAULT" : "OK") ~ ": " ~ prettyParams(params);
    }
}

string prettyParams(Variant[] params)
{
    return reduce!((a, b) { return a ~ (a.length ? ", " : "") ~ prettyParam(b); })("", params);
}

///**
// * Work-around for Variant containing Variant[string]
// * Look into the decoder implementation for explanation
// */
//string getString(Variant v)
//{
//    if (v.convertsTo!string())
//        return v.get!string;
//    
//    if (v.convertsTo!(char[])())
//        return cast(string)v.get!(char[]);
//    
//    throw new XmlRpcException("Variant is not convertible to string from " ~ to!string(v.type()));
//}
//
//bool convertsToString(Variant v)
//{
//    return v.convertsTo!string() || v.convertsTo!(char[])();
//}

private string prettyParam(Variant param)
{
//    if (convertsToString(param))
//        return "`" ~ getString(param) ~ "`";
    if (param.convertsTo!string())
        return "`" ~ param.get!string() ~ "`";
    
    if (param.convertsTo!(ubyte[]))
        return reduce!((a, b) { return format("%s %02x", a, b); })("hex:", param.get!(ubyte[])());
    
    if (param.convertsTo!XmlRpcArray)
        return "[" ~ prettyParams(param.get!XmlRpcArray) ~ "]";
    
    if (param.convertsTo!XmlRpcStruct)
    {
        string output;
        foreach (key, value; param.get!XmlRpcStruct)
        {
            output ~= output ? ", " : "[";
            output ~= "\"" ~ key ~ "\": " ~ prettyParam(value);
        }
        return output ~ "]";
    }
    
    return to!string(param);
}


version (xmlrpc_unittest) unittest
{
    import std.stdio;
    import std.exception;
    
    auto call = MethodCallData("method", [Variant(123), Variant(["key":Variant(cast(ubyte[])x"be da ca fe")])]);
    assert(call.toString() == `method(123, ["key": hex: be da ca fe])`);
    
//    Variant x = 123;
//    assert(!convertsToString(x));
//    assertThrown!XmlRpcException(getString(x));
//    Variant y = cast(char[])"123";
//    assert(convertsToString(y));
//    assert(getString(y) == "123");
//    Variant z = "456";
//    assert(convertsToString(z));
//    assert(getString(z) == "456");
}
