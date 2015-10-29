. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} ZPOOL"
    exit 1
}

_zpool=${1}
if [ -z "${_zpool}" ]; then
    usage
fi

# request variables and state
request container

# sanity check if there is already a root container designated
[ -z "${container}" ] \
    || err 1 "${container} is already designated as a fbsdist root container"

# sanity check whether pool exists
zpool list ${_zpool} >/dev/null

# try to create the fs
zfs create \
  -o mountpoint=none \
  -o canmount=noauto \
  -o atime=off \
  -o exec=off \
  -o setuid=off \
  -o fbsdist:type=container ${_zpool}/root

request container_mnt
touch ${container_mnt}/boot.config
