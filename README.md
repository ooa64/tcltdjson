# tcltdjson

Simple wrapper for Telegram JSON API (https://tdlib.github.io/td/build.html).

To install on unix/mac/cygwin/msys:

	./configure --with-tdlib=<tdlib_home_dir>
	make
	make test
	make install

To install on windows:

	cd win
	nmake -f makefile.vc TDROOT=<tdlib_home_dir>
	nmake -f makefile.vc TDROOT=<tdlib_home_dir> test
	nmake -f makefile.vc TDROOT=<tdlib_home_dir> install
