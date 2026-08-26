#!/bin/sh

xattr -dr com.apple.quarantine .

find . -type f -name "*.dylib" -print0 | xargs -0 -n 1 codesign --force --sign -

