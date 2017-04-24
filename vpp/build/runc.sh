#!/bin/bash
# Copyright (c) 2016 by cisco Systems, Inc.
# Alexander Popovsky (apopovsk@cisco.com)

getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "getopt is not supported on this system!"
    exit 2
fi

readonly short='io:f:C:dh'
readonly long='interactive,os:,file:,directory,debug,help'

readonly parsed=$(getopt --options ${short} --longoptions ${long} --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    exit 2
fi
eval set -- "${parsed}"

os='ubuntu:16.04'

show_help() {
    echo "runc.sh [OPTIONS] COMMAND"
    echo
    echo "Prepare a Docker container with VPP build and debug environment"
    echo "and run a COMMAND inside the container"
    echo
    echo "Available options:"
    echo
    echo "-C|--directory <DIR>  Change to DIR before performing any operations."
    echo "                      Default is '.' (current directory)."
    echo
    echo "-d|--debug            Prepare debug environment. Install VPP debug"
    echo "                      packages inside the container before running"
    echo "                      COMMAND."
    echo
    echo "-o|--os <OS>          Prepare container for the selected OS."
    echo "                      OS=ubuntu:14.04|ubunu:16.04|centos:7."
    echo "                      Default is 'ubuntu:16.04'"
    echo
    echo "-i, --interactive     Keep STDIN open. Allows interactive "
    echo "                      communication with the container."
    echo
    echo "-f, --file            Path to the Dockerfile to use."
    echo
    exit 1
}

while true; do
   case "$1" in
        -h|--help)
            show_help
            shift
            ;;
        -i|--interactive)
            interactive=y
            shift
            ;;
        -d|--debug)
            debug=y
            shift
            ;;
        -o|--os)
            os=$2
            shift 2
            ;;
        -f|--file)
            file=$2
            shift 2
            ;;
        -C|--directory)
            dir=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
    esac
done

# exit with error by default
ID=""
RET=99

stop() {
    # Stop the container (/bin/cat is still running)
    [[ !  -z  ${ID}  ]] && (docker kill ${ID}; docker rm --force ${ID})
    exit ${RET}
}

trap stop INT

container() {

    local os=$1
    local file=$2
    local vpp=$3
    local tag=$4

    # Build base docker image
    # In most cases cached image already exists
    # Some assumptions about Dockerfile names:
    #   centos:7 => Dockerfile.centos7
    #   ubuntu:14.04 => Dockerfile.ubuntu1404
    #   ubuntu:16.04 => Dockerfile.ubuntu1604
    #   foobar:1.5 => Dockerfile.foobar15

    local build=$(mktemp -d)

    cp ${vpp}/Makefile ${build}/Makefile
    cp ${file} ${build}/Dockerfile

    docker pull ${os}

    docker build \
        --tag ${tag} \
        --build-arg HTTP_PROXY="${HTTP_PROXY}" \
        --build-arg HTTPS_PROXY="${HTTPS_PROXY}" \
        --build-arg NO_PROXY="${NO_PROXY}" \
        --build-arg http_proxy="${http_proxy}" \
        --build-arg https_proxy="${http_proxy}" \
        --build-arg no_proxy="${no_proxy}" \
        --file ${build}/Dockerfile \
        ${build}

    rm -rf ${build}

    # Start the container
    ID=$(docker run \
        --name ${tag} \
        --hostname ${tag} \
        --tty \
        --detach \
        --volume ${vpp}:${vpp}:rw \
        --volume /tmp:/tmp:rw \
        --workdir ${vpp} \
        --env HTTP_PROXY="${HTTP_PROXY}" \
        --env HTTPS_PROXY="${HTTPS_PROXY}" \
        --env NO_PROXY="${NO_PROXY}" \
        --env http_proxy="${http_proxy}" \
        --env https_proxy="${http_proxy}" \
        --env no_proxy="${no_proxy}" \
        ${tag} /bin/cat)
}

kernel_modules() {
    local id=$1

    # Fake linux headers for DPDK module build on old branches
    docker exec --tty ${id} /bin/bash -c \
        'ln -sfnv $(find /lib/modules -type d -name [34]* | head -1) /lib/modules/$(uname -r)'
}

create_user() {
    local id=$1

    # Add user to make sudo/su happy
    # mostly for build-root/vagrant/build.sh
    local usr=$(id -u)
    local usrn=$(id -un)
    local grp=$(id -g)
    local grpn=$(id -gn)

    docker exec --tty ${id} /bin/bash -c \
        "groupadd -g ${grp} -o ${grpn}"

    docker exec --tty ${id}  /bin/bash -c \
        "useradd -u ${usr} -g ${grp} -m -o ${usrn}"

    docker exec --tty ${id} /bin/bash -c \
        "chown ${usr}:${grp} ~${usrn}"

    docker exec --tty ${id} /bin/bash -c \
        "echo ${usrn} ALL=\(ALL:ALL\) NOPASSWD: ALL > /etc/sudoers.d/80-vpp"

}

debug_symbols() {
    local id=$1
    local vpp=$2
    local key=$3

    cmd="apt-get install -y ${vpp}/build-root/*.deb"
    [[ ${key} == centos* ]] && cmd="yum install -y ${vpp}/build-root/*.rpm"

    docker exec --tty ${id} /bin/bash -c "${cmd}"

    docker exec --tty ${id} /bin/bash -c \
        "echo set substitute-path /vpp . >> ~$(id -un)/.gdbinit && " \

    docker exec --tty ${id} /bin/bash -c \
        "echo set substitute-path /home/jenkins/workspace/team_VTF/vtf-vpp/vpp . >> ~$(id -un)/.gdbinit"
}

run() {
    local id=$1
    local flags=$2
    local cmd=$3

    docker exec \
        --tty ${flags} \
        --user $(id -u):$(id -g) \
        ${id} /bin/bash -c "${cmd}"
    
    RET=$?
}

iam="$(readlink -f $(dirname $0))"

[ ! -z ${dir} ] && mkdir -p ${dir} && cd ${dir}

vpp="$(readlink -f $(pwd))"

key=$(echo ${os} | sed 's/\:\|\.//g')

[ -z "${file}" ] && file=${iam}/Dockerfile.${key}
if [ ! -f  ${file} ]; then
    echo ${file} does not exist!
    exit 1
fi

container ${os} ${file} ${vpp} vpp-sandbox-${key}
kernel_modules ${ID}
create_user ${ID}

[ ! -z "${debug}" ] && debug_symbols ${ID} ${vpp} ${key}

[ ! -z "${interactive}" ] && flags="-i"

run ${ID} "${flags}" "$*"

stop

