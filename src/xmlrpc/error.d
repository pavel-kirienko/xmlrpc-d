/*
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 */

module xmlrpc.error;

import xmlrpc.data;
import std.exception;
import std.stdio;

@safe:

/**
 * Root type for all XML-RPC exceptions
 */
class XmlRpcException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

/**
 * Client throws this exception if the remote method returns XML-RPC Fault Response.
 * Server catches this exception and converts it into XML-RPC Fault Response.
 */
class MethodFaultException : XmlRpcException
{
    package this(Variant value, string message)
    {
        this.value = value;
        super(message);
    }
    
    @trusted package this(Variant value)
    {
        this(value, format("XMLRPC method failure: %s", value.toString()));
    }
    
    this(string faultString, int faultCode)
    {
        this(makeFaultValue(faultString, faultCode));
    }
    
    Variant value;
}

/**
 * Fault Code Interoperability constants
 * http://xmlrpc-epi.sourceforge.net/specs/rfc.fault_codes.php
 */
enum FciFaultCodes : int
{
    parseErrorNotWellFormed       = -32_700,
    parseErrorUnsupportedEncoding = -32_701,
    parseErrorInvalidCharacter    = -32_702,
    
    serverErrorInvalidXmlRpc       = -32_600,
    serverErrorMethodNotFound      = -32_601,
    serverErrorInvalidMethodParams = -32_602,
    serverErrorInternalXmlRpcError = -32_603,
    
    applicationError = -32_500,
    systemError      = -32_400,
    transportError   = -32_300
}

package Variant makeFaultValue(string faultString, int faultCode)
{
    return Variant(["faultCode": Variant(faultCode), "faultString": Variant(faultString)]);
}
