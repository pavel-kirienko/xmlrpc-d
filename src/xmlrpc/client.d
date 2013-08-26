/*
 * XMLRPC client
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.client;

import xmlrpc.encoder : encodeCall;
import xmlrpc.decoder : decodeResponse;
import xmlrpc.data : MethodCallData, MethodResponseData;
import xmlrpc.paramconv : paramsToVariantArray;
import xmlrpc.exception : XmlRpcException;
import std.datetime : Duration, dur;
import std.variant : Variant;
import std.string : format;
import std.stdio : writefln;
static import curl = std.net.curl;

pragma(lib, "curl");

class Client
{
    this(string serverUri, Duration timeout = dur!"seconds"(10))
    {
        this.serverUri = serverUri;
        this.timeout = timeout;
    }
    
    final MethodResponseData rawCall(MethodCallData callData, bool throwOnMethodFault = false)
    {
        auto request = encodeCall(callData);
        immutable requestString = request.toString();
        
        debug (xmlrpc)
            writefln("client ==> %s", callData.toString());
        
        auto responseString = performHttpRequest(requestString);
        auto responseData = decodeResponse(responseString);
        
        debug (xmlrpc)
            writefln("client <== %s", responseData.toString());
        
        if (throwOnMethodFault && responseData.fault)
            throw new MethodFaultException(callData, responseData);
        
        return responseData;
    }
    
    final Variant[] call(string methodName, Args...)(Args args)
    {
        auto requestParams = paramsToVariantArray(args);
        auto callData = MethodCallData(methodName, requestParams);
        return rawCall(callData, true).params;
    }
    
private:
    string performHttpRequest(string data)
    {
        try
        {
            auto http = curl.HTTP(serverUri);
            http.operationTimeout = timeout;
            return cast(string)curl.post(serverUri, data, http);
        }
        catch (curl.CurlException ex)
            throw new TransportException(ex);
    }
    
    string serverUri;
    Duration timeout;
}

class MethodFaultException : XmlRpcException
{
    private this(MethodCallData callData, MethodResponseData responseData)
    {
        const msg = format("XMLRPC method failure: %s / Call: %s",
                           responseData.toString(), callData.toString());
        super(msg);
        
        if (responseData.params.length > 0)
            value = responseData.params[0];
    }
    
    Variant value;
}

class TransportException : XmlRpcException
{
    this(Exception next, string file = __FILE__, size_t line = __LINE__)
    {
        super(next.msg, file, line, next);
    }
}

version (xmlrpc_unittest) unittest
{
    import std.stdio : writeln;
    import xmlrpc.data : prettyParams;
    import std.exception : assertThrown;
    
    auto client = new Client("http://1.2.3.4", dur!"msecs"(10));
    
    // Should timeout:
    assertThrown!TransportException(client.call!"boo"());
    
    client = new Client("http://phpxmlrpc.sourceforge.net/server.php");
    
    // Should fail and throw:
    try
    {
        client.call!"nonExistentMethod"("Wrong", "parameters");
        assert(false);
    }
    catch (MethodFaultException ex)
    {
        assert(ex.value["faultCode"] == 1);
        assert(ex.value["faultString"].length);
    }
    
    /*
     * Misc logic checks
     */
    auto response = client.call!"examples.addtwodouble"(534.78, 168.36);
    assert(response.length == 1);
    assert(response[0] == 703.14);
    
    response = client.call!"examples.stringecho"("Hello Galaxy!");
    assert(response.length == 1);
    assert(response[0] == "Hello Galaxy!");
    
    response = client.call!"validator1.countTheEntities"("A < bunch ' of innocent >\" bystanders &");
    assert(response.length == 1);
    assert(1 == response[0]["ctQuotes"]);
    assert(1 == response[0]["ctLeftAngleBrackets"]);
    assert(1 == response[0]["ctRightAngleBrackets"]);
    assert(1 == response[0]["ctAmpersands"]);
    assert(1 == response[0]["ctApostrophes"]);
    
    int[string][] arrayOfStructs = [
        ["moe": 1, "larry": 2, "curly": 3],
        ["moe": -98, "larry": 23, "curly": -6]
    ];
    response = client.call!"validator1.arrayOfStructsTest"(arrayOfStructs);
    assert(response.length == 1);
    assert(response[0] == -3);
}
