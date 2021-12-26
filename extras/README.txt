Quick hack to disable hack control packets.

Note: This defaults to not installed unless HACKEDCLIENT
defined as this before the top of Protocol.c:

    #define HACKEDCLIENT(x) x

or on the commands line this option is added:

    -D'HACKEDCLIENT(x)=x'


