XML-RPC for D Programming Language
========
## Basic usage
### Client
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

### Server
```d
import xmlrpc.server;
import http_server_bob;

auto xmlrpcServer = new Server();

auto httpServer = new HttpServer(8000);
httpServer.requestHandler = (request)
{
    HttpResponseData httpResponse;
    auto encodedResponse = xmlrpcServer.handleRequest(cast(string)request.data);
    httpResponse.data = cast(const(ubyte)[])encodedResponse;
    return httpResponse;
};

real multiply(real a, real b) { return a * b; }
xmlrpcServer.addMethod!multiply();

Variant[] swap(Variant[] args) { return [args[1], args[0]]; }
xmlrpcServer.addRawMethod(&swap, "swap");

httpServer.spin();
```
Refer to `example/server.d` to learn more.

## Advanced examples
```shell
cd example && ./build.sh
# Start the server:
./build/server
# Switch to another terminal and execute the client:
./build/client
```

## Installation
```shell
# Optionally: INSTALL_PREFIX=/your/install/prefix
# Default INSTALL_PREFIX is /usr/local/
./build.sh install
```

## Requirements
Currently the client part of the library uses `libcurl`.
