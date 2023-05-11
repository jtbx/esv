IMPORT    = import
PREFIX    = /usr/local
MANPREFIX = /usr/share/man

DC     = ldc2
CFLAGS = -O -I${IMPORT} -w
OBJS   = main.o esv.o ini.o

all: esv

esv: ${OBJS}
	${DC} ${CFLAGS} -of$@ ${OBJS}

# main executable
main.o: main.d esv.o
	${DC} ${CFLAGS} -c main.d -of$@

esv.o: esv.d
	${DC} ${CFLAGS} -c esv.d -of$@

ini.o: ${IMPORT}/dini/*.d
	${DC} ${CFLAGS} -c ${IMPORT}/dini/*.d -of$@

clean:
	rm -f ${PROG} ${OBJS}

install: esv
	install -m755 esv ${DESTDIR}${PREFIX}/bin/esv
	cp -f esv.1 ${DESTDIR}${MANPREFIX}/man1
	cp -f esv.conf.5 ${DESTDIR}${MANPREFIX}/man5

.PHONY: clean install
