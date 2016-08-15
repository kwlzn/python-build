#!/bin/bash

set -euxo pipefail
umask 022

PYTHON_VERSION="2.7.10"
PYTHON_SRC_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
PYTHON_SRC_SHA256="eda8ce6eec03e74991abb5384170e7c65fcd7522e409b8e83d7e6372add0f12a"

OPENSSL_VERSION="1.0.2h"
OPENSSL_SRC_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_SRC_SHA256="1d4007e53aad94a5b2002fe045ee7bb0b3d98f1a47f8b2bc851dcd1c74332919"

ZLIB_VERSION="1.2.8"
ZLIB_SRC_URL="http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_SRC_SHA256="36658cb768a54c1d4dec43c3116c27ed893e88b02ecfcb44f2166f9c0b7f2a0d"

READLINE_VERSION="6.3"
READLINE_SRC_URL="ftp://ftp.cwru.edu/pub/bash/readline-${READLINE_VERSION}.tar.gz"
READLINE_SRC_SHA256="56ba6071b9462f980c5a72ab0023893b65ba6debb4eeb475d7a563dc65cafd43"

PYTRACEMALLOC_ROOT="~/pytracemalloc"


function secure_fetch_and_untar () {
  # Given a URL and SHA, fetch the URL and verify the SHA.
  URL=$1; shift
  SHA=$1; shift
  FILENAME=$(basename $URL)
  $(curl -#kLO $URL)
  [ $(shasum -a 256 $FILENAME | cut -f1 -d' ') == "$SHA" ]
  $(tar xzf $FILENAME)
}


SANDBOX=$(mktemp -d /tmp/python.XXXXXX)
pushd "$SANDBOX"
  echo "building readline"
  secure_fetch_and_untar $READLINE_SRC_URL $READLINE_SRC_SHA256
  READLINE_PREFIX="${SANDBOX}/readline"
  pushd "readline-${READLINE_VERSION}"
    ./configure --disable-shared --enable-static --prefix="${READLINE_PREFIX}"
    make -j8
    make install
  popd
  echo "done building readline"

  echo "building zlib"
  secure_fetch_and_untar $ZLIB_SRC_URL $ZLIB_SRC_SHA256
  ZLIB_PREFIX="${SANDBOX}/zlib"
  pushd "zlib-${ZLIB_VERSION}"
    ./configure --static --prefix="${ZLIB_PREFIX}"
    make -j8
    make install
  popd
  echo "done building zlib"

  echo "building openssl"
  secure_fetch_and_untar $OPENSSL_SRC_URL $OPENSSL_SRC_SHA256
  OPENSSL_PREFIX="${SANDBOX}/openssl"
  pushd "openssl-${OPENSSL_VERSION}"
    ./configure no-shared --prefix="${OPENSSL_PREFIX}" darwin64-x86_64-cc
    make depend
    make -j8
    make install
  popd
  echo "done building openssl"

  echo "building python"
  secure_fetch_and_untar $PYTHON_SRC_URL $PYTHON_SRC_SHA256
  PYTHON_DIR="Python-${PYTHON_VERSION}"
  DIST_NAME="${PYTHON_DIR}-MacOSX"
  PYTHON_PREFIX="${SANDBOX}/${DIST_NAME}"

  pushd "${PYTHON_DIR}"
    # Patch for `pytracemalloc`.
    patch -p1 < ${PYTRACEMALLOC_ROOT}/patches/2.7.10/2.7/pep445.patch

    LDFLAGS="-L../readline/lib -L../zlib/lib -L../openssl/lib" \
      CFLAGS="-I../readline/include -I../zlib/include -I../openssl/include" \
      ./configure --enable-unicode=ucs4 --prefix="${PYTHON_PREFIX}"
    make | tee python_build.result
    grep -A20 "Python build finished, but the necessary bits to build these modules were not found" python_build.result > python_build.missing
    # Ensure `ssl` and `zlib` modules were built.
    grep -vq "ssl" python_build.missing
    grep -vq "zlib" python_build.missing
    make install

    # Install `pytracemalloc`.
    pushd "${PYTRACEMALLOC_ROOT}"
      ${PYTHON_PREFIX}/bin/python2.7 setup.py install
    popd
  popd
  echo "done building python"

  echo "packaging"
  tar czf "${DIST_NAME}.tgz" "${DIST_NAME}"
popd

mv "${SANDBOX}/${DIST_NAME}.tgz" .
rm -rf "${SANDBOX}"
echo "wrote ${DIST_NAME}.tgz"
