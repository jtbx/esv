# The GPLv2 License (GPLv2)
# Copyright (c) 2023 Jeremy Baxter
# 
# esv is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# esv is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with esv.  If not, see <http://www.gnu.org/licenses/>.

PROG      = esv
IMPORT    = import
PREFIX    = /usr/local
MANPREFIX = /usr/share/man

DC     = ldc2
CFLAGS = -O -I${IMPORT}
OBJS   = main.o esv.o ini.o

ifeq (${DEBUG},)
	CFLAGS += -release
endif

ifneq (${WI},)
	CFLAGS += -wi
else
	CFLAGS += -w
endif

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
