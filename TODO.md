## TODO

- bootstrap.sh should take a number of nodes and auto-generate `inventory`
- Make dashboard publicly routable
- Run ntp update on boot
- Add ansible task to deploy dashboard
  - Remember to restart dashboard to get metrics
    - https://github.com/rak8s/rak8s/blob/master/roles/dashboard/tasks/main.yml
- Add ansible task to upgrade cluster
  - https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-12/
