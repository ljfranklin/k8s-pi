# A "production-ish" Kubernetes cluster on Raspberry Pi

![alt text](https://storage.googleapis.com/ansible-assets/k8s-rpi.jpg "Hardware Pic")

Table of contents:
- What are we building?
- Why though?
- Hardware
- Networking
- Flashing SD cards
- Deploy k8s
- Backup/Restore

## What are we building?

This guide shows how to build a "production-ish" Kubernetes (k8s) cluster on Raspberry Pi hardware.
There are many existing guides and tools available telling you how to deploy a "production-grade" k8s cluster, but
production-grade feels like a stretch when talking about a small stack of $30 single board computers.
So this guide shoots for a production-ish k8s cluster, meaning you can interact with it as you would a production k8s cluster
even if the hardware would have problems handling production workloads.

More specifically we want to support the following features:
- [Dynamic Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#dynamic) to add persistent data to pods
- Externally accessible URLs
- Load balancing of requests across multiple containers
- Automatic backup and restore workflow
- Easy installation of services via [Helm](https://helm.sh/)
- No out-of-band configuration of router or DNS records after initial setup
- Auto-renewing TLS certificates from [Let's Encrypt](https://letsencrypt.org/)
- VPN access to cluster for debugging

Most Kubernetes on Raspberry Pi guides show only a minimal installation.
It works but requires manually adjusting router settings and DNS records each time you add a new service.
You also have to use [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath) volumes for persistent data,
forcing pods to be locked to a specific worker node.
One of the main benefits of Kubernetes is that it abstracts away the underlying infrastructure so you don't need to know whether you're running on
GKE or AWS or bare metal, but these limitations mean we're not realizing that benefit.
This guide removes those limitations so the interacting with Kubernetes on Raspberry Pi _feels like_ interacting with a production cluster.

## Why though?

You might already be asking the following question: isn't this overkill for a Raspberry Pi setup?
My answer: yes, absolutely.
This setup has a ton of moving pieces, and combined with the fast-moving k8s ecosystem and limited hardware capabilities it can be difficult to debug
when something goes wrong.
Simply installing a Debian package directly onto the Raspberry Pi is a simpler and probably more stable setup than installing that app on k8s on underpowered hardware.
The primary goal of this setup is to learn more about Kubernetes and bare metal infrastructure (deployment/networking/storage) with some first-hand experimentation.
Plus this setup is pretty delightful to use once you get it working.

## Hardware

(see image above)

Much of the hardware selection was taken from Scott Hanselman's excellent
[How to Build a Kubernetes Cluster with ARM Raspberry Pi]https://www.hanselman.com/blog/HowToBuildAKubernetesClusterWithARMRaspberryPiThenRunNETCoreOnOpenFaas.aspx) guide.
Check out his guide for some extra rationale for why he chose each part.
TLDR buy tiny hardware that looks cute next to a stack of tiny Raspberry Pis.

Parts:
|Price|Count|Part|
|---|---|---|
|$210|6x|[Raspberry Pi 3 B+](https://www.pishop.us/product/raspberry-pi-3-model-b-plus/?src=raspberrypi)|
|-   |- |We'll use 1 master node and 5 worker nodes but you can adjust the number of worker nodes|
|$72 |6x|[32 GB MicroSD cards](http://amzn.to/2iEPjGg)|
|$18 |12x|[1 foot flat ethernet cables](http://amzn.to/2zUxVRX) (buy two packs, 12 cables total)|
|$32 |1x|[Anker PowerPort 6 Port USB Charging Hub](http://amzn.to/2zV6reM)|
|$40 |1x|[stacking Raspberry Pi case](http://amzn.to/2i9n0M5)|
|$40 |1x|[USB-powered 8 port switch](http://amzn.to/2gNzLzi)|
|$139|1x|(optional) [Unifi Security Gateway (router)](https://www.ubnt.com/unifi-routing/usg/)|
|-   |- |Optional, but parts of the guide assume a router with [BGP](https://en.wikipedia.org/wiki/Border_Gateway_Protocol) support|
|$89 |1x|(optional) [Unifi Wireless AC Lite](https://store.ubnt.com/collections/wireless/products/unifi-ac-lite)|
|$21 |1x|(optional) [Any 8 port switch](https://www.amazon.com/gp/product/B00A121WN6/)|
|---|---|---|
|$661|-|total|

Yikes, that is a large price tag.
Here's a few ways to cut down the cost:
- Buy fewer Raspberry Pis
  - You'll want at least 3 to avoid the cluster running out of memory
- Use ethernet cables, switches, etc you already have laying around
  - Most of the hardware above was picked because it's the same physical size as the Raspberry Pi, but this is only an aesthetic choice
- Skip the case
  - just tape those Pis to a cardboard box, I won't judge
- Use your current router rather than the Unifi networking equipment and 8-port switch
  - Your existing router will work fine for this setup with a couple small limitations
  - I'll note later in the guide when the Unifi Router is required

Even with these cost cutting steps, I realize the price will be a non-starter for many people.
I'd still recommend skimming the guide, hopefully still some interesting learnings even if you don't deploy it yourself.

## Networking

## Initial Setup

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
/tmp/
*.retry
EOF
```

Clone `k8s-pi` repo as a submodule:

```
mkdir submodules
git submodule add https://github.com/ljfranklin/k8s-pi.git ./submodules/k8s-pi
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

Plug a microSD card into your workstation (this example assumes the card has the device ID `/dev/sda`), then run the following command:

```
./submodules/k8s-pi/pi/provision.sh -d /dev/sda -n k8s-node1 -p "$(cat ~/.ssh/id_rsa_k8s.pub)" -i 192.168.1.100
```

> Note: the SD card must be unmounted prior to running the script

Unplug the microSD card and plug in the next one. Run the script again but increment the node number and IP:

```
./submodules/k8s-pi/pi/provision.sh -d /dev/sda -n k8s-node2 -p "$(cat ~/.ssh/id_rsa_k8s.pub)" -i 192.168.1.101
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

Create `ansible.cfg` file in project root:

```
cat << EOF > ansible.cfg
[defaults]
host_key_checking     = False
remote_user           = k8s
roles_path            = submodules/k8s-pi/roles/

[ssh_connection]
pipelining        = True
ssh_args          = -o ControlMaster=auto -o ControlPersist=30m -o ConnectionAttempts=100 -o UserKnownHostsFile=/dev/null
EOF
```

Install ansible + deps:

```
sudo pip install -r submodules/k8s-pi/requirements.txt
```

Create inventory file containing host information:

```
mkdir inventory

cat << EOF > inventory/hosts.ini
[all]
k8s-node1 ansible_host=192.168.1.100
k8s-node2 ansible_host=192.168.1.101
k8s-node3 ansible_host=192.168.1.102
k8s-node4 ansible_host=192.168.1.103
k8s-node5 ansible_host=192.168.1.104
k8s-node6 ansible_host=192.168.1.105

[kube-master]
k8s-node1

[kube-node]
k8s-node2
k8s-node3
k8s-node4
k8s-node5
k8s-node6

[gfs-cluster]
k8s-node6 volume_device=/dev/sda
EOF
```

> Note: this config file assumes 6 Raspberry Pis with sequential static IP addresses starting at 192.168.1.100.
It also assumes that the last node has a USB drive which we'll use for persistent storage of volumes.
Adjust the number of nodes and IP addresses to suit your setup.

Create three playbook files: `bootstrap.yml` (setup k8s from scratch), `upgrade.yml` (upgrade k8s), `deploy.yml` (deploy k8s services only):

```
cat << EOF > bootstrap.yml
- name: Include k8s-pi bootstrap tasks
  import_playbook: submodules/k8s-pi/bootstrap.yml
EOF

cat << EOF > upgrade.yml
- name: Include k8s-pi upgrade tasks
  import_playbook: submodules/k8s-pi/upgrade.yml
EOF

cat << EOF > deploy.yml
- name: Include k8s-pi deploy tasks
  import_playbook: submodules/k8s-pi/deploy.yml
EOF
```

Create a `secrets.yml` file and fill in your credentials for the deployed services:

```
mkdir -p secrets
cp submodules/k8s-pi/secrets/secrets.sample secrets/secrets.yml
```

Run the `bootstrap.yml` playbook to start the installation:

```
ansible-playbook -i inventory/hosts.ini --extra-vars @secrets/secrets.yml bootstrap.yml
```

> Important! Running `bootstrap.yml` playbook a second time will wipe all data from the cluster.

To upgrade k8s without wiping data, run the `upgrade.yml` playbook.

To upgrade just the apps running on k8s, run the `deploy.yml` playbook.

#### Setup Unifi Controller

- Ensure all devices are plugged into LAN1 port of Unifi Gateway
  - We'll switch some devices over to LAN2 in a later step to enable BGP routing
- Temporarily modify `/etc/hosts` on your workstation to route Controller traffic directly to the first worker node:
  - `sudo vim /etc/hosts` to add `$FIRST_WORKER_NODE_IP unifi.$INGRESS_DOMAIN`
  - Note: We'll revert this change once the Unifi controller is setup with BGP routing
- Visit `https://unifi.$INGRESS_DOMAIN`
  - Configure Wifi network name/password and controller/device username/passwords
- Adopt the Unifi Gateway (detailed steps [here](https://help.ubnt.com/hc/en-us/articles/204909754-UniFi-Device-Adoption-Methods-for-Remote-UniFi-Controllers#8)):
  - `ssh ubnt@192.168.1.1` (password `ubnt`)
  - If gateway was previously paired:
    - `sudo syswrapper.sh restore-default`
    - SSH session may get stuck, may need to kill it and re-SSH after reboot
  - `set-inform http://$FIRST_WORKER_IP:8080/inform`
  - Go to Controller UI and click Adopt on Devices tab
  - Wait for device to go from `Adopting` to `Provisioning` to `Connected` on Controller UI
- Add temporary port forwarding rule to bootstrap `port-forwarding-controller`:
  - Settings > Routing & Firewall > Port Forwarding > Create New Port Forwarding Rule
  - Name: tmp-k8s-ingress
  - Port: 443
  - Forward IP: $ingress_nginx_static_ip (from secrets.yml)
  - Forward Port: 443
  - Save
- Restart the `port-forwarding-controller` to ensure it adds port forwarding rules to controller
  - `kubectl delete pod port-forwarding-0`
  - Verify rules were added under Settings > Routing & Firewall > Port Forwarding
  - Delete `tmp-k8s-ingress` rule
- Remove `$WORKER_IP` line from `/etc/hosts`
- Done!

#### Optional: Move non-k8s machines over to LAN2 to enable BGP routing

A limitation of this BGP routing setup is that machines on the 192.168.1.0/24 subnet cannot route to the BGP Load Balancer IP addresses.
This is due to machines on the same subnet wanting to route traffic directly to the target machine rather than sending traffic through the router first.
To force traffic to go through the router we can move all non-k8s machines over to a new LAN2 network.

- Start with all machines plugged into LAN1 port on Unifi Gateway
- Visit `https://unifi.$INGRESS_DOMAIN`
  - Enable LAN2 network:
    - Settings > Networks > Create New Network
    - Name: LAN2
    - Interface: LAN2
    - Gateway/Subnet: 192.168.2.1/24
    - DHCP Range: 192.168.2.6 - 192.168.2.254
    - All other values default
    - Save
- Leave the k8s switch plugged into LAN1 port on Unifi Gateway, but plug a second switch into LAN2
- Connect all other machines (desktop, Wifi AP, etc.) into LAN2 switch
- Verify that you can now route directly to BGP LB addresses:
  - `nc -v -z $ingress_nginx_static_ip 443`
  - Should say `Connection to 192.168.1.51 443 port [tcp/https] succeeded!` or similar

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
