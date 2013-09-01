#!/usr/bin/env python

import xmlrpclib, sys, random

endpoint = sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8000'

proxy = xmlrpclib.ServerProxy(endpoint)

#
# Multicall extension
#
multicall = xmlrpclib.MultiCall(proxy)

multicall.swapTwoIntegers(42, -73)

someDoubles = [random.random() for _ in xrange(5)]
multicall.sortSomeDoubles(someDoubles, True)
multicall.sortSomeDoubles(someDoubles, False)

for res in multicall():
    print res

#
# Dynamic method
#
result = proxy.superDynamicMethod('The string', True, False, 12.3, 42)
print result
