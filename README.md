# A "production-grade" k8s on Raspberry Pi

![alt text](https://storage.googleapis.com/ansible-assets/k8s-rpi.jpg "Hardware Pic")

Table of contents:
- What are we building?
- Why though?
- Hardware
- Networking
- Flashing SD cards
- Deploy k8s
- Backup/Restore

## Hardware

TODO

## Getting Started

#### Create project

Create a new repository:

```
mkdir k8s-pi
cd k8s-pi
git init
```

Create `.gitignore`:

```
cat << EOF > .gitignore
/secrets/
/pi/tmp/
/tmp/
*.retry
EOF
```

#### Flash HypriotOS onto SD cards

> Why HypriotOS?
This Debian-based distribution is optimized for running Docker workloads such as a k8s cluster and
comes with many container utilities pre-installed.
It also includes a tool called `cloud-init` which allows us to specify options like SSH keys and
static IPs in a config file on the SD card rather than running setup commands over SSH after boot.

Create an SSH key to access the Raspberry Pi's:

```
ssh-keygen -t rsa -b 4096 -C k8s -N '' -f ~/.ssh/id_rsa_k8s
ssh-add ~/.ssh/id_rsa_k8s
```

Download some helper scripts from [this directory](https://github.com/ljfranklin/k8s-pi/tree/master/pi):

```
wget -O /tmp/pi.zip https://github.com/ljfranklin/k8s-pi/archive/master.zip
unzip -d /tmp /tmp/pi.zip
cp -r /tmp/k8s-pi-master/pi .
```

Plug a microSD card into your workstation (this example assumes the card has the device ID `/dev/sda`), then run the following command:

```
./pi/provision.sh -d /dev/sda -n k8s-node1 -p "$(cat ~/.ssh/id_rsa_k8s.pub)" -i 192.168.1.100
```

> Note: the SD card must be unmounted prior to running the script

Unplug the microSD card and plug in the next one. Run the script again but increment the node number and IP:

```
./pi/provision.sh -d /dev/sda -n k8s-node2 -p "$(cat ~/.ssh/id_rsa_k8s.pub)" -i 192.168.1.101
```

Repeat the process until all cards have been flashed.

#### Boot Raspberry Pi's

Plug all the cards into the Raspberry Pi's and attach the USB power cable to start them up.
The Raspberry Pi's will install necessary packages on boot and will automatically reboot once to finish a kernel update.

Shortly after this reboot you should be able to SSH onto each node:

```
ssh k8s@192.168.1.100
```

We'll also plug in a USB drive on the last node to store our Persistent Volumes.
Ensure the drive is plugged in but unmounted and run the following command to remove any existing filesystems:

```
ssh k8s@192.168.1.105
sudo wipefs -a /dev/sda # assumes USB drive has device ID /dev/sda
```

> Note: you can add USB drives to multiple nodes if you wish for extra redundancy.
Remember to add these hosts under the `[gfs-cluster]` section in `hosts.ini` as shown below.

#### Installing k8s

Clone `kubespray` repo as submodule:

```
mkdir submodules
git submodule add https://github.com/kubernetes-sigs/kubespray.git ./submodules/kubespray
```

Create `ansible.cfg` file in project root:

```
cat << EOF > ansible.cfg
[defaults]
host_key_checking     = False
remote_user           = k8s
library               = submodules/kubespray/library/
roles_path            = submodules/kubespray/roles/
display_skipped_hosts = False
deprecation_warnings  = False

[ssh_connection]
pipelining        = True
ssh_args          = -o ControlMaster=auto -o ControlPersist=30m -o ConnectionAttempts=100 -o UserKnownHostsFile=/dev/null
EOF
```

Install ansible + deps:

```
sudo pip install -r submodules/kubespray/requirements.txt
```

Create inventory file containing host information:

```
mkdir inventory

cat << EOF > inventory/hosts.ini
[all]
node1 ansible_host=192.168.1.100 etcd_member_name=etcd1
node2 ansible_host=192.168.1.101
node3 ansible_host=192.168.1.102
node4 ansible_host=192.168.1.103
node5 ansible_host=192.168.1.104
node6 ansible_host=192.168.1.105 disk_volume_device_1=/dev/sda

[kube-master]
node1

[etcd]
node1

[kube-node]
node2
node3
node4
node5
node6

[k8s-cluster:children]
kube-master
kube-node

[gfs-cluster]
node6
EOF
```

> Note: this config file assumes 6 Raspberry Pis with sequential static IP addresses starting at 192.168.1.100.
It also assumes that the last node has a USB drive which we'll use for persistent storage of volumes.
Adjust the number of nodes and IP addresses to suit your setup.

Copy `group_vars` directory into your project:

```
cp -r submodules/kubespray/inventory/sample/group_vars inventory/
```

Change the values under `inventory/group_vars/` to suite your needs. The following is a good starting place:

```
# edit inventory/group_vars/k8s-cluster/k8s-cluster.yml
kube_network_plugin: weave         # CNI plugin with ARM support
kube_apiserver_ip: 192.168.1.100   # IP of kube-master node
kubeconfig_localhost: true         # downloads kubectl config to inventory/artifacts
ignore_assert_errors: true         # ignore assert errors about not enough memory on Pi
etcd_image_repo: "k8s.gcr.io/etcd" # use arm enabled image
etcd_image_tag: "{{ etcd_version | replace('v', '') }}"
image_arch: arm
cni_binary_checksum: ffb62021d2fc6e1266dc6ef7f2058125b6e6b44c016291a2b04a15ed9b4be70a
kubeadm_binary_checksum: 9d33673798507959b888f1f82b418e0239c2e9588492b3d7ffee979dbd136c4a
hyperkube_download_url: "https://storage.googleapis.com/kubernetes-release/release/{{ kube_version }}/bin/linux/arm/hyperkube"
hyperkube_binary_checksum: 8e6ee8d10d8d13b453315811ed1ab60b0092f9168c933712fd176085cf080bb0

# edit inventory/group_vars/k8s-cluster/addons.yml
dashboard_enabled: false         # we'll install this later on
## TEMPORARY
# avoid panic on hyperkube v1.13 binary
# https://github.com/kubernetes/kubernetes/issues/72447
kube_version: v1.12.4
# kube_version: v1.13.1
```

Create a `cluster.yml` playbook in the project root:

```
cat << EOF > cluster.yml
- name: Include kubespray tasks
  import_playbook: submodules/kubespray/cluster.yml

- name: Include glusterfs tasks
  import_playbook: submodules/kubespray/contrib/network-storage/glusterfs/glusterfs.yml
EOF
```

Run the playbook to start the installation:

```
ansible-playbook -i inventory/hosts.ini --become --become-user=root cluster.yml
```

## Bootstrap cluster

TODO

- Set Ingress controller to use NodePort + ExternalIP initially
  - ExternalIP can be set to IP of any worker node
- `sudo vim /etc/hosts` to add `$WORKER_IP unifi.$YOUR_DOMAIN`
- Deploy controller
- Visit https://unifi.$YOUR_DOMAIN to ensure controller loads
- `ssh ubnt@192.168.1.1` (password `ubnt`)
- If gateway was previously paired: `sudo syswrapper.sh restore-default`, then SSH again
- `set-inform http://$WORKER_IP:8080/inform`
- Go to Controller UI and click Adopt on Devices tab
- Wait for Adopting state
- On gateway enter `set-inform` to save inform URL
- Wait for device to say Connected on Controller UI
- Under Controller Setting, create LAN2 network with `192.168.2.1/24` CIDR
  - This is necessary for BGP
- Enter forwarding rules on controller for new BGP IP
- Switch ingress config from NodePort to LoadBalancer
- Redeploy
- Remove `$WORKER_IP` line from `/etc/hosts`
- Done!

## MetalLB

Create second network on Unifi Router:
- Purpose: Corporate
- Network Group: LAN2
- Gateway/Subnet: 192.168.2.1/24
- Click Update DHCP Range
- Click Save
- Plug k8s switch into LAN2 port on Router
- Assign static IPs in 192.168.2.1/24 network for each Pi
- SSH onto Unifi Gateway using `ssh <user>@192.168.1.1`
  - User and password are the Device Authentication creds you entered when
    configuring the Controller
- Running the following commands while on the Gateway (enter IPs of workers):
  ```
  configure
  set protocols bgp 64512 parameters router-id 192.168.1.1
  set protocols bgp 64512 neighbor 192.168.1.101 remote-as 64512
  set protocols bgp 64512 neighbor 192.168.1.102 remote-as 64512
  set protocols bgp 64512 neighbor 192.168.1.103 remote-as 64512
  set protocols bgp 64512 neighbor 192.168.1.104 remote-as 64512
  set protocols bgp 64512 neighbor 192.168.1.105 remote-as 64512
  commit
  save
  exit
  ```

## Backup/Restore

TODO

After shutting down and restoring, ark was unable to take new backups.
This was due to `ark restic repo get` returning `NotReady`.
Turns out the Restic repository was still marked as "locked", possibly
due to not shutting down the cluster gracefully.
Running the following commands unlocks the repo:

```
kubectl -n heptio-ark exec -it ark-restic-POD_ID /bin/sh
restic unlock -r gs:<VOLUME_BACKUP_BUCKET>:default
# enter 'static-passw0rd' as the repo password
```

This assumes you're using Google Cloud Storage as your backup provides,
switch 'gs' to 's3' or similar depending on your provider.
The 'static-passw0rd' key is [hardcoded](https://github.com/heptio/ark/blob/9f72cf9c614bb4dc02dfacae08c9dcd11fbb5eaa/pkg/restic/repository_keys.go#L33)
in ark currently but this may change in future releases.
