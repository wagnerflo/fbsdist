SCRIPTS=	sbin/${SCRIPT}
SCRIPTSDIR=	${PREFIX}/sbin

FILES=		${:!ls share/fbsdist/${SCRIPT}_*.sh!}
FILESDIR=	${PREFIX}/share/fbsdist

.if ${SCRIPT} == "fbsdist"
FILES+=		share/fbsdist/common.sh
.elif ${SCRIPT} == "fbsjail"
FILES+=		${:!ls share/fbsdist/poudriere_*.sh!}
.endif

beforeinstall:
	test -e "${DESTDIR}${SCRIPTSDIR}" || mkdir -p "${DESTDIR}${SCRIPTSDIR}"
	test -e "${DESTDIR}${FILESDIR}"   || mkdir -p "${DESTDIR}${FILESDIR}"

.include <bsd.prog.mk>

