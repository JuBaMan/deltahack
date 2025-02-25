# Get the 22.04.4 Ubuntu OS:
# Get the minimal Ubuntu 22.04.4 OS image:
FROM ubuntu:jammy-20240808

# Ensures no prompts in the terminal sh terminal:
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/London

# Populate the list of all available packages for the 22.04.4 Ubuntu OS
# and install:
#   - wget for downloading Python, Spark, Java, Hadoop;
#   - gcc g++ make libc6-dev zlib1g-dev for compiling Python and associated packages;
#   - libpq-dev for PostgreSQL database and pg_config + psycopg2;
#   - libcairo2-dev for pycairo;
#   - libgirepository1.0-dev for PyGObject;
#   - libdbus-1-dev dbus for D-Bus and dbus-python;
#   - git libbz2-dev for libfaketime;
RUN apt-get update && apt-get install -y \
    wget \
    gcc g++ make libc6-dev zlib1g-dev libc6 \
    libssl-dev libsqlite3-dev libreadline-dev libffi-dev libgdbm-dev uuid-dev \
    libpq-dev \
    libcairo2-dev cmake pkg-config \
    libgirepository1.0-dev \
    libdbus-1-dev dbus \
    git libbz2-dev

# Download Python3.11.0 from the URL and complete manual build and install:
RUN cd usr/local/src && wget https://www.python.org/ftp/python/3.11.0/Python-3.11.0.tgz && \
    tar -xvf Python-3.11.0.tgz && \
    cd Python-3.11.0 && \
    ./configure --enable-optimizations --prefix=/usr/local && \
    make -j$(nproc) && \
    make install

# Create a virtual environment for the Databricks Python environment:
RUN cd /usr/local/ && mkdir -p /usr/local/venvs && \
    python3 -m venv /usr/local/venvs/databricks_venv && \
    . /usr/local/venvs/databricks_venv/bin/activate
COPY requirements.txt /usr/local/venvs/requirements.txt
RUN python3 -m pip install -r /usr/local/venvs/requirements.txt

# Multi-target host architecture Java build;
# Download Java 8 from the URL and complete manual build and install:
ARG TARGETARCH
RUN case ${TARGETARCH} in \
    amd64) \
        export ARCH="x64" ;; \
    arm64) \
        export ARCH="aarch64" ;; \
    *) \
        echo "Building for unknown architecture ${TARGETARCH}"; exit 1 ;; \
    esac && \
    mkdir -p /usr/local/java/zulu8.78.0.19 && \
    cd /usr/local/java && \
    wget "https://cdn.azul.com/zulu/bin/zulu8.78.0.19-ca-jdk8.0.412-linux_${ARCH}.tar.gz" && \
    tar -xvf zulu8.78.0.19-ca-jdk8.0.412-linux_${ARCH}.tar.gz \
        --strip-components=1 \
        -C /usr/local/java/zulu8.78.0.19
ENV JAVA_HOME=/usr/local/java/zulu8.78.0.19
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Download Spark 3.5.4 WITHOUT Hadoop:
RUN cd /usr/local && \
    wget https://archive.apache.org/dist/spark/spark-3.5.4/spark-3.5.4-bin-without-hadoop.tgz && \
    tar -xvf spark-3.5.4-bin-without-hadoop.tgz && \
    mv spark-3.5.4-bin-without-hadoop /usr/local/spark-3.5.4 && \
    ln -s /usr/local/spark-3.5.4 /usr/local/spark && \
    cd /usr/local/spark/python && \
    python3 setup.py sdist && \
    python3 -m pip install dist/pyspark-3.5.4.tar.gz
ENV SPARK_HOME=/usr/local/spark

# Download Hadoop 3.3.6,
# and set environment variables so we can use Hadoop:
RUN cd /usr/local && \
    mkdir -p /usr/local/hadoop-3.3.6 && \
    case ${TARGETARCH} in \
    amd64) \
        wget https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz && \
        tar -xvf hadoop-3.3.6.tar.gz \
            --strip-components=1 \
            -C /usr/local/hadoop-3.3.6 ;; \
    arm64) \
        wget https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6-aarch64.tar.gz && \
        tar -xvf hadoop-3.3.6-aarch64.tar.gz \
            --strip-components=1 \
            -C /usr/local/hadoop-3.3.6;; \
    *) \
        echo "Building for unknown architecture ${TARGETARCH}"; exit 1 ;; \
    esac && \
    ln -s /usr/local/hadoop-3.3.6 /usr/local/hadoop
ENV HADOOP_HOME=/usr/local/hadoop
ENV PATH="$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"

# We run 'hadoop classpath' in a shell to capture its output,
# and set it in the shell script to be read at Spark runtime;
# This also prepares the Spark environment to use Delta Lake:
RUN set -ex && \
    SPARK_DIST_CP="$(hadoop classpath)" && \
    echo "export SPARK_DIST_CLASSPATH=\"${SPARK_DIST_CP}\"" \
        >> /usr/local/spark/conf/spark-env.sh && \
    echo 'spark.sql.extensions io.delta.sql.DeltaSparkSessionExtension' \
        >> /usr/local/spark/conf/spark-defaults.conf && \
    echo 'spark.sql.catalog.spark_catalog org.apache.spark.sql.delta.catalog.DeltaCatalog' \
        >> /usr/local/spark/conf/spark-defaults.conf
# We also set the env variable to read the Spark config we just set:
ENV SPARK_CONF_DIR=/usr/local/spark/conf

# Download Delta Lake JARs compatible with Spark 3.5.4:
RUN cd /usr/local/spark/jars && \
    wget https://repo1.maven.org/maven2/io/delta/delta-spark_2.12/3.3.0/delta-spark_2.12-3.3.0.jar && \
    wget https://repo1.maven.org/maven2/io/delta/delta-storage/3.3.0/delta-storage-3.3.0.jar

# Installing time-change library:
RUN cd /usr/local/src && \
    git clone https://github.com/wolfcw/libfaketime.git &&\
    cd libfaketime/src && \
    make install

ENV LD_PRELOAD=/usr/local/lib/faketime/libfaketime.so.1
ENV FAKETIME_DONT_FAKE_MONOTONIC=1
