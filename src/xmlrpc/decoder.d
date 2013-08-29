/*
 * XMLRPC decoder
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.decoder;

import xmlrpc.exception;
import xmlrpc.data;
import std.stdio : writeln;
import std.xml : Element, Document;
import std.conv : to;
import std.exception : enforce;
import std.variant : Variant;
import std.typecons : Rebindable;
import std.string : format, strip;
import std.array : replace;
import std.datetime : DateTime;
import std.base64 : Base64;

class DecoderException : XmlRpcException
{
    private this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}

package:

MethodCallData decodeCall(in Element call)
{
    MethodCallData result;
    result.name = find(call, "methodName").text();
    result.params = decodeParams(tryFind(call, "params"));
    return result;
}

auto decodeCall(string text)
{
    return decodeCall(new Document(text));
}

MethodResponseData decodeResponse(in Element resp)
{
    MethodResponseData result;
    
    const fault = tryFind(resp, "fault");
    if (fault)
    {
        result.fault = true;
        result.params = decodeFault(fault);
    }
    else
    {
        result.fault = false;
        result.params = decodeParams(tryFind(resp, "params"));
    }
    return result;
}

auto decodeResponse(string text)
{
    return decodeResponse(new Document(text));
}

private:

auto decodeParams(in Element params)
{
    Variant[] result;
    if (params is null)      // Parameters are optional
        return result;
    
    foreach (param; params.elements)
    {
        if (param.tag.name != "param")
        {
            debug (xmlrpc)
                writeln("Decoder: Invalid parameter tag: ", param.tag.name);
            continue;
        }
        debug (xmlrpc)
        {
            if (param.elements.length != 1)
                writeln("Decoder: Parameter must contain exactly one sub-element, not ", param.elements.length);
        }
        result ~= decodeParam(param);
    }
    return result;
}

auto decodeFault(in Element fault)
{
    Variant[] result;
    auto value = tryFind(fault, "value");
    if (value)
        result ~= decodeValue(value);
    return result;
}

auto decodeParam(in Element param)
{
    return decodeValue(find(param, "value"));
}

Variant decodeValue(in Element value)
{
    Rebindable!(const Element) storage;
    string type;
    if (value.elements.length == 0)   // Default is string
    {
        storage = value;
        type = "string";
    }
    else
    {
        enforce(value.elements.length == 1, new DecoderException("Value tag must have at most one sub-element"));
        storage = value.elements[0];
        type = storage.tag.name;
    }
    
    if (type == "struct")
        return decodeStructValue(storage);
    
    if (type == "array")
        return decodeArrayValue(storage);
    
    return decodePrimitiveValue(storage, type);
}

Variant decodeStructValue(in Element storage)
{
    Variant[string] result;
    foreach (member; storage.elements)
    {
        if (member.tag.name != "member")
        {
            debug (xmlrpc)
                writeln("Decoder: Invalid struct subelement: ", member.tag.name);
            continue;
        }
        const nameNode = find(member, "name");
        const valueNode = find(member, "value");
        const key = nameNode.text();
        Variant value = decodeValue(valueNode);
        result[key] = value;
    }
    return Variant(result);
}

Variant decodeArrayValue(in Element storage)
{
    Variant[] result;
    const data = find(storage, "data");
    foreach (value; data.elements)
    {
        if (value.tag.name != "value")
        {
            debug (xmlrpc)
                writeln("Decoder: Invalid array member tag: ", value.tag.name);
            continue;
        }
        result ~= decodeValue(value);
    }
    return Variant(result);
}

Variant decodePrimitiveValue(in Element storage, string type)
{
    string data = storage.text();
    switch (type)
    {
        case "int":
        case "i4":
            return Variant(to!int(data));
        
        case "i8":
            return Variant(to!long(data));
        
        case "string":
            return Variant(data);
        
        case "double":
            return Variant(to!double(data));
        
        case "boolean":
            debug (xmlrpc)
            {
                if (data != "0" && data != "1")
                    writeln("Decoder: Invalid literal for boolean: " ~ data);
            }
            return Variant(to!int(data) != 0);            // Sloppy conversion
        
        case "dateTime.iso8601":
            data = replace(data, ":", "");                // Conversion to the basic format
            data = replace(data, "-", "");
            return Variant(DateTime.fromISOString(data));
        
        case "base64":
            return Variant(Base64.decode(data));
        
        case "nil":
            return Variant(null);
        
        default:
            throw new DecoderException("Unknown XMLRPC type " ~ type);
    }
}

const(Element) tryFind(in Element e, string tag)
{
    foreach (sub; e.elements)
        if (sub.tag.name == tag)
            return sub;
    return null;
}

const(Element) find(in Element e, string tag)
{
    const res = tryFind(e, tag);
    enforce(res !is null, new DecoderException(format("Element <%s> does not contain <%s>", e.tag.name, tag)));
    return res;
}

version (xmlrpc_unittest) unittest
{
    /*
     * Call
     */
    auto s = `<methodCall>
  <methodName>examples.getStateName</methodName>
  <params>
    <param>
        <value><i4>40</i4></value>
    </param>
    <param>
        <value>South Dakota</value>
    </param>
  </params>
</methodCall>`;
    auto call = decodeCall(s);
    assert(call.name == "examples.getStateName");
    assert(call.params[0] == 40);
    assert(call.params[1] == "South Dakota");
    
    /*
     * OK response
     */
    s = `<methodResponse>
  <params>
    <param>
        <value>
          <array>
            <data>
              <value><i4>12</i4></value>
              <value><string>Egypt</string></value>
              <value>Egypt</value>
              <value><boolean>0</boolean></value>
              <value><i4>-31</i4></value>
            </data>
          </array>
        </value>
    </param>
  </params>
</methodResponse>`;
    auto resp = decodeResponse(s);
    assert(!resp.fault);
    assert(resp.params[0][0] == 12);
    assert(resp.params[0][1] == "Egypt");
    assert(resp.params[0][2] == "Egypt");
    assert(resp.params[0][3] == false);
    assert(resp.params[0][4] == -31);
    
    /*
     * OK response
     */
    s = `<methodResponse>
  <params>
    <param>
        <value>40</value>
    </param>
    <param>
        <value><string>South Dakota</string></value>
    </param>
  </params>
</methodResponse>`;
    resp = decodeResponse(s);
    assert(!resp.fault);
    assert(resp.params[0] == "40");
    assert(resp.params[1] == "South Dakota");
    
    /*
     * Fault response
     */
    s = `<methodResponse>
   <fault>
      <value>
         <struct>
            <member>
               <name>faultCode</name>
               <value><int>4</int></value>
            </member>
            <member>
               <name>faultString</name>
               <value><string>Negative, Cassie. Computer control.</string></value>
            </member>
         </struct>
      </value>
   </fault>
</methodResponse>`;
    resp = decodeResponse(s);
    assert(resp.fault);
    assert(resp.params[0]["faultCode"] == 4);
    assert(resp.params[0]["faultString"] == "Negative, Cassie. Computer control.");
    
    /*
     * Call
     */
    s = `<methodCall>
  <methodName>theMethod</methodName>
  <params>
    <param>
      <value>
         <struct>
            <member><name>arrays</name>
            <value>
               <array>
                  <data>
                     <value><array><data><value><int>10</int></value></data></array></value>
                     <value><array><data><value><int>15</int></value></data></array></value>
                  </data>
               </array>
            </value>
            </member>
            <member><name>question</name><value>Kaneda, what do you see? Kaneda!</value></member>
         </struct>
      </value>
    </param>
    <param><value><dateTime.iso8601>19980717T14:08:55</dateTime.iso8601></value></param>
  </params>
</methodCall>`;
    call = decodeCall(s);
    assert(call.name == "theMethod");
    Variant arrays = call.params[0]["arrays"];
    assert(arrays[0][0] == 10);
    assert(arrays[1][0] == 15);
    assert(call.params[0]["question"] == "Kaneda, what do you see? Kaneda!");
    assert(call.params[1] == DateTime(1998, 7, 17, 14, 8, 55));
}
