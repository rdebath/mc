#!/bin/bash -
if [ -z "$BASH_VERSION" ];then exec bash "$0" "$@";else set +o posix;fi
################################################################################
set -e

# Running under mono (Patches allow all versions to operate)
#   1.0.0.0 Works
#   1.8.0.0 Works
#   1.8.1.0 Works but is numbered 1.8.0.0 (mis-targeted tag)
#   1.8.2.0 Works
#   1.8.3.0 Has compile errors. (mis-targeted tag)
#   1.8.4.0 Requires removal of compile errors in a "PerformUpdate" function.
#   ..1.8.6.0 Has Windows filesystem compile issues
#   ..1.8.7.5 Need Viewmode.cfg prepopulated
#   1.8.0.0..1.8.8.1 Emit errors but continue to work.
#   1.8.8.2 And later appear to be fully working.

# See use of "$COMMITISH" for untagged versions.

#  Ten Bit blocks starts on 1.9.0.5
#  Websocket starts on 1.9.1.3

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

If MCGalaxy directory exists in the under
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
    all ) BUILD="build_$1"; shift ;;
    latest|master ) BUILD=build_latest ; shift ;;

    local ) BUILD=build_local_version ; shift ;;
    [0-9]*.* ) BUILD=build_version ;;

    "") if [ -d MCGalaxy ]
	then BUILD=build_default
	else BUILD=build_latest
	fi
	;;
    *) echo >&2 "Unknown option '$1', use 'help' option" ; exit 1 ;;
    esac

    [ -d MCGalaxy ] &&
	git -C MCGalaxy describe --tags mcgalaxy/master HEAD | fmt | tr '-' ' ' |
	    awk '{ if(NF == 4 && $1 == $2) print $1 "+" $3;
		else print $1 "-" $2 "-" $3 "+" ($5-$2);}' \
	    > MCGalaxy/.git-latest

    $BUILD "$@"
    rm -f MCGalaxy/.git-latest ||:
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

    # fetch_lib
}

fetch_lib() {
    # Fetch lib directory
    if [ "$SSH_HOST" != '' ]
    then
	ssh "$SSH_HOST" \
	    'I='"$IMAGE"'; C=$(docker create "$I" :); docker cp $C:/opt/mcgalaxy/lib/. -; docker rm $C>&2' \
	> /tmp/mcgbin.tar
    else
	C=$(docker create "$IMAGE" :)
	docker cp $C:/opt/mcgalaxy/lib/. ->/tmp/mcgbin.tar
	docker rm $C>&2
    fi
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
    then
	if [ "$1" = master ]
	then IMAGE=mcgalaxy:latest
	else IMAGE=mcgalaxy:"$1"
	fi
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
    SSH_HOST=

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
	tar czf - --exclude=.git \
	    -C "$DKF" Dockerfile \
	    -C "$MC" MCGalaxy |
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    --build-arg=UID=$(id -u) \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    -
	rm "$DKF"/Dockerfile
	rmdir "$DKF" ||:

    elif [ "$LOCALSOURCE" = yes ]
    then
	# NB: Some of the early ones have bad tags, don't use local source

	DKF="/tmp/_tmp.dockerfile.$$"
	mkdir -p "$DKF"
	build "$0" > "$DKF"/Dockerfile
	git worktree remove /tmp/_wt."$CHECKOUT"/MCGalaxy 2>/dev/null ||:
	git worktree add /tmp/_wt."$CHECKOUT"/MCGalaxy "$CHECKOUT^0"

	tar czf - --exclude=.git -C "$DKF" Dockerfile \
	    -C /tmp/_wt."$CHECKOUT" MCGalaxy |
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    --build-arg=UID=$(id -u) \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    -
	rm "$DKF"/Dockerfile
	rmdir "$DKF" ||:
	git worktree remove /tmp/_wt."$CHECKOUT"/MCGalaxy 2>/dev/null ||:
	rmdir /tmp/_wt."$CHECKOUT" ||:

    elif [ "$SSH_HOST" != '' ]
    then
	build "$0" > /tmp/Dockerfile
	scp -p /tmp/Dockerfile "$SSH_HOST":/tmp/Dockerfile
	ssh -qt "$SSH_HOST" \
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    --build-arg=UID=$(id -u) \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    - \</tmp/Dockerfile

    else
	build "$0" |
	docker build -t "$IMAGE" \
	    ${TARGET:+"--target=$TARGET"} \
	    ${FROM:+"--build-arg=FROM=$FROM"} \
	    $COMPFLG \
	    $EXTRAFLAG \
	    --build-arg=UID=$(id -u) \
	    ${MONO_VERSION:+"--build-arg=MONO_VERSION=$MONO_VERSION"} \
	    -
    fi

    echo Build complete "$IMAGE" $TARGET $FROM $COMPFLG $EXTRAFLAG $MONO_VERSION
}

build_parts() {
    build_default

    for part in deb_build context
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
# If you blank this out you'll get "mono-devel" from Debian (5.18 in Buster, 6.8 in bullseye).
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
# This is a machine to fetch the source
# I copy the context into a VM so that I can create directories and stop
# it failing when they don't exist in the context.
#
FROM $FROM AS context
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
	ca-certificates git

################################################################################
WORKDIR /opt/mcgalaxy

# Make sure the directories we need exist here, overwrite them by the ones
# in the context if they exist.
ARG SERVER
RUN mkdir -p ${SERVER}
COPY . .

ARG GITREPO
ARG GITTAG
ADD --chown=1000:1000 ${GITREPO}/commits/master.atom .

WORKDIR /opt/mcgalaxy
BEGIN
[ -d ${SERVER} -a ! -e ${SERVER}/${SERVER}.sln ] && {
    # Remove directory if (mostly) empty
    [ -f ${SERVER}/Dockerfile ] && mv ${SERVER}/Dockerfile .
    rm -rf ${SERVER} 2>/dev/null ||:
    mkdir ${SERVER}
}

[ ! -e ${SERVER}/${SERVER}.sln -a ".$GITREPO" != '.' ] && {
    COMMITISH=
    case "$GITTAG" in
    # Some of the old ones have bad or missing tags.
    1.0.0.0 ) COMMITISH=877b26159b84b30a4f4fb00a66e4bc1fecafe6e3 ;;
    1.0.0.1 ) COMMITISH=f5c656a38d7e711249ea93615b1aa99a288f583c ;;
    1.0.0.2 ) COMMITISH=c1ee045b888c687a802cce78147f6392a02e114e ;;
    1.0.3.1 ) COMMITISH=7fa4f7c2938ad97959baa352dbf0e0cff3f094ff ;;
    1.5.0.7 ) COMMITISH=5182a1a2dd1f18cd6f5d0c1de615499dc8236d3e ;;
    1.5.0.8 ) COMMITISH=261cd468dee00a5060629c584c742e292b66de11 ;;
    1.5.1.0 ) COMMITISH=b32a63fc5ee9c9398ac7a24b53668f9220b55a9c ;;
    1.5.1.1 ) COMMITISH=d3e7fe60e0451c60e84ee5e4fcc565a37c9c38af ;;
    1.5.1.2 ) COMMITISH=568632bb81c8ee058f991d1b05cf5030c899133a ;;
    1.6.0.0 ) COMMITISH=d4fa2d2bd5ca807e70998aba7cc0b296eea1848a ;;
    1.6.0.2 ) COMMITISH=afcd10e8995aca745521ecdf040729b0ccc1170f ;;
    1.6.9.0 ) COMMITISH=005232abd4f48fb2def723b73e95662cc4ef5efe ;;
    1.7.0.0 ) COMMITISH=92e13ddc6034fb9af41ccb6b378005b64c0b270a ;;
    1.7.3.0 ) COMMITISH=0fa039edb6309f29376cc00a38dedbb2de3587bc ;;
    1.8.1.0 ) COMMITISH=78e57fcb227b5d06dcd725bfdd6bbd6cfb4b68c6 ;;
    1.8.2.0 ) COMMITISH=f2e7606b805cb75ea7839a4878cab08065be2fec ;;
    1.8.3.0 ) COMMITISH=59a5462e47b5d6d8be2f4eff753e6a5ca35bf61c ;;
    1.8.4.0 ) COMMITISH=b3b9dae5cb9a74806550e34a4afb06102ecf313f ;;
    1.8.9.2 ) COMMITISH=b5a4a8a8ae06af7a0aa807958ec18fc57cc24864 ;;
    1.9.0.3 ) COMMITISH=f32b0135e7cc3ac2f113c9b76b84f448ef47d860 ;;
    1.9.1.1 ) COMMITISH=2b5911ce04158f269452cf4fa5e657d07bbf905e ;;
    1.9.2.1 ) COMMITISH=961cf05972ee95af7ddf77a1925cae70b0a9788f ;;
    1.9.2.4 ) COMMITISH=816d52b6ad4a912ae748e7ce9f98d09be711d969 ;;
    esac

    git config --global advice.detachedHead false # STFU
    if [ "$COMMITISH" = '' ]
    then git clone --depth 1 "$GITREPO".git ${SERVER} ${GITTAG:+ -b "${GITTAG}"}
    else
	git clone "$GITREPO".git ${SERVER}
	git -C ${SERVER} checkout "$COMMITISH"
    fi
    [ "$GITTAG" != '' ] &&
	echo >&2 Cloned using id "$GITTAG" $COMMITISH
    rm -rf "$HOME"/.gitconfig ${SERVER}/.git ||:
}
:
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
export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=STFU
set -x
set_packages() {
    PKGS="unzip tini wget curl sqlite3 gdb rlwrap screen ca-certificates"
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

WORKDIR /opt/mcgalaxy
RUN chown 1000:1000 .
USER user

COPY --from=context --chown=user:user /opt/mcgalaxy/${SERVER} /opt/mcgalaxy/${SERVER}

################################################################################
# Create the build.sh script
BEGIN build.sh 'chmod +x build.sh'
#!/bin/sh
set -e
O=/opt/mcgalaxy
cd "$O"
[ -e ${SERVER}/${SERVER}.sln ] || {
    echo 'Nothing found to build, will download binaries at runtime' >&2
    exit 0
}

cd "$O/${SERVER}"

# Patch server to allow it to follow best practices.
#   http://www.mono-project.com/docs/getting-started/application-deployment
[ -f CLI/CLIProgram.cs ] &&
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	CLI/CLIProgram.cs
[ -f CLI/CLIProgram.cs ] &&
    sed -i '/if.*File.Exists.*MCGalaxy/s/^/if(false) {\/\/PATCH/' \
	CLI/CLIProgram.cs
[ -f CLI/CLI.cs ] &&
    sed -i '/if.*File.Exists.*MCGalaxy/s/^/if(false) {\/\/PATCH/' \
	CLI/CLI.cs
[ -f CLI/Program.cs ] &&
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	CLI/Program.cs

[ -f GUI/Program.cs ] &&
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	GUI/Program.cs
[ -f GUI/Program.cs ] &&
    sed -i '/if.*File.Exists.*MCGalaxy.*dll/s/^/if(false) {\/\/PATCH/' \
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

[ -f "${SERVER}"/Scripting/Scripting.cs ] &&
    sed -i '/"[A-Z][A-Za-z0-9]*_.dll");/s::Assembly.GetExecutingAssembly().Location); //PATCH:' \
	${SERVER}/Scripting/Scripting.cs
[ -f ${SERVER}/Modules/Compiling/Compiler.cs ] &&
    sed -i '/"[A-Z][A-Za-z0-9]*_.dll");/s::Assembly.GetExecutingAssembly().Location); //PATCH:' \
	${SERVER}/Modules/Compiling/Compiler.cs

[ -f ${SERVER}/Modules/Compiling/Compiler.cs ] &&
    sed -i '/Path.GetFileName(Assembly.GetExecutingAssembly().Location);/s::Assembly.GetExecutingAssembly().Location; //PATCH:' \
	${SERVER}/Modules/Compiling/Compiler.cs

################################################################################
# Insert a detailed version if available.
# Not cannot change "InternalVersion" or "Version" as it's format is fixed.
[ -f .git-latest ] && [ -f ${SERVER}/Server/Server.Fields.cs ] &&
    sed -i '/string fullName;/s:;: = "'"$SERVER $(cat .git-latest)"'"; //PATCH:' \
      ${SERVER}/Server/Server.Fields.cs

################################################################################
# Make initial setup less noisy
[ -f ${SERVER}/Player/List/PlayerList.cs ] &&
    sed -i '/Logger.Log(LogType.SystemActivity, "CREATED NEW:/s;^;//PATCH:;' \
	${SERVER}/Player/List/PlayerList.cs
[ -f ${SERVER}/Player/List/PlayerExtList.cs ] &&
    sed -i '/Logger.Log(LogType.SystemActivity, "CREATED NEW:/s;^;//PATCH:;' \
	${SERVER}/Player/List/PlayerExtList.cs

################################################################################
# These patches are needed for older versions.
# Sigh, Windows.
[ -f MCGalaxy/MCGalaxy_.csproj ] &&
    grep -q CmdFAQ MCGalaxy/MCGalaxy_.csproj &&
	sed -i 's/CmdFAQ.cs/CmdFaq.cs/' MCGalaxy/MCGalaxy_.csproj

[ -f MCGalaxy/Games/CTF/CTFGame.DB.cs ] &&
    grep -q CtfGame.DB MCGalaxy/MCGalaxy_.csproj &&
	sed -i 's/CtfGame.DB/CTFGame.DB/' MCGalaxy/MCGalaxy_.csproj

[ -f MCGalaxy/Network/ClassiCube.cs ] &&
    sed -i '/software=MCGalaxy";/s/";/%20" + Server.Version; \/\/PATCH/' \
	MCGalaxy/Network/ClassiCube.cs

################################################################################
# Very old versions: 1.0.0.0 .. 1.8.8.1
[ -f Program.cs ] && {
    sed -i '/\<CurrentDirectory\>.*=/s/^/\/\/PATCH/' \
	Program.cs
    sed -i '/if (File.Exists.*MCGalaxy.*))/s/^/if(true) \/\/PATCH/' \
	Program.cs

    [ -f MCGalaxy_.csproj ] && {

	grep -q Commands.Building MCGalaxy_.csproj &&
	    sed -i 's/Building/building/' MCGalaxy_.csproj
	grep -q Commands.'\<Other\>' MCGalaxy_.csproj &&
	    sed -i 's/\<Other\>/other/' MCGalaxy_.csproj
	grep -q '\<Util\>' MCGalaxy_.csproj &&
	    sed -i 's/\<Util\>/util/' MCGalaxy_.csproj
	grep -q SharkBite.Thresher MCGalaxy_.csproj &&
	    sed -i 's/SharkBite.Thresher/sharkbite.thresher/' MCGalaxy_.csproj
	grep -q '\<Queue\>' MCGalaxy_.csproj &&
	    sed -i 's/\<Queue\>/queue/' MCGalaxy_.csproj

	# Completely comment out the function!
	[ -f GUI/Program.cs ] &&
	    grep -q 'public static void PerformUpdate' GUI/Program.cs && {
		sed -i \
		    '/public static void PerformUpdate/i public static void PerformUpdate(){} \/\/PATCH
		    /public static void PerformUpdate/,/^        }/{
			s/^/\/\/ /
		    }' \
		    GUI/Program.cs
	    }

	[ -f Player/Player.cs ] &&
	    sed -i '/if (id != 17)/s/17)/17 \&\& id != 16) \/\/PATCH/' \
		Player/Player.cs
    }
    [ -f Server/Server.cs ] && {
	sed -i '/CheckFile.*dll"/s/^/\/\/PATCH/' \
	    Server/Server.cs
	sed -i '/QueueOnce.UpdateStaffList/s/^/\/\/PATCH/' \
	    Server/Server.cs
	sed -i '/UpdateStaffList();/s/^/\/\/PATCH/' \
	    Server/Server.cs
	sed -i '/Background.QueueOnce(UpdateStaffListTask);/s/^/\/\/PATCH/' \
	    Server/Server.cs
	sed -i '/Log("Starting Server");/{n;s/^ *{/if(false){\/\/PATCH/;}' \
	    Server/Server.cs
	sed -i '/UpdateGlobalSettings();/s/^/\/\/PATCH/' \
	    Server/Server.cs
	sed -i '/bool UseGlobalChat = true;/s/true/false/' \
	    Server/Server.cs
    }
    [ -f Server.cs ] && {
	sed -i '/if.*File.Exists.*\.dll.*[^{]*$/s/^/if(false) \/\/PATCH/' \
	    Server.cs
	sed -i '/UpdateStaffList();/s/^/\/\/PATCH/' \
	    Server.cs
	sed -i '/UpdateGlobalSettings();/s/^/\/\/PATCH/' \
	    Server.cs
	sed -i '/bool UseGlobalChat = true;/s/true/false/' \
	    Server.cs
    }
    [ -f Server/Server.Tasks.cs ] && {
	sed -i '/ml.Queue(UpdateStaffListTask);/s/^/\/\/PATCH/' \
	    Server/Server.Tasks.cs
    }
    [ -f Commands/Information/CmdInfo.cs ] && {
	sed -i '/Command.all.Find("devs")/s/^/\/\/PATCH/' \
	    Commands/Information/CmdInfo.cs
    }
    [ -f Network/ClassiCube.cs ] && {
	sed -i '/software=MCGalaxy";/s/";/%20" + Server.Version; \/\/PATCH/' \
	    Network/ClassiCube.cs
    }
    [ -f Database/SQLite.cs ] && {
	sed -i '/" + Server.apppath + ".MCGalaxy.db/s:" + Server.apppath + ".::' \
	    Database/SQLite.cs
    }
}
################################################################################
# Bugs

# [ -f GUI/Popups/PortTools.Designer.cs ] && {
#     sed -i '/System.EventHandler(this.LblInfoClick);/s/^/\/\/PATCH/' \
# 	GUI/Popups/PortTools.Designer.cs
# }

################################################################################

echo >&2 Patches applied ...

for XFILE in \
    ${SERVER}/Database/Backends/MySQL.cs \
    ${SERVER}/Database/Backends/SQLite.cs \
    ${SERVER}/Modules/Compiling/Compiler.cs \
    ${SERVER}/Scripting/Scripting.cs \
    ${SERVER}/Server/Server.Fields.cs \
    ${SERVER}/Server/Server.cs \
    CLI/CLI.cs \
    CLI/CLIProgram.cs \
    CLI/Program.cs \
    Commands/Information/CmdInfo.cs \
    GUI/Program.cs \
    GUI/Popups/PortTools.Designer.cs \
    Network/ClassiCube.cs \
    Player/Player.cs \
    Program.cs \
    Server/Server.Tasks.cs \
    Server/Server.cs

do [ -f "$XFILE" ] || continue ; grep //PATCH >&2 /dev/null "$XFILE" ||:
done

REL=/p:Configuration=Release
BINDIR=Release
# REL=/p:Configuration=Debug ; BINDIR=Debug
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
	TEN="/p:DefineConstants=TEN_BIT_BLOCKS,CLI"
    else
	BLD=msbuild
	TEN="/p:DefineConstants=\"TEN_BIT_BLOCKS;CLI\""
    fi

    HASTENBIT=$(find . -type f -exec grep -l TEN_BIT_BLOCKS {} + |wc -l)

    if [ "$HASTENBIT" -gt 0 ]
    then
	echo Ten bit build
	if $BLD $REL "$TEN" >/tmp/build-ten.log
	then
	    mkdir -p "tmp/$BINDIR"
	    mv "bin/$BINDIR/${SERVER}_.dll" "tmp/$BINDIR/${SERVER}_767.dll"
	    [ -f "bin/$BINDIR/${SERVER}_.dll.mdb" ] &&
		mv "bin/$BINDIR/${SERVER}_.dll.mdb" "tmp/$BINDIR/${SERVER}_767.dll.mdb"
	    [ -f "bin/$BINDIR/${SERVER}_.dll.config" ] &&
		mv "bin/$BINDIR/${SERVER}_.dll.config" "tmp/$BINDIR/${SERVER}_767.dll.config"
	    rm -rf bin obj ||:
	    mkdir -p "bin/$BINDIR"
	else cat /tmp/build-ten.log
	fi
    fi

    echo Eight bit build
    $BLD $REL ${SERVER}.sln > /tmp/build.log || { cat /tmp/build.log ; exit 1; }
    :
    [ -f "tmp/$BINDIR/${SERVER}_767.dll" ] && {
	    mv "tmp/$BINDIR/${SERVER}_767.dll" "bin/$BINDIR/${SERVER}_767.dll"
	[ -f "tmp/$BINDIR/${SERVER}_767.dll.mdb" ] &&
	    mv "tmp/$BINDIR/${SERVER}_767.dll.mdb" "bin/$BINDIR/${SERVER}_767.dll.mdb"
	[ -f "tmp/$BINDIR/${SERVER}_767.dll.config" ] &&
	    mv "tmp/$BINDIR/${SERVER}_767.dll.config" "bin/$BINDIR/${SERVER}_767.dll.config"
    }
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
[ "$DOALL" = 1 ] && { cp -a bin/$BINDIR/* "$O"/lib/. || { ls -lR bin ; exit 1 ;}; }
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
O=/opt/mcgalaxy
export PREFIX="$O/lib"
export VERSION=$(awk '{gsub("[v \r]*","",$0);print $0;exit;}' "$O"/lib/Changelog.txt )
MONO=mono

edit_prop() {
    PROPS=properties/server.properties ; PROP=$1 ; VAL=$2
    [ "$VAL" = '' ] && return;
    mkdir -p properties
    [ -f $PROPS ] || touch $PROPS
    grep -q '^'"$PROP"' *=' $PROPS || echo "$PROP" = $VAL >> $PROPS
    sed -i -s '/^'"$PROP"' *=/s/=.*/= '"$VAL"'/' $PROPS
}

# Use this to change env variables, ulimit settings etc.
[ -f mono_env ] && . ./mono_env

edit_prop port "$MCG_PORT"

[ "$1" = rcmd ] && {
    {
	while cat toserver ; do :; done &
	cat /dev/tty &
    } 2>/dev/null |
    "$MONO" $MONOOPTS "$2" |
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

case "$VERSION" in
# These have ten bit but no properties/cpe.properties
1.9.0.[5-9]|1.9.[12].*|1.9.3.[0-5] )
    [ ! -f properties/cpe.properties ] && {
	mkdir -p properties
	echo ExtendedBlocks = True > properties/cpe.properties
    }
    ;;
# No ten bit build
1.8.*|1.9.0.* ) ;;
esac

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

RUNDIR="$PREFIX"
# Populate bin dir (if present, or may be needed)
case "$VERSION" in
1.8.[89]*|1.9.[01].* ) mkdir -p bin ;; # server.properties:backup-location
1.8.*|1.0.* )
    mkdir -p bin
    # Newer versions default to cli in Mono.
    # Beware 1.8.[0-2].0 look at line number 5 for the "true" value.
    [ -f Viewmode.cfg ] || {
cat > Viewmode.cfg <<\!
#This file controls how the console window is shown to the server host
#cli: True or False (Determines whether a CLI interface is used) (Set True if on Mono)
#high-quality: True or false (Determines whether the GUI interface uses higher quality objects)

cli = true
high-quality = true
!
    }
    ;;
esac
[ -d bin ] && {
    cp -a "$O"/lib/* bin/. && RUNDIR="$(pwd)/bin"
}

SERVEREXE="$RUNDIR/${SERVER}"CLI.exe
[ ! -f "$PREFIX/${SERVER}CLI.exe" ] && [ -f "$PREFIX/${SERVER}.exe" ] &&
    SERVEREXE="$RUNDIR/${SERVER}.exe"

# Work around docker bug. (tty size is updated late)
[ "$(stty size 2>/dev/null)" = "0 0" ] && {
    for i in 1 2 3 4 5 ; do [ "$(stty size)" = "0 0" ] && sleep 1 ; done
    [ "$(stty size)" = "0 0" ] && {
	echo 'WARNING: Not using rlwrap because stty failed.'
	export TERM=dumb
	exec "$MONO" $MONOOPTS "$SERVEREXE"
    }
}

[ "$1" = direct ] &&
    exec "$MONO" $MONOOPTS "$SERVEREXE"

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
then exec /usr/bin/tini rlwrap -- -a -t dumb sh "$O"/start_server rcmd "$SERVEREXE"
else exec rlwrap -a -t dumb sh "$O"/start_server rcmd "$SERVEREXE"
fi

COMMIT
################################################################################

# This directory is where the data is stored
# The the script may copy the executables here too.
WORKDIR /home/user
ARG SERVER
ENV SERVER=${SERVER}
EXPOSE 25565
CMD [ "sh","/opt/mcgalaxy/start_server"]

