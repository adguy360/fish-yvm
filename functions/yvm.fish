set -g yvm_fish 0.5.0

function yvm -a cmd -d "yarn version manager"
    set -l options (fish_opt -s h -l help) (fish_opt -s v -l version)
    argparse $options -- $argv

    if test -n "$_flag_h"
      _yvm_help
      return 0
    end

    if test -n "$_flag_v"
      echo "$yvm_fish"
      return 0
    end

    set -q XDG_CONFIG_HOME
    or set XDG_CONFIG_HOME ~/.config
    set -g yvm_config $XDG_CONFIG_HOME/yvm-fish
    set -q yarn_releases_url
    or set -g yarn_releases_url "https://d236jo9e8rrdox.cloudfront.net/yarn-releases"

    if not test -d $yvm_config
        command mkdir -p $yvm_config
    end

    switch "$cmd"
        case ls list
            set -e argv[1]
            _yvm_ls $argv
        case use
            set -e argv[1]
            _yvm_use $argv
        case rm
            set -e argv[1]
            _yvm_rm $argv
        case ""
            echo HELLo
        case \*
            echo "yvm: unknown flag or command \"$cmd\"" >&2
            _yvm_help >&2
            return 1
    end
end

function _yvm_get_releases
    set -q yvm_last_updated
    or set -g yvm_last_updated 0
    set -l releases "$yvm_config/yarn_releases"

    if test -n "$_flag_f"
        or test ! -e $releases -o (math (command date +%s) - $yvm_last_updated) -gt 120
        # DOCUMENT
        echo "Fetching releases from $yarn_releases_url" >&2

        command curl -s $yarn_releases_url \
            | tr ',' '\n'\
 | awk -F'":"' '
                {
                  version;
                  gsub(/"/, "", $2)
                  if ($1 ~ /name/ ) { version = $2 }
                  if ($1 ~ /tarball/) { gsub(/v/, "", version); print version, $2 }
                }
            ' >$releases 2>/dev/null

        if test ! -s "$releases"
            echo "yvm: couldn't fetch releases -- is \"$yarn_releases_url\" a valid host?" >&2
            return 1
        end

        set -g yvm_last_updated (command date +%s)
    end

    echo $releases
end

function _yvm_use
    set -l options (fish_opt -s f -l force-fetch)
    argparse $options -- $argv

    set -l force_fetch 0

    if test -n "$_flag_f"
        set force_fetch 1
    end

    set -l releases (_yvm_get_releases "$force_fetch")

    set -l yarn_version
    set -l version_to_install $argv

    if test $version_to_install = "latest"
        set version_to_install (cat $releases | head -n 1 | awk '{ print $1 }')
    end

    if not test (grep "^$version_to_install" $releases)
        echo "Version $version_to_install not found. Consider running \"yvm ls\" and check that the version is correct."
        return 1
    end

    if not test -d "$yvm_config/$version_to_install"
        set -l tarball_base_name "yarn-v$version_to_install"

        set -l url "https://yarnpkg.com/downloads/$version_to_install/$tarball_base_name.tar.gz"

        echo "fetching $url" >&2

        set -l temp_dir (command mktemp -d -t "yvm-yarn-$version_to_install-XXXXXXXXXXXXX")

        if not command curl -L --fail --progress-bar $url | command tar -xzf- -C $temp_dir
            command rm -rf $temp_dir
            echo "yvm: fetch error -- are you offline?" >&2
            return 1
        end

        command mkdir -p "$yvm_config/$version_to_install/"

        # Newer yarn versions have /yarn_version/bin in their tarball
        if test -d "$temp_dir/$tarball_base_name/"
            command mv $temp_dir/$tarball_base_name/* "$yvm_config/$version_to_install/"
            # Older yarn versions have just /dist/bin and /dist/lib in the tarball
        else if test -d "$temp_dir/dist/"
            command mv $temp_dir/dist/* "$yvm_config/$version_to_install/"
        end

        command rm -r $temp_dir
    end

    if not test -d "$yvm_config/$version_to_install/"
      echo "Failed to install yarn version \"$version_to_install\", but curl didn't error. Please report this bug."
      return 1
    end

    if test -s "$yvm_config/version"
        read -l last <"$yvm_config/version"
        if set -l i (contains -i -- "$yvm_config/$last/bin" $fish_user_paths)
            set -e fish_user_paths[$i]
        end
    end

    echo $version_to_install >$yvm_config/version

    if not contains -- "$yvm_config/$version_to_install/bin" $fish_user_paths
        set -U fish_user_paths "$yvm_config/$version_to_install/bin" $fish_user_paths
    end
end

function _yvm_rm
    set -l options (fish_opt -s f -l force-fetch)
    argparse $options -- $argv

    set -l force_fetch 0

    if test -n "$_flag_f"
        set force_fetch 1
    end

    set -l releases (_yvm_get_releases "$force_fetch")

    set -l yarn_version $argv[1]
    read -l active_version <"$yvm_config/version"

    if test $yarn_version = "latest"
        set yarn_version (cat $releases | head -n 1 | awk '{ print $1 }')
    end

    if test -n "$active_version"
        echo "" >"$yvm_config/version"
    end

    if set -l i (contains -i -- "$yvm_config/$yarn_version/bin" $fish_user_paths)
        set -e fish_user_paths[$i]
    end

    if not test -d "$yvm_config/$yarn_version/"
        echo "No version \"$yarn_version\" found on file system in \"$yvm_config/$yarn_version/\""
    else
        rm -r "$yvm_config/$yarn_version/"
    end

    return 0
end

function _yvm_ls
    set -l options (fish_opt -s f -l force-fetch)
    argparse $options -- $argv
    set -l force_fetch 0

    if test -n "$_flag_f"
        set force_fetch 1
    end

    set -l releases (_yvm_get_releases "$force_fetch")
    set -l yarn_version

    if test -f "$yvm_config/version"
        read yarn_version <"$yvm_config/version"
    end

    # https://github.com/jorgebucaran/fish-cookbook#how-do-i-read-from-a-file-in-fish
    while read -la release
        set -l parts (string split " " $release)
        set -l release_version $parts[1]
        set -l is_installed 0

        if test -d "$yvm_config/$release_version"
            set is_installed 1
        end

        echo -n $release_version

        if test "$is_installed" -eq 1
            echo -n \t "installed"
        end

        if test -n $yarn_version
            and test "$yarn_version" = "$release_version"
            echo -n \t "active"
        end

        echo \t
    end <$releases
end

function _yvm_help
    echo "usage: yvm --help           Show this help"
    echo "       yvm --version        Show the current version of yvm"
    echo "       yvm use <version>    Download <version> and modify PATH to use it."
    echo "                            Needs to be the exact version from ls."
    echo "       yvm ls/list          List all versions including if they're installed and/or active"
    echo "       yvm rm               Remove specified version from file system and PATH."
    echo "                            Needs to be the exact version from ls."
    echo "       yvm -f/--force-fetch Force fetch the releases from remote before use or ls"
    echo "examples:"
    echo "       yvm use 1.17.3"
    echo "       yvm use latest"
    echo "       yvm ls"
    echo "       yvm ls -f"
end
