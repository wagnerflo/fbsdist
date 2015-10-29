. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} FILE"
    exit 1
}

_pkg=${1}
if [ -z "${_pkg}" ]; then
    usage
fi

read _type _timestamp _version _sha256 <<EOF
$(check_pkg ${_pkg})
EOF

request container_mnt

mkdir ${container_mnt}/${_timestamp}
add_cleanup rm -rf ${container_mnt}/${_timestamp}
tar xf ${_pkg} -C ${container_mnt}/${_timestamp} manifest data
del_cleanup rm -rf ${container_mnt}/${_timestamp}
