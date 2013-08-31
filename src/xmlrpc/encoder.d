/*
 * XMLRPC encoder
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.encoder;

import xmlrpc.error;
import xmlrpc.data;
import std.xml : Element, Document;
import std.conv : to;
import std.exception : enforce;
import std.string : join;
import std.variant : Variant;
import std.datetime : DateTime;
import std.base64 : Base64;
import std.stdio : writeln;

@trusted:

class EncoderException : XmlRpcException
{
    private this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}

package:

string encodeCall(MethodCallData call)
{
    auto root = new Element("methodCall");
    root ~= new Element("methodName", call.name);
    root ~= encodeParams(call.params);
    return toString(root);
}

string encodeResponse(MethodResponseData resp)
{
    auto root = new Element("methodResponse");
    if (resp.fault)
    {
        enforce(resp.params.length == 1, new EncoderException("Fault response must contain exactly one parameter"));
        auto fault = new Element("fault");
        fault ~= encodeValue(resp.params[0]);
        root ~= fault;
    }
    else
        root ~= encodeParams(resp.params);
    return toString(root);
}

private:

Element encodeParams(Variant[] params)
{
    auto node = new Element("params");
    foreach (ref par; params)
        node ~= encodeParam(par);
    return node;
}

Element encodeParam(Variant param)
{
    auto node = new Element("param");
    node ~= encodeValue(param);
    return node;
}

Element encodeValue(Variant param)
{
    auto node = new Element("value");
    // TODO: allow associative arrays with keys of arbitrary type?
    if (param.convertsTo!XmlRpcStruct)
        node ~= encodeStructValue(param);
    else if (param.convertsTo!XmlRpcArray)
        node ~= encodeArrayValue(param);
    else
        node ~= encodePrimitiveValue(param);
    return node;
}

Element encodeStructValue(Variant param)
{
    auto structNode = new Element("struct");
    foreach (key, ref value; param.get!XmlRpcStruct())
    {
        auto member = new Element("member");
        member ~= new Element("name", key);
        member ~= encodeValue(value);
        structNode ~= member;
    }
    return structNode;
}

Element encodeArrayValue(Variant param)
{
    auto array = new Element("array");
    auto data = new Element("data");
    foreach (ref value; param.get!XmlRpcArray)
        data ~= encodeValue(value);
    array ~= data;
    return array;
}

Element encodePrimitiveValue(Variant param)
{
    // Almost everything converts to boolean, thus we need to check the exact type match here:
    if (param.type() == typeid(bool))
        return new Element("boolean", param.get!bool() ? "1" : "0");
    
    if (param.convertsTo!int() || param.convertsTo!uint())
        return new Element("int", param.toString());
    
    // Extension (64-bit signed integer)
    if (param.convertsTo!long() || param.convertsTo!ulong())
        return new Element("i8", param.toString());
    
    if (param.convertsTo!real())
        return new Element("double", param.toString());
    
    if (param.convertsTo!(const(string))() ||
        param.convertsTo!(const(dstring))() ||
        param.convertsTo!(const(wstring))())
    {
        return new Element("string", param.toString());
    }
    
    if (param.convertsTo!DateTime())
    {
        const dt = param.get!DateTime();
        return new Element("dateTime.iso8601", dt.toISOString());
    }
    
    if (param.convertsTo!(const(ubyte[]))())
    {
        const source = param.get!(const(ubyte[]))();
        char[] encoded = Base64.encode(source);
        return new Element("base64", to!string(encoded));
    }
    
    // Extension (nil)
    if (param.convertsTo!(typeof(null)) && param.get!(typeof(null))() == null)
        return new Element("nil");
    
    throw new EncoderException(format("Unable to encode the value of type %s", param.type()));
}

string toString(in Element e)
{
    return join(e.pretty(0), "\n");
}

version (xmlrpc_unittest) unittest
{
    import xmlrpc.decoder;
    static import xmlrpc.paramconv;
    
    void assertResultsEqual(T)(T a, T b)
    {
        writeln(a.toString());
        //writeln(b.toString());
        // Variant type does not compare arrays properly
        assert(a.toString() == b.toString());
    }
    
    // Hardcore parameter set
    Variant[] params = [Variant(123U),
                        Variant(cast(const)"Our sun is dying."),
                        Variant(0xc0a1_e5ce_d64b_17UL),
                        Variant([Variant(123),
                                 Variant(12.3),
                                 Variant("abc"d),
                                 Variant(0),
                                 Variant(true),
                                 Variant(null)]),
                        Variant(DateTime(2013, 8, 25, 13, 38, 42)),
                        Variant(cast(const(ubyte[]))x"de ad be ef"),
                        Variant(["null":Variant(null)]),
                        Variant(["true":Variant(true)]),
                        Variant(["false":Variant(false)]),
                        Variant(["we":Variant(["need":Variant("to go deeper")])])];
    
    /*
     * Call
     */
    auto methodCallData = MethodCallData("theMethod", params);
    auto encoded = encodeCall(methodCallData);
    MethodCallData decodedCall = decodeCall(encoded);
    assertResultsEqual(decodedCall, methodCallData);
    
    /*
     * Response
     */
    auto methodResponseData = MethodResponseData(false, params);
    encoded = encodeResponse(methodResponseData);
    MethodResponseData decodedResponse = decodeResponse(encoded);
    assertResultsEqual(decodedResponse, methodResponseData);
    
    /*
     * Fault response
     */
    auto faultParams = xmlrpc.paramconv.paramsToVariantArray(["faultCode"w: Variant(42),
                                                              "faultString": Variant("Fire in oxygen garden."d)]);
    methodResponseData = MethodResponseData(true, faultParams);
    encoded = encodeResponse(methodResponseData);
    decodedResponse = decodeResponse(encoded);
    assert(decodedResponse.fault);
    assert(decodedResponse.params.length == 1);
    assert(decodedResponse.params[0]["faultCode"] == 42);
    assert(decodedResponse.params[0]["faultString"] == "Fire in oxygen garden.");
}
