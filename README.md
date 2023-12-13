# esv

*Read the Bible from your terminal*

`esv` is a utility that displays passages of the English Standard Bible
on your terminal. It connects to the ESV web API to retrieve the passages,
and allows configuration through command-line options and the configuration file.

Example usage:

```
$ esv Psalm 23
Psalm 23

The LORD Is My Shepherd

A Psalm of David.

    The LORD is my shepherd; I shall not want.
        He makes me lie down in green pastures....
```

The names of Bible books are not case sensitive, so John, john, and JOHN
are all accepted.

## Audio

`esv` supports playing audio passages through the -a option.
The `mpg123` audio/video player is utilised here and so it required if you
want to play audio passages. If you prefer, you can use a different player
(such as mpv) by editing config.di.

Audio usage is the same as normal text usage. `esv -a Matthew 5-7` will play
an audio passage of Matthew 5-7.

## Installation

To install `esv`, first make sure you have the
[LLVM D compiler (ldc)](https://github.com/ldc-developers/ldc#installation)
installed on your system.

Commands prefixed with a dollar sign ($) are intended to be run as
a standard user, and commands prefixed with a hash sign (#) are intended
to be run as the root user.

First, get the source code:

```
$ git clone https://codeberg.org/jtbx/esv
$ cd esv
```

Now, compile and install:

```
$ ./configure
$ make
# make install
```

## Documentation

All documentation is contained in the manual pages. To access them, you can run
`man esv` and `man esv.conf` for the `esv` utility and the configuration file respectively.

## Copying

Copying, modifying and redistributing this software is permitted
as long as your modified version conforms to the GNU General Public License version 2.

The file esvapi.d is a reusable library; all documentation is provided in the source file.

The license is contained in the file COPYING.

This software uses a modified version of a library named "dini". This is released under
the Boost Software License version 1.0, which can be found in import/dini/LICENSE.
dini can be found at https://github.com/robik/dini.
My changes can be found at https://github.com/jtbx/dini.
