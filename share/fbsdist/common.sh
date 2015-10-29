unexport() {
    local _tmp
    _tmp=$(eval echo '${'${1}'}')
    eval unset ${1}
    eval ${1}=${_tmp}
}

unexport _fbsdist_prefix
unexport _fbsdist_name
unexport _fbsdist_cmd

sig_handler() {
    trap - SIGTERM SIGKILL
    trap '' SIGINT
    err 1 "Signal caught, cleaning up and exiting"
}

exit_handler() {
    trap - EXIT SIGTERM SIGKILL
    trap '' SIGINT
    set | grep ^_fbsdist_cleanup_ | cut -d= -f1 | cut -d_ -f4 | sort -nr | \
    while read _num; do
        eval '${_fbsdist_cleanup_'${_num}'}'
    done
}

add_cleanup() {
    local _num
    _num=$(set | grep ^_fbsdist_cleanup_ | \
               cut -d= -f1 | cut -d_ -f4 | sort -nr | head -1)
    _num=$(expr 1 + ${_num:-0})
    eval _fbsdist_cleanup_${_num}=\""${*}"\"
}

del_cleanup() {
    eval unset $(set | grep ^_fbsdist_cleanup_ | \
                     cut -d= -f1 | cut -d_ -f4 | sort -n | \
                 while read _num; do
                     [ "$(eval echo '${_fbsdist_cleanup_'${_num}'}')" = \
                         "${*}" ] && echo _fbsdist_cleanup_${_num} && break
                 done)
}

list_by_type() {
    zfs get -H -slocal -ovalue,name -r fbsdist:type ${2} | grep "^${1}	" | cut -f2 | sort
}

get_mountpoint() {
    mount -p | awk -v name="${1}" '$1 == name && $3 == "zfs" { print $2 }'
}

is_snapshot () {
    local _type
    _type=$(zfs get -H -ovalue type ${1} 2>/dev/null || return 1)
    [ "${_type}" = "snapshot" ]
}

is_filesystem () {
    local _type
    _type=$(zfs get -H -ovalue type ${1} 2>/dev/null || return 1)
    [ "${_type}" = "filesystem" ]
}

zget() {
    zfs get -H -slocal -ovalue ${1} ${2}
}

tmpdir() {
    mktemp -d -tfbsdist
}

mountfs() {
    mount -t zfs ${1} ${2}
}

msg() {
    echo "====>> ${1}"
}

err() {
    echo "Error: ${2}" >&2
    exit ${1}
}

request() {
    _items=,$(IFS=',' ; echo "${*}"),

    [ -z "${rootfs}" ] && case "${_items}" in
        *,rootfs,*) rootfs=$(zfs list -H -oname /) ;;
    esac

    [ -z "${container}" ] && case "${_items}" in
        *,container,*|*,container_mnt,*|*,bootfs,*)
            container=$(zfs get -H -slocal -ovalue,name fbsdist:type | \
                            grep "^container	" | cut -f2) ;;
    esac

    [ -z "${container_mnt}" ] && case "${_items}" in
        *,container_mnt,*|*,bootfs,*)
            [ -z "${container}" ] && \
                err 1 "Cannot mount container; no filesystem destignated as such"
            container_mnt=$(tmpdir)
            add_cleanup rm -r ${container_mnt}
            mountfs ${container} ${container_mnt}
            add_cleanup umount ${container_mnt}
            ;;
    esac

    [ -z "${bootfs}" ] && case "${_items}" in
        *,bootfs,*) bootfs=$(cut -d: -f1 ${container_mnt}/boot.config \
                                 2>/dev/null || true) ;;
    esac
}

check_manifest() {
    local _m
    _m=$(gpg --decrypt 2>/dev/null || err 1 "Bad manifest signature")

    [ "$(echo "${_m}" | head -1)" = "# FBSDIST v1" ] \
        || err 1 "Unknown manifest format"

    echo $(echo "${_m}" | grep ^TYPE | cut -d= -f2) \
         $(echo "${_m}" | grep ^TIMESTAMP | cut -d= -f2) \
         $(echo "${_m}" | grep ^VERSION | cut -d= -f2) \
         $(echo "${_m}" | grep ^SHA256 | cut -d= -f2)
}

check_pkg() {
    local _type _timestamp _version _sha256

    [ -r "${1}" ] \
        || err 1 "Package ${1} doesn't exist or is not readable"

    [ $(tar tvf ${1} manifest | awk '{ print $5 }') -le 10240 ] \
        || err 1 "Manifest unreasonably big"

    read _type _timestamp _version _sha256 <<EOF
$(tar xOf ${1} manifest | check_manifest)
EOF

    [ "$(tar xOf ${1} data | sha256)" = "${_sha256}" ] \
        || err 1 "Package includes data with bad checksum"

    echo ${_type} ${_timestamp} ${_version} ${_sha256}
}

trap sig_handler SIGINT SIGTERM SIGKILL
trap exit_handler EXIT
