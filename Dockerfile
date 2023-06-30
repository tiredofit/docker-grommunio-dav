ARG DISTRO="alpine"
ARG PHP_VERSION=8.2

FROM docker.io/tiredofit/nginx-php-fpm:${PHP_VERSION}-${DISTRO} as grommunio-dav-builder
LABEL maintainer="Dave Conroy (github.com/tiredofit)"

ARG GROMMUNIO_DAV_VERSION
ARG GROMMUNIO_MAPI_HEADERS_VERSION

ENV GROMMUNIO_DAV_VERSION=${GROMMUNIO_DAV_VERSION:-"1.3"} \
    GROMMUNIO_MAPI_HEADERS_VERSION=${GROMMUNIO_MAPI_HEADERS_VERSION:-"1.1"} \
    GROMMUNIO_DAV_REPO_URL=${GROMMUNIO_DAV_REPO_URL:-"https://github.com/grommunio/grommunio-dav"} \
    GROMMUNIO_MAPI_HEADERS_REPO_URL=${GROMMUNIO_MAPI_HEADERS_REPO_URL:-"https://github.com/grommunio/mapi-header-php"} \
    PHP_ENABLE_GETTEXT=TRUE \
    PHP_ENABLE_MAPI=TRUE \
    PHP_ENABLE_MBSTRING=TRUE \
    PHP_ENABLE_SIMPLEXML=TRUE \
    PHP_ENABLE_SOAP=TRUE \
    PHP_ENABLE_POSIX=TRUE \
    PHP_ENABLE_PDO=TRUE \
    PHP_ENABLE_PDO_SQLITE=TRUE \
    PHP_ENABLE_REDIS=TRUE \
    PHP_ENABLE_SHMOP=TRUE \
    PHP_ENABLE_XMLWRITER=TRUE \
    PHP_ENABLE_TOKENIZER=TRUE

COPY build-assets/ /build-assets

RUN source /assets/functions/00-container && \
    set -ex && \
    package update && \
    package upgrade && \
    package install .grommunio-dav-build-deps \
                        git \
                        && \
    \
    ##### Fetch Grommunio MAPI PHP Headers
    clone_git_repo "${GROMMUNIO_MAPI_HEADERS_REPO_URL}" "${GROMMUNIO_MAPI_HEADERS_VERSION}" /usr/share/php-mapi && \
    echo "Gromunio MAPI PHP Headers ${GROMMUNIO_MAPI_HEADERS_VERSION} built from ${GROMMUNIO_MAPI_HEADERS_REPO_URL} on $(date +'%Y-%m-%d %H:%M:%S')" > /assets/.changelogs/grommunio-mapi-headers.version && \
    echo "Commit: $(cd /usr/share/php-mapi ; echo $(git rev-parse HEAD))" >> /assets/.changelogs/grommunio-mapi-headers.version && \
    rm -rf \
            /usr/share/php-mapi/.git* \
            /usr/share/php-mapi/.phpcs \
            /usr/share/php-mapi/.yml \
            /usr/share/php-mapi/Makefile \
            && \
    chown "${NGINX_USER}":"${NGINX_GROUP}" /usr/share/php-mapi && \
    \
    ### Fetch Source
    clone_git_repo "${GROMMUNIO_DAV_REPO_URL}" "${GROMMUNIO_DAV_VERSION}" /www/grommunio-dav && \
    \
    set +e && \
    if [ -d "/build-assets/src" ] ; then cp -Rp /build-assets/src/* /www/grommunio-dav ; fi; \
    if [ -d "/build-assets/scripts" ] ; then for script in /build-assets/scripts/*.sh; do echo "** Applying $script"; bash $script; done && \ ; fi ; \
    set -e && \
    \
    composer install && \
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
    echo "Built with Gromunio MAPI PHP Headers ${GROMMUNIO_MAPI_HEADERS_VERSION} built from ${GROMMUNIO_MAPI_HEADERS_REPO_URL} on $(date +'%Y-%m-%d %H:%M:%S')" > /rootfs/assets/.changelogs/grommunio-dav.version && \
    echo "Built with PHP ${PHP_VERSION} on ${DISTRO}" > /rootfs/assets/.changelogs/grommunio-dav.version && \
    \
    env | grep ^GROMMUNIO | sort >> /rootfs/assets/.changelogs/grommunio-dav.version && \
    cd /rootfs/ && \
    find . -name .git -type d -print0|xargs -0 rm -rf -- && \
    mkdir -p /grommunio-dav/ && \
    tar cavf /grommunio-dav/grommunio-dav.tar.zst . &&\
    \
    ### Cleanup
    package remove .grommunio-dav-build-deps && \
    package cleanup && \
    rm -rf \
            /usr/src/*

FROM scratch
LABEL maintainer="Dave Conroy (github.com/tiredofit)"

COPY --from=grommunio-dav-builder /grommunio-dav/* /grommunio-dav/
COPY CHANGELOG.md /tiredofit_docker-grommunio-dav.md
