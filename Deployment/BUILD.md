
See `vcluster.yml`

1. Create Cluster

```bash
# Create a vCluster in Docker (automatically connects)
sudo vcluster create my-vc1 --values vcluster.yml

# if Error
# Verify it's working
kubectl get nodes
kubectl get namespaces
```

3. Label nodes

```bash
kubectl label node worker-1 worker-2 worker-3 node-role.kubernetes.io/worker=worker
```

4. Create Namespaces

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: elastic
EOF
```
