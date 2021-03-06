# This file is renamed to "Makefile.ext" in release tarballs so that setup.py won't try to
# run it.  If you want setup.py to run "make" automatically, rename it back to "Makefile".

# The pyvenv multiple runtime support is based on https://github.com/DRMacIver/hypothesis/blob/master/Makefile

PYTHON?=python${TRAVIS_PYTHON_VERSION}
CYTHON?=cython



export PATH:=$(BUILD_RUNTIMES)/snakepit:$(TOOLS):$(PATH)
export LC_ALL=C.UTF-8


clean:
	rm -f src/gevent/libev/corecext.c src/gevent/libev/corecext.h
	rm -f src/gevent/ares.c src/gevent/ares.h
	rm -f src/gevent/_semaphore.c src/gevent/_semaphore.h
	rm -f src/gevent/local.c src/gevent/local.h
	rm -f src/gevent/*.so src/gevent/*.pyd src/gevent/libev/*.so src/gevent/libuv/*.so src/gevent/libev/*.pyd src/gevent/libuv/*.pyd
	rm -rf src/gevent/libev/*.o src/gevent/libuv/*.o src/gevent/*.o
	rm -rf src/gevent/__pycache__ src/greentest/__pycache__ src/greentest/greentest/__pycache__ src/gevent/libev/__pycache__
	rm -rf src/gevent/*.pyc src/greentest/*.pyc src/gevent/libev/*.pyc
	rm -rf src/greentest/htmlcov src/greentest/.coverage
	rm -rf build

distclean: clean
	rm -rf dist
	rm -rf deps/libev/config.h deps/libev/config.log deps/libev/config.status deps/libev/.deps deps/libev/.libs
	rm -rf deps/c-ares/config.h deps/c-ares/config.log deps/c-ares/config.status deps/c-ares/.deps deps/c-ares/.libs

doc:
	cd doc && PYTHONPATH=.. make html

whitespace:
	! find . -not -path "*.pem" -not -path "./.eggs/*" -not -path "./src/greentest/htmlcov/*" -not -path "./src/greentest/.coverage.*" -not -path "./.tox/*" -not -path "*/__pycache__/*" -not -path "*.so" -not -path "*.pyc" -not -path "./.git/*" -not -path "./build/*"  -not -path "./src/gevent/libev/*" -not -path "./src/gevent.egg-info/*" -not -path "./dist/*" -not -path "./.DS_Store" -not -path "./deps/*" -not -path "./src/gevent/libev/corecext.*.[ch]" -not -path "./src/gevent/ares.*" -not -path "./doc/_build/*" -not -path "./doc/mytheme/static/*" -type f | xargs egrep -l " $$"

prospector:
	which prospector
	which pylint
# debugging
#	pylint --rcfile=.pylintrc --init-hook="import sys, code; sys.excepthook = lambda exc, exc_type, tb: print(tb.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_next.tb_frame.f_locals['self'])" gevent src/greentest/* || true
	${PYTHON} scripts/gprospector.py -X

lint: prospector

test_prelim:
	which ${PYTHON}
	${PYTHON} --version
	${PYTHON} -c 'import greenlet; print(greenlet, greenlet.__version__)'
	${PYTHON} -c 'import gevent.core; print(gevent.core.loop)'
	${PYTHON} -c 'import gevent.ares; print(gevent.ares)'
	make bench

# Folding from https://github.com/travis-ci/travis-rubies/blob/9f7962a881c55d32da7c76baefc58b89e3941d91/build.sh#L38-L44
# 	echo -e "travis_fold:start:${GEVENT_CORE_CFFI_ONLY}\033[33;1m${GEVENT_CORE_CFFI_ONLY}\033[0m"
# Make calls /bin/echo, which doesn't support the -e option, which is part of the bash builtin.
# we need a python script to do this, or possible the GNU make shell function

basictest: test_prelim
	${PYTHON} scripts/travis.py fold_start basictest "Running basic tests"
	cd src/greentest && GEVENT_RESOLVER=thread ${PYTHON} testrunner.py --config known_failures.py --quiet
	${PYTHON} scripts/travis.py fold_end basictest

alltest: basictest
	${PYTHON} scripts/travis.py fold_start ares "Running c-ares tests"
	cd src/greentest && GEVENT_RESOLVER=ares GEVENTARES_SERVERS=8.8.8.8 ${PYTHON} testrunner.py --config known_failures.py --ignore tests_that_dont_use_resolver.txt --quiet
	${PYTHON} scripts/travis.py fold_end ares
# In the past, we included all test files that had a reference to 'subprocess'' somewhere in their
# text. The monkey-patched stdlib tests were specifically included here.
# However, we now always also test on AppVeyor (Windows) which only has GEVENT_FILE=thread,
# so we can save a lot of CI time by reducing the set and excluding the stdlib tests without
# losing any coverage. See the `threadfiletest` for what command used to run.
	${PYTHON} scripts/travis.py fold_start thread "Running GEVENT_FILE=thread tests"
	cd src/greentest && GEVENT_FILE=thread ${PYTHON} testrunner.py --config known_failures.py test__*subprocess*.py --quiet
	${PYTHON} scripts/travis.py fold_end thread

threadfiletest:
	cd src/greentest && GEVENT_FILE=thread ${PYTHON} testrunner.py --config known_failures.py `grep -l subprocess test_*.py` --quiet

allbackendtest:
	${PYTHON} scripts/travis.py fold_start default "Testing default backend"
	GEVENT_CORE_CFFI_ONLY= GEVENTTEST_COVERAGE=1 make alltest
	${PYTHON} scripts/travis.py fold_end default
	GEVENTTEST_COVERAGE=1 make cffibackendtest
# because we set parallel=true, each run produces new and different coverage files; they all need
# to be combined
	make coverage_combine


cffibackendtest:
	${PYTHON} scripts/travis.py fold_start libuv "Testing libuv backend"
	GEVENT_CORE_CFFI_ONLY=libuv GEVENTTEST_COVERAGE=1 make alltest
	${PYTHON} scripts/travis.py fold_end libuv
	${PYTHON} scripts/travis.py fold_start libev "Testing libev CFFI backend"
	GEVENT_CORE_CFFI_ONLY=libev make alltest
	${PYTHON} scripts/travis.py fold_end libev

leaktest: test_prelim
	${PYTHON} scripts/travis.py fold_start leaktest "Running leak tests"
	cd src/greentest && GEVENT_RESOLVER=thread GEVENTTEST_LEAKCHECK=1 ${PYTHON} testrunner.py --config known_failures.py --quiet --ignore tests_that_dont_do_leakchecks.txt
	${PYTHON} scripts/travis.py fold_end leaktest

bench:
	${PYTHON} src/greentest/bench_sendall.py

travis_test_linters:
	make lint
	make leaktest
	make cffibackendtest

coverage_combine:
	coverage combine . src/greentest/

	-coveralls --rcfile=src/greentest/.coveragerc


.PHONY: clean doc prospector lint travistest travis

# Managing runtimes

BUILD_RUNTIMES?=$(PWD)/.runtimes

PY278=$(BUILD_RUNTIMES)/snakepit/python2.7.8
PY27=$(BUILD_RUNTIMES)/snakepit/python2.7.14
PY34=$(BUILD_RUNTIMES)/snakepit/python3.4.7
PY35=$(BUILD_RUNTIMES)/snakepit/python3.5.4
PY36=$(BUILD_RUNTIMES)/snakepit/python3.6.4
PY37=$(BUILD_RUNTIMES)/snakepit/python3.7.0a4
PYPY=$(BUILD_RUNTIMES)/snakepit/pypy5100
PYPY3=$(BUILD_RUNTIMES)/snakepit/pypy3.5_5101

TOOLS=$(BUILD_RUNTIMES)/tools

TOX=$(TOOLS)/tox

TOOL_VIRTUALENV=$(BUILD_RUNTIMES)/virtualenvs/tools
ISORT_VIRTUALENV=$(BUILD_RUNTIMES)/virtualenvs/isort
TOOL_PYTHON=$(TOOL_VIRTUALENV)/bin/python
TOOL_PIP=$(TOOL_VIRTUALENV)/bin/pip
TOOL_INSTALL=$(TOOL_PIP) install --upgrade


$(PY27):
	scripts/install.sh 2.7

$(PY34):
	scripts/install.sh 3.4

$(PY35):
	scripts/install.sh 3.5

$(PY36):
	scripts/install.sh 3.6

$(PY37):
	scripts/install.sh 3.7

$(PYPY):
	scripts/install.sh pypy

$(PYPY3):
	scripts/install.sh pypy3


develop:
	${PYTHON} scripts/travis.py fold_start install "Installing gevent"
	ls -l $(BUILD_RUNTIMES)/snakepit/
	echo python is at `which $(PYTHON)`
# First install a newer pip so that it can use the wheel cache
# (only needed until travis upgrades pip to 7.x; note that the 3.5
# environment uses pip 7.1 by default)
	python -m pip install -U pip setuptools
# Then start installing our deps so they can be cached. Note that use of --build-options / --global-options / --install-options
# disables the cache.
# We need wheel>=0.26 on Python 3.5. See previous revisions.
	GEVENTSETUP_EV_VERIFY=3 ${PYTHON} -m pip install -U -r dev-requirements.txt
	${PYTHON} scripts/travis.py fold_end install

test-py27: $(PY27)
	PYTHON=python2.7.14 PATH=$(BUILD_RUNTIMES)/versions/python2.7.14/bin:$(PATH) make develop lint leaktest allbackendtest

test-py34: $(PY34)
	PYTHON=python3.4.7 PATH=$(BUILD_RUNTIMES)/versions/python3.4.7/bin:$(PATH) make develop allbackendtest

test-py35: $(PY35)
	PYTHON=python3.5.4 PATH=$(BUILD_RUNTIMES)/versions/python3.5.4/bin:$(PATH) make develop allbackendtest

test-py36: $(PY36)
	PYTHON=python3.6.4 PATH=$(BUILD_RUNTIMES)/versions/python3.6.4/bin:$(PATH) make develop allbackendtest

test-py37: $(PY37)
	PYTHON=python3.7.0a4 PATH=$(BUILD_RUNTIMES)/versions/python3.7.0a4/bin:$(PATH) make develop allbackendtest

test-pypy: $(PYPY)
	PYTHON=$(PYPY) PATH=$(BUILD_RUNTIMES)/versions/pypy5100/bin:$(PATH) make develop cffibackendtest coverage_combine

test-pypy3: $(PYPY3)
	PYTHON=$(PYPY3) PATH=$(BUILD_RUNTIMES)/versions/pypy3.5_5101/bin:$(PATH) make develop basictest

test-py27-noembed: $(PY27)
	cd deps/libev && ./configure --disable-dependency-tracking && make
	cd deps/c-ares && ./configure --disable-dependency-tracking && make
	cd deps/libuv && ./autogen.sh && ./configure --disable-static && make
	CPPFLAGS="-Ideps/libev -Ideps/c-ares -Ideps/libuv/include" LDFLAGS="-Ldeps/libev/.libs -Ldeps/c-ares/.libs -Ldeps/libuv/.libs" LD_LIBRARY_PATH="$(PWD)/deps/libev/.libs:$(PWD)/deps/c-ares/.libs:$(PWD)/deps/libuv/.libs" EMBED=0 GEVENT_CORE_CEXT_ONLY=1 PYTHON=python2.7.14 PATH=$(BUILD_RUNTIMES)/versions/python2.7.14/bin:$(PATH) make develop basictest
