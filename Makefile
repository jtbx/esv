IMPORT    = import
PREFIX    = /usr/local
MANPREFIX = /usr/share/man

DC      = ldc2
CFLAGS  = -O -I${IMPORT} -release -w
OBJS    = main.o esvapi.o ini.o

all: esv

esv: ${OBJS}
	${DC} ${CFLAGS} -of$@ ${OBJS}

# main executable
main.o: main.d esvapi.o
	${DC} ${CFLAGS} -c main.d -of$@

esvapi.o: esvapi.d
	${DC} ${CFLAGS} -c esvapi.d -of$@

ini.o: ${IMPORT}/dini/*.d
	${DC} ${CFLAGS} -c ${IMPORT}/dini/*.d -of$@

clean:
	rm -f esv ${OBJS}

install: esv
	install -m755 esv ${DESTDIR}${PREFIX}/bin/esv
	cp -f esv.1 ${DESTDIR}${MANPREFIX}/man1
	cp -f esv.conf.5 ${DESTDIR}${MANPREFIX}/man5

.PHONY: clean install
