. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} ID"
    exit 1
}

_install=${1}
if [ -z "${_install}" ]; then
    usage
fi

request container
_fs=${container}/${_install}
list_by_type root | grep -q ^${_fs}$ || \
    err 1 "No root filesystem ${_fs}"

request container_mnt
echo "zfs:${_fs}:boot/loader" > ${container_mnt}/boot.config
