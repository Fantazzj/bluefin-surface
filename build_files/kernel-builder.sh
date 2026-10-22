#!/bin/bash
# Thanks to https://github.com/LorbusChris/bluespin for the original file
# The kernel-builder stage (see Containerfile): anything that must INSTALL
# tooling in order to BUILD an artifact runs here, in a stage that is thrown
# away. The final image never sees a compiler, kernel-devel or sbsigntools --
# not even as an install-then-remove in its rpmdb history -- and the Secure
# Boot private key is only ever mounted into this stage. build.sh consumes
# what this writes to /out (mounted there as /kernel-out):
#
#   kver                 the kernel release everything here targeted
#   v4l2loopback.ko.xz   the virtual-camera module, signed when the key was
#                        present (unsigned otherwise, with a warning)
#   vmlinuz              surface only, key only: the kernel image re-signed
#                        with the bluespin MOK key
#
# This stage FROMs the same base as the final image, so on the vanilla
# platforms the kernel here IS the kernel that ships. The surface leg
# resolves its kernel from the @mobility/surface COPR in both stages
# independently; build.sh asserts both saw the same EVR (the kver file), so
# a COPR publish landing mid-build fails the build instead of shipping
# artifacts for a kernel the image does not carry.
set -xeuo pipefail

OUT=/out
install -d "${OUT}"

############################################################################
# The kernel to build against
############################################################################
# The COPR ships the surface kernel AS `kernel` (kernel-ark packaging
# with the linux-surface patches), versioned ahead of the branch's stock
# kernel. The stock kernel-core is already installed here, and dnf
# treats a plain "install kernel-core" as satisfied by it -- so resolve
# the COPR's EVR explicitly and ask for exactly that, which also pins
# -core (the vmlinuz to re-sign) and -devel (the build tree) to the
# same build. The stock kernel can stay: kernel packages are
# installonly, this stage ships nothing, and every path below names its
# kver explicitly.
dnf -y copr enable @mobility/surface
kevr="$(dnf -q repoquery --qf '%{VERSION}-%{RELEASE}\n' \
    --disablerepo='*' \
    --enablerepo='copr:copr.fedorainfracloud.org:group_mobility:surface' \
    kernel-core | sort -V | tail -1)"
if [[ -z "${kevr}" ]]; then
    echo "the @mobility/surface COPR has no kernel-core for this branch (chroot still building?)" >&2
    exit 1
fi
dnf -y install --setopt=disable_excludes=* \
    "kernel-core-${kevr}" "kernel-devel-${kevr}"
dnf -y copr disable @mobility/surface
kver="$(rpm -q "kernel-core-${kevr}" --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"

echo "${kver}" > "${OUT}/kver"
