#!/bin/bash -e
[ "${BASH_SOURCE[0]}" ] && SCRIPT_NAME="${BASH_SOURCE[0]}" || SCRIPT_NAME=$0
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_NAME")" && pwd -P)"

parmetis_ver="4.0.3"
parmetis_sha256="f2d9a231b7cf97f1fee6e8c9663113ebf6c240d407d3c118c55b3633d6be6e5f"
source "${SCRIPT_DIR}"/common_vars.sh
source "${SCRIPT_DIR}"/tool_kit.sh
source "${SCRIPT_DIR}"/signal_trap.sh
source "${INSTALLDIR}"/toolchain.conf
source "${INSTALLDIR}"/toolchain.env

[ -f "${BUILDDIR}/setup_parmetis" ] && rm "${BUILDDIR}/setup_parmetis"

PARMETIS_CFLAGS=''
PARMETIS_LDFLAGS=''
PARMETIS_LIBS=''
! [ -d "${BUILDDIR}" ] && mkdir -p "${BUILDDIR}"
cd "${BUILDDIR}"

case "$with_parmetis" in
    __INSTALL__)
        echo "==================== Installing ParMETIS ===================="
        pkg_install_dir="${INSTALLDIR}/parmetis-${parmetis_ver}"
        install_lock_file="$pkg_install_dir/install_successful"
        if verify_checksums "${install_lock_file}" ; then
            echo "parmetis-${parmetis_ver} is already installed, skipping it."
        else
            if [ -f parmetis-${parmetis_ver}.tar.gz ] ; then
                echo "parmetis-${parmetis_ver}.tar.gz is found"
            else
                download_pkg ${DOWNLOADER_FLAGS} ${parmetis_sha256} \
                             https://www.cp2k.org/static/downloads/parmetis-${parmetis_ver}.tar.gz
            fi
            echo "Installing from scratch into ${pkg_install_dir}"
            [ -d parmetis-${parmetis_ver} ] && rm -rf parmetis-${parmetis_ver}
            tar -xzf parmetis-${parmetis_ver}.tar.gz
            cd parmetis-${parmetis_ver}
            make config \
                 cc=${MPICC} \
                 cxx=${MPICXX} \
                 prefix=${pkg_install_dir} > configure.log 2>&1
            make -j $NPROCS > make.log 2>&1
            make install > install.log 2>&1
            # Have to build METIS again independently due to bug in ParMETIS make install
            echo "==================== Installing METIS ===================="
            cd metis
            make config \
                 cc=${MPICC} \
                 cxx=${MPICXX} \
                 prefix=${pkg_install_dir} > configure.log 2>&1
            make -j $NPROCS > make.log 2>&1
            make install > install.log 2>&1
            cd ../..
            write_checksums "${install_lock_file}" "${SCRIPT_DIR}/$(basename ${SCRIPT_NAME})"
        fi
        PARMETIS_CFLAGS="-I'${pkg_install_dir}/include'"
        PARMETIS_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
    __SYSTEM__)
        echo "==================== Finding ParMETIS from system paths ===================="
        check_lib -lparmetis "ParMETIS"
        add_include_from_paths PARMETIS_CFLAGS "parmetis.h" $INCLUDE_PATHS
        add_lib_from_paths PARMETIS_LDFLAGS "libparmetis.*" $LIB_PATHS
        ;;
    __DONTUSE__)
        ;;
    *)
        echo "==================== Linking ParMETIS to user paths ===================="
        pkg_install_dir="$with_parmetis"
        check_dir "${pkg_install_dir}/lib"
        check_dir "${pkg_install_dir}/include"
        PARMETIS_CFLAGS="-I'${pkg_install_dir}/include'"
        PARMETIS_LDFLAGS="-L'${pkg_install_dir}/lib' -Wl,-rpath='${pkg_install_dir}/lib'"
        ;;
esac
if [ "$with_parmetis" != "__DONTUSE__" ] ; then
    PARMETIS_LIBS="-lparmetis"
    if [ "$with_parmetis" != "__SYSTEM__" ] ; then
        cat <<EOF > "${BUILDDIR}/setup_parmetis"
prepend_path PATH "$pkg_install_dir/bin"
prepend_path LD_LIBRARY_PATH "$pkg_install_dir/lib"
prepend_path LD_RUN_PATH "$pkg_install_dir/lib"
prepend_path LIBRARY_PATH "$pkg_install_dir/lib"
prepend_path CPATH "$pkg_install_dir/include"
EOF
        cat "${BUILDDIR}/setup_parmetis" >> $SETUPFILE
    fi
    cat <<EOF >> "${BUILDDIR}/setup_parmetis"
export PARMETIS_INSTALL_MODE="${with_parmetis}"
export PARMETIS_CFLAGS="${PARMETIS_CFLAGS}"
export PARMETIS_LDFLAGS="${PARMETIS_LDFLAGS}"
export PARMETIS_LIBS="${PARMETIS_LIBS}"
export CP_CFLAGS="\${CP_CFLAGS} IF_MPI(${PARMETIS_CFLAGS}|)"
export CP_LDFLAGS="\${CP_LDFLAGS} IF_MPI(${PARMETIS_LDFLAGS}|)"
export CP_LIBS="IF_MPI(-lptscotchparmetis|) \${CP_LIBS}"
EOF
fi

# update toolchain environment
load "${BUILDDIR}/setup_parmetis"
export -p > "${INSTALLDIR}/toolchain.env"

cd "${ROOTDIR}"
report_timing "parmetis"
