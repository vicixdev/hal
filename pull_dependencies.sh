#!/bin/sh

set -e

mkdir -p ./.tmp

pull_github_commit () {
	local target_name=$1
	local github_user=$2
	local github_repository=$3
	local github_commit=$4

	wget https://github.com/$github_user/$github_repository/archive/$github_commit.tar.gz -O ./.tmp/download.tar.gz
	tar -xzf ./.tmp/download.tar.gz -C ./.tmp

	rm -rf ./$target_name
	mv ./.tmp/$github_repository-$github_commit ./$target_name
	rm ./.tmp/download.tar.gz
}

pull_github_release () {
	local target_name=$1
	local github_user=$2
	local github_repository=$3
	local github_release=$4
	local artifact=$5

	wget https://github.com/$github_user/$github_repository/releases/download/$github_release/$artifact.tar.gz -O ./.tmp/download.tar.gz

	rm -rf ./$target_name
	mkdir ./$target_name
	tar -xzf ./.tmp/download.tar.gz -C ./$target_name

	rm ./.tmp/download.tar.gz
}

get_slang () {
	case $(uname) in
		Darwin)	local slang_os=macos ;;
		Linux)	local slang_os=linux ;;
	esac

	case $(uname -m) in
		x86_64)		local slang_arch=x86_64 ;;
		aarch64)	local slang_arch=aarch64 ;;
	esac

	pull_github_release tools/slang shader-slang slang v2026.13 slang-2026.13-$slang_os-$slang_arch
}

pull_github_commit shared/back laytan back 9d4117268e49a710727de4eae1e65d7417fc1c2a
get_slang

rm -rf ./.tmp

