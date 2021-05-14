# Download, extract Nexus to /tmp/sonatype/nexus
FROM docker.io/arm64v8/alpine:latest as downloader

# Needed for dockerhub automated arm64 builds
#COPY qemu-arm-static /usr/bin

ARG NEXUS_VERSION=3.30.1-01
ARG NEXUS_DOWNLOAD_URL=https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz

ADD "${NEXUS_DOWNLOAD_URL}" "/tmp/nexus.tar.gz"
RUN mkdir /tmp/sonatype && \
    tar -zxf /tmp/nexus.tar.gz -C /tmp/sonatype && \
    mv /tmp/sonatype/nexus-${NEXUS_VERSION} /tmp/sonatype/nexus

# Runtime image
# Logic adapted from official Dockerfile
# https://github.com/sonatype/docker-nexus3/blob/master/Dockerfile
FROM docker.io/arm64v8/alpine:3.13

# Image metadata
# git commit
LABEL org.opencontainers.image.revision="-"
LABEL org.opencontainers.image.source="https://github.com/jkaldon/nexus3-docker/tree/alpine"

# Install Java 8 and wget
RUN apk update && \
    apk add openjdk8-jre

# Setup: Rename App, Data and Work directory per official image
# App directory (/opt/sonatype/nexus)
COPY --from=downloader /tmp/sonatype /opt/sonatype
RUN \
    # Data directory (/nexus-data)
    mv /opt/sonatype/sonatype-work/nexus3 /nexus-data && \
    # Work directory (/opt/sonatype/sonatype-work/nexus3)
    ln -s /nexus-data /opt/sonatype/sonatype-work/nexus3

# Setup: Start-up script (from official image)
COPY files/opt/sonatype/start-nexus-repository-manager.sh /opt/sonatype/start-nexus-repository-manager.sh
RUN chmod 755 /opt/sonatype/start-nexus-repository-manager.sh

# Fix-up: Startup command line: Remove hard-coded memory parameters in /opt/sonatype/nexus/bin/nexus.vmoptions (per official Docker image)
RUN sed -i -e '/^-Xms\|^-Xmx\|^-XX:MaxDirectMemorySize/d' /opt/sonatype/nexus/bin/nexus.vmoptions

# Enable NEXUS_CONTEXT env-variable via nexus-default.properties
RUN sed -i -e 's/^nexus-context-path=\//nexus-context-path=\/\${NEXUS_CONTEXT}/g' /opt/sonatype/nexus/etc/nexus-default.properties

# Fix-up: Startup error with OrientDB on ARM - replace in-place 4.5.0 with 5.5.0 lib (reference is hard-coded in config files)
# http://bhamail.github.io/pinexus/nexussetup.html
ADD https://repo1.maven.org/maven2/net/java/dev/jna/jna/5.5.0/jna-5.5.0.jar /opt/sonatype/nexus/system/net/java/dev/jna/jna/4.5.0/jna-4.5.0.jar
ADD https://repo1.maven.org/maven2/net/java/dev/jna/jna-platform/5.5.0/jna-platform-5.5.0.jar /opt/sonatype/nexus/system/net/java/dev/jna/jna-platform/4.5.0/jna-platform-4.5.0.jar
RUN chmod 644 \
      /opt/sonatype/nexus/system/net/java/dev/jna/jna/4.5.0/jna-4.5.0.jar \
      /opt/sonatype/nexus/system/net/java/dev/jna/jna-platform/4.5.0/jna-platform-4.5.0.jar

# Create Nexus user + group, based on official image:
#   nexus:x:400:400:Nexus Repository Manager user:/opt/sonatype/nexus:/bin/false
#   nexus:x:400:nexus
RUN addgroup -g 400 nexus && \
    adduser \
      -s /bin/false \
      -g 'Nexus Repository Manager user' \
      -h /opt/sonatype/nexus \
      -H \
      -D \
      -u 400 \
      -G nexus \
      nexus

# Data directory "/nexus-data" owns "nexus" user
RUN chown -R nexus:nexus /nexus-data

VOLUME /nexus-data

EXPOSE 8081

USER nexus

ENV INSTALL4J_ADD_VM_PARAMS="-Xms1200m -Xmx1200m -XX:MaxDirectMemorySize=2g -Djava.util.prefs.userRoot=/nexus-data/javaprefs"
ENV NEXUS_CONTEXT=''

CMD ["sh", "-c", "/opt/sonatype/start-nexus-repository-manager.sh"]
