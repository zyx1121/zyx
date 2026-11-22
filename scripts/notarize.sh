#!/bin/sh
# Notarizes a signed zyx.app with Apple and staples the ticket, so Gatekeeper
# accepts it on any Mac, even offline. Uses the notarytool keychain profile
# in NOTARY_PROFILE (default zyx-notary), made once with:
#   xcrun notarytool store-credentials zyx-notary --apple-id <id> --team-id 68PK3GTMDD
set -eu
app=$1
profile=${NOTARY_PROFILE:-zyx-notary}
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "$app: not notarized, no notarytool profile $profile"
  exit 0
fi
zip=$(mktemp -d)/zyx.zip
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl -a -vv "$app"
