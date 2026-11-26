#!/bin/bash
# Writes Sparkle's update feed for one build to standard output:
#   Scripts/appcast.sh <owner/repo> <build> <version x.y.z> <archive URL> <archive length> <EdDSA signature>
# <build> is CFBundleVersion, the commit count Sparkle compares; <version> is the release's
# v<x.y.z> and CFBundleShortVersionString. The feed holds only the newest build: Sparkle needs
# nothing older. Installed copies read it from
# https://github.com/<owner/repo>/releases/latest/download/appcast.xml (SUFeedURL).
# Every value is validated rather than escaped, so nothing written can need XML escaping.
# Tested by Scripts/test-release-scripts.sh.
set -euo pipefail

usage="usage: appcast.sh <owner/repo> <build> <version> <url> <length> <signature>"
repo="${1:?$usage}"
build="${2:?$usage}"
short="${3:?$usage}"
url="${4:?$usage}"
length="${5:?$usage}"
signature="${6:?$usage}"
minimum_system="27.0" # MACOSX_DEPLOYMENT_TARGET (docs/DECISIONS.md, 2026-08-22)

refuse() {
    echo "appcast: $*" >&2
    exit 1
}
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || refuse "repository $repo isn't owner/name"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || refuse "build $build isn't a positive number"
[[ "$short" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || refuse "version $short isn't x.y.z"
[[ "$length" =~ ^[1-9][0-9]*$ ]] || refuse "length $length isn't a positive number"
case "$url" in
    "https://github.com/$repo/releases/download/v$short/"*) ;;
    *) refuse "the archive isn't in the release v$short of $repo" ;;
esac
[[ "$url" != *[\&\<\>\"\'\ ]* ]] || refuse "the URL holds a character XML would need escaped"
[[ "$signature" =~ ^[A-Za-z0-9+/]+=*$ ]] || refuse "the signature isn't base64"
date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat <<FEED
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Markdown Editor</title>
    <item>
      <title>Markdown Editor $short</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$short</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
      <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
FEED
