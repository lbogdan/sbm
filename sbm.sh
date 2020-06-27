#!/bin/sh

# dependecies: grep, wget (curl?), chmod, head, cut, cat, tr

# functions

# get_first_line text
get_first_line() {
  echo "$1" | head -n 1
}

# get_version name
get_version() {
  binary_name="$1"

  if ! which "$binary_name" >/dev/null; then
    return
  fi

  binary="$(get_binary "$binary_name")"
  version="$(get_key "$binary" version)"

  if [ "$version" = "null" ]; then
    echo "ERROR: binary \"$binary_name\" doesn't have a version field"
    exit 1
  fi

  eval $binary_name $version
}

# get_version_list releaseArray
get_version_list() {
  printf "%s" "$1" | jq -r ".[] | .tag_name" | grep -E -v -- "-alpha|-beta|-?rc" | sort -r --version-sort
}

# get_release releaseObject version(/tag)
get_release() {
  # printf "%s" "$1" | jq ".[] | select(.tag_name == \"$2\")"
  printf "%s" "$1" | jq ".[] | select(.tag_name | test(\"v?$2\"))"
}

# get_binary name
get_binary() {
  printf "%s" "$BINARIES" | jq ".[] | select(.name == \"$1\")"
}

# get_key genericObject key
get_key() {
  printf "%s" "$1" | jq -r ".$2"
}

# get_releases repo
get_releases() {
  url="https://api.github.com/repos/$repo/releases"
  >&2 echo "DEBUG: fetching releases metadata from $url..."
  wget -O - -q "$url"
}

# get_asset releaseObject name
get_asset() {
  printf "%s" "$1" | jq ".assets[] | select(.name | test(\"$2\"))"
}

do_list_binaries() {
  printf "%s" "$BINARIES" | jq -r ".[] | .name"
}

# do_list_versions name
do_list_versions() {
  binary_name="$1"
  binary="$(get_binary "$binary_name")"

  if [ -z "$binary" ]; then
    >&2 echo "ERROR: \"$binary_name\" not found in the binary database"
    exit 1
  fi

  repo="$(get_key "$binary" repo)"
  releases="$(get_releases "$repo")"
  versions="$(get_version_list "$releases")"
  current_version="$(get_version "$binary_name")"
  for version in $(echo "$versions"); do
    version="${version##*v}"
    if [ "${current_version##*v}" = "${version##*v}" ]; then
      version="$version (current)"
    elif which "$BINDIR/$binary_name-$version" >/dev/null; then
      version="$version (installed)"
    fi
    echo "$version"
  done
}

do_install_binary() {
  binary_name="$1"
  version="${2-}"

  current_version="$(get_version "$binary_name")"
  # echo "current version: $current_version"

  binary="$(get_binary "$binary_name")"

  if [ -z "$binary" ]; then
    >&2 echo "ERROR: \"$binary_name\" not found in the binary database"
    exit 1
  fi

  repo="$(get_key "$binary" repo)"
  releases="$(get_releases "$repo")"

  if [ -z "$version" ]; then
    version=$(get_first_line "$(get_version_list "$releases")")
  fi

  # if [ "$(echo $current_version | tr -d v)" = "$(echo $version | tr -d v)" ]; then
  if [ "${current_version##*v}" = "${version##*v}" ]; then
    echo "$binary_name version $version already installed"
    return
  fi

  download_url="$(get_key "$binary" download_url)"
  if [ "$download_url" = "null" ]; then
    # echo $version
    release="$(get_release "$releases" $version)"
    # echo "release: [$release]"
    # exit
    asset="$(get_asset "$release" $(get_key "$binary" asset))"
    # echo "$asset"
    # exit
    url="$(get_key "$asset" browser_download_url)"
  else
    version="${version##*v}"
    url="$(eval echo "$download_url")"
  fi
  # echo "$url"
  # exit

  binary_file="$BINDIR/$binary_name"

  if [ ! -z "$current_version" -a -f "$binary_file" ]; then
    versioned_binary="$binary_file-${current_version##*v}"
    mv "$binary_file" "$versioned_binary"
    >&2 echo "DEBUG: renamed $binary_file to $versioned_binary"
  fi

  targz="$(get_key "$binary" targz)"

  if [ "$targz" != "null" ]; then
    tmp_file="/tmp/$binary_name.tar.gz"
    echo "DEBUG: downloading $binary_name ($version) archive from $url into $tmp_file..."
    wget -O "$tmp_file" -q "$url"
    # get the number of slashes in $targz, we need to strip that many
    # components from the path when we untar
    components="$(echo "$targz" | tr -cd / | wc -c)"
    tar -C "$BINDIR" -f "$tmp_file" -x -z --strip-components "$components" --wildcards "$targz"
    chmod +x "$binary_file"
    unlink "$tmp_file"
  else
    echo "DEBUG: downloading $binary_name ($version) from $url into $binary_file..."
    wget -O "$binary_file" -q "$url"
    chmod +x "$binary_file"
  fi
}

do_use_binary() {
  binary_name="$1"
  version="$2"

  binary_file="$BINDIR/$binary_name"
  versioned_binary="$binary_file-$version"

  if [ ! -f "$versioned_binary" ]; then
    >2& echo "ERROR: binary $binary_name version $version is not installed"
    exit 1
  fi

  current_version="$(get_version "$binary_name")"
  current_version="${current_version##*v}"

  >&2 echo "DEBUG: renaming $binary_file to $binary_file-$current_version"
  mv "$binary_file" "$binary_file-$current_version"
  >&2 echo "DEBUG: renaming $versioned_binary to $binary_file"
  mv "$versioned_binary" "$binary_file"
}

# binaries

BINARIES="$(cat <<-END
[
  {
    "name": "jq",
    "repo": "stedolan/jq",
    "asset": "jq-linux64",
    "version": "--version | cut -d - -f 2"
  },
  {
    "name": "kubectl",
    "repo": "kubernetes/kubernetes",
    "download_url": "https://storage.googleapis.com/kubernetes-release/release/v\$version/bin/linux/amd64/kubectl",
    "version": "version --client --short | cut -d ' ' -f 3"
  },
  {
    "name": "k9s",
    "repo": "derailed/k9s",
    "asset": "k9s_Linux_x86_64.tar.gz",
    "targz": "k9s",
    "version": "version -s | head -n 1 | tr -s ' ' | cut -d ' ' -f 2"
  },
  {
    "name": "kapp",
    "repo": "k14s/kapp",
    "asset": "kapp-linux-amd64",
    "version": "version | head -n 1 | cut -d ' ' -f 3"
  },
  {
    "name": "helm",
    "repo": "helm/helm",
    "download_url": "https://get.helm.sh/helm-v\$version-linux-amd64.tar.gz",
    "targz": "*/helm",
    "version": "version -c --short | cut -d ' ' -f 2 | cut -d + -f 1"
  },
  {
    "name": "sops",
    "repo": "mozilla/sops",
    "asset": "sops-.+linux",
    "version": "-v | cut -d ' ' -f 2"
  },
  {
    "name": "drone",
    "repo": "drone/drone-cli",
    "asset": "drone_linux_amd64.tar.gz",
    "targz": "drone",
    "version": "-v | cut -d ' ' -f 3"
  },
  {
    "name": "okteto",
    "repo": "okteto/okteto",
    "asset": "okteto-Linux-x86_64",
    "version": "version | cut -d ' ' -f 3"
  },
  {
    "name": "octant",
    "repo": "vmware-tanzu/octant",
    "asset": "octant_.+_Linux-64bit.tar.gz",
    "targz": "*/octant"
  },
  {
    "name": "kail",
    "repo": "boz/kail",
    "asset": "kail_.+_linux_amd64",
    "targz": "kail",
    "version": "version | cut -d ' ' -f 1"
  },
  {
    "name": "dive",
    "repo": "wagoodman/dive",
    "asset": "dive_.+_linux_amd64.tar.gz",
    "targz": "dive",
    "version": "-v | cut -d ' ' -f 2"
  }
]
END
)"

set -e
set -u
# set -x

eval BINDIR="${BINDIR:-~/bin}"

if ! echo $PATH | grep -q $BINDIR; then
  >&2 echo "ERR: BINDIR $BINDIR is not in PATH"
  exit 1
fi

if ! which jq >/dev/null; then
  >&2 echo "DEBUG: jq not found, downloading..."
  binary_file="$BINDIR/jq"
  wget -O $binary_file -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x $binary_file
fi

if [ $# -eq 1 -a "$1" = "list" ]; then
  do_list_binaries
fi

if [ $# -gt 1 -a "$1" = "list" ]; then
  shift
  do_list_versions $@
fi

if [ $# -gt 1 -a "$1" = "install" ]; then
  shift
  do_install_binary $@
fi

if [ $# -gt 1 -a "$1" = "use" ]; then
  shift
  do_use_binary $@
fi

if [ $# -gt 1 -a "$1" = "version" ]; then
  get_version "$2"
fi
