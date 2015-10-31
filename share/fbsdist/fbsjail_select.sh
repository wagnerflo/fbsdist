. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} JAIL ID"
    exit 1
}

_jailname=${1}
_timestamp=${2}

if [ -z "${_jailname}" -o -z "${_timestamp}" ]; then
    usage
fi

_jailsfs=$(poudriere_api get_jailsfs)
_jailfs=${_jailsfs}/${_jailname}/${_timestamp}

if ! is_filesystem ${_jailfs}; then
    err 1 "${_jailfs} is not a ZFS filesystem or doesn't exist"
fi

_jaildir=$(get_mountpoint ${_jailfs})

if [ -z "${_jaildir}" ]; then
    err 1 "${_jailfs} is not mounted"
fi

poudriere_api jset ${_jailname} fs ${_jailfs}
poudriere_api jset ${_jailname} method fbsjail
poudriere_api jset ${_jailname} mnt ${_jaildir}
poudriere_api jset ${_jailname} timestamp ${_timestamp}
poudriere_api jset ${_jailname} version \
              $(parse_newvers ${_jaildir}/usr/src)
