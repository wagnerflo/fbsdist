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
    echo "error: ${_confdir} doesn't exist or is no directory"
    exit 1
fi

# check if configuration files exist
#
for _file in "${_srcconf}" "${_kernconf}"; do
    if [ ! -f "${_file}" ]; then
        echo -n "error: "
        echo -n "$(basename $(dirname "${_file}"))/$(basename "${_file}") "
        echo    "doesn't exist or is no file"
        exit 1
    fi
done

# retrieve src snapshot and check if it's valid
#
eval _srcsnap=$(sed -n '/^FBSJAIL_SRCSNAP=/s/FBSJAIL_SRCSNAP=//p' ${_srcconf})
eval _jailcomp=$(sed -n '/^FBSJAIL_COMPRESSION=/s/FBSJAIL_COMPRESSION=//p' ${_srcconf})

if ! is_snapshot ${_srcsnap}; then
    echo "error: source dataset ${_srcsnap} is not a snapshot"
    exit 1
fi

# Calculate filesystems and create if necessary
#
_jailsfs=$(list_by_type jails)
_jailsdir=$(get_mountpoint ${_jailsfs})

if [ -z "${_jailsdir}" ]; then
    echo "error: jails filesystem ${_jailsfs} is not mounted"
    exit 1
fi

_basefs=${_jailsfs}/${_name}

if ! is_filesystem ${_basefs}; then
    if ! zfs create -o atime=off ${_basefs} >/dev/null 2>&1; then
        echo "error: couldn't create missing filesystem ${_basefs}"
        exit 1
    fi
fi

_basedir=$(get_mountpoint ${_basefs})

if [ -z ${_basedir} ]; then
    echo "error: filesystem ${_basefs} is not mounted"
    exit 1
fi

# clone and mount source
#
_tmpdir=$(mktemp -d)
_tmpfs=${_basefs}/$(basename "${_tmpdir}")
add_cleanup rm -r ${_tmpdir}

if ! zfs clone \
         -o atime=off \
         -o compression=${_jailcomp:-gzip} \
         -o mountpoint=none \
         -o sync=disabled \
         ${_srcsnap} ${_tmpfs} >/dev/null 2>&1; then
    echo "error: can't clone ${_srcsnap} to ${_tmpfs}"
    exit 1
fi

add_cleanup zfs destroy ${_tmpfs}

mount -t zfs ${_tmpfs} ${_tmpdir}
add_cleanup umount ${_tmpdir}

# prepare filesystem for building
#
_realsrcdir=${_tmpdir}/usr/src
_realobjdir=${_tmpdir}/usr/obj
_distdir=${_realobjdir}/dist

mkdir -p ${_realsrcdir} ${_realobjdir} ${_distdir}
add_cleanup chflags -R noschg ${_realobjdir}
add_cleanup rm -r ${_realobjdir}
find ${_tmpdir} -mindepth 1 -maxdepth 1 -not -name usr -exec mv {} ${_realsrcdir} \;

# null mount to /usr/src and /usr/obj
#
_srcdir=/usr/src
_objdir=/usr/obj

mount_nullfs ${_realsrcdir} ${_srcdir}
add_cleanup umount ${_srcdir}

mount_nullfs ${_realobjdir} ${_objdir}
add_cleanup umount ${_objdir}

# prepare config files for build
#
sed -e 's/#.*$//' -e 's/^.*=dist//' -e 's/^FBSJAIL_.*//' -e '/^$/d' \
    ${_srcconf} > ${_objdir}/src.conf
ln -s $(realpath ${_kernconf}) ${_objdir}/${_name}

makesrc() {
    env MAKEOBJDIRPREFIX=${_objdir} \
	SRCCONF=${_objdir}/src.conf \
	KERNCONFDIR=${_objdir} KERNCONF=${_name} \
	__MAKE_CONF=/dev/null NO_CLEAN=yes \
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
package dist ${_distdir} ${_basedir}/${_name}.${_timestamp}.fbsdist

# prepare jail
#
_jailfs=${_basefs}/${_timestamp}

sleep 5

umount ${_srcdir}
del_cleanup umount ${_srcdir}

umount ${_objdir}
del_cleanup umount ${_objdir}

chflags -R noschg ${_realobjdir}
del_cleanup chflags -R noschg ${_realobjdir}

rm -r ${_realobjdir}
del_cleanup rm -r ${_realobjdir}

umount -f ${_tmpdir}
del_cleanup umount ${_tmpdir}

zfs rename ${_tmpfs} ${_jailfs}
del_cleanup zfs destroy ${_tmpfs}
add_cleanup zfs destroy ${_jailfs}

zfs inherit sync ${_jailfs}
zfs inherit mountpoint ${_jailfs}
zfs snapshot ${_jailfs}@clean

del_cleanup zfs destroy ${_jailfs}
