. ${_fbsdist_prefix}/common.sh

_jailsfs=$(poudriere_api get_jailsfs)

zfs list -H -d1 -tfilesystem -oname ${_jailsfs} | \
    tail -n+2 | while read _basefs
do
    _jailname=${_basefs#${_jailsfs}/}
    _currentfs=$(poudriere_api jget ${_jailname} fs)

    printf "%s\n" ${_jailname}

    zfs list -H -d1 -tfilesystem -oname ${_basefs} | \
        tail -n+2 | while read _jailfs
    do
        _timestamp=${_jailfs#${_basefs}/}

        # skip if _timestamp is not a number
        case ${_timestamp#[-+]} in
            *[!0-9]*) continue;;
        esac

        _jaildir=$(get_mountpoint ${_jailfs})
        _version=$(parse_newvers ${_jaildir}/usr/src)

        printf "  [%1s] %-35s   %s\n" \
               "$([ "${_jailfs}" = "${_currentfs}" ] && echo "*")" \
               "${_timestamp} ($(date -r${_timestamp} "+%d %b %Y %R %Z"))" \
               "${_version}"
    done
done
