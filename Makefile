PROG      = esv
IMPORT    = import
PREFIX    = /usr/local
MANPREFIX = /usr/share/man

DC     = ldc2
CFLAGS = -O -I${IMPORT}
OBJS   = main.o esv.o ini.o

all: esv

esv: ${OBJS}
	${DC} ${CFLAGS} -of=${PROG} ${OBJS}

# main executable
main.o: main.d esv.o
	${DC} -c ${CFLAGS} main.d -of=main.o

esv.o: esv.d
	${DC} -c -i ${CFLAGS} esv.d -of=esv.o

ini.o: ${IMPORT}/dini/*.d
	${DC} -c -i ${CFLAGS} ${IMPORT}/dini/*.d -of=ini.o

clean:
	rm -f ${PROG} ${OBJS}

install: esv
	install -m755 esv ${DESTDIR}${PREFIX}/bin/esv
	cp -f esv.1 ${DESTDIR}${MANPREFIX}/man1
	cp -f esv.conf.5 ${DESTDIR}${MANPREFIX}/man5

.PHONY: clean install
