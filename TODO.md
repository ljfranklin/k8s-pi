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
[ ] Switch to heketi hostname in storage class
    - Blocked: https://github.com/kubernetes-incubator/kubespray/issues/3177
[ ] Use hostname in heketi topology.json
    - Blocked: https://github.com/coredns/coredns/pull/2233
[ ] Deploy unifi controller
    - https://github.com/helm/charts/tree/master/stable/unifi
    - Possible ARM issues: https://github.com/jacobalberty/unifi-docker/issues/54
[ ] Install pi-hole
[ ] Auto-renew Let's Encrypt cert
    - cert-manager needs arm image: https://github.com/jetstack/cert-manager/pull/780
[ ] Add ansible task to upgrade cluster
    - https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-12/
