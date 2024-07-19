. ${_fbsdist_prefix}/common.sh

usage() {
    echo "usage: ${_fbsdist_name} ${_fbsdist_cmd} NAME"
    exit 1
}

_name=${1}
if [ -z "${_name}" ]; then
    usage
fi

if [ -z "${_fbsjail_etc}" ]; then
    _fbsjail_etc=/usr/local/etc
fi

_parallel_jobs=$(sysctl -n hw.ncpu)
_confdir=${_fbsjail_etc}/fbsjail.d/${_name}
_srcconf=${_confdir}/src.conf
_kernconf=${_confdir}/kernel.conf

# check if configuration directory exists
#
if [ ! -d "${_confdir}" ]; then
    err 1 "${_confdir} doesn't exist or is no directory"
fi

# check if configuration files exist
#
for _file in "${_srcconf}" "${_kernconf}"; do
    if [ ! -f "${_file}" ]; then
        err 1 "$(basename $(dirname "${_file}"))/$(basename "${_file}")" \
            "doesn't exist or is no file"
    fi
done

# retrieve configuration and check validity
#
eval _srcsnap=$(sed -n '/^FBSJAIL_SRCSNAP=/s/FBSJAIL_SRCSNAP=//p' ${_srcconf})
eval _jailcomp=$(sed -n '/^FBSJAIL_COMPRESSION=/s/FBSJAIL_COMPRESSION=//p' ${_srcconf})
eval _distdest=$(sed -n '/^FBSJAIL_DIST_DEST=/s/FBSJAIL_DIST_DEST=//p' ${_srcconf})

if ! is_snapshot ${_srcsnap}; then
    err 1 "source dataset ${_srcsnap} is not a snapshot"
fi

_jailcomp=${_jailcomp:-gzip}
_distdest=${_distdest:-/tmp}

if [ ! -d "${_distdest}" ]; then
    err 1 "distribution destination ${_distdest} is not a directory"
fi

# Calculate filesystems and create if necessary
#
_jailsfs=$(poudriere_api get_jailsfs)
_basefs=${_jailsfs}/${_name}

if ! is_filesystem ${_basefs}; then
    if ! zfs create -p -o atime=off ${_basefs} >/dev/null 2>&1; then
        err 1 "couldn't create missing filesystem ${_basefs}"
    fi
    add_cleanup zfs destroy ${_basefs}
fi

_basedir=$(get_mountpoint ${_basefs})

if [ -z ${_basedir} ]; then
    err 1 "filesystem ${_basefs} is not mounted"
fi

# clone source snapshot and mount to temporary directory
#
_tmpdir=$(tmpdir)
_tmpfs=${_basefs}/$(basename "${_tmpdir}")
add_cleanup rm -r ${_tmpdir}

if ! zfs clone \
         -o atime=off \
         -o compression=${_jailcomp:-gzip} \
         -o mountpoint=none \
         ${_srcsnap} ${_tmpfs} >/dev/null 2>&1; then
    err 1 "error: can't clone ${_srcsnap} to ${_tmpfs}"
fi

add_cleanup zfs destroy ${_tmpfs}

mountzfs ${_tmpfs} ${_tmpdir}
add_cleanup umount ${_tmpdir}

# move contents into usr/src subdirectory
#
_realsrcdir=${_tmpdir}/usr/src

mkdir -p ${_realsrcdir}
find ${_tmpdir} -mindepth 1 -maxdepth 1 -not -name usr \
     -exec mv {} ${_realsrcdir} \;

# create temporary filesystem for usr/obj
#
_objfs=${_tmpfs}/obj

if ! zfs create \
         -o compression=off \
         -o sync=disabled \
         -o mountpoint=none \
         ${_objfs} >/dev/null 2>&1; then
    err 1 "error: can't create obj directory"
fi

add_cleanup zfs destroy ${_objfs}

# mount to /usr/src and /usr/obj
#
_srcdir=/usr/src
_objdir=/usr/obj
_distdir=${_objdir}/dist

mount_nullfs ${_realsrcdir} ${_srcdir}
add_cleanup umount ${_srcdir}

mountzfs ${_objfs} ${_objdir}
add_cleanup umount ${_objdir}

# prepare config files for build
#
sed -e 's/#.*$//' -e 's/^.*=dist//' -e 's/^FBSJAIL_.*//' -e '/^$/d' \
    ${_srcconf} > ${_srcdir}/src.conf
cp $(realpath ${_kernconf}) ${_srcdir}/${_name}

makesrc() {
    env MAKEOBJDIRPREFIX=${_objdir} \
	SRCCONF=${_srcdir}/src.conf \
	KERNCONFDIR=${_srcdir} KERNCONF=${_name} \
	__MAKE_CONF=/dev/null NO_CLEAN=yes \
        WITHOUT_REPRODUCIBLE_BUILD=yes \
        make -C${_srcdir} -j${_parallel_jobs} "${@}"
}

add_cleanup sleep 2

makesrc buildworld  || err 1 "Fail to build world"
makesrc buildkernel || err 1 "Fail to build kernel"

# install jail and dist
makesrc installworld DB_FROM_SRC=1 DESTDIR=${_tmpdir} \
    || err 1 "Fail to install world into jail"
makesrc distrib-dirs DB_FROM_SRC=1 DESTDIR=${_tmpdir} \
    || err 1 "Failed to install directories into jail"
makesrc distribution DB_FROM_SRC=1 DESTDIR=${_tmpdir} \
    || err 1 "Failed to install distribution files into jail"

sed -e 's/#.*$//' -e 's/=dist/=yes/' -e 's/^SRC=.*//' -e '/^$/d' \
    ${_srcconf} > ${_objdir}/src.conf

makesrc installworld DESTDIR=${_distdir} \
    || err 1 "Fail to install world into distribution"
makesrc installkernel DESTDIR=${_distdir} \
    || err 1 "Fail to install kernel into distribution"
makesrc distrib-dirs DESTDIR=${_distdir} \
    || err 1 "Failed to install directories into distribution"
makesrc distribution DESTDIR=${_distdir} \
    || err 1 "Failed to install distribution files into distribution"

# calculate version
_version=$(parse_newvers ${_srcdir})
_timestamp=$(date -jf " %a %b %d %T %Z %Y" \
		  "$(strings ${_distdir}/boot/kernel/kernel | grep "^@(#)" | \
             cut -d ':' -f 2-)" "+%s")

package () {
    _sha256=$( \
	tar cvf - -C ${2} --strip-components 1 . | \
	xz -z9ec - | \
	tee ${_objdir}/data | \
	sha256 )
    gpg --clearsign > ${_objdir}/manifest <<EOF
# FBSDIST v1
TYPE=${1}
TIMESTAMP=${_timestamp}
VERSION=${_version}
SHA256=${_sha256}
EOF
    tar cHf ${3} -C ${_objdir} manifest data
    [ "$(tar xOf ${3} data | sha256)" = "${_sha256}" ] \
        || err 1 "Bad checksum of data file"
}

# prepare package
#
package dist ${_distdir} ${_distdest}/${_name}.${_timestamp}.fbsdist

# prepare jail
#
_jailfs=${_basefs}/${_timestamp}

sleep 5

umount ${_srcdir}
del_cleanup umount ${_srcdir}

umount ${_objdir}
del_cleanup umount ${_objdir}

zfs destroy ${_objfs}
del_cleanup zfs destroy ${_objfs}

umount -f ${_tmpdir}
del_cleanup umount ${_tmpdir}

zfs rename ${_tmpfs} ${_jailfs}
del_cleanup zfs destroy ${_tmpfs}
add_cleanup zfs destroy ${_jailfs}

zfs inherit mountpoint ${_jailfs}
zfs snapshot ${_jailfs}@clean

del_cleanup zfs destroy ${_jailfs}
del_cleanup zfs destroy ${_basefs}
