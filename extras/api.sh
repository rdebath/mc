#!/bin/sh -

COOKIES="$HOME/.curl_cookies"
VERBOSE=no
CCARGS=no
case "$1" in
-v ) VERBOSE=yes; shift ;;
-c ) CCARGS=yes; shift ;;
esac

[ "$(echo '"+"'|jq -r .)" != + ] && { echo>&2 "Please install 'jq'"; exit 1; }

[ "$#" = 0 ] && {
    echo>&2 "Usage: $0 [-v] [-c] Host [UserName] [Password] [MFACode]"
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
NICKF=$(echo "$NICK" | tr 'A-Z' 'a-z')

api_login() {
    # Old filename
    [ -f "$COOKIES"/.cookie.$NICKF ] &&
	mv "$COOKIES"/.cookie.$NICKF "$COOKIES"/cookie.$NICKF

    [ "$NICK" != '' ] && {
	mkdir -p -m 0700 "$COOKIES"

	[ "$VERBOSE" = yes ] && echo>&2 -n 'API Cookie Login ... '
	JSON1=$(curl -sS \
	    --cookie "$COOKIES"/cookie.$NICKF \
	    --cookie-jar "$COOKIES"/cookie.$NICKF \
	    https://www.classicube.net/api/login/)
	[ "$VERBOSE" = yes ] && echo>&2 'Done.'

	AUTHD=$(echo "$JSON1" | jq -r .authenticated)
	TOKEN=$(echo "$JSON1" | jq -r .token)
	USERNAME=$(echo "$JSON1" | jq -r .username)

	if [ "$AUTHD" = false ]
	then
	    if [ "$PASS" != '' ]
	    then
		[ "$VERBOSE" = yes ] && echo>&2 -n 'API Password Login ... '
		JSON2=$(
		    curl -sS https://www.classicube.net/api/login \
			--cookie "$COOKIES"/cookie.$NICKF \
			--cookie-jar "$COOKIES"/cookie.$NICKF \
			--data username="$NICK" \
			--data password="$PASS" \
			--data token="$TOKEN" \
			${CODE:+ --data login_code="$CODE"} )

		AUTHD=$(echo "$JSON2" | jq -r .authenticated)
		USERNAME=$(echo "$JSON2" | jq -r .username)

		[ "$VERBOSE" = yes ] && {
		    if [ "$AUTHD" = false ]
		    then echo>&2 'Failed'
		    else echo>&2 'Done'
		    fi
		}

	    else JSON2="No password"
	    fi

	    [ "$AUTHD" = false ] && {
		echo >&2 "Login failed ..."
		echo >&2 "$JSON2"
		rm -f "$COOKIES"/cookie.$NICKF ||:
		echo '?'
		exit 1
	    }
	    [ "$VERBOSE" = yes ] && {
		echo "$JSON2" | jq '.' >&2
	    }
	else
	    [ "$VERBOSE" = yes ] && {
		echo "$JSON1" | jq '.' >&2
	    }
	fi
    }
}

TMP=/tmp/_tmp$$.txt
HASH=

[ "$NICK" != '' ] && {
    case "$SEARCH" in
    "" ) exit 0 ;;
    [0-9]*.*.*.*:*[0-9] )
	HASH="$(echo -n "$SEARCH" | md5sum - | awk '{print $1;}')" ;;
    [0-9]*.*.*.*[0-9] )
	HASH="$(echo -n "$SEARCH:25565" | md5sum - | awk '{print $1;}')" ;;
    esac
}

JSON3=''

api_login

if [ "$HASH" != '' ]
then echo>&2 "Using $HASH generated from '$SEARCH'"
elif [ "${#SEARCH}" = 32 ]
then HASH="$SEARCH"
     echo>&2 "Using $HASH directly"
else
    [ "$VERBOSE" = yes ] && echo>&2 -n 'Fetch server list ... '
    curl -sS ${NICK:+--cookie "$COOKIES"/cookie."$NICKF"} https://www.classicube.net/api/servers > "$TMP"
    [ "$VERBOSE" = yes ] && echo>&2 "Got $(jq<"$TMP" '.[]|length') servers"

    case "$SEARCH" in
    *\$ ) SEARCH="${SEARCH%?}	"
    esac

    NAME=$(jq<"$TMP" -r '.servers[] | [.name,.ip+":"+(.port|tostring)] | @tsv' | grep -i "$SEARCH" )

    [ "$(echo "$NAME" | wc -l)" -ne 1 ] && {
	echo >&2 "Found records..."
	echo "$NAME" | sed 's/[\t ]*:null//' | expand -58 >&2
	echo '?'
	exit 1
    }

    NAME=$(echo "$NAME" | awk -F'\t' 'NR==1{print $1;}')

    if [ "$VERBOSE" = yes ]||[ "$NICK" = '' ]
    then [ "$NAME" != '' ] && echo >&2 "Found record: \"$NAME\""
    fi

    [ "$NICK" = '' ] && {
	rm -f "$TMP"
	exit 0
    }

    [ "$NAME" = '' ]&&[ "${#SEARCH}" = 32 ]&& HASH="$SEARCH"

    if [ "$NAME" = '' ]&&[ "$HASH" = '' ]
    then
	echo >&2 "Server not found: $SEARCH."
	rm -f "$TMP"
	echo '?'
	exit 1
    fi

    [ "$NICK" != '' ] &&
	echo >&2 "Using \"$NAME$HASH\"  "

    [ "$HASH" = '' ] &&
	HASH=$( jq < "$TMP" -r '.servers[] | select(.name=="'"$NAME"'").hash')
    [ "$HASH" != '' ] &&
	JSON3="$(jq < "$TMP" '.servers[] | select(.hash=="'"$HASH"'" and has("mppass"))' )"
fi

fetch_j3() {
    [ "$VERBOSE" = yes ] && echo>&2 Fetch server record
    JSON3=$(curl -sS ${NICK:+--cookie "$COOKIES"/cookie."$NICKF"} \
		"https://www.classicube.net/api/server/$HASH")
}

case "$JSON3" in
""|null ) fetch_j3 ;;
* ) JSON3='{"servers":['"$JSON3"']}' ;;
esac

case "$(echo "$JSON3" | jq -r '.servers[0].mppass' 2>/dev/null)" in
"" )
    [ "$VERBOSE" = yes ] && echo>&2 "Error $JSON3"
    sleep 2 ; fetch_j3 ;;
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
    [ -t 2 ] && {
	echo "$JSON3" | jq -r '.servers[] | ["# "+.ip+":"+(.port|tostring)+" - '"$USERNAME"'/"+.mppass] | @tsv ' >&2
    }
}
