#!/bin/bash

# adapted from https://lobradov.github.io/Building-docker-multiarch-images/#same-dockerfile-template

set -eu

: "${IMAGE:?}"
: "${TAG:=latest}"

docker_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

replace() {
  if [ "$(uname -s)" == "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

pushd "${docker_dir}" > /dev/null
  for docker_arch in amd64 arm32v6 arm64v8; do
    case "${docker_arch}" in
      amd64)
        qemu_arch="x86_64"
        ;;
      arm32v6)
        qemu_arch="arm"
        ;;
      arm64v8)
        qemu_arch="aarch64"
        ;;
    esac

    wget -N "https://github.com/multiarch/qemu-user-static/releases/download/v3.0.0/x86_64_qemu-${qemu_arch}-static.tar.gz"
    tar -xvf "x86_64_qemu-${qemu_arch}-static.tar.gz"
    rm "x86_64_qemu-${qemu_arch}-static.tar.gz"

    cp Dockerfile.cross "Dockerfile.${docker_arch}"
    replace "s|__BASEIMAGE_ARCH__|${docker_arch}|g" "Dockerfile.${docker_arch}"
    replace "s|__QEMU_ARCH__|${qemu_arch}|g" "Dockerfile.${docker_arch}"
    if [ "${docker_arch}" == 'amd64' ]; then
      replace "/__CROSS_/d" "Dockerfile.${docker_arch}"
    else
      replace "s/__CROSS_//g" "Dockerfile.${docker_arch}"
    fi

    docker build \
      -f "Dockerfile.${docker_arch}" \
      -t "${IMAGE}:${docker_arch}-${TAG}" \
      .

    rm "Dockerfile.${docker_arch}"
    rm "qemu-${qemu_arch}-static"
  done
popd > /dev/null

echo ""
echo "Successfully build multi-arch images!"
echo 'Run `make docker-push` to push images to DockerHub'
