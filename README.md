# A "production-ish" Kubernetes cluster on Raspberry Pi

![alt text](https://storage.googleapis.com/ansible-assets/k8s-rpi.jpg "Hardware Pic")

TODO: update

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
|$10 |1x|[SD card reader](https://www.amazon.com/UGREEN-Reader-Memory-Windows-Simultaneously/dp/B01EFPX9XA)|
|$14 |1x|[32GB USB](https://www.amazon.com/gp/product/B00LFVITLK/)|
|$139|1x|(optional) [Unifi Security Gateway (router)](https://www.ubnt.com/unifi-routing/usg/)|
|-   |- |Optional, but parts of the guide assume a router with [BGP](https://en.wikipedia.org/wiki/Border_Gateway_Protocol) support|
|$89 |1x|(optional) [Unifi Wireless AC Lite](https://store.ubnt.com/collections/wireless/products/unifi-ac-lite)|
|$21 |1x|(optional) [Any 8 port switch](https://www.amazon.com/gp/product/B00A121WN6/)|
|---|---|---|
|$685|-|total|

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

#### Draw it out

Here's a networking diagram of what we'll be building:

![alt text](https://storage.googleapis.com/ansible-assets/k8s-rpi-networking.png "Network Diagram")

We have split the machines into two subnetworks, LAN1 and LAN2.
The k8s cluster will live in LAN1 and all other machines (desktop, laptop, phone, etc) will live on LAN2.
The Router acts a bridge, allowing machines in LAN1 to talk to machines in LAN2 and vice versa.

Let's zoom into LAN1 to examine networking within the k8s cluster:

![alt text](https://storage.googleapis.com/ansible-assets/k8s-rpi-forwarding.png "Network Forwarding Diagram")

Note: Switch present but not pictured, only 3 workers pictured

#### Example: deploy a VPN Service

For this example, let's say we wanted to deploy a VPN server into the k8s cluster.
We'll cover the specific installation steps down in the Initial Setup section, this section will introduce the concepts.
When you deploy an app to k8s, it runs as one or more [pods](https://kubernetes.io/docs/concepts/workloads/pods/pod/) within the cluster.
A pod is a group of one or more containers that should be grouped together on the same worker node.
Each pod has a replica count which tells k8s how many copies to create of each pod.
Since we specified three replicas in this example, k8s creates a VPN pod on each of the three workers.

After the deploy completes, we have three VPN server processes running but we need some way to route traffic to them.
First we'll create a k8s [service](https://kubernetes.io/docs/concepts/services-networking/service/) to define how we will access the pods.
There are several types of services support by k8s, we'll cover a few in this guide:
- [ClusterIP](https://kubernetes.io/docs/concepts/services-networking/service/#choosing-your-own-ip-address)
  - (default) Service is given a cluster-internal IP address and is accessible only to other apps within the cluster
- [NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#nodeport)
  - Service listens on a static port on the host machine, usually a high port like 30000
- [LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)
  - Service is exposed via some infrastructure load balancer service. Often this is a cloud-provider specific service like AWS ELBs
- [External IPs](https://kubernetes.io/docs/concepts/services-networking/service/#external-ips)
  - Used in conjunction with any of the previous service types
  - Specifying an `externalIP` for a service will cause all worker nodes to start listening on that service's `port`.
    If a worker receives traffic on that port and the destination IP of that packet matches the `externalIP` of a service,
    the worker will route that packet to the service's pod via the kube-proxy process.
  - Allows you to bind on low ports like 80 and 443 but requires a k8s user with elevated privileges

General rule of thumb when choosing Service type:
- Choose ClusterIP if the service will only be accessed from within the cluster
- Choose NodePort if the service should be externally accessible but you don't have Load Balancer infrastructure in place and you don't need a privileged port like 80 or 443
- Choose ClusterIP with ExternalIP if the service should be externally accessible but you don't have Load Balancer infrastructure in place and want a privileged port 
- Choose LoadBalancer if you want traffic balanced across all worker nodes containing pods for that service

#### Load Balancing with MetalLB

On a minimal k8s install we'd have to use either NodePort or ClusterIP+ExternalIP to expose a service externally.
This has the drawback that a single worker node would receive all traffic for a given service.
If that worker goes down your service is inaccessible until that worker comes back up.
To overcome this limitation we'll deploy [MetalLB](https://metallb.universe.tf/) to handle creation of LoadBalancer services.
MetalLB is a k8s load balancer implementation for bare metal setups like our Raspberry Pis.
MetalLB has two operating modes: [Layer 2 mode](https://metallb.universe.tf/concepts/layer2/) and [BGP mode](https://metallb.universe.tf/concepts/bgp/)

##### BGP Mode (recommended)

> Note: this section requires a Unifi Router or other router which supports BGP routing

BGP stands for [Border Gateway Protocol](https://en.wikipedia.org/wiki/Border_Gateway_Protocol).
BGP allows two machines to exchange routing information, something like "IP 1.2.3.4 is one hop away from IP 5.6.7.8".
This protocol is used on a global scale by Internet Service Providers (ISPs) to figure out how to route traffic between ISPs.
But we're going to use the same protocol on a tiny scale to load balance traffic between our router and k8s worker nodes.
We'll start by deploying MetalLB into our k8s cluster, configuring it with BGP options so that it can report route to our Unifi router.
MetalLB will watch for new services of type `LoadBalancer`, assign an IP to that service, and start publishing routes for that IP.
For example, let's say we had three workers (IPs 192.168.1.101, 192.168.1.102, and 192.168.1.103) and one VPN pod on the first worker.
We then create a Load Balancer service, causing MetalLB to assign that service an IP address of 192.168.1.200.
MetalLB will then tell the router that shortest route to 192.168.1.200 is via 192.168.1.101 (the first worker's IP).
If the router receives a request for 192.168.1.200, it will route that traffic to the first worker node and that worker will
send the traffic to its VPN pod.
If we then scale up to three VPN pods (one on each worker), MetalLB will tell the router that
that shortest route to 192.168.1.200 is via either 192.168.1.101, 192.168.1.102, or 192.168.1.103.
Since all routes have the same cost, the router will load balance requests across all three workers.
We have load balancing in our home network!

However, there in one gotcha to this setup:
machines within the same subnet will not be able to resolve the Load Balancer IP addresses.
This is because machines within the same subnet can route packets directly to each other without going through the router,
the router is only needed to route packets between different subnets.
Since the BGP route table is only present on the router, if the k8s cluster in on LAN1 and your laptop in on LAN1 you won't
be able to route traffic to that Load Balancer IP.
To overcome this, we broke our network into two subnets: LAN1 and LAN2.
The k8s cluster lives in LAN1 and everything else lives in LAN2.
This ensures that any requests from machines in LAN2 must go through the router which ensures the BGP routes are used.
The k8s machines can also route traffic to the Load Balancer IPs as each node has a MetalLB process on it which
adds `iptables` rules for each service to the host machine.
You can also side-step this limitation by always sending requests to your modem's public IP address and adding a port
forwarding rule to your router. We'll cover this setup shortly.

##### Layer 2 Mode (use if your router doesn't have BGP support)

Layer 2 refers to the [Data Link layer](https://en.wikipedia.org/wiki/Data_link_layer) of the
[Open Systems Interconnection (OSI) model](https://en.wikipedia.org/wiki/OSI_model) of describing
computer networks.
This layer is concerned with how machines within a single subnet communicate with each other.
The advantage of deploying MetalLB in Layer 2 mode rather than BGP mode is that Layer 2 mode doesn't require
any special networking hardware.
Let's replay our previous example with three worker nodes and one VPN pod on the first worker
MetalLB again assigns the service the IP 192.168.1.200.
In Layer 2 mode, MetalLB will use the [Address Resolution Protocol (ARP)](https://en.wikipedia.org/wiki/Address_Resolution_Protocol)
to advertise to other machines in that subnet that the first worker node also has the IP address 192.168.1.200 in addition to
its original IP of 192.168.1.101.
Any machine within that subnet can then route traffic to 192.168.1.200.
If we scale up to three VPN pods (one on each worker), MetalLB still only advertises the first worker's IP.
But when that worker receives traffic with a destination IP of 192.168.1.200,
it will load balance traffic across all pods in the cluster (even those on other workers) via the kube-proxy process.
So it isn't true load balancing as a single worker node has to initially receive all the traffic for
a given service, but traffic is balanced across all pods from there.
MetalLB will also automatically failover if that worker node goes down, giving a different worker that
service's IP.
Unlike BGP mode, this setup requires all machines live on the same subnet.

> Note: the ansible steps listed below currently only support BGP mode for MetalLB,
but you can change that role to match the layer 2 configuration shown
[here](https://metallb.universe.tf/configuration/#layer-2-configuration).
Send me a PR to make it configurable if you do!

#### Accessing services from outside the network

After deploying MetalLB, we now have an IP address for our service which load balances traffic.
However this address is only resolvable from within our home network.
For some services we'd like to access them from the office or when traveling.
For example, pointing my VPN client to `vpn.cats-are-cool.com:1194` should route the traffic
to my home modem's public IP address, which passes the traffic to my router, which has a port
forwarding rule to directly traffic on port `1194` to the MetalLB address `192.168.1.200`,
which finally routes traffic into one of the VPN pods.
Let's dive into the steps to make this happen automatically.

##### Managing DNS records

For this setup, we'd like a single wildcard DNS record which resolves to our modem's public IP.
This guide uses [CloudFlare](https://www.cloudflare.com/) as the DNS provider, but other
providers should follow similar steps.
We'd start by looking up our modem's public IP (hint: google "what's my ip").
Then we'll go our DNS provider and create an [A record](https://support.dnsimple.com/articles/a-record/)
for `*.cats-are-cool.com` pointing to our public IP and a Time-to-Live (TTL) of 2 minutes (shortest value you can).
This means that requests for any subdomain of `cats-are-cool.com` (like `vpn.cats-are-cool.com`) will be routed
to your modem/router.
However, normally residential networks have ephemeral public IP addresses, meaning it can change
at any time.
Any we'd like to avoid manual creation of DNS records anyway.

To handle the creating and updating of this wildcard record, the setup steps below include a
`dns-updater` [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
which creates the wildcard record if it doesn't exist and updates the IP address if your public
IP has changed.
This job runs every 5 minutes as a pod within the k8s cluster.

> Note: the ansible steps listed below currently only support Cloudflare as a DNS provider, but can be tweaked to support
other providers

##### Managing port forwarding rules

Next we'll need to add port forwarding rules to our router.
Forwarding rules are a mapping of port to IP address.
When the router receives a request on a given port, it will check its list of port forwarding rules
to see if it has a rule for that port.
If it does it will forward the traffic to the IP address listed in that rule.
For the VPN example, we need to add a port forwarding for port `1194` and IP `192.168.1.200` (the MetalLB service IP).
Normally you do this via your router's UI page, accessible at `http://192.168.1.1` usually.

However, if you've got a Unifi router we can manage these port forwarding rules automatically.
I created a custom k8s controller called the [port-forwarding-controller](https://github.com/ljfranklin/port-forwarding-controller).
You deploy this controller into your cluster with credentials to talk to your Unifi router and
it watches for new services similar to MetalLB.
When the controller sees a new or updated service, it checks whether the Unifi controller has a forwarding rule
matching that service's IP and port.
If no rule exists, the controller will create it automatically.
With this last bit in place, requests to `vpn.cats-are-cool.com` should be forwarded successfully into the VPN pods.

> Again, the port-forwarding-controller currently only supports the Unifi API. PRs accepted!

##### Handling HTTPS traffic

In our VPN example, our service used the port `1194` and any traffic
to that port went to the VPN pods.
This worked well, but what if you wanted several different services to receive HTTPS traffic?
You could have each one listen on a different port, but it'd be nice if they could all use the standard 443 port.
To give a specific example, we'd like requests to `https://homepage.cats-are-cool.com`
to go to a homepage app while requests to `https://passwords.cats-are-cool.com` to go to a password manager.

To accomplish this, k8s provides an [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) resource
to create a mapping between requests and services.
For example, you can create an Ingress resource that says any request containing the hostname `homepage.cats-are-cool.com`
should be routed to the `homepage` Service.
However, creating an Ingress resource doesn't do anything on its own, you need an ingress controller.
We'll deploy the [ingress-nginx-controller](https://kubernetes.github.io/ingress-nginx/) to manage these objects for us.
This controller watches for new and updated Ingress resources to build up a mapping of request options to target services.
When the controller itself receives a request, it checks this mapping to see where to forward the traffic.
This means the ingress controller is deployed between MetalLB and a target service like the homepage app.
We'll need to create a Load Balancer service in front of the ingress controller so that a Load Balancer IP and port forwarding
rules are created.

Let's walk through an example HTTPS request end-to-end by visiting `https://homepage.cats-are-cool.com` from outside the network.
As with the VPN example, this request reaches our modem's public IP which passes the traffic to the router.
The router has a port forwarding rule to forward traffic on port `443` to the MetalLB address `192.168.1.201`.
That address was assigned to the ingress-controller so MetalLB forwards the request to the ingress-controller pod.
The ingress-controller sees that the target hostname of the request matches an Ingress resource
whose target service is the `homepage` service.
This match causes the controller to forward the traffic to one of the `homepage` pods.
If no matching Ingress resource was found, the nginx-ingress-controller would use its default backend to return a 404.

##### Generating TLS certificates

Handling HTTPS traffic comes with another complication: generating TLS certificates.
Certificates are used by HTTPS clients like web browsers to verify the identity of the requested website.
Certificates are issued by Certificate Authorities (CAs) which are trusted by your browser.
By default, most k8s HTTPS services will deploy with self-signed TLS certificates which are not trusted.
Visiting a site with a self-signed certificate in your browser will show a scary "Connection is not secure" warning
as your browser can't verify that site's identity.

To automatically generate trusted certificates, we'll use a component called [cert-manager](https://github.com/jetstack/cert-manager)
to get certificates from the free [Let's Encrypt CA](https://letsencrypt.org/).
You start by deploying cert-manager with credentials for your DNS provider (we'll use CloudFlare again) as well as your Let's Encrypt email.
Once deployed, cert-manager looks for Ingress resources with a `tls` key as shown [here](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls).
For each `tls` key, cert-manager will make a certificate request to a Let's Encrypt server to generate a
certificate for each DNS record listed in `tls.hosts`.
The Let's Encrypt server will then ask cert-manager to prove it owns the requested DNS records by
pushing a bit of DNS metadata to the DNS provider.
Once Let's Encrypt verifies that the requested DNS metadata was added, it will return the requested certificates.
cert-manager will then take that certificate and store it in a k8s [Secret](https://kubernetes.io/docs/concepts/configuration/secret/).
This secret can later be mounted into a web server's container as a file.
Let's Encrypt certificates are only valid for 90 days, but cert-manager will automatically renew any certificates that are
nearing their expiration.

> Note: Let's Encrypt has strict [rate limits](https://letsencrypt.org/docs/rate-limits/) for how many certificates it will generate.
During your initial testing you can use the staging Let's Encrypt server (https://acme-staging-v02.api.letsencrypt.org/directory) rather
than the production one to test your setup with fake certs until you get it working.

## Storage

With the previous steps in place, we're able to deploy stateless apps to our k8s cluster.
But some apps need to store persistent data that is still present after a reboot.
k8s defines a [Volume](https://kubernetes.io/docs/concepts/storage/volumes) resource to allow persistent data to be
mounted into the container.

On a single node bare metal k8s cluster, you could use a [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
volume which mounts a directory from the underlying worker machine into the container.
We have a multi-node cluster so this won't work.

In a multi-node cluster we could instead use a [Local Volume](https://kubernetes.io/docs/concepts/storage/volumes/#local).
This is similar to a `hostPath` volume in that it mounts a disk or directory from the underlying host machine into the
container, but this is supported in a multi-node cluster.
This works, but still has a couple limitations:
- Volumes must be manually created prior to deploying the app
- All pods that use the volume are locked to a single worker node
- If the worker goes down the app will be inaccessible until the worker comes back

To overcome this limitation, we're going to use [Dynamic Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#dynamic).
With Dynamic Volumes, a deployment can create a [Persistent Volume Claim (PVC)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#claims-as-volumes)
to request a volume of a given size.
Your cluster's volume provider watches for these claims and creates volumes on demand.
Once the volume is ready, the pod that requested it will be created and the volume will be mounted into the container.

For this bare metal setup, we'll use [GlusterFS](https://docs.gluster.org/en/latest/) and [Heketi](https://github.com/heketi/heketi/wiki)
as our volume provider.
GlusterFS is a multi-node network filesystem and Heketi is an API layer to manage GlusterFS volumes.
Later on we'll use the [gluster-kubernetes](https://github.com/gluster/gluster-kubernetes) project to configure
these components to handle provisioning of Volumes in our cluster.
In the steps shown below we'll plug a USB drive into one of our worker nodes.
This worker will run the GlusterFS server and all persistent data will be stored on the USB drive.
However, these volumes can be mounted over the network by containers running on other workers.
If you want, you can buy a couple more USB drives and deploy GlusterFS onto multiple nodes
to add replicate data and increase availability.

Once we have GlusterFS+Heketi deployed, we can start using dynamic persistent volumes.
Our VPN deployment might create a Persistent Volume Claim of size 5GB.
Our volume provider will notice this new claim and create a 5GB volume in Gluster filesystem.
Once the Volume is ready, k8s will continuing creating the VPN container and mount the
Volume into the container.
If the VPN container is deleted, the volume will be re-attached to the new container and
the existing data will still be present.

## Initial Setup

Now that we understand the concepts, let's start deploying it.

#### Hardware Setup

> Note: See picture at top of page as reference

Steps to setup hardware:
- Plug Unifi Gateway's WAN1 port into your modem
- Plug Unifi Gateway's LAN1 port into the larger switch
  - Note: the picture shows some components plugged into LAN2, we'll cover this in a later section
- The Unifi AP should come with a Power-over-Ethernet (PoE) adapter
  - Plug the LAN port of the adapter into the larger switch
  - Plug the PoE port of the adapter into the Unifi AP
- Assemble the Raspberry Pi's into the stacking case
  - The case linked above includes a 7th level that we won't use
- Plug USB cables into the charging dock but don't plug then into the Raspberry Pi's yet
  - We'll power up the Pi's after we flash the SD cards
- Plug the USB power cable of the mini switch into a USB port on one of the Pi's
- Plug each Pi into the mini switch using the mini ethernet cables
- Plug the mini switch into the larger switch using another mini ethernet cable
- Plug everything into AC power

> Note: you'll need a wired ethernet connection on your workstation for now
Later steps will install the Unifi Controller into the k8s cluster which will allow you
to setup the Wifi network.

#### Ansible Introduction

The following steps assume you already have `git` and `python` installed.

We'll use [Ansible](https://www.ansible.com/) to deploy the cluster.
Ansible works by running commands over SSH from your workstation to each node
in the Raspberry Pi cluster.
Ansible has many features, but we'll introduce three basics here: inventory, roles, and playbooks.

An inventory file lists the IP addresses of each machine you want to provision and
groups each machine by responsibility.
This file looks similar to the following:
```
[all]
k8s-node1 ansible_host=192.168.1.100
k8s-node2 ansible_host=192.168.1.101
k8s-node3 ansible_host=192.168.1.102

[kube-master]
k8s-node1

[kube-node]
k8s-node2
k8s-node3
```
This inventory file describes a three node k8s cluster.
All the machines are listed at the top under the `all`,
the first machine will serve as the master node,
and the other two machines will be worker nodes.

A role is a set of configuration options, files, and commands to run on a target machine.
For example, the `upgrade-master` role will update k8s to the specified version while
the `openvpn` role will deploy a VPN container into the cluster.
A role will usually contain a `tasks/main.yml` file which lists which commands to run,
a `templates` directory containing files to transfer to the target machine,
and a `defaults/main.yml` file which lists supported configuration options.

Finally, playbooks will tie the inventory and roles together.
Here's a playbook example:
```
- hosts: all
  roles:
    - glusterfs-client

- hosts: gfs-cluster
  roles:
    - glusterfs-server
```
This playbook tells Ansible to run the `glusterfs-client` role on all machines,
then run the `glusterfs-server` role only on machines in the `gfs-cluster` inventory group.

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

Install Ansible + deps:

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

You should now have a running k8s cluster!
To interact with the cluster, install the [kubectl CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/) and
copy the kubectl config file into your home directory:

```
cp ./secrets/admin.conf ~/.kube/config
```

To check that it's working run `kubectl -n kube-system get pods`.

#### Optional: Setup Unifi Controller

> Skip if you don't have a Unifi Router

After following the above steps, a Unifi Controller should be running as a pod in your k8s cluster.
The following steps are required to ensure the Router and AP are adopted by the Controller.
After adopting both devices you will be able to configure settings like the Wifi network by
visiting `https://unifi.$INGRESS_DOMAIN`.

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
- Adopt the Unifi AP
  - If the AP was not previously paired with another controller:
    - The AP should appear in the Devices tab, click Adopt next to it in the UI
  - If the AP was previously paired:
    - Hold down the small Reset button on the AP with a paper clip to reset to factory default settings
    - After reseting the AP should appear in the Devices tab, click Adopt
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

## Optional: Access K8S Dashboard

A dashboard for your k8s cluster should now be available at `https://k8s.$INGRESS_DOMAIN`.
This dashboard displays metrics like CPU and memory usage, as well as listing all deployed k8s resources.
To get a login token, run `./submodules/k8s-pi/scripts/get-dashboard-token.sh`.
Visit the dashboard URL, select Token on the login prompt, and paste in the token returned by the script.

## Optional: Connect to cluster with VPN

A VPN server is now available at `vpn.$INGRESS_DOMAIN`.
To access it, generate a secret VPN config file by running this script:

```
./submodules/k8s-pi/scripts/generate-vpn-cert.sh vpn.$INGRESS_DOMAIN
```

This will create a `secrets/k8s.ovpn` file containing the necessary connection information.
Pass this file to your VPN client to connect to k8s internal services and cluster IPs even when
outside your home network.

## Optional: Backup/Restore

It wouldn't be a real production-ish cluster if we didn't have automated backups.
The Ansible playbooks deploy the [Ark](https://github.com/heptio/ark) k8s backup/restore utility.
With the default configuration, Ark will take a backup of all k8s resources and persistent volumes once a day.
This means you can delete your entire cluster, restore from a backup, and all pods, services, and persistent
data will be restored just as it was when the last backup was taken.
The Ark deployment includes a component called [Restic](https://restic.net/) to take backups of GlusterFS volumes.
These backups will be stored a Google Cloud Storage (GCS) bucket although you can configure it with other
backup services like S3.
Ark will also automatically remove backups that are more than two weeks old.

#### Take backup on-demand

Backups are taken automatically once a day.
To take one on-demand:

```
ark create backup backup-01032019 --ttl 360h0m0s
```

This command takes a backup of the entire cluster.
Ark will automatically delete this backup after ~2 weeks (360 hours).

#### Restoring entire cluster from backup

First, get the name of the latest backup:

```
$ ark get backups
NAME                           STATUS      CREATED                         EXPIRES   SELECTOR
daily-backups-20190103070021   Completed   2019-01-02 23:00:21 -0800 PST   13d       <none>
daily-backups-20190102070021   Completed   2019-01-01 23:00:21 -0800 PST   12d       <none>
...
```

To start from a completely clean state,
repeat the steps above to wide all the SD cards.
Also remember to run `sudo wipefs -a /dev/sda` to clear out the USB drive used by GlusterFS.

Comment out the `- import_playbook: deploy.yml` line of the `upgrade.yml` playbook to skip re-creating any k8s resources.
Uncomment the line `backup_restore_only_mode: true` in `secrets/secrets.yml` so that Ark does add or delete any existing backups.

Now run the `bootstrap.yml` playbook to recreate the cluster from scratch.
Finally restore all k8s resources from backup:

```
ark create restore restore-01032019 --from-backup backup daily-backups-20190103070021
```

You can check on the restore progress with:

```
ark describe restore restore-01032019 --volume-details
```

Undo your changes to `upgrade.yml` and `secrets.yml` and re-run the `ark` role to allow it to resume taking daily backups.

#### Restoring select deployments from backup

If you'd like to restore only a subset of resources, e.g. only the VPN resources, specify a label selector on the restore:

```
ark create restore restore-01032019 --from-backup backup daily-backups-20190103070021 --label app=openvpn
```

#### Possible gotcha: Restic Repo shows NotReady

At one point after shutting down and restoring, my Ark deployment was unable to take new backups.
This was due to `ark restic repo get` returning `NotReady`.
Turns out the Restic repository was still marked as "locked", possibly
due to not shutting down the cluster gracefully.
Running the following commands unlocked the repo:

```
kubectl -n heptio-ark exec -it ark-restic-POD_ID /bin/sh
restic unlock -r gs:<VOLUME_BACKUP_BUCKET>:default
# enter 'static-passw0rd' as the repo password
```

At time of writing, volume backups are encrypted with the [hardcoded](https://github.com/heptio/ark/blob/9f72cf9c614bb4dc02dfacae08c9dcd11fbb5eaa/pkg/restic/repository_keys.go#L33)
key 'static-passw0rd'. This may change in future releases.

## Optional: Adding your own Ansible tasks

TODO

## Optional: Building ARM images

TODO

## Open Issues

TODO

## Future work

TODO

## Finished!

TODO
