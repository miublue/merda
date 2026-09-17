DC = dmd
PREFIX = /usr/local

all:
	${DC} -O merda.d
	${DC} -shared -of=merda_lib.so lib.d merda.d

install: all
	mkdir -p ${DESTDIR}${PREFIX}/share/merda ${DESTDIR}${PREFIX}/bin
	cp common.mr ${DESTDIR}${PREFIX}/share/merda/
	cp merda_lib.so ${DESTDIR}${PREFIX}/share/merda/
	install -s merda ${DESTDIR}${PREFIX}/share/merda/
	ln -s ${DESTDIR}${PREFIX}/share/merda/merda ${DESTDIR}${PREFIX}/bin/merda

uninstall:
	rm ${DESTDIR}${PREFIX}/bin/merda
	rm -rf ${DESTDIR}${PREFIX}/share/merda

clean:
	rm *.o *.so merda

.PHONY: all clean install uninstall
