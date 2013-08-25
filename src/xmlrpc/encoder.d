/*
 * XMLRPC encoder
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.encoder;

import xmlrpc.exception;
import xmlrpc.data;
import std.xml : Element, Document;
import std.conv : to;
import std.exception : enforce;
import std.string : join;
import std.variant : Variant;
import std.datetime : DateTime;
import std.base64 : Base64;

class EncoderException : XmlRpcException
{
    private this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}

Element encodeCall(MethodCallData call)
{
    auto root = new Element("methodCall");
    root ~= new Element("methodName", call.name);
    root ~= encodeParams(call.params);
    return root;
}

Element encodeResponse(MethodResponseData resp)
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
    {
        root ~= encodeParams(resp.params);
    }
    return root;
}

private
{
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
        if (param.type() == typeid(XmlRpcStruct))
            node ~= encodeStructValue(param);
        else if (param.type() == typeid(XmlRpcArray))
            node ~= encodeArrayValue(param);
        else
            node ~= encodePrimitiveValue(param);
        return node;
    }
    
    Element encodeStructValue(Variant param)
    {
        auto structNode = new Element("struct");
        foreach (string key, ref Variant value; param.get!XmlRpcStruct())
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
        {
            data ~= encodeValue(value);
        }
        array ~= data;
        return array;
    }
    
    Element encodePrimitiveValue(Variant param)
    {
        // Almost everything converts to boolean, thus we need to check the exact type match
        if (param.type() == typeid(bool))
            return new Element("boolean", param.get!bool() ? "1" : "0");
        
        // Boolean implicitly converts to integer, thus the former must be checked first
        if (param.convertsTo!int())
            return new Element("int", to!string(param.get!int()));
        
        if (param.convertsTo!double())
            return new Element("double", to!string(param.get!double()));
        
//        if (convertsToString(param))
//            return new Element("string", getString(param));
        if (param.convertsTo!string())
            return new Element("string", to!string(param));
        
        if (param.convertsTo!DateTime())
        {
            auto dt = param.get!DateTime();
            return new Element("dateTime.iso8601", dt.toISOString());
        }
        
        if (param.convertsTo!(ubyte[])())
        {
            ubyte[] source = param.get!(ubyte[])();
            char[] encoded = Base64.encode(source);
            return new Element("base64", cast(string)encoded);
        }
        
        if (param.convertsTo!(typeof(null)) && param.get!(typeof(null))() == null)
            return new Element("nil");
        
        throw new EncoderException(format("Unable to encode the value of type %s", param.type()));
    }
}


version (xmlrpc_unittest) unittest
{
    import std.stdio;
    import xmlrpc.decoder;
    static import xmlrpc.paramconv;
    
    string pretty(in Element e)
    {
        return join(e.pretty(4), "\n");
    }
    
    void assertResultsEqual(T)(T a, T b)
    {
        //writeln(a.toString());
        //writeln(b.toString());
        // Ridiculous. Variant type does not compare arrays properly:
        assert(a.toString() == b.toString());
    }
    
    // Hardcore parameter set
    Variant[] params = [Variant(123), xmlrpc.decoder.Variant("Our sun is dying."),
                        Variant([Variant(123), Variant(12.3), Variant("123"), Variant(0), Variant(0.0)]),
                        Variant(DateTime(2013, 8, 25, 13, 38, 42)),
                        Variant(cast(ubyte[])x"de ad be ef"),
                        Variant(["null":Variant(null)]),
                        Variant(["true":Variant(true)]),
                        Variant(["false":Variant(false)]),
                        Variant(["we":Variant(["need":Variant("to go deeper")])])];
    
    /*
     * Call
     */
    auto methodCallData = MethodCallData("theMethod", params);
    auto encoded = encodeCall(methodCallData);
    //writefln(pretty(encoded));
    MethodCallData decodedCall = decodeCall(pretty(encoded));
    assertResultsEqual(decodedCall, methodCallData);
    
    /*
     * Response
     */
    auto methodResponseData = MethodResponseData(false, params);
    encoded = encodeResponse(methodResponseData);
    MethodResponseData decodedResponse = decodeResponse(pretty(encoded));
    assertResultsEqual(decodedResponse, methodResponseData);
    
    /*
     * Fault response
     */
    auto faultParams = xmlrpc.paramconv.paramsToVariantArray(["faultCode": Variant(42),
                                                              "faultString": Variant("Fire in oxygen garden.")]);
    methodResponseData = MethodResponseData(true, faultParams);
    encoded = encodeResponse(methodResponseData);
    decodedResponse = decodeResponse(pretty(encoded));
    //writeln(pretty(encoded));
    //writeln(decodedResponse.toString());
    assert(decodedResponse.fault);
    assert(decodedResponse.params.length == 1);
    assert(decodedResponse.params[0]["faultCode"] == 42);
    //assert(getString(decodedResponse.params[0]["faultString"]) == "Fire in oxygen garden.");
    assert(decodedResponse.params[0]["faultString"] == "Fire in oxygen garden.");
}
