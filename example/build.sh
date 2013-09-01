#!/bin/sh

# Compiler identification
if gdmd --help &> /dev/null
then
    D_COMPILER='gdmd'
else
    D_COMPILER='dmd'
fi
echo "D compiler: $D_COMPILER"

LIB_ROOT='../src'

XMLRPC_SOURCES=$(find $LIB_ROOT/xmlrpc -name '*.d')
HTTP_SERVER_SOURCES=$LIB_ROOT/http_server_bob.d

function build_one()
{
    mkdir build &> /dev/null
    target="${1%.*}"
    cmd="$D_COMPILER -w -debug=xmlrpc -odbuild -ofbuild/$target -I$LIB_ROOT $@"
    echo $cmd
    $cmd || exit 1
    rm build/*.o &> /dev/null
}

build_one readme_samples.d $XMLRPC_SOURCES $HTTP_SERVER_SOURCES
build_one client.d $XMLRPC_SOURCES
build_one server.d $XMLRPC_SOURCES $HTTP_SERVER_SOURCES
