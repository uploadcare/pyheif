FROM quay.io/pypa/manylinux2014_x86_64

###############
# Build tools #
###############

# pkg-config
RUN set -ex \
    && mkdir -p /build-tools && cd /build-tools \
    && PKG_CONFIG_VERSION="0.29.2" \
    && curl -fLO https://pkg-config.freedesktop.org/releases/pkg-config-${PKG_CONFIG_VERSION}.tar.gz \
    && tar xvf pkg-config-${PKG_CONFIG_VERSION}.tar.gz \
    && cd pkg-config-${PKG_CONFIG_VERSION} \
    && ./configure \
    && make -j4 \
    && make install \
    && pkg-config --version \
    && rm -rf /build-tools

# nasm
RUN set -ex \
    && mkdir -p /build-tools && cd /build-tools \
    && NASM_VERSION="2.15.02" \
    && curl -fLO https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/nasm-${NASM_VERSION}.tar.gz \
    && tar xvf nasm-${NASM_VERSION}.tar.gz \
    && cd nasm-${NASM_VERSION} \
    && ./configure \
    && make -j4 \
    && make install \
    && nasm --version \
    && rm -rf /build-tools

################
# Dependencies #
################

# x265
RUN set -ex \
    && mkdir -p /build-deps && cd /build-deps \
    && X265_VERSION="3.5" \
    && curl -fLO https://bitbucket.org/multicoreware/x265_git/downloads/x265_${X265_VERSION}.tar.gz \
    && tar xvf x265_${X265_VERSION}.tar.gz \
    && cd x265_${X265_VERSION} \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr -G "Unix Makefiles" ./source \
    && make -j4 \
    && make install \
    && ldconfig \
    && rm -rf /build-deps

# libde265
RUN set -ex \
    && mkdir -p /build-deps && cd /build-deps \
    && LIBDE265_VERSION="1.0.5" \
    && curl -fLO https://github.com/strukturag/libde265/releases/download/v${LIBDE265_VERSION}/libde265-${LIBDE265_VERSION}.tar.gz \
    && tar xvf libde265-${LIBDE265_VERSION}.tar.gz \
    && cd libde265-${LIBDE265_VERSION} \
    && ./autogen.sh \
    && ./configure --prefix /usr --disable-encoder --disable-dec265 --disable-sherlock265 --disable-dependency-tracking \
    && make -j4 \
    && make install \
    && ldconfig \
    && rm -rf /build-deps

# libaom
RUN set -ex \
    && mkdir -p /build-deps && cd /build-deps \
    && LIBAOM_VERSION="v2.0.0" \
    && mkdir -v aom && mkdir -v aom_build && cd aom \
    && curl -fLO "https://aomedia.googlesource.com/aom/+archive/${LIBAOM_VERSION}.tar.gz" \
    && tar xvf ${LIBAOM_VERSION}.tar.gz \
    && cd ../aom_build \
    && MINIMAL_INSTALL="-DENABLE_TESTS=0 -DENABLE_TOOLS=0 -DENABLE_EXAMPLES=0 -DENABLE_DOCS=0" \
    && cmake $MINIMAL_INSTALL -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=1 ../aom \
    && make -j4 \
    && make install \
    && ldconfig \
    && rm -rf /build-deps

# libheif
RUN set -ex \
    && mkdir -p /build-deps && cd /build-deps \
    && LIBHEIF_VERSION="1.7.0" \
    && curl -fLO https://github.com/strukturag/libheif/releases/download/v${LIBHEIF_VERSION}/libheif-${LIBHEIF_VERSION}.tar.gz \
    && tar xvf libheif-${LIBHEIF_VERSION}.tar.gz \
    && cd libheif-${LIBHEIF_VERSION} \
    && ./configure --prefix /usr --disable-examples \
    && make -j4 \
    && make install \
    && ldconfig \
    && rm -rf /build-deps

##########################
# Build manylinux wheels #
##########################

# setup
RUN mkdir /wheelhouse /repaired
COPY ./ /pyheif/

# build wheels
# python 3.6
RUN set -ex \
    && cd "/opt/python/cp36-cp36m/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*
# python 3.7
RUN set -ex \
    && cd "/opt/python/cp37-cp37m/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*
# python 3.8
RUN set -ex \
    && cd "/opt/python/cp38-cp38/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*
# python 3.9
RUN set -ex \
    && cd "/opt/python/cp39-cp39/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*
# python 3.10
RUN set -ex \
    && cd "/opt/python/cp310-cp310/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*
# pypy 3.7
RUN set -ex \
    && cd "/opt/python/pp37-pypy37_pp73/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*
# pypy 3.8
RUN set -ex \
    && cd "/opt/python/pp38-pypy38_pp73/bin/" \
    && ./pip install auditwheel \
    && ./pip wheel /pyheif -w /wheelhouse/ \
    && ./auditwheel repair /wheelhouse/*pyheif*.whl --plat manylinux2014_x86_64 -w /repaired \
    && rm /wheelhouse/*

# upload
ARG PYPI_USERNAME
ARG PYPI_PASSWORD
RUN set -ex \
    && cd "/opt/python/cp38-cp38/bin/" \
    && ./pip install twine \
    && ./twine upload /repaired/*manylinux2014*.whl -u ${PYPI_USERNAME} -p ${PYPI_PASSWORD} \