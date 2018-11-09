#!/bin/bash

set -eu -o pipefail

sd_device_path=""
static_ip=""
pi_hostname=""
ssh_pub_key=""
os_version="1.9.0"

usage() {
  cat <<EOF
Writes HypriotOS image to SD card for Raspberry Pi

Usage:
  $0 <options>

Options:
  -d <path>       (required) The device path of the target SD card, e.g. /dev/sda
                             Note: Unmount this device before running this script
  -i <static_ip>  (optional) Static IP to assign to machine, e.g. 192.168.1.240
                             Note: Give master node a static IP, others can have dynamic
  -n <hostname>   (required) The hostname for the Pi, e.g. k8s-master
                             The device should be reachable via k8s-master.local
  -p <pub_key>    (required) The SSH public key contents to add to Pi's authorized keys
  -o <os_version> (optional) The HypriotOS version to install, defaults to '${os_version}'
  -h                         Show this help text
EOF
  exit 1
}

while getopts "d:i:n:p:o:h" opt; do
  case "${opt}" in
    d)
      sd_device_path="$OPTARG"
      ;;
    i)
      static_ip="$OPTARG"
      ;;
    n)
      pi_hostname="$OPTARG"
      ;;
    p)
      ssh_pub_key="$OPTARG"
      ;;
    o)
      os_version="$OPTARG"
      ;;
    h)
      usage
      ;;
    *)
      echo "Unknown argument: ${opt}!"
      usage
      ;;
  esac
done

if [ -z "${sd_device_path}" ] || [ -z "${pi_hostname}" ] || [ -z "${ssh_pub_key}" ]; then
  echo "Missing required arg!"
  usage
fi

script_dir="$( cd "$( dirname "$0" )" && pwd )"
pushd "${script_dir}" > /dev/null
  mkdir -p ./tmp
  pushd ./tmp > /dev/null
    if [ ! -f "./hypriotos-rpi-v${os_version}.img" ]; then
      echo "Downloading HypriotOS ${os_version}..."

      curl -sSL "https://github.com/hypriot/image-builder-rpi/releases/download/v${os_version}/hypriotos-rpi-v${os_version}.img.zip" \
        -o "hypriotos-rpi-v${os_version}.img.zip"
      curl -sSL "https://github.com/hypriot/image-builder-rpi/releases/download/v${os_version}/hypriotos-rpi-v${os_version}.img.zip.sha256" \
        -o "hypriotos-rpi-v${os_version}.img.zip.sha256"
      shasum -c "hypriotos-rpi-v${os_version}.img.zip.sha256"

      unzip "hypriotos-rpi-v${os_version}.img.zip"
      rm "hypriotos-rpi-v${os_version}.img.zip"
    fi
  popd > /dev/null

  echo "Flashing HypriotOS ${os_version} to SD card ${sd_device_path}..."
  if mount | grep -q "${sd_device_path}"; then
    echo "Error: unmount ${sd_device_path} before running this script!"
    exit 1
  fi

  sudo dd if="./tmp/hypriotos-rpi-v${os_version}.img" of="${sd_device_path}" bs=1M

  sleep 5 # give drive time to mount
  os_mount="$(mount | grep "${sd_device_path}.*HypriotOS" | awk '{print $3}')"
  root_mount="$(mount | grep "${sd_device_path}.*root" | awk '{print $3}')"

  echo "Writing user-data to ${os_mount}/user-data..."
  trimmed_pub_key="$(xargs echo <<< "${ssh_pub_key}")"
  config_contents="$(cat ./hypriot/user-data.yml)"
  config_contents="$(sed -e "s#REPLACE_WITH_HOSTNAME#${pi_hostname}#g" <<< "${config_contents}")"
  config_contents="$(sed -e "s#REPLACE_WITH_PUB_KEY#${trimmed_pub_key}#g" <<< "${config_contents}")"
  if [ -n "${static_ip}" ]; then
    subnet_prefix="$(cut -d '.' -f1-3 <<< "${static_ip}")" # assumes /24 subnet
    static_ip_config="$(cat ./hypriot/static-ip-partial.yml)"
    static_ip_config="$(sed -e "s#REPLACE_WITH_STATIC_IP#${static_ip}#g" <<< "${static_ip_config}")"
    static_ip_config="$(sed -e "s#REPLACE_WITH_SUBNET_PREFIX#${subnet_prefix}#g" <<< "${static_ip_config}")"
    config_contents="${config_contents}\n${static_ip_config}"
  fi
  echo -e "${config_contents}" > "${os_mount}/user-data"

  umount "${os_mount}"
  umount "${root_mount}"

  echo "Success!"
popd > /dev/null
