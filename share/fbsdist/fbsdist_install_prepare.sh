log() {
    echo "---- ${1} ----"
}

copy () {
    local _current _new
    _current="${current}${1}"
    _new="${new}${1}"

    if [ -e "${_current}" ]; then
        log "Copying ${1} unmodified"
        cp -a "${_current}" "${_new}"
    else
        log "Won't copy ${1} as it doesn't exist in current root"
    fi
}

merge () {
    local _origin _current _new _conflicts _apply
    _origin="${origin}${1}"
    _current="${current}${1}"
    _new="${new}${1}"

    if [ ! -e "${_current}" ]; then
        log "Won't merge ${1} as it doesn't exist in current root"
        return
    fi

    if [ ! -f "${_current}" ]; then
        log "Won't merge ${1} as it is not a file in current root"
        return
    fi

    if [ ! -e "${_new}" ]; then
        log  "Won't merge ${1} as it doesn't exist in new root"
        copy "${1}"
        return
    fi

    if [ ! -f "${_new}" ]; then
        log "Won't merge ${1} as it is not a file in new root"
        return
    fi

    if [ ! -e "${_origin}" ]; then
        log "Won't merge ${1} as it doesn't exist in origin root"
        copy "${1}"
        return
    fi

    if [ ! -f "${_origin}" ]; then
        log "Won't merge ${1} as it is not a file in origin root"
        return
    fi

    if diff "${_origin}" "${_current}" >/dev/null; then
        log "No changes in ${1} thus no merge required"
        return
    fi

    command merge \
        -L "new distributed" -L "origin" -L "current modified" \
        -p "${_new}" "${_origin}" "${_current}" > "${_new}.merged" 2>/dev/null
    _conflicts=${?}

    if [ ${_conflicts} ]; then
        log "No merge conflicts for ${1}; patch follows"
        diff -u "${_new}" "${_new}.merged" | tail -n +3
        printf "End of patch. Apply (y/N)? "
        read _apply
        case "${_apply}" in
            [Yy]|[Yy][Ee][Ss])
                mv "${_new}.merged" "${_new}"
                return 0
                ;;
        esac
    else
        log "Merge conflict for ${1}"
    fi

    log "Leaving merged file at ${1}.merged for user to inspect"
}

. ${1}
