ARG IMAGE_VERSION
# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Builder image
FROM quay.io/fedora-ostree-desktops/silverblue:${IMAGE_VERSION} AS kernel-builder-surface
# Fedora base image: quay.io/fedora/fedora-bootc:${IMAGE_VERSION}
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=secureboot_key,required=false \
    /ctx/kernel-builder.sh

# Base Image
FROM ghcr.io/ublue-os/bluefin:${IMAGE_VERSION}

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=kernel-builder-surface,source=/out,target=/kernel-out \
    /ctx/surface.sh && \
    /ctx/variant-finish.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
