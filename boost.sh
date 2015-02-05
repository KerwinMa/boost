#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
# Modified version
#===============================================================================
#
# Builds a Boost framework for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_LIBS:        which libraries to build
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 5.1)
#
# Then go get the source tar.bz of the boost you want to build, shove it in the
# same directory as this script, and run "./boost.sh". Grab a cuppa. And voila.
#===============================================================================

: ${BOOST_LIBS:="regex thread system date_time"}
: ${IPHONE_SDKVERSION:=`xcodebuild -showsdks | grep iphoneos | egrep "[[:digit:]]+\.[[:digit:]]+" -o | tail -1`}
: ${OSX_SDKVERSION:=10.8}
: ${XCODE_ROOT:=`xcode-select -print-path`}
: ${EXTRA_CPPFLAGS:=""}
: ${STD_FLAG:="c++11"}
: ${STDLIB_FLAG:="libc++"}

#
# WARNING
#
# Use "-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS" in the
# EXTRA_CPPFLAGS definition to work around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

: ${TARBALLDIR:=`pwd`}
: ${SRCDIR:=`pwd`/src}
: ${IOSBUILDDIR:=`pwd`/ios/build}
: ${OSXBUILDDIR:=`pwd`/osx/build}
: ${PREFIXDIR:=`pwd`/ios/prefix}
: ${IOSFRAMEWORKDIR:=`pwd`/ios/framework}
: ${IOSLIBRARYDIR:=`pwd`/ios/library}
: ${OSXFRAMEWORKDIR:=`pwd`/osx/framework}
: ${OSXLIBRARYDIR:=`pwd`/osx/library}
: ${COMPILER:="clang++"}

: ${BOOST_VERSION:=1.53.0}
: ${BOOST_VERSION2:=1_53_0}

BOOST_TARBALL=$TARBALLDIR/boost_$BOOST_VERSION2.tar.bz2
BOOST_SRC=$SRCDIR/boost_${BOOST_VERSION2}

#===============================================================================
ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"
OSX_DEV_CMD="xcrun --sdk macosx"

ARM_COMBINED_LIB=$IOSBUILDDIR/lib_boost_arm.a
SIM_COMBINED_LIB=$IOSBUILDDIR/lib_boost_x86.a

#===============================================================================


#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "================================================================="
    echo "Done"
    echo
}

#===============================================================================

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...

    rm -rf iphone-build iphonesim-build osx-build
    rm -rf $IOSBUILDDIR
    rm -rf $OSXBUILDDIR
    rm -rf $PREFIXDIR
    rm -rf $IOSFRAMEWORKDIR/$FRAMEWORK_NAME.framework
    rm -rf $OSXFRAMEWORKDIR/$FRAMEWORK_NAME.framework

    doneSection
}

#===============================================================================

downloadBoost()
{
    if [ ! -s $TARBALLDIR/boost_${BOOST_VERSION2}.tar.bz2 ]; then
        echo "Downloading boost ${BOOST_VERSION}"
        curl -L -o $TARBALLDIR/boost_${BOOST_VERSION2}.tar.bz2 http://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/boost_${BOOST_VERSION2}.tar.bz2/download
    fi

    doneSection
}

#===============================================================================

downloadPatch()
{
    if [ "${BOOST_VERSION}" = "1.54.0" ]; then
        if [ ! -s $TARBALLDIR/boost-1.54.0-thread-link_atomic.patch ]; then
            echo "Downloading patches for boost ${BOOST_VERSION}"
            curl -L -o $TARBALLDIR/boost-1.54.0-thread-link_atomic.patch https://svn.boost.org/trac/boost/raw-attachment/ticket/9041/boost-1.54.0-thread-link_atomic.patch
        fi
    fi

    doneSection
}

#===============================================================================

unpackBoost()
{
    [ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking boost into $SRCDIR...

    [ -d $SRCDIR ]    || mkdir -p $SRCDIR
    [ -d $BOOST_SRC ] || ( cd $SRCDIR; tar xfj $BOOST_TARBALL )
    [ -d $BOOST_SRC ] && echo "    ...unpacked as $BOOST_SRC"

    doneSection
}

#===============================================================================

applyBoostPatch()
{
    if [ "${BOOST_VERSION}" = "1.54.0" ]; then
        if [ ! -s "$SRCDIR/boost-1.54.0-thread-link_atomic.patch" ]; then
            echo Copying patch into $SRCDIR...

            [ -f "$TARBALLDIR/boost-1.54.0-thread-link_atomic.patch" ] || abort "Source patch is missing."

            cp "$TARBALLDIR/boost-1.54.0-thread-link_atomic.patch" "$SRCDIR/boost-1.54.0-thread-link_atomic.patch"

            pushd "$SRCDIR"
            patch -p0 < boost-1.54.0-thread-link_atomic.patch
            popd
        fi
    fi

    doneSection
}

#===============================================================================

restoreBoost()
{
    cp $BOOST_SRC/tools/build/v2/user-config.jam-bk $BOOST_SRC/tools/build/v2/user-config.jam
}

#===============================================================================

updateBoost()
{
    echo Updating boost into $BOOST_SRC...

    cp $BOOST_SRC/tools/build/v2/user-config.jam $BOOST_SRC/tools/build/v2/user-config.jam-bk

    cat >> $BOOST_SRC/tools/build/v2/user-config.jam <<EOF
using darwin : ${IPHONE_SDKVERSION}~iphone
: $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$COMPILER -arch armv6 -arch armv7 -arch armv7s -arch arm64 -fvisibility=hidden -fvisibility-inlines-hidden -std=$STD_FLAG -stdlib=$STDLIB_FLAG $EXTRA_CPPFLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${IPHONE_SDKVERSION}~iphonesim
: $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$COMPILER -arch i386 -fvisibility=hidden -fvisibility-inlines-hidden -std=$STD_FLAG -stdlib=$STDLIB_FLAG $EXTRA_CPPFLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF

    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers

    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $BOOST_SRC
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC

    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA

    doneSection
}

#===============================================================================

buildBoostForIPhoneOS()
{
    cd $BOOST_SRC

    # Install this one so we can copy the includes for the frameworks...
    ./bjam -j16 --build-dir=iphone-build --stagedir=iphone-build/stage --prefix=$PREFIXDIR toolset=darwin architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static stage
    ./bjam -j16 --build-dir=iphone-build --stagedir=iphone-build/stage --prefix=$PREFIXDIR toolset=darwin architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static install
    doneSection

    ./bjam -j16 --build-dir=iphonesim-build --stagedir=iphonesim-build/stage --toolset=darwin-${IPHONE_SDKVERSION}~iphonesim architecture=x86 target-os=iphone macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage
    doneSection

    ./b2 -j16 --build-dir=osx-build --stagedir=osx-build/stage toolset=clang cxxflags="-std=$STD_FLAG -stdlib=$STDLIB_FLAG -arch i386 -arch x86_64" linkflags="-stdlib=$STDLIB_FLAG" link=static threading=multi stage
    doneSection
}

#===============================================================================

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd $BOOST_SRC

    mkdir -p $IOSBUILDDIR/armv6/obj
    mkdir -p $IOSBUILDDIR/armv7/obj
    mkdir -p $IOSBUILDDIR/armv7s/obj
    mkdir -p $IOSBUILDDIR/i386/obj
    mkdir -p $IOSBUILDDIR/arm64/obj

    mkdir -p $OSXBUILDDIR/i386/obj
    mkdir -p $OSXBUILDDIR/x86_64/obj

    ALL_LIBS=""

    echo Splitting all existing fat binaries...

    for NAME in $BOOST_LIBS; do
        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"

        $ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv6 -o $IOSBUILDDIR/armv6/libboost_$NAME.a
        $ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv7 -o $IOSBUILDDIR/armv7/libboost_$NAME.a
        $ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv7s -o $IOSBUILDDIR/armv7s/libboost_$NAME.a
		$ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin arm64 -o $IOSBUILDDIR/arm64/libboost_$NAME.a
		
        cp "iphonesim-build/stage/lib/libboost_$NAME.a" $IOSBUILDDIR/i386/

        $ARM_DEV_CMD lipo "osx-build/stage/lib/libboost_$NAME.a" -thin i386 -o $OSXBUILDDIR/i386/libboost_$NAME.a
        $ARM_DEV_CMD lipo "osx-build/stage/lib/libboost_$NAME.a" -thin x86_64 -o $OSXBUILDDIR/x86_64/libboost_$NAME.a
    done

    echo "Decomposing each architecture's .a files"

    for NAME in $ALL_LIBS; do
        echo Decomposing $NAME...
        (cd $IOSBUILDDIR/armv6/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/armv7/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/armv7s/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/arm64/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/i386/obj; ar -x ../$NAME );

        (cd $OSXBUILDDIR/i386/obj; ar -x ../$NAME );
        (cd $OSXBUILDDIR/x86_64/obj; ar -x ../$NAME );
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"

    rm $IOSBUILDDIR/*/libboost.a
    
    echo ...armv6
    (cd $IOSBUILDDIR/armv6; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...armv7
    (cd $IOSBUILDDIR/armv7; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...armv7s
    (cd $IOSBUILDDIR/armv7s; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...arm64
    (cd $IOSBUILDDIR/arm64; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...i386
    (cd $IOSBUILDDIR/i386;  $SIM_DEV_CMD ar crus libboost.a obj/*.o; )

    rm $OSXBUILDDIR/*/libboost.a
    echo ...osx-i386
    (cd $OSXBUILDDIR/i386;  $SIM_DEV_CMD ar crus libboost.a obj/*.o; )

    echo ...x86_64
    (cd $OSXBUILDDIR/x86_64;  $SIM_DEV_CMD ar crus libboost.a obj/*.o; )
}

#===============================================================================
buildFramework()
{
    : ${1:?}
    FRAMEWORKDIR=$1
    BUILDDIR=$2
    LIBRARYDIR=$3

    VERSION_TYPE=Alpha
    FRAMEWORK_NAME=boost
    FRAMEWORK_VERSION=A

    FRAMEWORK_CURRENT_VERSION=$BOOST_VERSION
    FRAMEWORK_COMPATIBILITY_VERSION=$BOOST_VERSION

    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf $FRAMEWORK_BUNDLE
    rm -rf "$LIBRARYDIR/FRAMEWORK_NAME.a"

    echo "Framework: Setting up directories..."
    mkdir -p $FRAMEWORK_BUNDLE
    mkdir -p $FRAMEWORK_BUNDLE/Versions
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation
	mkdir -p $LIBRARYDIR

    echo "Framework: Creating symlinks..."
    ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
    ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
    ln -s .                                $FRAMEWORK_BUNDLE/Headers/boost
    ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
    ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
    ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME
    ln -s "$FRAMEWORK_NAME.a"              $FRAMEWORK_BUNDLE/Versions/Current/$FRAMEWORK_NAME

    FRAMEWORK_INSTALL_NAME="$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME.a"
    LIBRARY_INSTALL_NAME="$LIBRARYDIR/$FRAMEWORK_NAME.a"

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    $ARM_DEV_CMD lipo -create $BUILDDIR/*/libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
	$ARM_DEV_CMD lipo -create $BUILDDIR/*/libboost.a -o "$LIBRARY_INSTALL_NAME" || abort "Lipo $1 failed"
	
    echo "Framework: Copying includes..."
    cp -r $PREFIXDIR/include/boost/*  $FRAMEWORK_BUNDLE/Headers/

    echo "Framework: Creating plist..."
    cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleDevelopmentRegion</key>
<string>English</string>
<key>CFBundleExecutable</key>
<string>${FRAMEWORK_NAME}</string>
<key>CFBundleIdentifier</key>
<string>org.boost</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundlePackageType</key>
<string>FMWK</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

mkdir -p $IOSBUILDDIR

cleanEverythingReadyToStart #may want to comment if repeatedly running during dev
restoreBoost

echo "BOOST_VERSION:     $BOOST_VERSION"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_SRC:         $BOOST_SRC"
echo "IOSBUILDDIR:       $IOSBUILDDIR"
echo "OSXBUILDDIR:       $OSXBUILDDIR"
echo "PREFIXDIR:         $PREFIXDIR"
echo "IOSFRAMEWORKDIR:   $IOSFRAMEWORKDIR"
echo "IOSLIBRARYDIR:   	 $IOSLIBRARYDIR"
echo "OSXFRAMEWORKDIR:   $OSXFRAMEWORKDIR"
echo "OSXLIBRARYDIR:   	 $OSXLIBRARYDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo "XCODE_ROOT:        $XCODE_ROOT"
echo "COMPILER:          $COMPILER"
echo

downloadBoost
#downloadPatch
unpackBoost
#applyBoostPatch
#inventMissingHeaders
bootstrapBoost
updateBoost
buildBoostForIPhoneOS
scrunchAllLibsTogetherInOneLibPerPlatform
buildFramework $IOSFRAMEWORKDIR $IOSBUILDDIR $IOSLIBRARYDIR
buildFramework $OSXFRAMEWORKDIR $OSXBUILDDIR $OSXLIBRARYDIR

restoreBoost

echo "Completed successfully"

#===============================================================================
