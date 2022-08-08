#!/bin/bash

FEDORA_KERNEL_VERSION=5.18.16-200.fc36
PATCHES_GIT=https://github.com/Redecorating/mbp-16.1-linux-wifi
PATCHES_COMMIT=0f18a8ee0e2eb7893222e3d0f433f75ce689aa91

# Dependencies
dnf install -y fedora-packager git curl pesign ncurses-devel libkcapi libkcapi-devel libkcapi-static libkcapi-tools libbpf fedpkg rpmdevtools dwarves

# Set home build directory
rpmdev-setuptree

# Get kernel source and install dependencies
cd /root/rpmbuild/SOURCES
koji download-build --arch=src kernel-${FEDORA_KERNEL_VERSION}
rpm -Uvh kernel-${FEDORA_KERNEL_VERSION}.src.rpm
cd /root/rpmbuild/SOURCES
curl "https://wiki.t2linux.org/tools/rmmod_tb.sh" > rmmod_tb.sh
cd /root/rpmbuild/SPECS 
dnf -y builddep kernel.spec

# Download patches
mkdir /tmp/download && cd /tmp/download 
git clone --single-branch --branch main ${PATCHES_GIT}
cd *
git checkout ${PATCHES_COMMIT}
rm -rf 0001-arch-additions.patch
for f in *.patch; do mv "$f" "$f.t2"; done
cp *.patch.t2 /root/rpmbuild/SOURCES/

# Get apple modules
mkdir /tmp/src && cd /tmp/src
KERNEL_SRC="/root/rpmbuild/SOURCES/linux-*.tar.xz"
tar -xf $KERNEL_SRC
KERNEL_TMP="*"
cd $KERNEL_TMP
git clone --depth=1 https://github.com/t2linux/apple-bce-drv drivers/staging/apple-bce
git clone --depth=1 https://github.com/t2linux/apple-ib-drv drivers/staging/apple-ibridge
rm -rf drivers/staging/*/.git
cd ..
rm "$KERNEL_SRC"
tar -cf "$KERNEL_SRC" "$KERNEL_TMP"

# Apply patches
cd /root/rpmbuild/SPECS
echo "CONFIG_APPLE_BCE=m" >> "/root/rpmbuild/SOURCES/kernel-local"
echo "CONFIG_APPLE_IBRIDGE=m" >> "/root/rpmbuild/SOURCES/kernel-local"
sed -i "s/# define buildid.*/%define buildid .t2/" "/root/rpmbuild"/SPECS/kernel.spec

for i in /root/rpmbuild/SOURCES/*.patch.t2; do
    PATCH_ID=$(($(grep ^Patch "/root/rpmbuild/SPECS/kernel.spec" | tail -n2 | head -n1 | awk '{ print $1 }' | sed s/Patch// | sed s/://) + 1 ))
    sed -i "s@# END OF PATCH DEFINITIONS@Patch$PATCH_ID: $i\n\n# END OF PATCH DEFINITIONS@g" /root/rpmbuild/SPECS/kernel.spec
done;

# Build non-debug rpms
cd "/root/rpmbuild"/SPECS
cp /repo/*.spec .
rpmbuild -bb --with baseonly --without debug --without debuginfo --target=x86_64 kernel.spec
rpmbuild -bb --target=x86_64 t2linux-config.spec


# Copy artifacts to shared volume
cd "/repo"
mkdir -p ./output
mkdir -p ./output/RPMS
cp -rfv /root/rpmbuild/RPMS/* ./output/RPMS/
