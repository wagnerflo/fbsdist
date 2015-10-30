SCRIPTS=	sbin/${SCRIPT}
SCRIPTSDIR=	${PREFIX}/sbin

FILES=		share/fbsdist/${SCRIPT}_*
.if ${SCRIPT} == "fbsdist"
FILES+=		share/fbsdist/common.sh
.endif
FILESDIR=	${PREFIX}/share/fbsdist

beforeinstall:
	test -e "${DESTDIR}${SCRIPTSDIR}" || mkdir -p "${DESTDIR}${SCRIPTSDIR}"
	test -e "${DESTDIR}${FILESDIR}"   || mkdir -p "${DESTDIR}${FILESDIR}"

.include <bsd.prog.mk>

