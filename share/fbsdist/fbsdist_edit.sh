. ${_fbsdist_prefix}/common.sh

request container_mnt

${EDITOR:-$(echo $(which zile) $(which nano) $(which vi) | cut -wf1)} \
    ${container_mnt}/prepare.sh
