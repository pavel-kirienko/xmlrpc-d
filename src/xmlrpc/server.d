/*
 * XMLRPC server
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.server;

import xmlrpc.encoder : encodeResponse;
import xmlrpc.decoder : decodeCall;
import xmlrpc.data : MethodCallData, MethodResponseData;
import xmlrpc.paramconv : paramsToVariantArray, variantArrayToParams;
import xmlrpc.error : XmlRpcException, MethodFaultException, FciFaultCodes, makeFaultValue;
import std.exception : enforce;
import std.variant : Variant, VariantException;
import std.string : format;
import std.conv : to;
import std.stdio : writefln, write;
import std.traits : isCallable, ParameterTypeTuple, ReturnType;

alias void delegate(string) ErrorLogHandler;
alias Variant[] delegate(Variant[]) RawMethodHandler;

@trusted:

class Server
{
    /**
     * Params:
     *     errorLogHandler = Error logging delegate. By default logs are directed into stdout.
     */
    this(ErrorLogHandler errorLogHandler = null)
    {
        if (!errorLogHandler)
            errorLogHandler = (msg) => write(msg);
        errorLogHandler_ = errorLogHandler;
        addSystemMethods(this);
    }
    
    /**
     * Handles one XML-RPC request. Can be used with HTTP server directly.
     * Params:
     *     encodedRequest = Raw request, encoded in XML
     * Returns: XML-encoded response
     */
    string handleRequest(string encodedRequest)
    {
        try
        {
            // Decode the request
            MethodCallData callData;
            try
                callData = decodeCall(encodedRequest);
            catch (Exception ex)
                throw new MethodFaultException(ex.msg, FciFaultCodes.serverErrorInvalidXmlRpc);
            debug (xmlrpc)
                writefln("server <== %s", callData.toString());
            
            MethodResponseData responseData = callMethod(callData);
            
            // Encode the response
            debug (xmlrpc)
                writefln("server ==> %s", responseData.toString());
            return encodeResponse(responseData);
        }
        catch (MethodFaultException ex)
        {
            tryLogError("Method fault: %s", ex.msg);
            auto responseData = makeMethodFaultResponse(ex);
            return encodeResponse(responseData);
        }
        catch (Exception ex)
        {
            tryLogError("Server exception: %s", ex);
            MethodResponseData responseData;
            responseData.fault = true;
            responseData.params ~= makeFaultValue(ex.msg, FciFaultCodes.serverErrorInternalXmlRpcError);
            return encodeResponse(responseData);
        }
    }
    
    /**
     * Adds one method.
     * Throws: MethodExistsException if method already registered
     */
    void addRawMethod(RawMethodHandler handler, string name, string help = "", string[][] signatures = null)
    {
        enforce(name.length, new XmlRpcException("Method name must not be empty"));
        if (name in methods_)
            throw new MethodExistsException(name);
        methods_[name] = MethodInfo(handler, help, signatures);
    }
    
    /**
     * Removes method if exists, otherwise does nothing
     * Returns: True if the method was removed, false otherwise.
     */
    nothrow bool removeMethod(string name)
    {
        return methods_.remove(name);
    }
    
    /**
     * Lists all registered methods, including system methods.
     */
    @property string[] methods() const { return methods_.keys(); }
    
    /**
     * Configures error logging. 'null' disables logging.
     * Examples:
     * --------------------
     * server.errorLogHandler = (msg) => write(msg);  // Write to stdout
     * server.errorLogHandler = null;                 // Disable logging
     * --------------------
     */
    @property void errorLogHandler(ErrorLogHandler lh) { errorLogHandler_ = lh; }
    @property nothrow ErrorLogHandler errorLogHandler() { return errorLogHandler_; }
    
private:
    MethodResponseData callMethod(MethodCallData callData)
    {
        try
        {
            const methodInfoPtr = callData.name in methods_;
            if (methodInfoPtr is null)
            {
                const msg = "Unknown method: " ~ callData.name;
                throw new MethodFaultException(msg, FciFaultCodes.serverErrorMethodNotFound);
            }
            enforce(methodInfoPtr.handler != null, new XmlRpcException("Impossible happens!"));
            
            MethodResponseData responseData;
            responseData.params = methodInfoPtr.handler(callData.params);
            return responseData;
        }
        catch (MethodFaultException ex)
        {
            throw ex;  // Propagate further, no conversion required
        }
        catch (Exception ex)
        {
            const msg = format("%s:%s: %s: %s", ex.file, ex.line, typeid(ex), ex.msg);
            throw new MethodFaultException(msg, FciFaultCodes.applicationError);
        }
    }
    
    nothrow void tryLogError(S...)(string fmt, S s)
    {
        if (errorLogHandler_ is null)
            return;
        try
            errorLogHandler_(format(fmt, s) ~ "\n");
        catch (Exception ex)
        {
            debug (xmlrpc)
            {
                try writefln("Log handler exception: %s", ex);
                catch (Exception) { }
            }
        }
    }
    
    static struct MethodInfo
    {
        RawMethodHandler handler;
        string help;
        string[][] signatures;
    }
    
    ErrorLogHandler errorLogHandler_;
    MethodInfo[string] methods_;
}

class MethodExistsException : XmlRpcException
{
    private this(string methodName)
    {
        this.methodName = methodName;
        super("Method already exists: " ~ methodName);
    }
    
    string methodName;
}

/**
 * Registers anything callable as XML-RPC method.
 * By default method name is derived from the callable's identifier.
 * 
 * We can't use member function here because that doesn't work with local handlers:
 * Error: template instance addMethod!(method) cannot use local 'method' as parameter to non-global template <...>
 */
void addMethod(alias method, string name = __traits(identifier, method))(Server server, string help = "",
                                                                         string[][] signatures = null)
{
    static assert(name.length, "Method name must not be empty");
    auto handler = makeRawMethod!method();
    server.addRawMethod(handler, name, help, signatures);
}

private:

/**
 * Takes anything callable at compile-time, returns delegate that conforms RawMethodHandler type.
 * The code that converts XML-RPC types into the native types and back will be generated at compile time.
 */
RawMethodHandler makeRawMethod(alias method)()
{
    static assert(isCallable!method, "Method handler must be callable");
    
    alias ParameterTypeTuple!method Input;
    alias ReturnType!method Output;
    
    auto tryVariantArrayToParams(Args...)(Variant[] variants)
    {
        try
            return variantArrayToParams!(Args)(variants);
        catch (Exception ex)
            throw new MethodFaultException(ex.msg, FciFaultCodes.serverErrorInvalidMethodParams);
    }
    
    return (Variant[] inputVariant)  // Well, the life is getting tough now.
    {
        static if (Input.length == 0)
        {
            enforce(inputVariant.length == 0,
                new MethodFaultException("Method expects no arguments", FciFaultCodes.serverErrorInvalidMethodParams));
            
            static if (is(Output == void))
                method();
            else
                Output output = method();
        }
        else
        {
            Input input = tryVariantArrayToParams!(Input)(inputVariant);
            static if (is(Output == void))
                method(input);
            else
                Output output = method(input);
        }
        
        static if (is(Output == void))
        {
            Variant[] dummy;
            return dummy;
        }
        else static if (is(typeof( paramsToVariantArray(output.expand) )))
            return paramsToVariantArray(output.expand);
        else
            return paramsToVariantArray(output);
    };
}

MethodResponseData makeMethodFaultResponse(MethodFaultException ex)
{
    MethodResponseData responseData;
    responseData.fault = true;
    responseData.params ~= ex.value;
    return responseData;
}

void addSystemMethods(Server server)
{
    Server.MethodInfo* findMethod(string methodName)
    {
        auto infoPtr = methodName in server.methods_;
        const msg = "No such method: " ~ methodName;
        enforce(infoPtr, new MethodFaultException(msg, -1));
        return infoPtr;
    }
    
    string[] listMethods() { return server.methods_.keys(); }
    
    string methodHelp(string name) { return findMethod(name).help; }
    
    Variant methodSignature(string name)              // This one is tricky
    {
        auto signatures = findMethod(name).signatures;
        if (signatures.length == 0)
            return Variant("undef");                  // Return type is computed at runtime
        Variant[] variantSignatures;
        variantSignatures.length = signatures.length;
        foreach (signIndex, sign; signatures)
        {
            Variant[] variantSign;
            variantSign.length = sign.length;
            foreach (typeIndex, type; sign)
                variantSign[typeIndex] = Variant(type);
            variantSignatures[signIndex] = variantSign;
        }
        return Variant(variantSignatures); // Array of arrays of strings
    }
    
    string[string][string] getCapabilities()
    {
        string[string][string] capabilities;
        void cap(string name, string specUrl, string specVersion)
        {
            capabilities[name] = ["specUrl": specUrl, "specVersion": specVersion];
        }
        cap("xmlrpc", "http://www.xmlrpc.com/spec", "1");
        cap("introspection", "http://phpxmlrpc.sourceforge.net/doc-2/ch10.html", "2");
        cap("system.multicall", "http://www.xmlrpc.com/discuss/msgReader$1208", "1");
        return capabilities;
    }
    
    Variant[] multicall(Variant[] calls)
    {
        MethodResponseData invoke(Variant callParams)
        {
            MethodCallData callData;
            try
            {
                callData.name = callParams["methodName"].get!string();
                callData.params = callParams["params"].get!(Variant[])();
            }
            catch (VariantException ex)
                throw new MethodFaultException(ex.msg, FciFaultCodes.serverErrorInvalidMethodParams);
            
            if (callData.name == "system.multicall")
                throw new MethodFaultException("Recursive system.multicall is forbidden", -1);
            
            return server.callMethod(callData);
        }
        Variant[] responses;
        responses.length = calls.length;
        foreach (idx, call; calls)
        {
            MethodResponseData response;
            try
                response = invoke(call);
            catch (MethodFaultException ex)
                response = makeMethodFaultResponse(ex);
            
            if (response.fault)
            {
                assert(response.params.length == 1, "Invalid fault from server: " ~ to!string(response.params));
                responses[idx] = response.params[0];
            }
            else
                responses[idx] = response.params;
        }
        return responses;
    }
    
    server.addMethod!(listMethods, "system.listMethods")();
    server.addMethod!(methodHelp, "system.methodHelp")();
    server.addMethod!(methodSignature, "system.methodSignature")();
    server.addMethod!(getCapabilities, "system.getCapabilities")();
    server.addMethod!(multicall, "system.multicall")();
}

version (xmlrpc_unittest) unittest
{
    import xmlrpc.encoder : encodeCall;
    import xmlrpc.decoder : decodeResponse;
    import std.math : approxEqual;
    import std.typecons : tuple;
    import std.exception : assertThrown;
    import std.algorithm : canFind;
    import std.stdio : writeln;
    
    /*
     * Issue a request on the server instance
     */
    template call(string methodName, ReturnTypes...)
    {
        auto call(Args...)(Args args)
        {
            auto requestParams = paramsToVariantArray(args);
            auto callData = MethodCallData(methodName, requestParams);
            const requestString = encodeCall(callData);
            
            const responseString = server.handleRequest(requestString);
            
            auto responseData = decodeResponse(responseString);
            if (responseData.fault)
                throw new MethodFaultException(responseData.params[0]);
            
            static if (ReturnTypes.length == 0)
            {
                assert(responseData.params.length == 0);
                return;
            }
            else
            {
                return variantArrayToParams!(ReturnTypes)(responseData.params);
            }
        }
    }
    
    auto server = new Server();
    
    /*
     * Various combinations of the argument types and the return types are tested below.
     * This way we can be sure that the magic inside makeRawMethod() works as expected.
     */
    // Returns tuple
    auto swap(int a, int b) { return tuple(b, a); }
    server.addMethod!swap();
    auto resp1 = call!("swap", int, int)(123, 456);
    assert(resp1[0] == 456);
    assert(resp1[1] == 123);
    
    // Returns scalar
    auto doWeirdThing(real a, real b, real c) { return a * b + c; }
    server.addMethod!doWeirdThing();
    double resp2 = call!("doWeirdThing", double)(1.2, 3.4, 5.6);
    assert(approxEqual(resp2, 9.68));
    
    // Takes nothing
    auto ultimateAnswer() { return 42; }
    server.addMethod!ultimateAnswer();
    assert(call!("ultimateAnswer", int)() == 42);
    
    // Returns nothing
    void blackHole(dstring s) { assert(s == "goodbye"d); }
    server.addMethod!blackHole();
    call!"blackHole"("goodbye");
    
    // Takes nothing, returns nothing
    void nothingGetsNothingGives() { writefln("Awkward."); }
    server.addMethod!nothingGetsNothingGives();
    call!"nothingGetsNothingGives"();
    
    /*
     * Make sure that the methods can be removed properly
     */
    assert(server.removeMethod("nothingGetsNothingGives"));
    assert(!server.removeMethod("nothingGetsNothingGives"));
    
    /*
     * Error handling
     */
    int methodFaultErrorCode(Expr, size_t line = __LINE__)(lazy Expr expression)
    {
        try
            expression();
        catch (MethodFaultException ex)
            return ex.value["faultCode"].get!int();
        assert(false, to!string(line));
    }
    
    // Non-existent method
    auto errcode = methodFaultErrorCode(call!"nothingGetsNothingGives"());
    assert(errcode == FciFaultCodes.serverErrorMethodNotFound);
    
    // Wrong parameter types, non-convertible to int
    errcode = methodFaultErrorCode(call!"swap"("ck", "fu"));
    assert(errcode == FciFaultCodes.serverErrorInvalidMethodParams);
    
    // Wrong number of arguments
    errcode = methodFaultErrorCode(call!"swap"("ck", "fu", "give"));
    assert(errcode == FciFaultCodes.serverErrorInvalidMethodParams);
    
    errcode = methodFaultErrorCode(call!"swap"());
    assert(errcode == FciFaultCodes.serverErrorInvalidMethodParams);
    
    errcode = methodFaultErrorCode(call!("ultimateAnswer", int)(123, 456));
    assert(errcode == FciFaultCodes.serverErrorInvalidMethodParams);
    
    // Malformed XML
    auto responseString = server.handleRequest("I am broken XML. <phew>");
    auto responseData = decodeResponse(responseString);
    assert(responseData.fault);
    errcode = responseData.params[0]["faultCode"].get!int();
    assert(errcode == FciFaultCodes.serverErrorInvalidXmlRpc);
    
    // Application error
    void throwWeirdException() { throw new Exception("Come break me down bury me bury me"); }
    server.addMethod!throwWeirdException();
    errcode = methodFaultErrorCode(call!"throwWeirdException"());
    assert(errcode == FciFaultCodes.applicationError, to!string(errcode));
    
    // Application throws an FCI error
    void throwFciException() { throw new MethodFaultException("Hi!", 1); }
    server.addMethod!throwFciException();
    errcode = methodFaultErrorCode(call!"throwFciException"());
    assert(errcode == 1);
    
    /*
     * Introspection
     */
    auto capabilities = call!("system.getCapabilities", string[string][string])();
    assert(capabilities.length == 3);
    assert(capabilities["xmlrpc"] == ["specUrl": "http://www.xmlrpc.com/spec", "specVersion": "1"]);
    assert(capabilities["introspection"] ==
           ["specUrl": "http://phpxmlrpc.sourceforge.net/doc-2/ch10.html", "specVersion": "2"]);
    assert(capabilities["system.multicall"] ==
           ["specUrl": "http://www.xmlrpc.com/discuss/msgReader$1208", "specVersion": "1"]);
    
    // Playing with one method and system.listMethods()
    assertThrown!MethodExistsException(server.addMethod!swap());
    server.removeMethod("swap");
    string[] methods = call!("system.listMethods", string[])();
    assert(!canFind(methods, "swap"));
    server.addMethod!swap("Help string for swap", [["int, int", "int", "int"]]);
    methods = call!("system.listMethods", string[])();
    assert(canFind(methods, "swap"));
    
    // Checking the help strings
    assert(call!("system.methodHelp", string)("swap") == "Help string for swap");
    assert(call!("system.methodHelp", string)("ultimateAnswer") == "");
    errcode = methodFaultErrorCode(call!("system.methodHelp", string)("noSuchMethod"));
    assert(errcode == -1);
    
    // Checking the signatures
    string[][] signatures = call!("system.methodSignature", string[][])("swap");    // Return type is string[][]
    assert(signatures == [["int, int", "int", "int"]]);
    
    string noSignature = call!("system.methodSignature", string)("ultimateAnswer"); // Return type is string
    assert(noSignature == "undef");
    
    /*
     * Multicall
     */
    Variant[] multicallArgs;
    void addCall(Args...)(string method, Args args)
    {
        auto call = Variant([
            "methodName": Variant(method),
            "params": Variant(paramsToVariantArray(args))
        ]);
        multicallArgs ~= call;
    }
    addCall("swap", 123, 456);
    addCall("ultimateAnswer");
    addCall("ultimateAnswer", "unexpected");
    addCall("system.multicall");    // will fail
    addCall("throwWeirdException");
    
    Variant[] multicallResponses = call!("system.multicall", Variant[])(multicallArgs);
    auto fetchMulticallResponse(Types...)()
    {
        auto v = multicallResponses[0].get!(Variant[])();
        multicallResponses = multicallResponses[1..$];
        return variantArrayToParams!(Types)(v);
    }
    auto assertMulticallFault(int errorCode)
    {
        auto v = multicallResponses[0];
        multicallResponses = multicallResponses[1..$];
        writeln("Mulitcall fault: ", v["faultString"].get!string());
        assert(errorCode == v["faultCode"].get!int());
    }
    // swap
    auto mcresp = fetchMulticallResponse!(int, int)();
    assert(mcresp[0] == 456);
    assert(mcresp[1] == 123);
    // ultimateAnswer
    assert(fetchMulticallResponse!(int)() == 42);
    // ultimateAnswer - unepected arg
    assertMulticallFault(FciFaultCodes.serverErrorInvalidMethodParams);
    // system.multicall
    assertMulticallFault(-1);
    // throwWeirdException
    assertMulticallFault(FciFaultCodes.applicationError);
    
    // Make sure the multicall will not fail on empty request
    Variant[] emptyMulticallArgs;
    assert(call!("system.multicall", Variant[])(emptyMulticallArgs).length == 0);
}
