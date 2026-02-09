# -------------------------------- base ------------------------------------------------
FROM quay.io/pypa/manylinux_2_28:2026.02.06-1 AS base

WORKDIR /build

RUN dnf install -y nasm
RUN pipx install --force "cmake<4"


# -------------------------------- base ------------------------------------------------
FROM base AS build-deps

ENV X265_VERSION=4.1
RUN set -ex \
    && curl -fLO https://bitbucket.org/multicoreware/x265_git/downloads/x265_${X265_VERSION}.tar.gz \
    && tar xvf x265_${X265_VERSION}.tar.gz \
    && cd x265_${X265_VERSION} \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr -G "Unix Makefiles" ./source \
    && make -j $(nproc) && make install && ldconfig \
    && rm -rf /build

ENV LIBDE265_VERSION=1.0.16
RUN set -ex \
    && curl -fLO https://github.com/strukturag/libde265/releases/download/v${LIBDE265_VERSION}/libde265-${LIBDE265_VERSION}.tar.gz \
    && tar xvf libde265-${LIBDE265_VERSION}.tar.gz \
    && cd libde265-${LIBDE265_VERSION} \
    && ./autogen.sh \
    && CXXFLAGS="-g1 -O2" ./configure --prefix /usr --disable-encoder --disable-dec265 \
        --disable-sherlock265 --disable-dependency-tracking \
    && make -j $(nproc) && make install && ldconfig \
    && rm -rf /build

ENV LIBAOM_VERSION=v3.13.1
RUN set -ex \
    && mkdir -v aom && mkdir -v aom_build && cd aom \
    && curl -fLO "https://aomedia.googlesource.com/aom/+archive/${LIBAOM_VERSION}.tar.gz" \
    && tar xvf ${LIBAOM_VERSION}.tar.gz \
    && cd ../aom_build \
    && MINIMAL_INSTALL="-DENABLE_TESTS=0 -DENABLE_TOOLS=0 -DENABLE_EXAMPLES=0 -DENABLE_DOCS=0" \
    && cmake $MINIMAL_INSTALL -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=1 ../aom \
    && make -j $(nproc) && make install && ldconfig \
    && rm -rf /build


# -------------------------------- libheif ---------------------------------------------
FROM build-deps AS libheif

ARG LIBHEIF_VERSION=1.18.2
RUN set -ex \
    && LIBHEIF_VERSION="$LIBHEIF_VERSION" \
    && curl -fLO https://github.com/strukturag/libheif/releases/download/v${LIBHEIF_VERSION}/libheif-${LIBHEIF_VERSION}.tar.gz \
    && tar xvf libheif-${LIBHEIF_VERSION}.tar.gz && mv libheif-${LIBHEIF_VERSION} libheif \
    && mkdir libheif_build && cd libheif_build \
    && cmake --install-prefix=/usr --preset=release-noplugins -DWITH_EXAMPLES=no ../libheif \
    && make -j $(nproc) && make install && ldconfig \
    && rm -rf /build

COPY ./ /pyheif

RUN set -ex \
    && PNV="/opt/python/cp310-cp310/bin" \
    && $PNV/pip wheel /pyheif \
    && auditwheel repair pyheif*.whl -w /wheelhouse \
    && $PNV/pip install --only-binary :all: -r /pyheif/requirements-test.txt \
    && $PNV/pip install /wheelhouse/*-cp310-*.whl \
    && cd /pyheif && $PNV/pytest


# -------------------------------- all-pythons-repaired --------------------------------
FROM libheif AS all-pythons-repaired

COPY ./ /pyheif

RUN /opt/python/cp38-cp38/bin/pip wheel /pyheif
RUN /opt/python/cp39-cp39/bin/pip wheel /pyheif
RUN /opt/python/cp310-cp310/bin/pip wheel /pyheif
RUN /opt/python/cp311-cp311/bin/pip wheel /pyheif
RUN /opt/python/cp312-cp312/bin/pip wheel /pyheif
RUN /opt/python/cp313-cp313/bin/pip wheel /pyheif
RUN /opt/python/cp314-cp314/bin/pip wheel /pyheif
RUN /opt/python/pp311-pypy311_pp73/bin/pip wheel /pyheif
RUN auditwheel repair pyheif*.whl -w /wheelhouse


# -------------------------------- tested ----------------------------------------------
FROM base AS tested

COPY ./requirements-test.txt /tmp/requirements-test.txt

RUN /opt/python/cp38-cp38/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/cp39-cp39/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/cp310-cp310/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/cp311-cp311/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/cp312-cp312/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/cp313-cp313/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/cp314-cp314/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt
RUN /opt/python/pp311-pypy311_pp73/bin/pip install --only-binary :all: -r /tmp/requirements-test.txt

COPY --from=all-pythons-repaired /wheelhouse /wheelhouse
COPY ./ /pyheif
WORKDIR /pyheif

# python 3.8
RUN set -ex \
    && PNV="/opt/python/cp38-cp38/bin" \
    && $PNV/pip install /wheelhouse/*-cp38-*.whl \
    && $PNV/pytest
# python 3.9
RUN set -ex \
    && PNV="/opt/python/cp39-cp39/bin" \
    && $PNV/pip install /wheelhouse/*-cp39-*.whl \
    && $PNV/pytest
# python 3.10
RUN set -ex \
    && PNV="/opt/python/cp310-cp310/bin" \
    && $PNV/pip install /wheelhouse/*-cp310-*.whl \
    && $PNV/pytest
# python 3.11
RUN set -ex \
    && PNV="/opt/python/cp311-cp311/bin" \
    && $PNV/pip install /wheelhouse/*-cp311-*.whl \
    && $PNV/pytest
# python 3.12
RUN set -ex \
    && PNV="/opt/python/cp312-cp312/bin" \
    && $PNV/pip install /wheelhouse/*-cp312-*.whl \
    && $PNV/pytest
# python 3.13
RUN set -ex \
    && PNV="/opt/python/cp313-cp313/bin" \
    && $PNV/pip install /wheelhouse/*-cp313-*.whl \
    && $PNV/pytest
# python 3.14
RUN set -ex \
    && PNV="/opt/python/cp314-cp314/bin" \
    && $PNV/pip install /wheelhouse/*-cp314-*.whl \
    && $PNV/pytest
# pypy 3.11
RUN set -ex \
    && PNV="/opt/python/pp311-pypy311_pp73/bin" \
    && $PNV/pip install /wheelhouse/*-pp311-*.whl \
    && $PNV/pytest
