#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:-'/usr/local'}

LIB_ROOT='src'
XMLRPC_SOURCES=$(find $LIB_ROOT/xmlrpc -name '*.d')
HTTP_SERVER_SOURCES=$LIB_ROOT/http_server_bob.d

if gdmd --help &> /dev/null
then D_COMPILER='gdmd'
else D_COMPILER='dmd'
fi

function execute() { echo "$@" && $@ || exit 1; }

function build_library()
{
    execute $D_COMPILER -release -w -lib -I$LIB_ROOT -odbuild -ofxmlrpc-d.a $XMLRPC_SOURCES $HTTP_SERVER_SOURCES
}

function generate_headers() # output dir, file1 ... fileN
{
    output=$1
    shift
    for file in $@
    do execute $D_COMPILER -o- -I$LIB_ROOT -Hd$output $file
    done
}

mkdir build &> /dev/null

case $1 in
    clean)
        rm -rf build
        ;;
    lib)
        build_library
        ;;
    install)
        build_library
        generate_headers build/headers $XMLRPC_SOURCES
        sudo mkdir $INSTALL_PREFIX/include/xmlrpc &> /dev/null
        execute sudo cp build/headers/*.di $INSTALL_PREFIX/include/xmlrpc
        execute sudo cp build/xmlrpc-d.a $INSTALL_PREFIX/lib
        execute sudo cp $HTTP_SERVER_SOURCES $INSTALL_PREFIX/src
        ;;
    http_test)
        execute $D_COMPILER -w -ofbuild/http_test -main -unittest -version=http_server_unittest -debug=http $HTTP_SERVER_SOURCES
        ;;
    *)
        src="$XMLRPC_SOURCES $HTTP_SERVER_SOURCES"
        execute $D_COMPILER -w -I$LIB_ROOT -ofbuild/test -main -unittest -version=xmlrpc_unittest -debug=xmlrpc $src
        ;;
esac
