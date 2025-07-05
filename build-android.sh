#!/bin/bash
set -e
source swift-define

# Build with SwiftPM
export JAVA_HOME=$SWIFT_ANDROID_SYSROOT/usr
xcrun --toolchain swift swift build -c $SWIFT_COMPILATION_MODE \
    --swift-sdk $SWIFT_TARGET_NAME \
    --toolchain $XCTOOLCHAIN