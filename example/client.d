/*
 * XMLRPC client example
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

import std.stdio;
import std.string;
import std.datetime;
import std.math;
import std.variant;

import xmlrpc.data : MethodCallData;
import xmlrpc.client : Client, TransportException;
import xmlrpc.error : MethodFaultException, FciFaultCodes;

void main(string[] args)
{
    const endpoint = (args.length > 1) ? args[1] : "http://localhost:8000";
    
    auto client = new Client(endpoint);
    
    // ====== Basic usage ======
    
    /*
     * Return type definition
     * Note "int, int" after the method name - that's return type
     */
    auto swappedIntegers = client.call!("swapTwoIntegers", int, int)(42, 9000);
    
    // Returned value has type Tuple!(int, int)
    assert(swappedIntegers[0] == 9000);
    assert(swappedIntegers[1] == 42);
    
    /*
     * Automatic return type conversion
     * Note how integers are turned into string and double
     */
    auto stringAndDouble = client.call!("swapTwoIntegers", string, double)(42, 9000);
    
    // Returned value has type Tuple!(string, double)
    assert(stringAndDouble[0] == "9000");
    assert(approxEqual(stringAndDouble[1], 42.0));
    
    /*
     * And now something completely different.
     * The xmlrpc-d server will try it's best to cast arguments into proper types
     */
    auto swappedIntegersFromStrings = client.call!("swapTwoIntegers", int, int)("42", "9000"d);
    
    assert(swappedIntegers[0] == 9000);
    assert(swappedIntegers[1] == 42);
    
    /*
     * Single return value is not packed into tuple
     * Note that automatic type conversion works with any types, like double[] --> long[] or double[] --> string[]
     */
    long[] sortedLongs = client.call!("sortSomeDoubles", long[])([13, 83, -35], true);
    
    assert(sortedLongs == [-35, 13, 83]);
    
    string[] sortedDoublesAsStrings = client.call!("sortSomeDoubles", string[])([13, 83, -35], true);
    
    assert(sortedDoublesAsStrings == ["-35", "13", "83"]);
    
    /*
     * When the remote method fails, the client throws xmlrpc.error.MethodFaultException
     */
    try
    {
        client.call!"noSuchMethod"();
        assert(false);
    }
    catch (MethodFaultException ex)
        assert(ex.value["faultCode"].get!int() == FciFaultCodes.serverErrorMethodNotFound);
    
    /*
     * In case of transport failure client throws TransportException
     */
    auto clientWithBrokenEndpoint = new Client("http://kremlin.ru");
    try
    {
        writeln("Now we're going to fail");
        clientWithBrokenEndpoint.call!"listHumanRights"();
        assert(false);
    }
    catch (TransportException ex)
        writeln("Transport failure: ", ex.msg);
    
    // ====== Advanced ======
    
    /*
     * If the return types are not specified, call() will return the values as is in the array of type Variant[]
     */
    Variant[] rawReturnValues = client.call!"superDynamicMethod"("Redrum", true, false, 100500);
    
    assert(rawReturnValues[0] == "Redrum");
    assert(rawReturnValues[1] == "true");
    assert(rawReturnValues[2] == "false");
    assert(rawReturnValues[3] == 100500);
    
    /*
     * If the argument list is not known at compile time, use rawCall()
     */
    MethodCallData rawCallData;
    rawCallData.name = "superDynamicMethod";
    rawCallData.params = [Variant(true), Variant("Fire in oxygen garden!")];
    
    auto rawResponseData = client.rawCall(rawCallData, false/* suppress MethodFaultException on method fault */);
    
    assert(rawResponseData.fault == false);
    assert(rawResponseData.params[0] == "true");
    assert(rawResponseData.params[1] == "Fire in oxygen garden!");
}
