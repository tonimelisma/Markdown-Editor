# What makes the published app different from the one in the newest release: its sources, its
# project, and the scripts that sign it. Signing is in that list because build 202's defect was
# entirely in the signing — a fix that only touched Scripts/ would never have been published.
#
# One list, read by both sides of the question "is there an app to publish?": Scripts/release.sh,
# which publishes when these paths differ from the newest release, and CI's `changes` job, which
# must run the macOS job whenever the release would (.github/workflows/ci.yml).
# shellcheck disable=SC2034 # read by the scripts that source this file
app_paths=("Markdown Editor" "Markdown Editor.xcodeproj" Scripts/release.sh Scripts/adhoc-harden.sh)
