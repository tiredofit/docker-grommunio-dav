ARG DISTRO="alpine"
ARG PHP_BASE=8.0

FROM docker.io/tiredofit/nginx-php-fpm:${DISTRO}-${PHP_BASE} as grommunio-dav-builder
LABEL maintainer="Dave Conroy (github.com/tiredofit)"

ARG GROMMUNIO_DAV_VERSION

ENV GROMMUNIO_DAV_VERSION=${GROMMUNIO_DAV_VERSION:-"1.1"} \
    GROMMUNIO_DAV_REPO_URL=${GROMMUNIO_DAV_REPO_URL:-"https://github.com/grommunio/grommunio-dav.git"}

ADD build-assets/ /build-assets

RUN source /assets/functions/00-container && \
    set -ex && \
    apk update && \
    apk upgrade && \
    apk add -t .grommunio-dav-build-deps \
               git \
               && \
    \
    ### Fetch Source
    clone_git_repo ${GROMMUNIO_DAV_REPO_URL} ${GROMMUNIO_DAV_VERSION} && \
    \
    set +e && \
    if [ -d "/build-assets/src" ] ; then cp -Rp /build-assets/src/* /usr/src/grommunio_dav ; fi; \
    if [ -d "/build-assets/scripts" ] ; then for script in /build-assets/scripts/*.sh; do echo "** Applying $script"; bash $script; done && \ ; fi ; \
    set -e && \
    \
    ### Setup RootFS
    mkdir -p /rootfs/assets/.changelogs && \
    mkdir -p /rootfs/www/grommunio-dav && \
    mkdir -p /rootfs/assets/grommunio/config/dav && \
    \
    ### Move files to RootFS
    cp -Rp * /rootfs/www/grommunio-dav/ && \
    mv config.php /rootfs/assets/grommunio/config/dav/ && \
    ln -sf /etc/grommunio/dav.php config.php && \
    \
    chown -R ${NGINX_USER}:${NGINX_GROUP} /rootfs/www/grommunio-dav && \
    \
    ### Cleanup and Compress Package
    echo "Gromunio Dav ${GROMMUNIO_DAV_VERSION} built from ${GROMMUNIO_DAV_REPO_URL} on $(date +'%Y-%m-%d %H:%M:%S')" > /rootfs/assets/.changelogs/grommunio-dav.version && \
    echo "Commit: $(cd /usr/src/grommunio-dav ; echo $(git rev-parse HEAD))" >> /rootfs/assets/.changelogs/grommunio-dav.version && \
    env | grep GROMMUNIO | sort >> /rootfs/assets/.changelogs/grommunio-dav.version && \
    cd /rootfs/ && \
    find . -name .git -type d -print0|xargs -0 rm -rf -- && \
    mkdir -p /grommunio-dav/ && \
    tar cavf /grommunio-dav/grommunio-dav.tar.zst . &&\
    \
    ### Cleanup
    apk del .grommunio-dav-build-deps && \
    rm -rf /usr/src/* /var/cache/apk/*

FROM scratch
LABEL maintainer="Dave Conroy (github.com/tiredofit)"

COPY --from=grommunio-dav-builder /grommunio-dav/* /grommunio-dav/
COPY CHANGELOG.md /tiredofit_docker-grommunio-dav.md
