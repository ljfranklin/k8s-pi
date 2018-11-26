## TODO

[x] Setup dynamic dns cron
[x] Add ansible task to deploy dashboard
[x] bootstrap.sh should take a number of nodes and auto-generate `inventory`
[x] Set static IP for master node
[x] Run ntp update on boot
[x] Switch to nginx for UDP ingress
[x] Deploy GlusterFS for persistent data
    - Ansible playbook: https://github.com/gluster/gluster-kubernetes/pull/155/files
    - Installing glusterfs on arm: http://larmog.github.io/2016/02/22/glusterfs-on-kubernetes-arm/
    - Installing heketi on K8S: https://github.com/heketi/heketi/blob/master/docs/admin/install-kubernetes.md
    - Another install guide: https://github.com/psyhomb/heketi
[x] Create StorageClass and test service
[x] Run openvpn to allow outside connection
    - Router forward VPN traffic
    - https://github.com/helm/charts/tree/master/stable/openvpn
    - Use TCP service: https://github.com/helm/charts/tree/master/stable/nginx-ingress
[x] Use HTTPS get grab public IP
[x] Deploy unifi controller
    - https://github.com/helm/charts/tree/master/stable/unifi
    - Possible ARM issues: https://github.com/jacobalberty/unifi-docker/issues/54
[x] Auto-renew Let's Encrypt cert
    - cert-manager needs arm image: https://github.com/jetstack/cert-manager/pull/780
[x] Backup persistent data
    - install ark + restic
    - pull in chart w/restic PR
    - manually build ARM ark image
    - create GCP bucket + service account
[x] Set automated schedule for backups
[x] Take a backup
[x] Install weave-net
[x] Restore from backup
[x] Get cluster on LAN2
    - Put everything on LAN 1
    - Get controller connected
    - Put wireless AP and switch on LAN 2
[x] Install MetalLB
    - Change K8S master advertise IP to DNS record
    - Enable BGP on router
    - Blog: https://medium.com/@ipuustin/using-metallb-as-kubernetes-load-balancer-with-ubiquiti-edgerouter-7ff680e9dca3
    - Docs: https://help.ubnt.com/hc/en-us/articles/205222990-EdgeRouter-Border-Gateway-Protocol
[x] Automatically annotate openvpn + unifi for backups
    - kubectl annotate pod openvpn-54bdcd4d7b-sj6nn backup.ark.heptio.com/backup-volumes=certs
    - kubectl annotate pod unifi-55f6dcc44c-khbrk backup.ark.heptio.com/backup-volumes=unifi-data
[x] Add following contents to `data/sites/default/config.gateway.json` in Unifi controller volume
```
{
    "protocols": {
        "bgp": {
            "64512": {
                "neighbor": {
                    "192.168.1.101": {
                        "remote-as": "64512"
                    },
                        "192.168.1.102": {
                            "remote-as": "64512"
                        },
                        "192.168.1.103": {
                            "remote-as": "64512"
                        },
                        "192.168.1.104": {
                            "remote-as": "64512"
                        },
                        "192.168.1.105": {
                            "remote-as": "64512"
                        }
                },
                    "parameters": {
                        "router-id": "192.168.1.1"
                    }
            }
        }
    }
}
```
[ ] Parameterize static IPs
[ ] Get off fork of nginx-ingress
[ ] Add ansible task to upgrade cluster
    - https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-12/
[ ] Get off forked docker images
[ ] Install pi-hole
