XML RPC Library for D Programming Language
========

Client:
```d
import xmlrpc.client;

auto client = new Client("http://localhost:8000/");

int answer = client.call!("multiply", int)(6, 9);
assert(answer != 42);

auto swappedStrings = client.call!("swap", string, string)("first", "second");
assert(swappedStrings[0] == "second" && swappedStrings[1] == "first");

auto swappedIntAndString = client.call!("swap", int, string)("hi", 17);
assert(swappedIntAndString[0] == 17 && swappedIntAndString[1] == "hi");
```
Refer to `example/client.d` to learn more.

Server:
```d
import xmlrpc.server;
import http_server_bob;

auto xmlrpcServer = new Server();

auto httpServer = new HttpServer(8000);
httpServer.requestHandler = (request)
{
    HttpResponseData response;
    response.data = cast(const(ubyte)[])xmlrpcServer.handleRequest(cast(string)request.data);
    return response;
};

real multiply(real a, real b) { return a * b; }
xmlrpcServer.addMethod!multiply();

Variant[] swap(Variant[] args) { return [args[1], args[0]]; }
xmlrpcServer.addRawMethod(&swap, "swap");

httpServer.spin();
```
Refer to `example/server.d` to learn more.
