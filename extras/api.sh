#!/bin/sh -

COOKIES="$HOME/.curl_cookies"
VERBOSE=no
CCARGS=no
case "$1" in
-v ) VERBOSE=yes; shift ;;
-c ) CCARGS=yes; shift ;;
esac

[ "$(echo '"+"'|jq -r .)" != + ] && { echo>&2 "Please install 'jq'"; exit 1; }

[ "$1" = '' ] && {
    echo>&2 "Usage: $0 [-v] [-c] [ServerName_ipport_or_hash] [UserName] [Password] [MFACode]"
    echo>&2 "The Password and Code are usually optional "
    echo>&2 "Omitting the username just lists matching hosts"
    echo>&2 "The host can be a regex to match against the server name or"
    echo>&2 "the ip address and port (127.0.0.1:25565) or the hash of the"
    echo>&2 "server (ie: of it's ip and port)."
    echo>&2 ""
    echo>&2 "Authentication cookies are stored in $COOKIES"
    exit 1
}

SEARCH="$1"
NICK="$2"
PASS="$3"
CODE="$4"

[ "$NICK" != '' ] && {
    mkdir -p -m 0700 "$COOKIES"

    JSON1=$(curl -sS \
	--cookie "$COOKIES"/.cookie.$NICK \
	--cookie-jar "$COOKIES"/.cookie.$NICK \
	https://www.classicube.net/api/login/)

    AUTHD=$(echo "$JSON1" | jq -r .authenticated)
    TOKEN=$(echo "$JSON1" | jq -r .token)
    USERNAME=$(echo "$JSON1" | jq -r .username)

    [ "$AUTHD" = false ] && {
	if [ "$PASS" != '' ]
	then
	    JSON2=$(
		curl -sS https://www.classicube.net/api/login \
		    --cookie "$COOKIES"/.cookie.$NICK \
		    --cookie-jar "$COOKIES"/.cookie.$NICK \
		    --data username="$NICK" \
		    --data password="$PASS" \
		    --data token="$TOKEN" \
		    ${CODE:+ --data login_code="$CODE"} )

		echo >&2 "$JSON2"
		AUTHD=$(echo "$JSON2" | jq -r .authenticated)
		USERNAME=$(echo "$JSON2" | jq -r .username)
	else JSON2="No password"
	fi

	[ "$AUTHD" = false ] && {
	    echo >&2 "Login failed ... $JSON2"
	    exit 1
	}
    }
}

TMP=/tmp/_tmp$$.txt
HASH=

[ "$NICK" != '' ] && {
    case "$SEARCH" in
    [0-9]*.*.*.*:*[0-9] )
	HASH="$(echo -n "$SEARCH" | md5sum - | awk '{print $1;}')" ;;
    esac
}

if [ "$HASH" != '' ]
then echo>&2 "Using $HASH generated from $SEARCH"
elif [ "${#SEARCH}" = 32 ]
then HASH="$SEARCH"
     echo>&2 "Using $HASH directly"
else
    curl -sS ${NICK:+--cookie "$COOKIES"/.cookie."$NICK"} https://www.classicube.net/api/servers > "$TMP"

    case "$SEARCH" in
    *\$ ) SEARCH="${SEARCH%?}	"
    esac

    NAME=$(jq<"$TMP" -r '.servers[] | [.name,.ip+":"+(.port|tostring)] | @tsv' | grep -i "$SEARCH" )

    [ "$(echo "$NAME" | wc -l)" -ne 1 ] && {
	echo >&2 "Found records..."
	echo "$NAME" | expand -64 >&2
	exit 1
    }

    NAME=$(echo "$NAME" | awk -F'\t' 'NR==1{print $1;}')

    if [ "$VERBOSE" = yes ]||[ "$NICK" = '' ]
    then echo >&2 "Found record: \"$NAME\""
    fi

    [ "$NICK" = '' ] && {
	rm -f "$TMP"
	exit 0
    }

    [ "$NAME" = '' ]&&[ "${#SEARCH}" = 32 ]&& HASH="$SEARCH"

    if [ "$NAME" = '' ]&&[ "$HASH" = '' ]
    then
	echo >&2 "Server not found: $SEARCH"
	rm -f "$TMP"
	exit 1
    fi

    [ "$NICK" != '' ] &&
	echo >&2 "Using \"$NAME$HASH\""

    [ "$HASH" = '' ] &&
	HASH=$( jq < "$TMP" -r '.servers[] | select(.name=="'"$NAME"'").hash')
fi

fetch_j3() {
    JSON3=$(curl -sS ${NICK:+--cookie "$COOKIES"/.cookie."$NICK"} \
		"https://www.classicube.net/api/server/$HASH")
}

fetch_j3
case "$JSON3" in
*429* ) sleep 2 ; fetch_j3 ;;
esac

[ "$VERBOSE" = yes ] && {
    echo "$JSON3" | jq '.servers[0]' >&2
}

[ "$NICK" != '' ] && {
    USERNAME="${USERNAME:-$NICK}"
    if [ "$CCARGS" != yes ]
    then
	echo "$JSON3" | jq -r '.servers[] | ["mc://"+.ip+":"+(.port|tostring)+"/'"$USERNAME"'/"+.mppass] | @tsv '
    else
	echo "$JSON3" | jq -r '.servers[] | ["'"$USERNAME"' "+.mppass+" "+.ip+" "+(.port|tostring)] | @tsv '
    fi
}
