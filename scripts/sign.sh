#!/bin/sh
# Signs zyx.app with the hardened runtime.
set -eu
app=$1
id=${SIGN_IDENTITY:-"Developer ID Application: YongXiang Zhan (68PK3GTMDD)"}
xattr -cr "$app"
codesign --force --timestamp --options runtime --sign "$id" "$app"
codesign --verify --strict "$app"
echo "$app: signed by $id"
