To provission multi-master kubernetes cluster, assuming AWS access is properly configured, "cks" key exists

1. terraform apply
2. ansible-playbook -i dynamic_inventory.py kcluster-playbook.yaml
3. kubectl --kubeconfig admin.conf get nodes
4. terraform destroy