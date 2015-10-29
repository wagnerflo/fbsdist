. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} DIST"
    exit 1
}

_dist=${1}
if [ -z "${_dist}" ]; then
    usage
fi

request rootfs container container_mnt

read _type _timestamp _version _sha256 <<EOF
$(check_manifest < ${container_mnt}/${_dist}/manifest)
EOF

[ "$(sha256 < ${container_mnt}/${_dist}/data)" = "${_sha256}" ] \
    || err 1 "Distribution data file has bad checksum"

_nextfs=$(list_by_type root | sed "s@${container}/@@" | sort -nr | head -1)
_nextfs=${container}/$(expr ${_nextfs:-0} + 1)

zfs create \
    -o mountpoint=none \
    -o atime=off \
    -o devices=on \
    -o exec=on \
    -o setuid=on \
    -o canmount=noauto \
    -o fbsdist:type=root \
    -o fbsdist:version=${_version} \
    -o fbsdist:timestamp=${_timestamp} \
    ${_nextfs}
add_cleanup zfs destroy -r ${_nextfs}

_nextmnt=$(tmpdir)
add_cleanup rm -rf ${_nextmnt}

mountfs ${_nextfs} ${_nextmnt}
add_cleanup umount ${_nextmnt}

tar xf ${container_mnt}/${_dist}/data -C ${_nextmnt}
zfs snapshot ${_nextfs}@clean

if [ ! -z "$(zfs list -H ${rootfs}@clean 2>/dev/null)" \
    -a -f ${container_mnt}/prepare.sh ]
then
    _origin=$(tmpdir)
    add_cleanup rm -rf ${_origin}

    _current=$(tmpdir)
    add_cleanup rm -rf ${_current}

    mountfs ${rootfs}@clean ${_origin}
    add_cleanup umount ${_origin}

    zfs snapshot ${rootfs}@__fbsdist_current__
    add_cleanup zfs destroy ${rootfs}@__fbsdist_current__

    mountfs ${rootfs}@__fbsdist_current__ ${_current}
    add_cleanup umount ${_current}

    env -i PATH=${PATH} \
        origin=${_origin} current=${_current} new=${_nextmnt} \
        /bin/sh -e ${_fbsdist_prefix}/fbsdist_install_prepare.sh \
        ${container_mnt}/prepare.sh
fi

del_cleanup zfs destroy -r ${_nextfs}
zfs snapshot ${_nextfs}@prepare
