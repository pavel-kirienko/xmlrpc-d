/**
 * Yet Another Embedded HTTP Server Written In D
 * 
 * Pavel Kirienko, 2013 (pavel.kirienko@gmail.com)
 * 
 * This module is free software. It comes without any warranty, to the extent permitted
 * by applicable law. You can redistribute it and/or modify it under the terms of the
 * DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE, Version 2, as published by Sam Hocevar.
 * 
 *              DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
 *                      Version 2, December 2004
 *   
 *   Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
 *   
 *   Everyone is permitted to copy and distribute verbatim or modified
 *   copies of this license document, and changing it is allowed as long
 *   as the name is changed.
 *   
 *              DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
 *     TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
 *   
 *    0. You just DO WHAT THE FUCK YOU WANT TO.
 */

/**
 * Build options: 
 *     -version=http_server_unittest
 *     Runs the server in the unittest
 *
 *     -debug=http
 *     Prints extra debug info into stdout
 *
 * How to use:
 *     Refer to the unittest at the end of this file.
 */

import std.socket;
import std.string;
import std.exception;
import std.conv;
import std.datetime;
import std.stdio;
import std.regex;
import std.algorithm;

alias HttpResponseData delegate(HttpRequestData) RequestHandler;

@trusted:

class HttpServer
{
    this(Address address)
    {
        listener = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
        listener.blocking = false;
        listener.bind(address);
        listener.listen(10);
        debug (http) writefln("Listening on %s", this.address);
    }

    this(ushort port)
    {
        this(new InternetAddress(port));
    }

    ~this()
    {
        close();
    }

    void close()
    {
        if (listener.isAlive)
            listener.close();
    }

    void spin(Duration timeout)
    {
        const deadline = Clock.currTime + timeout;
        while (Clock.currTime < deadline)
        {
            const selectTimeout = Clock.currTime - deadline;
            if (selectTimeout.isNegative)
                break;
            spinOnce(selectTimeout);
        }
    }

    void spin()
    {
        for (;;)
            spinOnce(dur!"minutes"(1));
    }

    @property Address address() { return listener.localAddress; }

private:
    void spinOnce(Duration timeout)
    {
        auto rds = new SocketSet;
        auto wrs = new SocketSet;
        rds.add(listener);
        foreach (con; clients.byValue())
        {
            rds.add(con.socket);
            if (con.bufWrite)
                wrs.add(con.socket);
        }

        const selectRet = Socket.select(rds, wrs, null, timeout);
        if (selectRet <= 0)
            return;

        if (rds.isSet(listener))
            accept();

        foreach (client; clients.values())
        {
            if (rds.isSet(client.socket))
            {
                if (!handleRead(client))
                {
                    closeAndRemove(client);
                    continue;
                }
            }
            if (wrs.isSet(client.socket))
            {
                if (!handleWrite(client))
                    closeAndRemove(client);
            }
        }
    }

    void accept()
    {
        enforce(listener.isAlive, new HttpServerException("Dead listener"));
        auto sock = listener.accept();
        enforce(sock.isAlive, new HttpServerException("accept() returned dead socket"));
        try sock.setKeepAlive(tcpKeepAliveTime, tcpKeepAliveInterval);    // throws if not supported
        catch (SocketOSException ex)
            debug (http) writefln("Failed to configure TCP keep-alive: %s", ex.msg);
        clients[sock] = new Client(sock);
        debug (http) writefln("New connection from %s, total %s", sock.remoteAddress, clients.length);
    }

    void closeAndRemove(Client client)
    {
        debug (http)
        {
            try writefln("Closing connection to %s", client.socket.remoteAddress); // may throw
            catch (Exception ex)
                writefln("Closing connection to <?>, fd: %s", client.socket.handle);
        }
        clients.remove(client.socket);
        try client.socket.close();
        catch (Exception ex) {}
        debug (http) writefln("Active connections: %s", clients.length);
    }

    bool handleWrite(Client client)
    {
        const ret = client.socket.send(client.bufWrite);
        if (ret == Socket.ERROR || ret == 0)
            return false;

        client.bufWrite = client.bufWrite[ret..$];
        if (client.bufWrite.length == 0)
        {
            if (client.keepAlive == false)
                return false;
            debug (http) writefln("Staying alive: %s", client.socket.remoteAddress);
        }
        return true;
    }

    bool handleRead(Client client)
    {
        ubyte[4096] data = void;
        const size = client.socket.receive(data);
        if (size == Socket.ERROR || size == 0)
            return false;
        try
        {
            HttpRequestData request;
            if (!client.parser.handleRead(data[0..size], request))
                return true;
            
            client.keepAlive = needToKeepAlive(request);
            
            if (!requestHandler)
            {
                debug (http) writeln("Request ignored because the handler is not configured");
                return false;
            }
            
            HttpResponseData response;
            try
                response = requestHandler(request);
            catch (Exception ex)
            {
                debug (http) writefln("Request handler exception: %s", ex);
                auto errorString = "Internal Server Error\n" ~ ex.msg;
                response.code = 500; // HTTP Internal Server Error
                response.data = cast(const(ubyte)[])errorString;
            }
            
            auto encodedResponse = generateHttpResponse(response);
            debug (http) writefln("Response %s bytes", encodedResponse.length);
            client.bufWrite ~= encodedResponse;
        }
        catch (HttpRequestParserException ex)
        {
            debug (http) writefln("HTTP parser failed: %s", ex.msg);
            return false;
        }
        return true;
    }

    class Client
    {
        Socket socket;
        HttpRequestParser parser;
        const(ubyte)[] bufWrite;
        bool keepAlive;

        this(Socket socket)
        {
            this.socket = socket;
            parser = new HttpRequestParser(maxRequestLength);
        }
    }

    Socket listener;
    Client[Socket] clients;

public:
    private int tcpKeepAliveTime_ = 60;
    @property int tcpKeepAliveTime() const { return tcpKeepAliveTime_; }
    @property void tcpKeepAliveTime(int x)
    {
        enforce(x > 0, new HttpServerException("Invalid keepalive parameter"));
        tcpKeepAliveTime_ = x;
    }

    private int tcpKeepAliveInterval_ = 10;
    @property int tcpKeepAliveInterval() const { return tcpKeepAliveInterval_; }
    @property void tcpKeepAliveInterval(int x)
    {
        enforce(x > 0, new HttpServerException("Invalid keepalive parameter"));
        tcpKeepAliveInterval_ = x;
    }

    long maxRequestLength = 1024 * 1024 * 100;
    RequestHandler requestHandler;
}

class HttpServerException : Exception
{
    private this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

struct HttpRequestData
{
    string method;
    string[2][] headers;
    const(ubyte)[] data;
}

struct HttpResponseData
{
    ushort code = 200;
    string[2][] headers;
    const(ubyte)[] data;
}

private:

class HttpRequestParser
{
    this(long maxRequestLength)
    {
        this.maxRequestLength = maxRequestLength;
    }

    bool handleRead(const(ubyte)[] data, out HttpRequestData output)
    {
        buf ~= data;
        if (expect == 0)
        {
            if (!parse())
                return false;
            debug (http)
            {
                writefln("Method: %s", currentRequest.method);
                writefln("Headers: %s", currentRequest.headers);
            }
        }
        else
        {
            const(ubyte)[] additional = (expect < data.length) ? data[0 .. expect] : data;
            assert(expect >= additional.length);
            expect -= additional.length;
            currentRequest.data ~= additional;
        }
        assert(expect >= 0);
        if (expect > 0)
            return false;

        output = currentRequest;
        currentRequest = HttpRequestData.init;
        return true;
    }

private:
    bool parse()
    {
        // Extract the header block from the data
        const headerEndIndex = buf.countUntil("\r\n\r\n");
        if (headerEndIndex < 0)
            return false;
        const(char)[] headerBlock = cast(const(char)[])buf[0..headerEndIndex];
        auto contentBlock = buf[headerEndIndex + 4 .. $];

        // Extract the method name and the connection header
        enum reMethod = regex(r"^(?P<method>[A-Z]{3,8})[^\r\n]+?HTTP", "m");
        auto methodMatch = match(headerBlock, reMethod);
        enforce(methodMatch, new HttpRequestParserException("Invalid connection header"));
        currentRequest.method = to!string(methodMatch.front["method"]);

        // HTTP headers
        enum reHeader = regex(r"^(?P<key>[a-zA-Z0-9\-]+?):\s*(?P<value>[^\r\n]+)", "gm");
        foreach (c; match(headerBlock, reHeader))
        {
            string key = to!string(c["key"]);
            string value = to!string(c["value"]);
            currentRequest.headers ~= [key, value];
        }
        enforce(currentRequest.headers, new HttpRequestParserException("No headers found"));

        // Data length, payload extraction
        expect = 0;
        const contentLengthHeader = findHeader(currentRequest.headers, "Content-Length");
        if (contentLengthHeader)
        {
            try expect = to!long(contentLengthHeader);
            catch (Exception) {}
        }
        enforce(expect <= maxRequestLength, new HttpRequestParserException(format("Content is too long (%s)", expect)));
        enforce(expect >= 0, new HttpRequestParserException(format("Content length cannot be negative (%s)", expect)));
        if (expect == 0)                            // Entire buffer belongs to the current request
        {
            debug (http) writefln("No Content-Length header; assuming %s bytes", contentBlock.length);
            currentRequest.data = contentBlock;
            buf = null;
        }
        else if (expect < contentBlock.length)      // Buffer shares the data between two or more consecutive requests
        {
            currentRequest.data = contentBlock[0..expect];
            buf = contentBlock[expect .. $];
            expect = 0;
        }
        else                                        // All of the buffer contents goes to the current request
        {
            currentRequest.data = contentBlock;
            expect -= contentBlock.length;
            buf = null;
        }
        return true;
    }

    long expect;
    const long maxRequestLength;
    const(ubyte)[] buf;
    HttpRequestData currentRequest;

    unittest
    {
        HttpRequestParser o;
        HttpRequestData rd;

        void reset() { o = new HttpRequestParser(1000000); rd = rd.init; }
        bool feed(string data) { return o.handleRead(cast(const(ubyte)[])data, rd); }
        void assertData(int line = __LINE__)(string data)
        {
            assert(rd.data == cast(const(ubyte[]))data, to!string(line));
        }

        reset();
        assert(!feed("GET / HTTP/1.0\r\n"));
        assert(feed("My-Header: my-data\r\n\r\n"));
        assertData("");

        reset();
        assert(!feed("POST /abcd/ HTTP/1.0\r\n"));
        assert(!feed("Content-Length: 4\r\n\r\n"));
        assert(!feed("1"));
        assert(!feed("23"));
        assert(feed("4"));
        assertData("1234");

        reset();
        const chunk = "POST / HTTP/1.0\r\nContent-Length: 4\r\n\r\nabcdPOST / HTTP/1.0\r\nContent-Length: 2\r\n\r\n:)";
        assert(feed(chunk));
        assertData("abcd");
        assert(feed(""));
        assertData(":)");
        assertNotThrown!HttpRequestParserException(feed("No newlines - no header"));
        // Note that this exception invalidates the parser object
        assertThrown!HttpRequestParserException(feed("Hi! I am not an HTTP header. Well, that's about it.\r\n\r\n"));

        reset();
        assert(!feed("POST / HTTP/1.0\r\n"));
        assertThrown!HttpRequestParserException(feed("Content-Length: 1000000000\r\n\r\n"));  // Request is too long

        reset();
        assert(!feed("POST / HTTP/1.0\r\n"));
        assertThrown!HttpRequestParserException(feed("Content-Length: -123\r\n\r\n"));
    }
}

class HttpRequestParserException : Exception
{
    this(string msg) { super(msg); }
}

const(ubyte)[] generateHttpResponse(HttpResponseData response)
{
    // Add the content length
    response.headers ~= ["Content-Length", to!string(response.data.length)];

    // Generate response header
    string header = format("HTTP/1.1 %d \r\n", response.code);
    foreach (pair; response.headers)
        header ~= format("%s: %s\r\n", pair[0], pair[1]);
    header ~= "\r\n";

    // Concatenate with the content and return
    return (cast(const(ubyte)[])header) ~ response.data;
}

unittest
{
    HttpResponseData input;
    input.headers ~= [["One-Header", "to-rule-them-all"]];
    input.data = cast(const(ubyte)[])"Data";
    const output = generateHttpResponse(input);
    const expected = "HTTP/1.1 200 \r\nOne-Header: to-rule-them-all\r\nContent-Length: 4\r\n\r\nData";
    assert(output == expected);
}

bool needToKeepAlive(HttpRequestData request)
{
    const header = findHeader(request.headers, "Connection");
    if (header)
        return header.strip().toLower() == "keep-alive";
    return false;
}

string findHeader(string[2][] headers, string target)
{
    target = target.toLower();
    foreach (pair; headers)
    {
        if (pair[0].toLower() == target)
            return pair[1];
    }
    return null;
}

version (http_server_unittest) unittest
{
    auto server = new HttpServer(new InternetAddress(1024));

    server.requestHandler = (request)
    {
        HttpResponseData resp;
        resp.headers = request.headers;
        resp.data = request.data;
        resp.data = generateHttpResponse(resp);
        return resp;
    };

    server.spin();
}
