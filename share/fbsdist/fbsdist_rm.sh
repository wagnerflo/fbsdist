. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} ID/TIMESTAMP"
    exit 1
}

_item=${1}
if [ -z "${_item}" ]; then
    usage
fi

request container
_fs=${container}/${_item}

if [ "$(zfs get -H -slocal -ovalue fbsdist:type ${_fs} 2>/dev/null)" \
        = "root" ]
then
    request rootfs
    [ "${_fs}" = "${rootfs}" ] && \
        err 1 "As ${_fs} is the current system root it cannot be destroyed!"

    request bootfs
    [ "${_fs}" = "${bootfs}" ] && \
        err 1 "As ${_fs} is selected for booting it cannot be destroyed!"

    printf "Do you really want to destroy installation ${_fs} (y/n)? "
    read _c
    case "${_c}" in
        y|Y|[Yy][Ee][Ss])
            zfs destroy -r ${_fs}
            ;;
    esac

    exit 0
fi

request container_mnt
_dist=${container_mnt}/${_item}

if [ -d "${_dist}" ]
then
    printf "Do you really want to remove distribution ${_item} (y/n)? "
    read _c
    case "${_c}" in
        y|Y|[Yy][Ee][Ss])
            rm -rf "${_dist}"
            ;;
    esac

    exit 0
fi

err 1 "Cannot find installation or distribution ${_item}"
