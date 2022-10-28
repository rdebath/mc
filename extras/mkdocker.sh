#!/bin/bash -
if [ -z "$BASH_VERSION" ];then exec bash "$0" "$@";else set +o posix;fi
################################################################################
set -e

#   1.8.6.0 and earlier do not compile; windows filesystem issue.
#   1.8.7.* Compiles, does not run (GUI only?)
#   1.8.8.0 & 1.8.8.1 Run with errors
#   1.8.8.2 And later appear to be fully working.

# Some versions may need mcgalaxy2/MCGalaxy_.dll to exist

help() {
    fmt <<!
Usage
    "$0" [hostname] [[build-type] build options]

    Without arguments creates "mcgalaxy:latest"

    A hostname argument "vps-123.company.com" connects to that host using ssh
    and runs docker there.

    The build type can be "master" or a version number to build that
    particular docker image.

Other possible types include:
    df
	    Just dump the Dockerfile generated from this file after
	    the "DOCKERFILE" line.
    build_all
	    Create a large collection of images with different combinations
	    of options.
    build_i386
	    Build based on rdebath/debian-i386:buster
    build_mono
	    Build based on mono:latest
    build_all_mono
	    Build based on debian and various Mono releases
    build_parts
	    Tag specific pieces of the build process.

If MCGalaxy and ClassiCube directories exist in the under
"$MC" they will be used rather than "git clone".
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
	eval "docker() { ssh $1 docker \"\$@\"; }"
	shift
	;;
    esac

    case "$1" in
    df ) build "$0" ; exit ;;

    build_* ) BUILD="$1" ; shift ;;
    all|latest ) BUILD="build_$1"; shift ;;
    master ) BUILD=build_latest ; shift ;;

    local ) BUILD=build_local_version ; shift ;;
    [0-9]*.* ) BUILD=build_version ;;

    "") if [ -d MCGalaxy -a -d ClassiCube ]
	then BUILD=build_default
	else BUILD=build_latest
	fi
	;;
    *) echo >&2 "Unknown option '$1', use 'help' option" ; exit 1 ;;
    esac

    [ -d ClassiCube ] &&
	git -C ClassiCube rev-parse --short HEAD > ClassiCube/.git-latest

    [ -d MCGalaxy ] &&
	git -C MCGalaxy describe --tags mcgalaxy/master HEAD | fmt | tr '-' ' ' |
	    awk '{ if(NF == 4 && $1 == $2) print $1 "+" $3;
		else print $1 "-" $2 "-" $3 "+" ($5-$2);}' \
	    > MCGalaxy/.git-latest

    $BUILD "$@"
    rm -f ClassiCube/.git-latest MCGalaxy/.git-latest ||:
    exit
}

build_default() {
    if [ "$TARGET" != '' ]
    then IMAGE=mcgalaxy:"$TARGET"
    elif [ "$LOCALSOURCE" = yes ]
    then IMAGE=mcgalaxy:patched
    else IMAGE=mcgalaxy:latest
    fi

    FROM=
    MONO_VERSION=
    build_std
}

build_all() {
    build_latest
    build_mono
    build_i386
    build_all_mono
}

build_version() {
    if [ "$2" = '' ]
    then IMAGE=mcgalaxy:"$1"
    else IMAGE=mcgalaxy:"$1-$2"
    fi

    EXTRAFLAG="--build-arg=GITTAG=$1"
    TARGET=
    FROM=
    MONO_VERSION="$3"
    LOCALSOURCE=no

    build_std
}

build_local_version() {
    if [ "$2" = '' ]
    then IMAGE=mcgalaxy:"$1"
    else IMAGE=mcgalaxy:"$1-$2"
    fi

    CHECKOUT="$1"
    EXTRAFLAG=
    TARGET=
    FROM=
    MONO_VERSION="$3"
    LOCALSOURCE=yes

    build_std
}

init_setup() {
    FROM=
    MC="$HOME/ClassiCube"
    TARGET=''
    IMAGE=''
    MONO_VERSION=
    LOCALSOURCE=yes
    EXTRAFLAG=
    CHECKOUT=

    [ -d "$MC" ] || LOCALSOURCE=no

    # msbuild only
    # COMPFLG=--build-arg=COMPILE_FLAGS='SOME_OTHER_FLAG;TEN_BIT_BLOCKS'
}

build_std() {
    COMPFLG=

    echo Build "$IMAGE" $TARGET $FROM $COMPFLG $EXTRAFLAG $MONO_VERSION

    if [ "$LOCALSOURCE" = yes ]&&[ "$CHECKOUT" = '' ]
    then
	DKF="/tmp/_tmp.dockerfile.$$"
	mkdir -p "$DKF"
	build "$0" > "$DKF"/Dockerfile
	tar czf - --exclude=.git -C "$DKF" Dockerfile -C "$MC" \
	    ClassiCube MCGalaxy |
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    -
	rm "$DKF"/Dockerfile
	rmdir "$DKF" ||:

    elif [ "$LOCALSOURCE" = yes ]
    then
	DKF="/tmp/_tmp.dockerfile.$$"
	mkdir -p "$DKF"
	build "$0" > "$DKF"/Dockerfile
	git worktree remove /tmp/_wt."$CHECKOUT"/MCGalaxy 2>/dev/null ||:
	git worktree add /tmp/_wt."$CHECKOUT"/MCGalaxy "$CHECKOUT"^0

	tar czf - --exclude=.git -C "$DKF" Dockerfile \
	    -C "$MC" ClassiCube \
	    -C /tmp/_wt."$CHECKOUT" MCGalaxy |
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    -
	rm "$DKF"/Dockerfile
	rmdir "$DKF" ||:
	git worktree remove /tmp/_wt."$CHECKOUT"/MCGalaxy 2>/dev/null ||:
	rmdir /tmp/_wt."$CHECKOUT" ||:

    else
	build "$0" |
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    -
    fi

    echo Build complete "$IMAGE" $TARGET $FROM $COMPFLG $EXTRAFLAG $MONO_VERSION
}

build_parts() {
    build_default

    for part in deb_build context serversrc classicube webclient windowsclient
    do
	TARGET="$part"
	IMAGE=mcgalaxy:"$part"
	build_std
    done
    TARGET=
    IMAGE=
}

build_i386() {
    IMAGE=mcgalaxy:stable-i386
    FROM='rdebath/debian-i386:buster'
    MONO_VERSION=
    build_std
}

build_latest() {
    if [ "$1" = '' ]
    then IMAGE=mcgalaxy:latest
    else IMAGE=mcgalaxy:"master-$1"
    fi

    FROM=
    MONO_VERSION=
    LOCALSOURCE=no
    build_std
}

build_mono() {
    IMAGE=mcgalaxy:mono-latest
    FROM='mono:latest'
    MONO_VERSION=
    LOCALSOURCE=no
    build_std
}

build_all_mono() {
    for MONO_VERSION in 6.0 6.4 6.6 6.8 6.10 6.12
    do
	IMAGE=mcgalaxy:mono-$MONO_VERSION
	build_std ||:
    done
}

build_llvm() {
    MONO_VERSION=6.8
    IMAGE=mcgalaxy:mono-$MONO_VERSION
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

# Base linux distribution, Debian works fine
ARG FROM=debian:bullseye
# Supernova also worked.
ARG SERVER=MCGalaxy
# GITREPO will be pulled if the context doesn't contain "$SERVER.sln"
ARG GITREPO=https://github.com/UnknownShadow200/${SERVER}
# Pick a specific version tag
ARG GITTAG=
# To choose one compile for /p:DefineConstants
ARG COMPILE_FLAGS=
# Choose a Mono version from mono-project.com, "-" means current.
# If you blank this out you'll get "mono-devel" from Debian (5.18 in Buster).
# If $FROM already contains /usr/bin/mono, this has no effect.
ARG MONO_VERSION=

################################################################################
# Useful commands.
# docker run --name=mcgalaxy --rm -it -p 25565:25565 -v "$(pwd)/mcgalaxy":/home/user mcgalaxy
# docker run --name=mcgalaxy --rm -d -p 25565:25565 -v mcgalaxy:/home/user mcgalaxy
#
# If you use "-it" mcgalaxy will run on the virtual console, for "-d" a copy
# of "screen" will be started to show recent messages.
# The /home/user directory will be mcgalaxy's current directory.
# MCGalaxy will run as user id 1000. (ARG UID)
# The startup script ensures that /restart works and uses "rlwrap" for history.
#
# Ctrl-P Ctrl-Q
# docker attach mcgalaxy
#
# docker exec -it mcgalaxy bash
# docker exec -it mcgalaxy screen -U -D -r  # Ctrl-a d to detach
# docker exec -it -u 0 mcgalaxy bash
# docker logs mcgalaxy

################################################################################
# This is the basic build machine.
FROM $FROM AS deb_build
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
	wget curl ca-certificates \
	binutils git unzip zip build-essential \
	imagemagick pngcrush p7zip-full \
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
ARG SERVER
RUN mkdir -p ${SERVER} ClassiCube
COPY . .

################################################################################
FROM deb_build AS serversrc

ARG SERVER
ARG GITREPO
ARG GITTAG
ADD --chown=1000:1000 ${GITREPO}/commits/master.atom .
WORKDIR /opt/classicube/${SERVER}

# Check if we got source from the context, if not, download it.
COPY --from=context /opt/classicube/${SERVER} .

WORKDIR /opt/classicube
BEGIN
[ -d ${SERVER} -a ! -e ${SERVER}/${SERVER}.sln ] && {
    # Remove directory if (mostly) empty
    [ -f ${SERVER}/Dockerfile ] && mv ${SERVER}/Dockerfile .
    rm -rf ${SERVER} 2>/dev/null ||:
    mkdir ${SERVER}
}

[ ! -e ${SERVER}/${SERVER}.sln -a ".$GITREPO" != '.' ] && {
    git config --global advice.detachedHead false # STFU
    git clone --depth 1 "$GITREPO".git ${SERVER} ${GITTAG:+ -b "${GITTAG}"}
    [ "$GITTAG" != '' ] &&
	echo >&2 Cloned using id "$GITTAG"
    rm -f "$HOME"/.gitconfig ||:
}
:
COMMIT

################################################################################
FROM deb_build AS classicube
# Download ClassiCube if there's no source in the context.
WORKDIR /opt/classicube/ClassiCube
COPY --from=context /opt/classicube/ClassiCube .
RUN [ -d src ] || \
    git clone --depth=1 https://github.com/UnknownShadow200/ClassiCube.git .

################################################################################
FROM deb_build AS windowsclient
# The build VM has windows cross compilers.
ENV ROOT_DIR=/opt/classicube
WORKDIR $ROOT_DIR
COPY --from=classicube /opt/classicube/ClassiCube .

################################################################################
BEGIN
WIN32_CC="i686-w64-mingw32-gcc"
WIN64_CC="x86_64-w64-mingw32-gcc"
WIN32_FLAGS="-mwindows -nostartfiles -Wl,-e_main_real -DCC_NOMAIN"
WIN64_FLAGS="-mwindows -nostartfiles -Wl,-emain_real -DCC_NOMAIN"
ALL_FLAGS="-O1 -s -fno-stack-protector -fno-math-errno -Qn -w"

build_win32() {
  echo "Building win32.."
  cp $ROOT_DIR/misc/CCicon_32.res $ROOT_DIR/src/CCicon_32.res

  EXE=ClassiCube.32.exe
  rm -f "$EXE" ||:
  $WIN32_CC *.c $ALL_FLAGS $WIN32_FLAGS -o "$EXE" CCicon_32.res -DCC_COMMIT_SHA=\"$LATEST\" -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32

  echo "Building win32 OpenGL.."
  EXE=ClassiCube.32-opengl.exe
  rm -f "$EXE" ||:
  $WIN32_CC *.c $ALL_FLAGS $WIN32_FLAGS -o "$EXE" CCicon_32.res -DCC_COMMIT_SHA=\"$LATEST\" -DCC_BUILD_MANUAL -DCC_BUILD_WIN -DCC_BUILD_GL -DCC_BUILD_WINGUI -DCC_BUILD_WGL -DCC_BUILD_WINMM -DCC_BUILD_WININET -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32 -lopengl32

}

build_win64() {
  echo "Building win64.."
  cp $ROOT_DIR/misc/CCicon_64.res $ROOT_DIR/src/CCicon_64.res
  
  EXE=ClassiCube.64.exe
  rm -f "$EXE" ||:
  $WIN64_CC *.c $ALL_FLAGS $WIN64_FLAGS -o "$EXE" CCicon_64.res -DCC_COMMIT_SHA=\"$LATEST\" -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32

  echo "Building win64 OpenGL.."
  EXE=ClassiCube.64-opengl.exe
  rm -f "$EXE" ||:
  $WIN64_CC *.c $ALL_FLAGS $WIN64_FLAGS -o "$EXE" CCicon_64.res -DCC_COMMIT_SHA=\"$LATEST\" -DCC_BUILD_MANUAL -DCC_BUILD_WIN -DCC_BUILD_GL -DCC_BUILD_WINGUI -DCC_BUILD_WGL -DCC_BUILD_WINMM -DCC_BUILD_WININET -lws2_32 -lwininet -lwinmm -limagehlp -lcrypt32 -lopengl32

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
FROM $FROM
# The mono run time VM includes sufficient to compile MCGalaxy, so do it there.
# I don't want to reduce it too far as plugins will need to be compiled at
# run time.
#TXT# SHELL ["/bin/bash", "-c"]

ARG MONO_VERSION
################################################################################
BEGIN
export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=Shut_the_fuck_up
set -x
set_packages() {
    PKGS="unzip tini wget curl sqlite3 rlwrap screen ca-certificates"
    # If mono is already installed use that version
    [ -x /usr/bin/mono ] && return

    PKGS="$PKGS mono-devel"

    if [ "$MONO_VERSION" = '' ]
    then
	apt-get update

	for pkgname in msbuild
	do
	    FOUND=$(apt-cache show $pkgname |
		sed -n 's/^Package: //p' 2>/dev/null)
	    [ "$FOUND" != "" ] &&
		PKGS="$PKGS $pkgname"
	    :
	done
    else
	# Beware: Mono repo key.
	fetch_apt_key 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF

	XPKGS=

	# Add some more packages -- mono:latest non-slim version
	XPKGS="$XPKGS binutils ca-certificates-mono fsharp mono-vbnc"
	XPKGS="$XPKGS nuget referenceassemblies-pcl"

	# Recommended
	XPKGS="$XPKGS libmono-btls-interface4.0-cil cli-common"
	XPKGS="$XPKGS krb5-locales binfmt-support mono-llvm-support"

	# Note: No bullseye snapshot directory yet.
	DEBBASE=buster
	MSBUILD=msbuild
	LLVM=
	MOREPKGS=
	case "$MONO_VERSION" in
	"-" ) MOREPKGS="$XPKGS" ;;
	6.8 ) DEBBASE=buster ; LLVM=mono-llvm-support ;;
	6.6|6.4|6.0 ) DEBBASE=buster ; MSBUILD= ;;
	6.* ) DEBBASE=buster ;;
	5.* ) DEBBASE=stretch ;;
	[34].* ) DEBBASE=stable ;;
	esac

	if [ "$MONO_VERSION" = '' -o ".$MONO_VERSION" = '.-' ]
	then
	    echo "deb http://download.mono-project.com/repo/debian" \
		 "$DEBBASE main" \
		>> /etc/apt/sources.list
	else
	    echo "deb http://download.mono-project.com/repo/debian" \
		 "$DEBBASE/snapshots/$MONO_VERSION main" \
		>> /etc/apt/sources.list
	fi

	apt-get update

	# If I don't install mono-profiler mono profiling breaks nastily
	for pkgname in $MSBUILD mono-utils mono-profiler $LLVM $MOREPKGS
	do
	    FOUND=$(apt-cache show $pkgname |
		sed -n 's/^Package: //p' 2>/dev/null)
	    [ "$FOUND" != "" ] &&
		PKGS="$PKGS $pkgname"
	done
    fi
    :
}

fetch_apt_key() {
    apt-get update
    apt-get install -y --no-install-recommends gnupg
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$1"
    apt-get purge -y --auto-remove gnupg
}

deb_cleanup(){
    apt-get update -qq --list-cleanup -oDir::Etc::SourceList=/dev/null
    apt-get clean
    dpkg --clear-avail
    rm -f /etc/apt/apt.conf.d/01autoremove-kernels
    rm -f /var/lib/dpkg/*-old
    rm -rf /var/tmp/* /tmp/*
    :|find /var/log -type f ! -exec tee {} \;
    exit 0
}

[ "$MONO_VERSION" != '' ] && {
    # The mono site now force redirects to https.
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates
}

set_packages
apt-get upgrade -y --no-install-recommends
apt-get install -y --no-install-recommends $PKGS
deb_cleanup
COMMIT
################################################################################

# Do compile and run of application as "user"
ARG SERVER
# Match UID to your non-root user.
ARG UID=1000
RUN U=user ; useradd $U -u $UID -d /home/$U -m -l

WORKDIR /opt
COPY --from=context --chown=user:user /opt/classicube/default.zip /opt/classicube/default.zip
COPY --from=webclient --chown=user:user /src/cc.* /opt/classicube/client/
COPY --from=windowsclient --chown=user:user /opt/classicube/src/*.exe /opt/classicube/client/
COPY --from=serversrc --chown=user:user /opt/classicube/${SERVER} /opt/classicube/${SERVER}

WORKDIR /opt/classicube
USER user

################################################################################
# Create the build.sh script
BEGIN build.sh 'chmod +x build.sh'
#!/bin/sh
set -e
O=/opt/classicube
cd "$O"
[ -e ${SERVER}/${SERVER}.sln ] || {
    echo 'Nothing found to build, will download binaries at runtime' >&2
    exit 0
}

cd "$O/${SERVER}"

# These patches work back to version 1.8.8.2

# Sigh, Windows.
[ -f MCGalaxy/MCGalaxy_.csproj ] &&
    grep -q CmdFAQ MCGalaxy/MCGalaxy_.csproj &&
	sed -i 's/CmdFAQ.cs/CmdFaq.cs/' MCGalaxy/MCGalaxy_.csproj

[ -f MCGalaxy/Games/CTF/CTFGame.DB.cs ] &&
    grep -q CtfGame.DB MCGalaxy/MCGalaxy_.csproj &&
	sed -i 's/CtfGame.DB/CTFGame.DB/' MCGalaxy/MCGalaxy_.csproj

# Patch server to allow it to follow best practices.
#   http://www.mono-project.com/docs/getting-started/application-deployment
[ -f CLI/CLIProgram.cs ] &&
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	CLI/CLIProgram.cs
[ -f CLI/CLIProgram.cs ] &&
    sed -i '/if.*File.Exists.*MCGalaxy/s/^/if(false) {\/\/PATCH/' \
	CLI/CLIProgram.cs
[ -f CLI/Program.cs ] &&
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	CLI/Program.cs

[ -f GUI/Program.cs ] &&
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	GUI/Program.cs
[ -f GUI/Program.cs ] &&
    sed -i '/if.*File.Exists.*MCGalaxy/s/^/if(false) {\/\/PATCH/' \
	GUI/Program.cs

[ -f "${SERVER}"/Server/Server.cs ] && {
    sed -i '/CheckFile.*dll"/s/^/\/\/PATCH/' \
	${SERVER}/Server/Server.cs
    sed -i '/QueueOnce.InitTasks.UpdateStaffList/s/^/\/\/PATCH/' \
    ${SERVER}/Server/Server.cs
}

[ -f "${SERVER}"/Database/Backends/MySQL.cs ] && {
    sed -i '/CheckFile.*dll"/s/^/\/\/PATCH/' \
	${SERVER}/Database/Backends/MySQL.cs
}

[ -f "${SERVER}"/Database/Backends/SQLite.cs ] && {
    sed -i '/CheckFile.*dll"/s/^/\/\/PATCH/' \
	${SERVER}/Database/Backends/SQLite.cs
}

[ -f MCGalaxy/Scripting/Scripting.cs ] &&
    sed -i '/"[A-Z][A-Za-z0-9]*_.dll");/s::Assembly.GetExecutingAssembly().Location); //PATCH:' \
	${SERVER}/Scripting/Scripting.cs
[ -f ${SERVER}/Modules/Compiling/Compiler.cs ] &&
    sed -i '/"[A-Z][A-Za-z0-9]*_.dll");/s::Assembly.GetExecutingAssembly().Location); //PATCH:' \
	${SERVER}/Modules/Compiling/Compiler.cs

[ -f ${SERVER}/Modules/Compiling/Compiler.cs ] &&
    sed -i '/Path.GetFileName(Assembly.GetExecutingAssembly().Location);/s::Assembly.GetExecutingAssembly().Location; //PATCH:' \
	${SERVER}/Modules/Compiling/Compiler.cs

[ -f .git-latest ] &&
    sed -i '/string fullName;/s:;: = "'"$SERVER $(cat .git-latest)"'"; //PATCH:' \
      ${SERVER}/Server/Server.Fields.cs

echo >&2 Patches applied ...

XFILES=
[ -f CLI/CLIProgram.cs ] && XFILES="$XFILES CLI/CLIProgram.cs"
X=MCGalaxy/Database/Backends/SQLite.cs ; [ -f $X ] && XFILES="$XFILES $X"
X=MCGalaxy/Database/Backends/MySQL.cs ; [ -f $X ] && XFILES="$XFILES $X"

grep //PATCH >&2 \
    ${XFILES} \
    CLI/Program.cs \
    GUI/Program.cs \
    ${SERVER}/Server/Server.cs \
    ${SERVER}/Server/Server.Fields.cs \
    ${SERVER}/Scripting/Scripting.cs \
    ${SERVER}/Modules/Compiling/Compiler.cs \
    ||:

REL=/p:Configuration=Release
BINDIR=Release
#REL= ; BINDIR=Debug
if [ "$COMPILE_FLAGS" != '' ]
then
    if [ ! -x "/usr/bin/msbuild" -a -x "/usr/bin/xbuild" ]
    then echo >&2 Warning: msbuild is missing, using xbuild.
	 xbuild $REL ${COMPILE_FLAGS:+"/p:DefineConstants=$COMPILE_FLAGS"}
    else msbuild $REL ${COMPILE_FLAGS:+"/p:DefineConstants=\"$COMPILE_FLAGS\""}
    fi
else
    if [ ! -x "/usr/bin/msbuild" -a -x "/usr/bin/xbuild" ]
    then
	echo >&2 Warning: msbuild is missing, using xbuild.
	BLD=xbuild
	TEN="/p:DefineConstants=TEN_BIT_BLOCKS"
    else
	BLD=msbuild
	TEN="/p:DefineConstants=\"TEN_BIT_BLOCKS\""
    fi

    $BLD $REL "$TEN" && {
	mkdir -p "tmp/$BINDIR"
	mv "bin/$BINDIR/${SERVER}_.dll" "tmp/$BINDIR/${SERVER}_767.dll"
	[ -f "bin/$BINDIR/${SERVER}_.dll.mdb" ] &&
	    mv "bin/$BINDIR/${SERVER}_.dll.mdb" "tmp/$BINDIR/${SERVER}_767.dll.mdb"
	[ -f "bin/$BINDIR/${SERVER}_.dll.config" ] &&
	    mv "bin/$BINDIR/${SERVER}_.dll.config" "tmp/$BINDIR/${SERVER}_767.dll.config"
	rm -rf bin obj ||:
	mkdir -p "bin/$BINDIR"
    }
    :
    $BLD $REL
    :
    mv "tmp/$BINDIR/${SERVER}_767.dll" "bin/$BINDIR/${SERVER}_767.dll"
    [ -f "tmp/$BINDIR/${SERVER}_767.dll.mdb" ] &&
	mv "tmp/$BINDIR/${SERVER}_767.dll.mdb" "bin/$BINDIR/${SERVER}_767.dll.mdb"
    [ -f "tmp/$BINDIR/${SERVER}_767.dll.config" ] &&
	mv "tmp/$BINDIR/${SERVER}_767.dll.config" "bin/$BINDIR/${SERVER}_767.dll.config"
    :
fi

# LLVM AOT compile should run faster.
#
# LLVM seems to be often be broken. (Not included on Debian)
# Error messages are consistent with LLVM moving the goalposts.
# LLVM works on Mono 6.4, 6.8
# 6.0 -- Mono Warning: llvm support could not be loaded.
# 6.10, 6.12 -- llc: Unknown command line argument '-disable-fault-maps'.
#
# Not used: MCGalaxy.exe MySql.Data.dll
# Fails to compile: LibNoise.dll
#
[ -x /usr/lib/mono/llvm/bin/opt ] || echo>&2 LLVM AOT not found.
[ -x /usr/lib/mono/llvm/bin/opt ] && (
    echo >&2 "Checking LLVM AOT compile $MONO_VERSION"
    RV=0
    P="$(pwd)"
    cd /tmp
    cat > hello.cs <<\!
// Hello World! program
namespace HelloWorld
{
    class Hello {
	static void Main(string[] args)
	{
	    System.Console.WriteLine("Hello World!");
	}
    }
}
!
    AOT="--aot=mcpu=generic"
    mcs hello.cs && {
	mono "$AOT" --llvm -O=all,-shared hello.exe >hello.log 2>&1 || {
	    AOT=--aot
	    mono "$AOT" --llvm -O=all,-shared hello.exe >hello.log 2>&1
	} || RV=1
    } || RV=1
    cat hello.log

    if [ "$RV" = 0 ]
    then
	grep -q '^Executing llc:' hello.log || {
	    echo "Lies: AOT succeeded but llc didn't execute" >&2
	    RV=1
	}
    fi

    rm -rf /tmp/hello.* /tmp/mono_aot_* ||:

    if [ "$RV" = 0 ]
    then
	cd "$P"
	echo >&2 "Attempting LLVM AOT compile with $AOT"
	cd "bin/$BINDIR"
	for DLL in ${SERVER}_*.dll ${SERVER}CLI.exe
	do mono "$AOT" --llvm -O=all,-shared $DLL ||:
	done
    else
	echo >&2 "WARNING: Skipping LLVM AOT compile, it looks broken."
    fi
    :
)

DOALL=1
for f in \
    LICENSE.txt Changelog.txt \
    ${SERVER}.exe ${SERVER}.exe.config \
    ${SERVER}CLI.exe ${SERVER}CLI.exe.config ${SERVER}CLI.exe.so \
    ${SERVER}_.dll ${SERVER}_.dll.mdb ${SERVER}_.dll.config ${SERVER}_.dll.so \
    ${SERVER}_767.dll ${SERVER}_767.dll.mdb ${SERVER}_767.dll.config ${SERVER}_767.dll.so \
    MySql.Data.dll Newtonsoft.Json.dll \
    sqlite3_x32.dll sqlite3_x64.dll \
    System.Data.SQLite.dll

do [ -e "bin/$BINDIR/$f" ] && { FILES="$FILES bin/$BINDIR/$f" ; continue ; }
   [ -e "$f" ] && { FILES="$FILES $f" ; continue ; }
   case "$f" in
   *.config )
	if [ "$f" = "${SERVER}_767.dll.config" ]
	then [ -f "${SERVER}_767.dll" ] || continue;
	fi

	# These are missing from git repo.
	cat > "bin/$f" <<-\@
	<?xml version="1.0" encoding="utf-8"?>
	<configuration>
	  <startup>
	    <supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.0"/>
	  </startup>
	  <runtime>
	    <gcAllowVeryLargeObjects enabled="true"/>
	  </runtime>
	</configuration>
@
	FILES="$FILES bin/$f"
    ;;
    ${SERVER}_767.dll )
	echo >&2 "NOTE: Can't find file $f -- 10bit mode failed to compile."
	;;
    ${SERVER}CLI.exe|*.dll )
	echo >&2 "ERROR: Can't find file $f will copy everything"
	DOALL=1
	;;
    * ) echo >&2 "WARNING: Can't find file $f" ;;

    # TODO? For MySql.Data.dll sqlite3_x32.dll sqlite3_x64.dll
    # 	    From MCGalaxy/MCGalaxy/Server/Maintenance/Updater.cs:
    # public const string BaseURL    = "https://raw.githubusercontent.com/UnknownShadow200/MCGalaxy/master/";

    esac
done

mkdir -p "$O"/lib
[ "$DOALL" = 1 ] && cp -a bin/$BINDIR/* "$O"/lib/.
cp -a $FILES "$O"/lib
cd "$O"

rm -rf ~/.mono ~/.cache ${SERVER}
:
COMMIT
################################################################################
ARG COMPILE_FLAGS

# Build the mcgalaxy binaries from the git repo (or context).
RUN ./build.sh

################################################################################
# Create the start_server script.
BEGIN start_server 'chmod +x start_server'
#!/bin/sh
set -e
export LANG=C.UTF-8
O=/opt/classicube
export PREFIX="$O/lib"
SERVEREXE="$PREFIX/${SERVER}"CLI.exe
GUISERVEREXE="$PREFIX/${SERVER}".exe
[ ! -f "$SERVEREXE" ] && [ -f "$GUISERVEREXE" ] &&
    SERVEREXE="$GUISERVEREXE"

# Use this to change env variables, ulimit settings etc.
[ -f mono_env ] && . ./mono_env

[ "$1" = rcmd ] && {
    {
	while cat toserver ; do :; done &
	cat /dev/tty &
    } 2>/dev/null |
    mono $MONOOPTS "$SERVEREXE" |
    cut -b1-320
    exit
}

# No term; use screen to fake one.
[ "$TERM" = '' ] && [ "$1" = '' ] && {

    [ -f "$HOME/.screenrc" ] || cat > "$HOME/.screenrc" <<\!
defc1 off
defbce on
defutf8 on
utf8 on
termcapinfo * "ti@:te@:G0"
!

    echo Starting inside screen.
    echo "To see ${SERVER} console use:"
    echo "docker exec -it $(cat /etc/hostname) screen -r"
    [ -x /bin/bash ] && export SHELL=/bin/bash
    exec screen -U -D -m "$O"/start_server
}

if [ -f properties/cpe.properties ]
then
    if grep -iq 'ExtendedBlocks *= *True' properties/cpe.properties
    then
	echo "($(date +%T)) Ten bit blocks version selected"
	L="$O/lib/${SERVER}_"
	[ -f "${L}767.dll" ] && {
	    mv "${L}.dll" "${L}255.dll"
	    [ -f "${L}.dll.so" ] && mv "${L}.dll.so" "${L}255.dll.so"
	    [ -f "${L}.dll.mdb" ] && mv "${L}.dll.mdb" "${L}255.dll.mdb"
	    [ -f "${L}.dll.config" ] && mv "${L}.dll.config" "${L}255.dll.config"
	    mv "${L}767.dll" "${L}.dll"
	    [ -f "${L}767.dll.so" ] && mv "${L}767.dll.so" "${L}.dll.so"
	    [ -f "${L}767.dll.mdb" ] && mv "${L}767.dll.mdb" "${L}.dll.mdb"
	    [ -f "${L}767.dll.config" ] && mv "${L}767.dll.config" "${L}.dll.config"
	}
    fi
fi

[ -f "$O"/lib/${SERVER}_.dll.so ] &&
    echo "($(date +%T)) AOT compiled version is in use."

# Populate bin dir (if present)
[ -d bin ] && {
    cp -a "$O"/lib/* bin/. ||:
}

# Populate the webclient dir
[ -d "$O"/client ] && {
    mkdir -p webclient
    cp -a "$O"/client/. webclient/.
    cp -p "$O"/default.zip webclient/.
}

# Work around docker bug. (tty size is updated late)
[ "$(stty size 2>/dev/null)" = "0 0" ] && {
    for i in 1 2 3 4 5 ; do [ "$(stty size)" = "0 0" ] && sleep 1 ; done
    [ "$(stty size)" = "0 0" ] && {
	echo 'WARNING: Not using rlwrap because stty failed.'
	export TERM=dumb
	exec mono $MONOOPTS "$SERVEREXE"
    }
}

[ "$1" = direct ] &&
    exec mono $MONOOPTS "$SERVEREXE"

# This fifo is so we can send huge lines to MCGalaxy for /mb
rm -f toserver ||:
mkfifo toserver ||:

# Things to check:
#  1) Command line history from rlwrap
#  2) /shutdown 1 completes and ends the container.
#  3) /restart does not end the container.
#  4) Large commands >4k can be sent into toserver from outside the container.
#  5) For very large commands >50Mb make sure you clean up MCGalaxy.db
#  6) rlwarp does not cleanup zombies.
#
# Also: Mono tries to be evil to the tty, rlwrap is easily confused.

if [ "$$" = 1 ]
then exec /usr/bin/tini rlwrap -- -a -t dumb sh "$O"/start_server rcmd
else exec rlwrap -a -t dumb sh "$O"/start_server rcmd
fi

COMMIT
################################################################################

# This directory is where the data is stored
# The the script may copy the executables here too.
WORKDIR /home/user
ARG SERVER
ENV SERVER=${SERVER}
EXPOSE 25565
CMD [ "sh","/opt/classicube/start_server"]

