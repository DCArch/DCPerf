#!/bin/bash

# DCPerf Combined Installation Script
# Installs all dependencies for all DCPerf benchmarks

# set -e  # Exit on error
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BUILD_DIR="${SCRIPT_DIR}/release"
mkdir -p $BUILD_DIR

echo "=== Installing DCPerf Combined Dependencies ==="

# Update package manager
sudo apt update

# ============================================
# COMMON SYSTEM DEPENDENCIES (deduplicated)
# ============================================

echo "Installing common build tools..."
sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config

echo "Installing common libraries..."
sudo apt install -y \
    libssl-dev \
    libboost-all-dev \
    libgflags-dev \
    libgoogle-glog-dev \
    libevent-dev \
    libdouble-conversion-dev \
    libgtest-dev \
    libnuma-dev \
    libffi-dev \
    libsodium-dev \
    liblz4-dev \
    libzstd-dev \
    libfmt-dev \
    libjemalloc-dev

echo "Installing development tools..."
sudo apt install -y \
    yasm \
    nasm \
    p7zip-full \
    xz-utils

# ============================================
# LANGUAGE RUNTIMES
# ============================================

echo "Installing Python and pip..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-dev

echo "Installing Java..."
sudo apt install -y openjdk-11-jdk

echo "Installing PHP and extensions..."
sudo apt install -y \
    php \
    php-mysql \
    php-xml \
    php-mbstring \
    php-json \
    php-intl \
    php-apcu \
    php-gd \
    php-cli \
    php-curl

# ============================================
# DATABASES AND CACHING
# ============================================

echo "Installing databases..."
sudo apt install -y \
    mariadb-server \
    mariadb-client \
    memcached

# ============================================
# LOAD TESTING TOOLS
# ============================================

echo "Installing load generators..."
sudo apt install -y \
    wrk \
    siege

# ============================================
# VIDEO PROCESSING DEPENDENCIES
# ============================================

echo "Installing video codec libraries..."
sudo apt install -y \
    libx264-dev \
    libx265-dev \
    libvpx-dev \
    libfdk-aac-dev \
    libmp3lame-dev \
    libopus-dev

# ============================================
# PYTHON PACKAGES
# ============================================

echo "Installing Python packages..."
pip3 install --user \
    django \
    uwsgi \
    cassandra-driver \
    python-memcached \
    psycopg2-binary \
    pyspark \
    numpy \
    pandas

# ============================================
# BUILD FROM SOURCE SECTION
# ============================================

# # --- OpenSSL (for TaoBench) ---
# echo "Building OpenSSL..."
# OPENSSL_VERSION="openssl-3.3.2"
# if [ ! -d "$BUILD_DIR/openssl" ]; then
#     wget -q https://github.com/openssl/openssl/archive/refs/tags/${OPENSSL_VERSION}.tar.gz
#     tar -xzf ${OPENSSL_VERSION}.tar.gz
#     cd openssl-${OPENSSL_VERSION}
#     ./config --prefix=$HOME/local/openssl
#     make -j$(nproc)
#     make install
#     cd ..
# fi
# 
# # --- Folly (for FeedSim/WDLBench) ---
# echo "Building Folly..."
# if [ ! -d "$BUILD_DIR/folly" ]; then
#     git clone https://github.com/facebook/folly.git
#     cd folly
#     git checkout v2023.07.17.00
#     mkdir _build && cd _build
#     cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/local -DBUILD_SHARED_LIBS=ON
#     make -j$(nproc)
#     make install
#     cd ../..
# fi
# 
# # --- Apache Cassandra (for Django) ---
# echo "Setting up Cassandra..."
# if ! command -v cassandra &> /dev/null; then
#     wget -q -O - https://www.apache.org/dist/cassandra/KEYS | sudo apt-key add -
#     sudo sh -c 'echo "deb http://www.apache.org/dist/cassandra/debian 40x main" > /etc/apt/sources.list.d/cassandra.list'
#     sudo apt update
#     sudo apt install -y cassandra
# fi

# --- HHVM (for Mediawiki) ---
echo "Installing HHVM..."
if ! command -v hhvm &> /dev/null; then
    git clone --branch HHVM-3.30.12 --depth 1 https://github.com/facebook/hhvm.git
    cd ${SCRIPT_DIR}/hhvm && git submodule update --init --recursive
    cd ${SCRIPT_DIR}/hhvm && grep -rlIZPi 'https://scm.gforge.inria.fr/anonscm/git/cudf/cudf.git' | xargs -0r perl -pi -e 's/https:\/\/scm.gforge.inria.fr\/anonscm\/git\/cudf\/cudf.git/https:\/\/gitlab.com\/irill\/cudf.git/gi;'
    cd ${SCRIPT_DIR}/hhvm && grep -rlIZPi 'https://gforge.inria.fr/git/cudf/cudf.git' | xargs -0r perl -pi -e 's/https:\/\/gforge.inria.fr\/git\/cudf\/cudf.git/https:\/\/gitlab.com\/irill\/cudf.git/gi;'
    cd ${SCRIPT_DIR}/hhvm && grep -rlIZPi 'https://scm.gforge.inria.fr/anonscm/git/dose/dose.git' | xargs -0r perl -pi -e 's/https:\/\/scm.gforge.inria.fr\/anonscm\/git\/dose\/dose.git/https:\/\/gitlab.com\/irill\/dose3.git/gi;'
    cd ${SCRIPT_DIR}/hhvm && git submodule update --init --recursive
    git clone https://gitlab.com/irill/dose3.git
    mv dose3/tests/* hhvm/third-party/ocaml/opam_deps/dose/tests/
    rm -rf dose3
    sed --in-place '16,18d;' hhvm/.git/modules/third-party/modules/ocaml/opam_deps/dose/config
    sed --in-place '4,6d;' hhvm/third-party/ocaml/opam_deps/dose/.gitmodules
    cd ${SCRIPT_DIR}/hhvm && git submodule update --init --recursive
    cp DCSimHooks.h hhvm/DCSimHooks.h
    sed -i '86i #include "DCSimHooks.h"\n' hhvm/hphp/runtime/server/admin-request-handler.cpp
    sed -i '501i     if (cmd == "simulator-start") {\n      Logger::Info("Starting Simulator");\n      DCSimStartGlobalROI();\n      break;\n    }\n    if (cmd == "simulator-stop") {\n      Logger::Info("Stopping Simulator");\n      DCSimEndGlobalROI();\n      break;\n    }' hhvm/hphp/runtime/server/admin-request-handler.cpp
    mkdir hhvm/build/ && mkdir hhvm/builddeps/
    # CMake specific version
    cd ${SCRIPT_DIR}/hhvm && wget -q https://cmake.org/files/v3.9/cmake-3.9.4.tar.gz && tar -xzvf cmake-3.9.4.tar.gz && rm cmake-3.9.4.tar.gz
    cd ${SCRIPT_DIR}/hhvm/cmake-3.9.4 && LDFLAGS=-pthread ./bootstrap --prefix=${SCRIPT_DIR}/hhvm/builddeps --parallel=64 && make -j64 && make install
    rm ${SCRIPT_DIR}/hhvm/cmake-3.9.4 -rf
    # Boost specific verion
    cd ${SCRIPT_DIR}/hhvm && wget -q https://archives.boost.io/release/1.67.0/source/boost_1_67_0.tar.bz2 && tar -jxvf boost_1_67_0.tar.bz2 && rm boost_1_67_0.tar.bz2
    cd ${SCRIPT_DIR}/hhvm/boost_1_67_0 && ./bootstrap.sh --without-libraries=python --prefix=${SCRIPT_DIR}/hhvm/builddeps && ./b2 variant=release threading=multi --layout=tagged -j64 && ./b2 variant=release threading=multi --layout=tagged -j64 install
    rm ${SCRIPT_DIR}/hhvm/boost_1_67_0 -rf
    # jemalloc specific version
    cd ${SCRIPT_DIR}/hhvm && git clone --branch 4.5.0 --depth 1 https://github.com/jemalloc/jemalloc.git
    cd ${SCRIPT_DIR}/hhvm/jemalloc && ./autogen.sh && ./configure --prefix=${SCRIPT_DIR}/hhvm/builddeps --enable-static && make -j64 && make install
    rm ${SCRIPT_DIR}/hhvm/jemalloc -rf
    # libevent specific version
    cd ${SCRIPT_DIR}/hhvm && git clone --branch release-2.1.8-stable --depth 1 https://github.com/libevent/libevent.git
    cd ${SCRIPT_DIR}/hhvm/libevent && ./autogen.sh && ./configure --prefix=${SCRIPT_DIR}/hhvm/builddeps && make -j64 && make install
    rm ${SCRIPT_DIR}/hhvm/libevent -rf
    # glog 
    cd ${SCRIPT_DIR}/hhvm && git clone --branch v0.3.5 --depth 1 https://github.com/google/glog.git
    cd ${SCRIPT_DIR}/hhvm/glog && autoreconf -vfi && ./configure --prefix=${SCRIPT_DIR}/hhvm/builddeps && make -j64 && make install
    rm ${SCRIPT_DIR}/hhvm/glog -rf
    # TBB
    cd ${SCRIPT_DIR}/hhvm && git clone --branch 2018_U6 --depth 1 https://github.com/intel/tbb.git
    cd ${SCRIPT_DIR}/hhvm/tbb && make -j64 && cp -r include/tbb ${SCRIPT_DIR}/hhvm/builddeps/include/ && cp -r build/linux_*_release/libtbb* ${SCRIPT_DIR}/hhvm/builddeps/lib/
    rm ${SCRIPT_DIR}/hhvm/tbb -rf
    # OpenSSL
    cd ${SCRIPT_DIR}/hhvm && git clone --branch OpenSSL_1_1_1b --depth 1 https://github.com/openssl/openssl.git
    cd ${SCRIPT_DIR}/hhvm/openssl && ./config --prefix=${SCRIPT_DIR}/hhvm/builddeps && make -j64 && make install
    rm ${SCRIPT_DIR}/hhvm/openssl -rf
    # MAriaDB
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    sudo mysql_secure_installation
    # GCC
    cd ${SCRIPT_DIR}/hhvm && git clone https://github.com/BobSteagall/gcc-builder && cd gcc-builder && git checkout gcc7
    cd ${SCRIPT_DIR}/hhvm/gcc-builder && grep -rlIZPi 'export GCC_VERSION=7' | xargs -0r perl -pi -e 's/export GCC_VERSION=7\..*\.0/export GCC_VERSION=7.5.0/gi;'
    cd ${SCRIPT_DIR}/hhvm/gcc-builder && ./build-gcc.sh && ./stage-gcc.sh
    # HHVM itself
    cd ${SCRIPT_DIR}/hhvm/build/ && CC=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/gcc CXX=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/g++ PATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin:$PATH ${SCRIPT_DIR}/hhvm/builddeps/bin/cmake ../ -G 'Unix Makefiles' -Wno-dev -DCMAKE_INSTALL_PREFIX=${SCRIPT_DIR}/release/MediaWiki/ -DBOOST_ROOT=${SCRIPT_DIR}/hhvm/builddeps -DBOOST_INCLUDEDIR=${SCRIPT_DIR}/hhvm/builddeps/include -DBOOST_LIBRARYDIR=${SCRIPT_DIR}/hhvm/builddeps/lib -DBoost_NO_SYSTEM_PATHS=ON -DBoost_NO_BOOST_CMAKE=ON -DCMAKE_PREFIX_PATH=${SCRIPT_DIR}/hhvm/builddeps -DSTATIC_CXX_LIB=On -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER:FILEPATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/gcc -DCMAKE_CXX_COMPILER:FILEPATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/g++ -DCMAKE_AR:FILEPATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/gcc-ar -DCMAKE_RANLIB:FILEPATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/gcc-ranlib -DCMAKE_C_FLAGS="-fPIC" -DCMAKE_CXX_FLAGS="-fPIC" -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    cd ${SCRIPT_DIR}/hhvm/build/ && CC=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/gcc CXX=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/g++ CFLAGS="-fPIC" CXXFLAGS="-fPIC" PATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin:$PATH make -j64
    cd ${SCRIPT_DIR}/hhvm/build/ && CC=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/gcc CXX=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin/g++ CFLAGS="-fPIC" CXXFLAGS="-fPIC" PATH=${SCRIPT_DIR}/hhvm/gcc-builder/dist/usr/local/gcc/7.5.0/bin:$PATH make install
    rm ${SCRIPT_DIR}/hhvm -rf
fi

# # --- Hadoop (for SparkBench) ---
# echo "Installing Hadoop..."
# if [ ! -d "$HOME/local/hadoop" ]; then
#     HADOOP_VERSION="3.3.4"
#     wget -q https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz
#     tar -xzf hadoop-${HADOOP_VERSION}.tar.gz
#     mv hadoop-${HADOOP_VERSION} $HOME/local/hadoop
# fi
# 
# # --- Spark (for SparkBench) ---
# echo "Installing Spark..."
# if [ ! -d "$HOME/local/spark" ]; then
#     SPARK_VERSION="3.4.1"
#     wget -q https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz
#     tar -xzf spark-${SPARK_VERSION}-bin-hadoop3.tgz
#     mv spark-${SPARK_VERSION}-bin-hadoop3 $HOME/local/spark
# fi
# 
# # --- SVT-AV1 (for VideoTranscode) ---
# echo "Building SVT-AV1..."
# if [ ! -d "$BUILD_DIR/SVT-AV1" ]; then
#     git clone https://gitlab.com/AOMediaCodec/SVT-AV1.git
#     cd SVT-AV1
#     git checkout v1.7.0
#     cd Build
#     cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/local
#     make -j$(nproc)
#     make install
#     cd ../..
# fi
# 
# # --- libaom (for VideoTranscode) ---
# echo "Building libaom..."
# if [ ! -d "$BUILD_DIR/aom" ]; then
#     git clone https://aomedia.googlesource.com/aom
#     cd aom
#     git checkout v3.6.1
#     mkdir build && cd build
#     cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/local
#     make -j$(nproc)
#     make install
#     cd ../..
# fi
# 
# # --- x264 (for VideoTranscode) ---
# echo "Building x264..."
# if [ ! -d "$BUILD_DIR/x264" ]; then
#     git clone https://code.videolan.org/videolan/x264.git
#     cd x264
#     ./configure --prefix=$HOME/local --enable-shared --enable-pic
#     make -j$(nproc)
#     make install
#     cd ..
# fi
# 
# # --- FFmpeg (for VideoTranscode) ---
# echo "Building FFmpeg..."
# if [ ! -f "$HOME/local/bin/ffmpeg" ]; then
#     git clone https://git.ffmpeg.org/ffmpeg.git
#     cd ffmpeg
#     git checkout n5.1.3
#     ./configure \
#         --prefix=$HOME/local \
#         --enable-gpl \
#         --enable-libx264 \
#         --enable-libx265 \
#         --enable-libsvtav1 \
#         --enable-libaom-av1 \
#         --enable-libvpx \
#         --enable-libfdk-aac \
#         --enable-libmp3lame \
#         --enable-libopus \
#         --enable-nonfree
#     make -j$(nproc)
#     make install
#     cd ..
# fi
# 
# # --- fbthrift (for WDLBench) ---
# echo "Building fbthrift..."
# if [ ! -d "$BUILD_DIR/fbthrift" ]; then
#     git clone https://github.com/facebook/fbthrift.git
#     cd fbthrift
#     git checkout v2023.07.17.00
#     mkdir _build && cd _build
#     cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/local
#     make -j$(nproc)
#     make install
#     cd ../..
# fi
# 
# # --- lzbench (for WDLBench) ---
# echo "Building lzbench..."
# if [ ! -f "$HOME/local/bin/lzbench" ]; then
#     git clone https://github.com/inikep/lzbench.git
#     cd lzbench
#     make -j$(nproc)
#     cp lzbench $HOME/local/bin/
#     cd ..
# fi
# 
# # --- MediaWiki ---
# echo "Setting up MediaWiki..."
# if [ ! -d "/var/www/mediawiki" ]; then
#     wget https://releases.wikimedia.org/mediawiki/1.39/mediawiki-1.39.0.tar.gz
#     tar -xzf mediawiki-1.39.0.tar.gz
#     sudo mv mediawiki-1.39.0 /var/www/mediawiki
# fi
# 
# # --- Composer (for PHP) ---
# echo "Installing Composer..."
# if ! command -v composer &> /dev/null; then
#     php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
#     php composer-setup.php --2.2
#     sudo mv composer.phar /usr/local/bin/composer
#     rm composer-setup.php
# fi
# 
# # ============================================
# # ENVIRONMENT SETUP
# # ============================================
# 
# echo "Setting up environment variables..."
# cat >> $HOME/.bashrc << 'EOF'
# 
# # DCPerf Environment Variables
# export DCPERF_HOME=$HOME/dcperf
# export PATH=$HOME/local/bin:$PATH
# export LD_LIBRARY_PATH=$HOME/local/lib:$HOME/local/lib64:$LD_LIBRARY_PATH
# export PKG_CONFIG_PATH=$HOME/local/lib/pkgconfig:$PKG_CONFIG_PATH
# 
# # Java
# export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
# 
# # Hadoop
# export HADOOP_HOME=$HOME/local/hadoop
# export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
# 
# # Spark
# export SPARK_HOME=$HOME/local/spark
# export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
# 
# EOF
# 
# echo "Updating library cache..."
# sudo ldconfig
# 
# echo "=== Installation Complete ==="
# echo "Please run: source ~/.bashrc"
# echo "Then verify with: echo \$DCPERF_HOME"
