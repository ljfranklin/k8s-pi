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

## Ingress

Automatic Let's Encrypt certs blocked on [this issue](https://github.com/jetstack/cert-manager/pull/780).
In the meantime I've manually grabbed a cert with the [lego cli](https://github.com/xenolf/lego).

## GlusterFS

TODO: fill in instructions here

- `sudo wipefs -a /dev/sda`

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
