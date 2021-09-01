#!/bin/bash
set -ex

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
BASEDIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# Whether to build an 'iso' or 'qcow'
build_type="${1:-qcow}"
# The host mount to use to exchange data with this container
host_mount_directory="${2:-$BASEDIR/../manifests}"
# Docker image to use when launching this container
image="${3:-port/image-builder:latest-ubuntu_focal}"
# boot timeout for image validation
boot_timeout="${4:-300}"
# proxy to use, if applicable
proxy="$5"
# noproxy to use, if applicable
noproxy="$6"

workdir="$(realpath ${host_mount_directory})"

# Overrides
: ${user_data:=$workdir/user_data}
: ${network_config:=$workdir/network_data.json}

if [ -n "$proxy" ]; then
  export http_proxy=$proxy
  export https_proxy=$proxy
  export HTTP_PROXY=$proxy
  export HTTPS_PROXY=$proxy
fi

if [ -n "$noproxy" ]; then
  export no_proxy=$noproxy
  export NO_PROXY=$noproxy
fi

# Install pre-requisites
install_pkg(){
  dpkg -l $1 2> /dev/null | grep ^ii > /dev/null || sudo -E apt-get -y install $1
}

if [ ! -f /var/lib/apt/periodic/update-success-stamp ] || \
     sudo find /var/lib/apt/periodic/update-success-stamp -mtime +1 | grep update-success-stamp; then
     sudo -E apt -y update
fi

install_pkg qemu-kvm
install_pkg virtinst
install_pkg libvirt-daemon-system
install_pkg libvirt-clients
install_pkg cloud-image-utils
install_pkg ovmf
install_pkg util-linux
type docker >& /dev/null || (echo "Error: You do not have docker installed in your environment." && exit 1)
sudo docker version | grep Community >& /dev/null || (echo "Error: Could not find Community version of docker" && \
	echo "You must uninstall docker.io and install docker-ce. For instructions, see https://docs.docker.com/engine/install/ubuntu/" && \
	exit 1)

if [ -d /sys/firmware/efi ]; then
  uefi_mount='--volume /sys/firmware/efi:/sys/firmware/efi:rw'
  uefi_boot_arg='--boot uefi'
fi

if [[ $build_type = iso ]]; then
  : ${img_name:=ephemeral.iso}
  if sudo virsh list | grep ${img_name}; then
    sudo virsh destroy ${img_name}
  fi
  iso_config=/tmp/${img_name}_config
  echo "user_data:
$(cat $user_data | sed 's/^/    /g')
network_config:
$(cat $network_config | sed 's/^/    /g')
outputFileName: $img_name" > ${iso_config}
  sudo -E docker run -i --rm \
   --volume $workdir:/config \
   --env IMAGE_TYPE="iso" \
   --env VERSION="v2" \
   --env http_proxy=$proxy \
   --env https_proxy=$proxy \
   --env HTTP_PROXY=$proxy \
   --env HTTPS_PROXY=$proxy \
   --env no_proxy=$noproxy \
   --env NO_PROXY=$noproxy \
   ${image} < ${iso_config}
  disk1="--disk path=${workdir}/${img_name},device=cdrom"
  network='--network network=default,mac=52:54:00:6c:99:85'
elif [[ $build_type == qcow ]]; then
  : ${img_name:=airship-ubuntu.qcow}
  if sudo virsh list | grep ${img_name}; then
    sudo virsh destroy ${img_name}
  fi
  sudo -E modprobe nbd
  qcow_config=/tmp/${img_name}_config
  echo "osconfig:
$(cat $osconfig_params | sed 's/^/    /g')
qcow:
$(cat $qcow_params | sed 's/^/    /g')
outputFileName: $img_name" > ${qcow_config}
  echo "Note: This step can be slow if you don't have an SSD."
  sudo -E docker run -i --rm \
   --privileged \
   --volume /dev:/dev:rw  \
   --volume /dev/pts:/dev/pts:rw \
   --volume /proc:/proc:rw \
   --volume /sys:/sys:rw \
   --volume /lib/modules:/lib/modules:rw \
   --volume /run/systemd/resolve:/run/systemd/resolve:rw \
   --volume $workdir:/config \
   ${uefi_mount} \
   --env BUILDER_CONFIG=/config/${build_type}.yaml \
   --env IMAGE_TYPE="qcow" \
   --env VERSION="v2" \
   --env http_proxy=$proxy \
   --env https_proxy=$proxy \
   --env HTTP_PROXY=$proxy \
   --env HTTPS_PROXY=$proxy \
   --env no_proxy=$noproxy \
   --env NO_PROXY=$noproxy \
   ${image} < ${qcow_config}
  cloud_init_config_dir='assets/tests/qcow/cloud-init'
  sudo -E cloud-localds -v --network-config="${cloud_init_config_dir}/network-config" "${workdir}/${img_name}_config.iso" "${cloud_init_config_dir}/user-data" "${cloud_init_config_dir}/meta-data"
  disk1="--disk path=${workdir}/${img_name}"
  disk2="--disk path=${workdir}/${img_name}_config.iso,device=cdrom"
  network='--network network=default'
else
  echo Unknown build type: $build_type, exiting.
  exit 1
fi

logfile=/var/log/${img_name}.log
imagePath=$(echo $disk1 | cut -d'=' -f2 | cut -d',' -f1)
echo Image successfully written to $imagePath

sudo -E virsh destroy ${img_name} 2> /dev/null || true
sudo -E virsh undefine ${img_name} --nvram 2> /dev/null || true

cpu_type=''
virt_type=qemu
if kvm-ok >& /dev/null; then
  cpu_type='--cpu host-passthrough'
  virt_type=kvm
fi

if ! sudo -E virsh net-list | grep default | grep active > /dev/null; then
  network='--network none'
fi

# Default to 4 vcpus
num_vcpus=4
# Reduce the vcpu count in the event physical cpu count is less
num_pcpus=$(($(lscpu -e | wc -l) - 1))
if [[ ${num_pcpus} -lt ${num_vcpus} ]]; then
  echo Reducing num_vcpus to ${num_pcpus}
  num_vcpus=${num_pcpus}
fi
# Exit if the number of vcpus is less than 1, i.e. there is a problem
if [[ ${num_vcpus} -lt 1 ]]; then
  echo ERROR: num_vcpus of ${num_vcpus} is less than 1
  exit 1
fi

serial=''
perform_boot_test="false"
# User may set boot_timeout to 0 to skip boot test and allow for manual "virsh console" debugging
if [ $boot_timeout -gt 0 ]; then
  serial="--serial file,path=${logfile}"
  perform_boot_test="true"
fi

xml=$(mktemp)
sudo -E virt-install --connect qemu:///system \
 --name ${img_name} \
 --memory 1536 \
 ${network} \
 ${cpu_type} \
 --vcpus ${num_vcpus} \
 --import \
 ${serial} \
 ${disk1} \
 ${disk2} \
 --virt-type ${virt_type} \
 ${uefi_boot_arg} \
 --noautoconsole \
 --graphics vnc,listen=0.0.0.0 \
 --print-xml > $xml
virsh define $xml

echo Virsh definition accepted
echo Image artifact located at $imagePath

if [[ $perform_boot_test = "true" ]]; then
  echo Starting ${img_name} ...
  virsh start ${img_name}
  successful_boot=false
  time_waited=0
  while [ $time_waited -lt $boot_timeout ]; do
    if sudo cat ${logfile} | grep "login:" >& /dev/null; then
      echo ${img_name} boot test SUCCESS after $time_waited seconds.
      successful_boot=true
      break
    fi
    sleep 5
    time_waited=$(($time_waited + 5))
  done
  echo Stopping ${img_name} ...
  virsh destroy ${img_name}
  if [ $successful_boot != "true" ]; then
    echo ${img_name} boot test FAIL after $boot_timeout second timeout.
    exit 1
  fi
fi
