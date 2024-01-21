#!/bin/bash -
if [ -z "$BASH_VERSION" ];then exec bash "$0" "$@";else set +o posix;fi
################################################################################
set -e

help() {
    fmt <<!
Usage
    "$0" [hostname] [[build-type] build options]

    Without arguments creates "classicube:latest"

    A hostname argument "vps-123.company.com" connects to that host using ssh
    and runs docker there.

Other possible types include:
    df
	Just dump the Dockerfile generated from this file after
	the "DOCKERFILE" line.

If a ClassiCube directoy exists in the under
"$MC" it will be used rather than "git clone".
!
    exit 0
}

main() {
    init_setup
    [ -d "$MC" ] && { cd "$MC" || exit; }

    case "$1" in
    -*|-h|--help|help ) help ; exit ;;

    build*|all|"" ) ;;

    [a-z]*.* )
	SSH_HOST="$1"
	eval "docker() { ssh $1 docker \"\$@\"; }"
	shift
	;;
    esac

    case "$1" in
    df ) build "$0" ; exit ;;

    build_* ) BUILD="$1" ; shift ;;
    latest|master ) BUILD=build_latest ; shift ;;
    [0-9]*.* ) VERSION="$1" ; BUILD=build_version ; shift ;;

    "") if [ -d ClassiCube ]
	then BUILD=build_default
	else BUILD=build_latest
	fi
	;;
    *) echo >&2 "Unknown option '$1', use 'help' option" ; exit 1 ;;
    esac

    [ -d ClassiCube ] &&
	git -C ClassiCube rev-parse --short HEAD > ClassiCube/.git-latest

    $BUILD "$@"
    rm -f ClassiCube/.git-latest ||:
    exit
}

build_default() {
    if [ "$LOCALSOURCE" = yes ]
    then IMAGE=classicube:patched
    else IMAGE=classicube:latest
    fi

    build_std
}

init_setup() {
    MC="$HOME/ClassiCube"
    IMAGE=''
    LOCALSOURCE=yes
    VERSION=
    SSH_HOST=

    [ -d "$MC" ] || LOCALSOURCE=no
}

build_std() {
    echo Build "$IMAGE"

    if [ "$LOCALSOURCE" = yes ]
    then
	DKF="/tmp/_tmp.dockerfile.$$"
	mkdir -p "$DKF"
	build "$0" > "$DKF"/Dockerfile
	tar czf - --exclude=.git -C "$DKF" Dockerfile -C "$MC" \
	    ClassiCube |
	docker build -t "$IMAGE" \
	    --build-arg=UID=$(id -u) \
	    -
	rm "$DKF"/Dockerfile
	rmdir "$DKF" ||:

    else
	build "$0" |
	docker build -t "$IMAGE" \
	    --build-arg=UID=$(id -u) \
	    --build-arg=VERSION="$VERSION" \
	    -
    fi

    echo Build complete "$IMAGE"
}

build_latest() {
    if [ "$1" = '' ]
    then IMAGE=classicube:latest
    else IMAGE=classicube:"$1"
    fi

    LOCALSOURCE=no
    build_std
}

build_version() {
    if [ "$VERSION" = '' ]
    then IMAGE=classicube:master
    else IMAGE=classicube:"$VERSION"
    fi

    LOCALSOURCE=no
    build_std
}

################################################################################
# This function takes this script and extracts the Dockerfile that follows
# the line that starts with "DOCKERFILE". Any sections between a "BEGIN" and
# "COMMIT" line are encoded using gzip and base64 into a "RUN" command.
# NB: https://github.com/moby/moby/issues/34423
build() {
read -d '' -r SCRIPT<<'#EOS'||:
BEGIN { # vim: set filetype=awk:
    sh = "sh";
    dsed = "sed 's/^@//' <<\\@";
    for(i=1; i<ARGC; i++) {
	if (ARGV[i] == "-d") {
	    sh = "cat";
	    ARGV[i] = "";
	}
    }
    print "#!/bin/sh"|sh
    print "encode() {"|sh
    print "  N=\"${1:-/tmp/install}\""|sh
    print "  D=\"${2:+;$2}\";D=\"${D:-;sh -e $N;rm -f $N}\""|sh
    print "  S=$(sed -e 's/^@//' -e '0,/./{/^$/d}')"|sh
    print "  echo 'RUN set -eu;_() { echo \"$@\";};(\\'"|sh
    print "  printf \"%s\\n\" \"$S\" | gzip -cn9 | base64 -w 72 | sed 's/.*/_ &;\\\\/'"|sh
    print "  echo \")|base64 -d|gzip -d>$N$D\""|sh
    print "}"|sh
    mode=0; ln=""; ty="";
}

/^#!\/bin\/[a-z]*sh\>/ && mode==0 { mode=3; next; }
/^DOCKERFILE/ && mode==3 { mode=0; next; }
mode==3 { next;}
# Standard Dockerfile with BEGIN and COMMIT translation
/^BEGIN$/||/^BEGIN /{ if (mode) print "@"|sh; mode=2; $1="encode<<\\@"; print|sh; next }
/^COMMIT *$/ && mode==2 { print "@"|sh; mode=0; next; }
mode==0 { print dsed|sh; mode=1; }
mode!=0 { if (substr($0, 1, 1) == "@") print "@" $0|sh; else print $0|sh; }
END { if (mode && mode!=3) print ln"@"|sh; mode=0; }
END { if (ty!="") { print dsed|sh; print ty"@"|sh;}}
#EOS
    awk "$SCRIPT" "$@"
}

main "$@" ; exit

################################################################################
DOCKERFILE
################################################################################
# This is the basic build machine.
FROM debian:bullseye AS deb_build
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
	wget curl ca-certificates \
	binutils git unzip zip build-essential \
	gdb imagemagick pngcrush p7zip-full \
	gcc-mingw-w64-x86-64 gcc-mingw-w64-i686 \
	libreadline-dev zlib1g-dev libbz2-dev \
	libsqlite3-dev libtinfo-dev libssl-dev \
	libpcre2-dev

################################################################################
# I copy the context into a VM so that I can create directories and stop
# it failing when they don't exist in the context.
FROM deb_build AS context
WORKDIR /opt/classicube
# Do this first, it can be overwritten if it exists in the context.
RUN [ -f default.zip ] || \
    wget --progress=dot:mega -O default.zip \
        http://www.classicube.net/static/default.zip

# Recompress the png files ... hard.
BEGIN
    mkdir /tmp/default
    cd /tmp/default
    unzip -jq /opt/classicube/default.zip
    for i in *.png
    do
	convert "$i" tmp_1.png
	pngcrush -brute tmp_1.png tmp_2.png
	[ -s tmp_1.png ] && mv tmp_1.png "$i"
	rm -f tmp_1.png tmp_2.png
    done

    mkdir mob
    for f in skinnedcube.png \
	    chicken.png creeper.png pig.png pony.png sheep.png \
	    sheep_fur.png skeleton.png spider.png zombie.png
    do  [ -f "$f" ] || continue
	mv "$f" mob/.
    done

    mkdir gui
    for f in gui.png gui_classic.png default.png icons.png touch.png
    do  [ -f "$f" ] || continue
	mv "$f" gui/.
    done

    mkdir env
    for f in particles.png rain.png snow.png clouds.png
    do  [ -f "$f" ] || continue
	mv "$f" env/.
    done

    7z -tzip -mx9 a default-7z.zip -r '*.*'
    mv default-7z.zip /opt/classicube/default.zip
COMMIT

# Make sure the directories we need exist here, overwrite them by the ones
# in the context if they exist.
RUN mkdir -p ClassiCube
COPY . .

WORKDIR /opt/classicube

################################################################################
FROM deb_build AS classicube
# Download ClassiCube if there's no source in the context.
WORKDIR /opt/classicube/ClassiCube
COPY --from=context /opt/classicube/ClassiCube .
ARG VERSION=
RUN [ -d src ] || \
    git clone --depth=1 https://github.com/UnknownShadow200/ClassiCube.git . ${VERSION:+ -b "${VERSION}"}

################################################################################
FROM deb_build AS windowsclient
# The build VM has windows cross compilers.
ENV ROOT_DIR=/opt/classicube
WORKDIR $ROOT_DIR
COPY --from=classicube /opt/classicube/ClassiCube .

################################################################################
# Compile the windows exe version
BEGIN
WIN32_CC="i686-w64-mingw32-gcc"
WIN64_CC="x86_64-w64-mingw32-gcc"
WIN32_FLAGS="-mwindows -nostartfiles -Wl,-e_main_real -DCC_NOMAIN"
WIN64_FLAGS="-mwindows -nostartfiles -Wl,-emain_real -DCC_NOMAIN"
ALL_FLAGS="-O1 -s -fno-stack-protector -fno-math-errno -Qn -w"

build_win32() {
  echo "Building win32.."
  [ -f $ROOT_DIR/misc/CCicon_32.res ] &&
      cp $ROOT_DIR/misc/CCicon_32.res $ROOT_DIR/src/CCicon_32.res
  [ -f $ROOT_DIR/misc/windows/CCicon_32.res ] &&
      cp $ROOT_DIR/misc/windows/CCicon_32.res $ROOT_DIR/src/CCicon_32.res

  EXE=ClassiCube.32.exe
  rm -f "$EXE" ||:
  $WIN32_CC *.c $ALL_FLAGS $WIN32_FLAGS -o "$EXE" CCicon_32.res -DCC_COMMIT_SHA=\"$LATEST\" -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32

  echo "Building win32 OpenGL.."
  EXE=ClassiCube.32-opengl.exe
  rm -f "$EXE" ||:
  $WIN32_CC *.c $ALL_FLAGS $WIN32_FLAGS -o "$EXE" CCicon_32.res -DCC_COMMIT_SHA=\"$LATEST\" -DCC_BUILD_MANUAL -DCC_BUILD_WIN -DCC_BUILD_GL -DCC_BUILD_WINGUI -DCC_BUILD_WGL -DCC_BUILD_WINMM -DCC_BUILD_HTTPCLIENT -DCC_BUILD_SCHANNEL -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32 -lopengl32

}

build_win64() {
  echo "Building win64.."
  [ -f $ROOT_DIR/misc/CCicon_64.res ] &&
      cp $ROOT_DIR/misc/CCicon_64.res $ROOT_DIR/src/CCicon_64.res
  [ -f $ROOT_DIR/misc/windows/CCicon_64.res ] &&
      cp $ROOT_DIR/misc/windows/CCicon_64.res $ROOT_DIR/src/CCicon_64.res
  
  EXE=ClassiCube.64.exe
  rm -f "$EXE" ||:
  $WIN64_CC *.c $ALL_FLAGS $WIN64_FLAGS -o "$EXE" CCicon_64.res -DCC_COMMIT_SHA=\"$LATEST\" -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32

  echo "Building win64 OpenGL.."
  EXE=ClassiCube.64-opengl.exe
  rm -f "$EXE" ||:
  $WIN64_CC *.c $ALL_FLAGS $WIN64_FLAGS -o "$EXE" CCicon_64.res -DCC_COMMIT_SHA=\"$LATEST\" -DCC_BUILD_MANUAL -DCC_BUILD_WIN -DCC_BUILD_GL -DCC_BUILD_WINGUI -DCC_BUILD_WGL -DCC_BUILD_WINMM -DCC_BUILD_HTTPCLIENT -DCC_BUILD_SCHANNEL -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32 -lopengl32

  if grep -q HACKEDCLIENT *.c
  then
      echo "Building win64 hacked.."
      EXE=ClassiCube.64-hack.exe
      rm -f "$EXE" ||:
      $WIN64_CC -D'HACKEDCLIENT(x)=x' *.c $ALL_FLAGS $WIN64_FLAGS -o "$EXE" CCicon_64.res -DCC_COMMIT_SHA=\"$LATEST\" -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32
  fi
}

if [ -d .git ]
then LATEST=$(git rev-parse --short HEAD || cat .git-latest || echo unknown)
else LATEST=$(cat .git-latest || echo unknown)
fi
cd $ROOT_DIR/src

build_win32
build_win64

COMMIT

################################################################################
FROM emscripten/emsdk AS webclient
# Using a different VM to build the web version of classicube.
COPY --from=classicube /opt/classicube/ClassiCube .
COPY --from=context /opt/classicube/default.zip texpacks/default.zip

################################################################################
# Compile with emscripten
BEGIN
set -x
LATEST=$(git rev-parse --short HEAD || cat .git-latest)
LATEST="${LATEST:+-DCC_COMMIT_SHA=\"$LATEST\"}"

[ -f src/interop_web.js ] && JLIB='--js-library src/interop_web.js'
emcc \
    src/*.c \
    -w -O1 \
    -o cc.js \
    $JLIB \
    "$LATEST" \
    -s WASM=1 \
    -s LEGACY_VM_SUPPORT=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s ABORTING_MALLOC=0 \
    -s ERROR_ON_UNDEFINED_SYMBOLS=1 \
    --preload-file texpacks/default.zip

#-------------------------------------------------------------------------------
# fix mouse wheel scrolling page not being properly prevented
# "[Intervention] Unable to preventDefault inside passive event listener
# due to target being treated as passive."
[ -f cc.js ] && {
    echo >&2 Patching cc.js ...
    cp -p cc.js cc.js.orig
    sed -i 's#eventHandler.useCapture);#{ useCapture: eventHandler.useCapture, passive: false });#g' cc.js

    diff -u cc.js.orig cc.js ||:
    rm -f cc.js.orig ||:
}

:
#-------------------------------------------------------------------------------
# Notes
# -g4 -> C source shown in browser.
# -s WASM=1 \	-- "WebAssembly" is undefined on slow browser (IE).
# -s SINGLE_FILE=1 \
#
#  -ldylink.js -lbrowser.js
# Also see misc/buildbot.sh
COMMIT

################################################################################
FROM alpine
# Just something with a shell.
################################################################################

# Match UID to your non-root user.
ARG UID=1000
RUN U=user ; adduser $U --uid $UID --home /home/$U -D

WORKDIR /opt
COPY --from=context --chown=user:user /opt/classicube/default.zip /opt/classicube/default.zip
COPY --from=webclient --chown=user:user /src/cc.* /opt/classicube/webclient/
COPY --from=windowsclient --chown=user:user /opt/classicube/src/*.exe /opt/classicube/client/

WORKDIR /opt/classicube
USER user

################################################################################
# Create the copy script.
BEGIN copy_exe 'chmod +x copy_exe'
#!/bin/sh
set -e
O=/opt/classicube

# Populate the webclient dir
mkdir -p webclient
cp -a "$O"/webclient/. webclient/.
cp -a "$O"/client/. webclient/.
cp -p "$O"/default.zip webclient/.
COMMIT
################################################################################

# This directory is where the data is stored
# The the script may copy the executables here too.
WORKDIR /home/user
CMD [ "sh","/opt/classicube/copy_exe"]

