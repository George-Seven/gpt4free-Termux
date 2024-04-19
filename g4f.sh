#!/data/data/com.termux/files/usr/bin/bash

set -e

usage_text(){
echo "Usage: $0 \"QUERY\" | -i | -u | -s | -g | -h | --help

More options and descriptions -
  -i, --install  Install dependencies and
                 setup g4f container.

  -u, --update   Updates g4f inside container.
                 Equivalent to running :-
                  \"pip3 install -U g4f\"

  -s, --script   Pass a Python script to run
                 inside the container.

  -g, --gui      Run the g4f GUI

  -c, --cmd      Pass arguments to the container

  -p, --pip      Install python modules inside container
                 Use it as :-
                  --pip module1 module2 module3...

  -l, --login    Login to the container
"

return 0
}

example_text(){
echo "
Example for \"QUERY\" -

  $0 \"what chatgpt-4 needs to do -> the block of text to process\"


Try example -

  $0 \"extract my otp, do not make it bold, do not write extra sentences only the number -> hello your otp, not the account which is 1234, is 9270. thanks\"

You will get the output 9270 and avoid the account number
"

return 0
}

missing_deps_text(){
echo "
Install missing dependencies -

  $0 -i

Or

  $0 --install
"

return 0
}

fix_udocker_hardlinks(){
# Fix errors when extracting hardlinks from Docker images
# https://github.com/indigo-dc/udocker/issues/388#issuecomment-1527277800
UDOCKER_PATCH='
--- udocker/container/structure.py
+++ udocker.mod/container/structure.py
@@ -281,7 +281,7 @@
             if Msg.level >= Msg.VER:
                 verbose = '\'v'\''
                 Msg().out("Info: extracting:", tarf, l=Msg.INF)
-            cmd = ["tar", "-C", destdir, "-x" + verbose,
+            cmd = ["proot", "--link2symlink", "tar", "-C", destdir, "-x" + verbose,
                    "--one-file-system", "--no-same-owner", "--overwrite",
                    "--exclude=dev/*", "--exclude=etc/udev/devices/*",
                    "--no-same-permissions", r"--exclude=.wh.*",
'

TMP_PATCH_FILE="$(mktemp)"
patch -p0 --no-backup-if-mismatch -r "${TMP_PATCH_FILE}" -d "$(python -c "import sysconfig; print(sysconfig.get_path('platlib'))" 2>/dev/null || echo "${PREFIX}/lib/python3.11/site-packages")" 2>/dev/null >/dev/null <<< "${UDOCKER_PATCH}" || true
rm -rf "${TMP_PATCH_FILE}"

return 0
}

fix_udocker_qemu(){
# Fix qemu not found errors that occurs when running non-native platform containers
# Not needed for g4f container, but helpful for your other platform containers if any
UDOCKER_PATCH='
--- udocker/engine/base.py
+++ udocker.mod/engine/base.py
@@ -690,4 +690,4 @@
         if not qemu_path:
             Msg().err("Warning: qemu required but not available", l=Msg.WAR)
             return ""
-        return qemu_path if return_path else qemu_filename
+        return qemu_path if return_path else qemu_path
'

TMP_PATCH_FILE="$(mktemp)"
patch -p0 --no-backup-if-mismatch -r "${TMP_PATCH_FILE}" -d "$(python -c "import sysconfig; print(sysconfig.get_path('platlib'))" 2>/dev/null || echo "${PREFIX}/lib/python3.11/site-packages")" 2>/dev/null >/dev/null <<< "${UDOCKER_PATCH}" || true
rm -rf "${TMP_PATCH_FILE}"

return 0
}

install_g4f(){
clear 2>/dev/null || true

apt update
#yes | pkg upgrade
yes | pkg install curl python-pip proot
pip install -U udocker

fix_udocker_hardlinks

fix_udocker_qemu

LATEST_TAG="$(udocker search --list-tags hlohaus789/g4f | tail -n 2 | head -n 1)"

if [ -z "${LATEST_TAG}" ]; then
    echo "Bad connection, exiting..."
    exit 1
fi

G4F_IMAGE="hlohaus789/g4f:${LATEST_TAG}"

IMAGE_DEPS=" \
bitnami/minideb:bookworm \
${G4F_IMAGE} \
"

for i in ${IMAGE_DEPS}; do
    echo
    echo " Checking dependency image ${i} ..."
    echo
    if ! udocker inspect "${i}" 2>/dev/null >/dev/null; then
        retry=1
        echo
        echo " Downloading image ${i} ..."
        echo
        while [ ${retry} -lt 25 ]; do
            if UDOCKER_LOGLEVEL=3 udocker pull "${i}"; then
                break
            fi
            echo
            echo " Network error, retrying..."
            echo
            retry="$(("${retry}"+1))"
            if [ ${retry} -eq 20 ]; then
                echo
                echo " Bad Connection, exiting..."
                echo
                return 1
            fi
            sleep 5
        done
    fi
done

for i in $(udocker images | cut -d\  -f1 | grep "hlohaus789/g4f" | grep -v -F "${G4F_IMAGE}"); do
    udocker rmi -f "${i}" 2>/dev/null >/dev/null || true
done

for i in debian-python-builder g4f; do
    udocker rm -f "${i}" 2>/dev/null >/dev/null || true
done

for i in $(udocker ps | cut -d\  -f1 | tail -n +2); do
    if ! udocker inspect "${i}" 2>/dev/null >/dev/null; then
        udocker rm -f "${i}" 2>/dev/null >/dev/null || true
    fi
done

PYTHON_VERSION="3.11.8"
PYTHON_MAJOR="3"

if ! tar xOf "${HOME}/.udocker/extras/python-${PYTHON_VERSION}.tar.gz" 2>/dev/null >/dev/null; then

    echo
    echo " Dependency not found, missing python-${PYTHON_VERSION}.tar.gz in \"~/.udocker/extras\" ..."
    echo

    mkdir -p "${HOME}/.udocker/extras"

    PYTHON_TARGZ_DEP="https://github.com/George-Seven/gpt4free-Termux/releases/download/python-fixed/python-${PYTHON_VERSION}-$(uname -m).tar.gz"

# The python multiprocessing module needs to be fixed to work in Android
# https://github.com/termux/termux-packages/pull/8990

# PYTHON_TARGZ_DEP contains the fixed python with patches applied
# and generated via GitHub Actions workflow
# https://github.com/George-Seven/gpt4free-Termux/blob/main/.github/workflows/build_python.yml

# It'll be used to keep the installation short and simple , otherwise you can force
# an on-device-build by commenting out the PYTHON_TARGZ_DEP variable.
# This is added as a backup measure and for transparency.

build_python_on_device(){
# Patches for supporting python multiprocessing module in Android environment
# https://github.com/termux/termux-packages/pull/8990
PYTHON_PATCH_1='
--- Python-'${PYTHON_VERSION}'/Lib/multiprocessing/heap.py      2022-02-07 11:51:46.427116300 +0800
+++ Python-'${PYTHON_VERSION}'.mod/Lib/multiprocessing/heap.py  2022-02-07 11:52:48.432577700 +0800
@@ -70,7 +70,7 @@
         """

         if sys.platform == '\''linux'\'':
-            _dir_candidates = ['\''/dev/shm'\'']
+            _dir_candidates = []
         else:
             _dir_candidates = []


--- Python-'${PYTHON_VERSION}'/Modules/_multiprocessing/multiprocessing.c        2021-12-07 02:23:39.000000000 +0800
+++ Python-'${PYTHON_VERSION}'.mod/Modules/_multiprocessing/multiprocessing.c    2022-02-10 03:05:11.249248300 +0800
@@ -172,7 +172,7 @@
     _MULTIPROCESSING_RECV_METHODDEF
     _MULTIPROCESSING_SEND_METHODDEF
 #endif
-#if !defined(POSIX_SEMAPHORES_NOT_ENABLED) && !defined(__ANDROID__)
+#if !defined(POSIX_SEMAPHORES_NOT_ENABLED)
     _MULTIPROCESSING_SEM_UNLINK_METHODDEF
 #endif
     {NULL}

--- Python-'${PYTHON_VERSION}'/Modules/_multiprocessing/posixshmem.c     2021-12-07 02:23:39.000000000 +0800
+++ Python-'${PYTHON_VERSION}'.mod/Modules/_multiprocessing/posixshmem.c 2022-02-10 01:37:03.547649100 +0800
@@ -11,6 +11,9 @@
 #include <sys/mman.h>
 #endif

+int shm_open(const char *, int, mode_t);
+int shm_unlink(const char *);
+
 /*[clinic input]
 module _posixshmem
 [clinic start generated code]*/

--- Python-'${PYTHON_VERSION}'/Modules/_multiprocessing/posix-shm-extension.c        1970-01-01 08:00:00.000000000 +0800
+++ Python-'${PYTHON_VERSION}'.mod/Modules/_multiprocessing/posix-shm-extension.c    2022-02-12 13:25:30.306949200 +0800
@@ -0,0 +1,77 @@
+/* This file is a port of posix shared memory for Python3 on Termux Android, 
+   based on musl-libc which is licensed under the following standard MIT 
+   license. The ported files are listed as following.
+
+   File(s): src/mman/shm_open.c
+
+   Copyright © 2005-2020 Rich Felker, et al.
+
+   Permission is hereby granted, free of charge, to any person obtaining
+   a copy of this software and associated documentation files (the
+   "Software"), to deal in the Software without restriction, including
+   without limitation the rights to use, copy, modify, merge, publish,
+   distribute, sublicense, and/or sell copies of the Software, and to
+   permit persons to whom the Software is furnished to do so, subject to
+   the following conditions:
+
+   The above copyright notice and this permission notice shall be
+   included in all copies or substantial portions of the Software.
+
+   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
+   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
+   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
+   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
+   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
+   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
+   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
+ */
+
+#define _DEFAULT_SOURCE
+#include <fcntl.h>     // open()
+#include <string.h>    // strlen(), memcpy()
+#include <errno.h>     // errno
+#include <limits.h>    // NAME_MAX
+#include <unistd.h>    // unlink()
+
+#define SHM_PREFIX "/tmp/shm."
+
+static __inline__ char *__strchrnul(const char *s, int c)
+{
+    c = (unsigned char)c;
+    if (!c) return (char *)s + strlen(s);
+    for (; *s && *(unsigned char *)s != c; s++);
+    return (char *)s;
+}
+
+static char *__shm_mapname(const char *name, char *buf)
+{
+    char *p;
+    while (*name == '\''/'\'') name++;
+    if (*(p = __strchrnul(name, '\''/'\'')) || p==name ||
+        (p-name <= 2 && name[0]=='\''.'\'' && p[-1]=='\''.'\'')) {
+        errno = EINVAL;
+        return 0;
+    }
+    if (p-name > NAME_MAX-4) {
+        errno = ENAMETOOLONG;
+        return 0;
+    }
+    memcpy(buf, SHM_PREFIX, strlen(SHM_PREFIX));
+    memcpy(buf+strlen(SHM_PREFIX), name, p-name+1);
+    return buf;
+}
+
+int shm_open(const char *name, int flag, mode_t mode)
+{
+    char buf[NAME_MAX+strlen(SHM_PREFIX)+1];
+    if (!(name = __shm_mapname(name, buf))) return -1;
+    int fd = open(name, flag|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK, mode);
+    return fd;
+}
+
+int shm_unlink(const char *name)
+{
+    char buf[NAME_MAX+strlen(SHM_PREFIX)+1];
+    if (!(name = __shm_mapname(name, buf))) return -1;
+    return unlink(name);
+}
'

PYTHON_PATCH_2='
--- Python-'${PYTHON_VERSION}'/setup.py	2022-10-24 23:05:39.000000000 +0530
+++ Python-'${PYTHON_VERSION}'/setup.py	2022-10-25 19:23:59.154046267 +0530
@@ -1328,8 +1329,8 @@
             sysconfig.get_config_var('\''POSIX_SEMAPHORES_NOT_ENABLED'\'')
         ):
             multiprocessing_srcs.append('\''_multiprocessing/semaphore.c'\'')
-        self.addext(Extension('\''_multiprocessing'\'', multiprocessing_srcs))
-        self.addext(Extension('\''_posixshmem'\'', ['\''_multiprocessing/posixshmem.c'\'']))
+        self.addext(Extension('\''_multiprocessing'\'', multiprocessing_srcs))
+        self.addext(Extension('\''_posixshmem'\'', ['\''_multiprocessing/posixshmem.c'\'','\''_multiprocessing/posix-shm-extension.c'\'']))

     def detect_uuid(self):
         # Build the _uuid module if possible
'

echo
echo " Creating container debian-python-builder..."
echo
udocker create --name=debian-python-builder bitnami/minideb:bookworm

TMP_DIR="$(mktemp -d)"

mkdir -p "${TMP_DIR}/patches/Python-${PYTHON_VERSION}"

for i in $(seq -s " " 1 "$(set | cut -d= -f1 | grep -E "PYTHON_PATCH_[0-9]+" | wc -l)"); do
    eval "echo \"\$PYTHON_PATCH_$i\" > '${TMP_DIR}/patches/Python-${PYTHON_VERSION}/python_patch_$i.patch'"
done

echo
echo " Configuring container debian-python-builder..."
echo
udocker run debian-python-builder bash -c ' \
    echo "nameserver 1.1.1.1" > /etc/resolv.conf; \
    apt update || exit 1; \
    DEBIAN_FRONTEND=noninteractive apt reinstall -y perl-base; DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends curl ca-certificates gcc libbz2-dev libev-dev libffi-dev libgdbm-dev liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev make tk-dev wget tar zlib1g-dev || exit 1; \
'

echo
echo " Building dependency python-${PYTHON_VERSION}.tar.gz ..."
echo
udocker run -v "${TMP_DIR}/patches:/tmp/patches" debian-python-builder bash -c ' \ 
    export PYTHON_VERSION='${PYTHON_VERSION}' PYTHON_MAJOR='${PYTHON_MAJOR}'; \
    wget "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" -O "Python-${PYTHON_VERSION}.tgz" || exit 1; \
    rm -rf "Python-${PYTHON_VERSION}"; \
    mkdir -p "Python-${PYTHON_VERSION}"; \
    tar -xf "Python-${PYTHON_VERSION}.tgz" -C "Python-${PYTHON_VERSION}" --strip-components=1; \
    find "/tmp/patches/Python-${PYTHON_VERSION}" -maxdepth 1 -type f -name "python_patch_*\.patch" -exec patch -p0 -i "{}" \;; \
    cd "Python-${PYTHON_VERSION}"; \
    ./configure --prefix=/usr --enable-shared --enable-optimizations LDFLAGS=-Wl,-rpath=/usr/lib,--disable-new-dtags ac_cv_posix_semaphores_enabled=yes ac_cv_func_sem_open=yes ac_cv_func_sem_timedwait=yes ac_cv_func_sem_getvalue=yes ac_cv_func_sem_unlink=yes; \
    make || exit 1; \
    rm -rf dist; \
    PATH="$(pwd)/dist/usr/bin:${PATH}" DESTDIR=dist make install; \
    tar -I "gzip --best" -cf "python-${PYTHON_VERSION}.tar.gz" -C dist ./usr; \
    cp "python-${PYTHON_VERSION}.tar.gz" /tmp; \
'

mv -f "${TMP_DIR}/python-${PYTHON_VERSION}.tar.gz" "${HOME}/.udocker/extras"

echo
echo " Finished building dependency python-${PYTHON_VERSION}.tar.gz ..."
echo

rm -rf "${TMP_DIR}"

echo
echo " Removing container debian-python-builder as dependency has been built..."
echo
udocker rm -f debian-python-builder 2>/dev/null >/dev/null

return 0
}

    rm -rf "${HOME}/.udocker/extras/python-${PYTHON_VERSION}.tar.gz"

    if [ -n "${PYTHON_TARGZ_DEP}" ]; then

        TMP_FILE="$(mktemp)"

        if curl -L "${PYTHON_TARGZ_DEP}" -o "${TMP_FILE}" && tar xOf "${TMP_FILE}" 2>/dev/null >/dev/null; then
            mv -f "${TMP_FILE}" "${HOME}/.udocker/extras/python-${PYTHON_VERSION}.tar.gz"
        else
            build_python_on_device
        fi

    else
        build_python_on_device
    fi
fi

echo
echo " Creating container g4f..."
echo
udocker create --name=g4f "${G4F_IMAGE}"

TMP_DIR="$(mktemp -up /tmp)"

echo
echo " Configuring container g4f..."
echo
udocker run -v "${HOME}/.udocker/extras:${TMP_DIR}" --user=root g4f bash -c ' \
    export PYTHON_VERSION='${PYTHON_VERSION}' PYTHON_MAJOR='${PYTHON_MAJOR}'; \
    echo "127.0.0.1 localhost" >>/etc/hosts; \
    tar -xf "'${TMP_DIR}'/python-${PYTHON_VERSION}.tar.gz" -C / --preserve-permissions || exit 1; \
    pip3 install -U --break-system-packages --root-user-action=ignore g4f supervisor; \
    mkdir -p /app; \
    cd app; \
    echo -n "#!" > chatgpt.py; echo -e '\''/usr/bin/env python3\n\nimport sys\nfrom g4f.client import Client\n\nclient = Client()\nresponse = client.chat.completions.create(\n model="gpt-4",\n    messages=[{"role": "user", "content": " ".join(sys.argv[1:])}],\n)\nprint(response.choices[0].message.content)'\'' >> chatgpt.py; chmod 755 chatgpt.py; \
'

rm -rf "${TMP_DIR}"

#echo
#echo " Removing image "${G4F_IMAGE}" as dependency has been built..."
#echo
#udocker rmi -f "${G4F_IMAGE}" 2>/dev/null >/dev/null

clear 2>/dev/null || true

usage_text
example_text

return 0
}

mkdir -p "${HOME}/.udocker/lib"

cat <<'EOF' > "${HOME}/.udocker/udocker.conf"
[DEFAULT]
use_proot_executable = /data/data/com.termux/files/usr/bin/proot
proot_link2symlink = True
verbose_level = 1
EOF

echo "2.9.9" > "${HOME}/.udocker/lib/VERSION"

fix_udocker_hardlinks

fix_udocker_qemu

if [ $# -lt 1 ]; then
    usage_text
    example_text
    exit 1
else
    check_arch(){
        if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "x86_64" ]; then
            return 0
        else
            echo "The architecture $(uname -m) not supported!"
            echo "aarch64 and x86_64 are supported"
            echo "https://hub.docker.com/r/hlohaus789/g4f/tags"
            return 1
        fi
    }
    check_deps(){
    check_arch
    for i in curl pip udocker proot; do
        if ! command -v "${i}" 2>/dev/null >/dev/null; then
            echo "Missing command \"$i\""
            missing_deps_text
            return 1
        fi
    done
    if ! udocker inspect g4f 2>/dev/null >/dev/null; then
        echo "Container g4f not found"
        missing_deps_text
        return 1
    fi
    return 0
    }
    case "$1" in
        -u|--update)
            check_deps
            exec udocker run --user=root g4f pip3 install -U --break-system-packages --root-user-action=ignore g4f
        ;;

        -i|--install)
            check_arch
            install_g4f
        ;;

        -s|--script)
            check_deps
            if [ ! -f "$2" ]; then
                echo "$2 not found"
                exit 1
            fi
            TMP_FILE="$(mktemp -up /tmp)"
            exec udocker run -v "$(mktemp -d):/dev/shm" -v "$(readlink -f "$2"):${TMP_FILE}" g4f python3 "${TMP_FILE}"
        ;;

        -g|--gui)
            check_deps
            exec udocker run -v "$(mktemp -d):/dev/shm" g4f g4f gui
        ;;

        -c|--cmd)
            check_deps
            if [ -z "$2" ]; then
                echo "No commands given"
                exit 1
            fi
            unset CMD
            CMD="${@:2}"
            exec udocker run -v "$(mktemp -d):/dev/shm" g4f bash -c "${CMD}"
        ;;

        -p|--pip)
            check_deps
            exec udocker run --user=root g4f pip3 install -U --break-system-packages --root-user-action=ignore ${@:2}
        ;;

        -l|--login)
            check_deps
            exec udocker run -v "$(mktemp -d):/dev/shm" --user=root g4f bash
        ;;

        -h|--help)
            usage_text
            example_text
        ;;

        *)
            check_deps
            exec udocker run -v "$(mktemp -d):/dev/shm" --entrypoint /app/chatgpt.py g4f "$@"
    esac
fi

exit 0
