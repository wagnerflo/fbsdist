. ${_fbsdist_prefix}/common.sh

request rootfs bootfs container_mnt

_first_inst=1
_first_dist=1

list_by_type root ${container} | sed "s@^${container}/@@" | sort -n | while read _num; do
    [ ${_first_inst} -eq 1 ] && \
        printf "Installations:\\n" && _first_inst=0

    _fs="${container}/${_num}"
    _version="$(zget fbsdist:version ${_fs})"
    _timestamp="$(zget fbsdist:timestamp ${_fs})"

    printf " [ "
    [ "${_fs}" = "${rootfs}" ] && printf "R " || printf "  "
    [ "${_fs}" = "${bootfs}" ] && printf "B " || printf "  "
    printf "] ${container}/"
    printf "%-3i" ${_num}
    [ ! -z "${_version}" ] && printf "   ${_version}"
    [ ! -z "${_timestamp}" ] && \
        printf "   $(date -r${_timestamp} "+%d %b %Y %R %Z") (${_timestamp})"
    printf "\\n"
done

find -s ${container_mnt} -mindepth 2 -maxdepth 2 -type f -name manifest | \
while read manifest
do
    [ ${_first_dist} -eq 1 ] && \
        printf "\\nDistributions:\\n" && _first_dist=0

    read type timestamp version sha256 <<EOF
$(check_manifest < ${manifest})
EOF
    echo " (${timestamp})   ${version}   $(date -r${timestamp} "+%d %b %Y %R %Z")"
done

printf "\\n"
