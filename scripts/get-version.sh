#!/bin/bash
# shellcheck disable=SC2164

# consistently name all builds, regardless of OS or desktop/mobile
#
# we do need to be able to create three digit (M.m.p) and four digit (M.m.p.c) version strings
# default is VERSION_EXTENSION version - an argument of '1', '3', or '4' gets you a digits only version string
#
# we hardcode a base version - this will rarely change
# (we actually haven't discussed a situation where it would change...)
SUBSURFACE_BASE_VERSION=6.0

# little silly helper functions
croak() {
	echo "$0: $*" >&2
	exit 1
}
croak_usage() {
	croak "Usage: $0 [1|3|4]"
}

if [[ $# -gt 1 ]] ; then croak_usage ; fi
if [[ $# -eq 1 ]] ; then
	if [[ $1 != "1" && $1 != "3" && $1 != "4" ]] ; then croak_usage ; fi
	DIGITS="$1"
fi

# figure out where we are in the file system
pushd "$(dirname "$0")/../" &> /dev/null
export SUBSURFACE_SOURCE=$PWD

VERSION_EXTENSION="-"

# add the build number to this as 'patch' component
# if we run in an environment where we are given a build number (e.g. CICD builds)
# we just grab that - otherwise we have to figure it out on the fly
if [ ! -f latest-subsurface-buildnumber ] ; then
	# figure out the most recent build number, given our own git history
	# this assumes that (a) we are in a checked out git tree and
	# (b) we have the ability to check out another git repo
	# in situations where either of these isn't true, it's the caller's
	# responsibility to ensure that the latest-subsurface-buildnumber file exists
	if [ ! -d "nightly-builds" ] ; then
		git clone https://github.com/subsurface/nightly-builds &> /dev/null || croak "failed to clone nightly-builds repo"
	fi
	pushd nightly-builds &> /dev/null
	git fetch &> /dev/null
	LAST_BUILD_BRANCHES=$(git branch -a --sort=-committerdate --list | grep remotes/origin/branch-for | cut -d/ -f3)
	for LAST_BUILD_BRANCH in $LAST_BUILD_BRANCHES "not-found" ; do
		LAST_BUILD_SHA=$(cut -d- -f 3 <<< "$LAST_BUILD_BRANCH")
		git -C "$SUBSURFACE_SOURCE" merge-base --is-ancestor "$LAST_BUILD_SHA" HEAD && break
	done
	[ "not-found" = "$LAST_BUILD_BRANCH" ] && croak "can't find a build number for the current working tree"
	git checkout "$LAST_BUILD_BRANCH" &> /dev/null || croak "failed to check out $LAST_BUILD_BRANCH in nightly-builds"
	BUILDNR=$(<./latest-subsurface-buildnumber)
	popd &> /dev/null
	VERSION_EXTENSION+=$(git log --pretty="oneline" "${LAST_BUILD_SHA}...HEAD" | wc -l | tr -d '[:space:]')
	VERSION_EXTENSION+="-"
	[ "$VERSION_EXTENSION" = "-0-" ] && VERSION_EXTENSION="-"
else
	BUILDNR=$(<"latest-subsurface-buildnumber")
fi

if [ -f "latest-subsurface-buildnumber-extension" ] ; then
	VERSION_EXTENSION+=$(<"latest-subsurface-buildnumber-extension")
else
	VERSION_EXTENSION+="local"
fi

COMMITS_SINCE=$(tr -cd "[:digit:]" <<<"$VERSION_EXTENSION")
[[ -z $COMMITS_SINCE ]] && COMMITS_SINCE="0"

if [[ $DIGITS == "1" ]] ; then
	VERSION="${BUILDNR}"
elif [[ $DIGITS == "3" ]] ; then
	VERSION="${SUBSURFACE_BASE_VERSION}.${BUILDNR}"
elif [[ $DIGITS == "4" ]] ; then
	VERSION="${SUBSURFACE_BASE_VERSION}.${BUILDNR}.${COMMITS_SINCE}"
else
	VERSION="${SUBSURFACE_BASE_VERSION}.${BUILDNR}${VERSION_EXTENSION}"
fi

printf '%s' "$VERSION"

popd &> /dev/null
