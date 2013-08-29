/*
 * XMLRPC client
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.client;

import xmlrpc.encoder : encodeCall;
import xmlrpc.decoder : decodeResponse;
import xmlrpc.data : MethodCallData, MethodResponseData;
import xmlrpc.paramconv : paramsToVariantArray, variantArrayToParams;
import xmlrpc.exception : XmlRpcException;
import std.datetime : Duration, dur;
import std.variant : Variant;
import std.string : format;
import std.stdio : writefln;
import std.conv : to;
static import curl = std.net.curl;

pragma(lib, "curl");

class Client
{
    this(string serverUri, Duration timeout = dur!"seconds"(10))
    {
        serverUri_ = serverUri;
        timeout_ = timeout;
    }
    
    final MethodResponseData rawCall(MethodCallData callData, bool throwOnMethodFault = false)
    {
        const requestString = encodeCall(callData);
        
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
    
    template call(string methodName, ReturnTypes...)
    {
        final auto call(Args...)(Args args)
        {
            auto requestParams = paramsToVariantArray(args);
            auto callData = MethodCallData(methodName, requestParams);
            Variant[] vars = rawCall(callData, true).params;
            
            // Perform automatic return type conversion if requested, otherwise return Variant[] as is
            static if (ReturnTypes.length == 0)
            {
                return vars;
            }
            else
            {
                return variantArrayToParams!(ReturnTypes)(vars);
            }
        }
    }
    
    @property string serverUri() const { return serverUri_; }
    
    @property Duration timeout() const { return timeout_; }
    @property void timeout(Duration timeout) { timeout_ = timeout; }
    
private:
    string performHttpRequest(string data)
    {
        try
        {
            auto http = curl.HTTP(serverUri_);
            http.operationTimeout = timeout_;
            return to!string(curl.post(serverUri_, data, http));
        }
        catch (curl.CurlException ex)
            throw new TransportException(ex);
    }
    
    const string serverUri_;
    Duration timeout_;
}

class MethodFaultException : XmlRpcException
{
    private this(MethodCallData callData, MethodResponseData responseData)
    {
        const msg = format("XMLRPC method failure: %s / Call: %s", responseData.toString(), callData.toString());
        super(msg);
        
        if (responseData.params.length > 0)
            value = responseData.params[0];
        
        if (responseData.params.length != 1)
        {
            debug (xmlrpc)
                writefln("Wrong number of values in the method fault response: %s", responseData.toString());
        }
    }
    
    Variant value;
}

class TransportException : XmlRpcException
{
    private this(Exception nested, string file = __FILE__, size_t line = __LINE__)
    {
        this.nested = nested;
        super(nested.msg, file, line);
    }
    
    Exception nested;
}

version (xmlrpc_client_unittest) unittest
{
    import std.stdio : writeln;
    import xmlrpc.data : prettyParams;
    import std.exception : assertThrown;
    import std.math : approxEqual;
    
    auto client = new Client("http://1.2.3.4", dur!"msecs"(10));
    
    // Should timeout:
    assertThrown!TransportException(client.call!"boo"());
    
    client = new Client("http://phpxmlrpc.sourceforge.net/server.php");
    
    // Should fail and throw:
    try
    {
        Variant[] raw = client.call!"nonExistentMethod"("Wrong", "parameters");
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
    double resp1 = client.call!("examples.addtwodouble", double)(534.78, 168.36);
    assert(approxEqual(resp1, 703.14));
    
    string resp2 = client.call!("examples.stringecho", string)("Hello Galaxy!");
    assert(resp2 == "Hello Galaxy!");
    
    real resp2_1 = client.call!("examples.stringecho", real)("123.456");   // IMPLICIT CONVERSION
    assert(approxEqual(resp2_1, 123.456));
    
    int[string] resp3 = client.call!("validator1.countTheEntities", int[string])("A < C ' > 45\" 12 &");
    assert(1 == resp3["ctQuotes"]);
    assert(1 == resp3["ctLeftAngleBrackets"]);
    assert(1 == resp3["ctRightAngleBrackets"]);
    assert(1 == resp3["ctAmpersands"]);
    assert(1 == resp3["ctApostrophes"]);
    
    int[string][] arrayOfStructs = [
        ["moe": 1, "larry": 2, "curly": 3],
        ["moe": -98, "larry": 23, "curly": -6]
    ];
    int resp4 = client.call!("validator1.arrayOfStructsTest", int)(arrayOfStructs);
    assert(resp4 == -3);
}
