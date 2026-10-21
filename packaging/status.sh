# rootful ios 10 did not load Senko's status extension through a payload symlink
shiro_status_install() (
    status_source=$1
    status_filter=$2
    status_dir=$3
    status_rootless=$4
    [ -f "$status_source" ] && [ -f "$status_filter" ] || return 1
    mkdir -p "$status_dir" || return 1
    for status_name in shirostatus.dylib shirostatus.plist; do
        status_target=$status_dir/$status_name
        if [ -L "$status_target" ]; then
            case "$(readlink "$status_target")" in
                /var/jb/usr/lib/shirostatus.dylib|/var/jb/usr/lib/shirostatus-modern.dylib|/var/jb/usr/lib/shirostatus.plist) ;;
                *) echo "refusing to replace unmanaged $status_target" >&2; return 1 ;;
            esac
        elif [ -e "$status_target" ] && [ ! -f "$status_dir/.shirostatus-managed" ]; then
            echo "refusing to replace unmanaged $status_target" >&2
            return 1
        fi
        [ ! -e "$status_target.dpkg-new" ] && [ ! -L "$status_target.dpkg-new" ] || return 1
    done
    trap 'rm -f "$status_dir/shirostatus.dylib.dpkg-new" "$status_dir/shirostatus.plist.dpkg-new"' 0
    if [ "$status_rootless" = 1 ]; then
        ln -s "$status_source" "$status_dir/shirostatus.dylib.dpkg-new" || return 1
    else
        cp "$status_source" "$status_dir/shirostatus.dylib.dpkg-new" || return 1
        chmod 755 "$status_dir/shirostatus.dylib.dpkg-new" || return 1
    fi
    cp "$status_filter" "$status_dir/shirostatus.plist.dpkg-new" || return 1
    chmod 644 "$status_dir/shirostatus.plist.dpkg-new" || return 1
    # mark ownership before replacing an older managed pair, so a failed upgrade can be retried
    : > "$status_dir/.shirostatus-managed" || return 1
    mv -f "$status_dir/shirostatus.dylib.dpkg-new" "$status_dir/shirostatus.dylib" || return 1
    mv -f "$status_dir/shirostatus.plist.dpkg-new" "$status_dir/shirostatus.plist" || return 1
)
