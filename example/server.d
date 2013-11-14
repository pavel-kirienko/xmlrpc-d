/*
 * XMLRPC server example
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

import std.conv;
import std.stdio;
import std.string;
import std.typecons;
import std.algorithm;
import std.datetime;
import std.variant;

import xmlrpc.server : Server, addMethod;
import xmlrpc.error : MethodFaultException, FciFaultCodes;
import http_server_bob : HttpServer, HttpResponseData;

void main(string[] args)
{
    /*
     * Initializing the XMLRPC server
     */
    auto xmlrpc = new Server();
    xmlrpc.errorLogHandler = (msg) => write(msg);  // Setting up the error message handler (muted by default)
    
    /*
     * Initializing the HTTP server, connecting it with XMLRPC server
     */
    const port = (args.length > 1) ? to!ushort(args[1]) : cast(ushort)8000;
    auto httpServer = new HttpServer(port);
    
    httpServer.requestHandler = (request)
    {
        const input = cast(string)request.data;
        // Call the XMLRPC server with raw text data:
        const output = xmlrpc.handleRequest(input);
        // Now 'output' contains XML-encoded response
        HttpResponseData response;
        response.data = cast(const(ubyte)[])output;
        return response;
    };
    
    /*
     * Some methods that we are going to call through XMLRPC
     */
    auto swapTwoIntegers(int a, int b)
    {
        // Tuple allows to return more than one parameter
        return tuple(b, a);
    }
    
    double[] sortSomeDoubles(double[] arr, bool ascending)
    {
        if (ascending)
            return sort(arr).release();
        else
            return sort!"a > b"(arr).release();
    }
    
    // Type of the argument is not known at compile time
    string typeOf(Variant arg)
    {
        if (arg.type() == typeid(bool))
            return format("Boolean [%s]", arg);
        
        if (arg.convertsTo!string())
            return "Looks like string";
        
        if (arg.convertsTo!DateTime())
            return "DateTime: " ~ arg.toString();
        
        if (arg.convertsTo!int())
            return "Integer";
        
        if (arg.convertsTo!(const(ubyte)[])())
            return "Base64";
        
        const typeName = arg.type().toString();
        const errorMessage = "I don't like this type: " ~ typeName;
        /* 
         * Method can ask the server to return XMLRPC Fault Response by throwing xmlrpc.error.MethodFaultException
         * Any other exception triggers Fault Response too, but the error code would be
         *     xmlrpc.error.FciFaultCodes.applicationError
         * Other standard error codes are available from xmlrpc.error.FciFaultCodes
         */
        throw new MethodFaultException(errorMessage, FciFaultCodes.serverErrorInvalidMethodParams);
    }
    
    // This method is uber-dynamic: both input and output parameter lists are packed into Variant[] arrays
    Variant[] superDynamicMethod(Variant[] args)
    {
        foreach (ref arg; args)
        {
            // Turn each boolean parameter into string:
            if (arg.type() == typeid(bool))
                arg = arg.toString();
        }
        // Return the same number of parameters:
        return args;
    }
    
    /*
     * Register the methods above with XMLRPC server
     */
    xmlrpc.addMethod!swapTwoIntegers();            // The server derives method name from the function name
    xmlrpc.addMethod!(swapTwoIntegers, "swap")();  // Method can be added multiple times under different names
    xmlrpc.addMethod!sortSomeDoubles();
    xmlrpc.addMethod!typeOf("Help string");        // Help string will be available via XMLRPC introspection
    
    // Dynamic methods are registered differently:
    xmlrpc.addRawMethod(&superDynamicMethod, "superDynamicMethod");
    
    // Any method can be removed this way:
    xmlrpc.removeMethod("swap");
    
    // Lists all registered methods:
    writeln("XMLRPC methods: ", xmlrpc.methods);
    
    // It is possible to override system methods (if you really know what are you doing):
    string myNewHelpMethod() { return "Call 911 if you need help"; }
    xmlrpc.removeMethod("system.methodHelp");
    xmlrpc.addMethod!(myNewHelpMethod, "system.methodHelp")();
    
    /*
     * Finally, start the HTTP server
     */
    httpServer.spin();
}
