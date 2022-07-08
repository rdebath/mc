ClassiCube-Hacked-Client.diff
    Quick hack to disable hack control packets.

    Note: This defaults to not installed unless HACKEDCLIENT
    defined as this before the top of Protocol.c:

        #define HACKEDCLIENT(x) x

    or on the command line this option is added:

        -D'HACKEDCLIENT(x)=x'

api.sh
    Script to access the classicube.net API and create mc://
    URLs with mppass values.

mini_chat.c
    Tiny chat client template.

mkdocker.sh
    Big fat script to create docker images.

node-http-s.df
    Little Docker file for a web server suitable to host texture zips

