#!/bin/sh

# dependecies: grep, wget (curl?), chmod, head, cut, cat

# functions

# get_first_line text
get_first_line() {
  echo "$1" | head -n 1
}

# get_version name
get_version() {
  case $1 in
  jq)
    $1 --version | cut -d - -f 2
    ;;
  okteto)
    $1 version | cut -d " " -f 3
    ;;
  esac
}

# get_version_list releaseArray
get_version_list() {
  printf "%s" "$1" | jq -r ".[] | .tag_name"
}

# get_release releaseObject version(/tag)
get_release() {
  printf "%s" "$1" | jq ".[] | select(.tag_name == \"$2\")"
}

# get_binary name
get_binary() {
  printf "%s" "$BINARIES" | jq ".[] | select(.name == \"$1\")"
}

# get_key genericObject key
get_key() {
  printf "%s" "$1" | jq -r ".$2"
}

# get_releases name
get_releases() {
  wget -O - -q "https://api.github.com/repos/$(get_key "$1" repo)/releases"
}

# get_asset releaseObject name
get_asset() {
  printf "%s" "$1" | jq ".assets[] | select(.name == \"$2\")"
}

# binaries

BINARIES="$(cat <<-END
[
  {
    "name": "okteto",
    "repo": "okteto/okteto",
    "asset": "okteto-Linux-x86_64"
  }
]
END
)"

set -e
set -u
# set -x

eval BINDIR="${BINDIR:-~/bin}"

if ! echo $PATH | grep $BINDIR; then
  echo "ERR: BINDIR is not in PATH"
  exit 1
fi

if ! which jq; then
  echo "DBG: jq not found, downloading..."
  binary_file="$BINDIR/jq"
  wget -O $binary_file -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x $binary_file
fi

binary_name=$1

if which $binary_name; then
  echo "ERR: $binary_name ($(get_version $binary_name)) already installed"
  exit 1
fi

binary="$(get_binary $binary_name)"

if [ -z "$binary" ]; then
  echo "not found"
fi

releases="$(get_releases "$binary")"

last_version=$(get_first_line "$(get_version_list "$releases")")

# echo $last_version

release="$(get_release "$releases" $last_version)"

asset="$(get_asset "$release" $(get_key "$binary" asset))"

url="$(get_key "$asset" browser_download_url)"

# echo "$url"

binary_file=$BINDIR/$binary_name

echo "DBG: downloading $binary_name ($last_version) from $url into $binary_file..."

wget -O $binary_file -q $url
chmod +x $binary_file
