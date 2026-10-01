# On Premises Kubernetes CI/CD Lab

This repository demonstrates a complete CI/CD and GitOps workflow on a small on-premises Kubernetes cluster.

When application code is pushed to `main`:

1. GitHub Actions runs the tests.
2. It builds the container and performs an HTTP smoke test.
3. It publishes an immutable `sha-<commit>` image to GHCR.
4. It writes the new image tag to `k8s/deployment.yaml` and commits that change.
5. Argo CD detects the Git change and synchronizes it into Kubernetes.
6. Kubernetes performs a rolling update across two worker nodes.

```text
Code change
    -> GitHub Actions
    -> tests and container build
    -> GHCR image
    -> image tag committed to Git
    -> Argo CD
    -> Kubernetes rolling update
```

The application is intentionally a small static website. This keeps the lab focused on Kubernetes, delivery automation, GitOps, and troubleshooting.

## What the lab demonstrates

- automated tests and container smoke tests
- immutable container tags based on Git commit SHAs
- container publishing to GHCR
- Git as the declared deployment state
- Argo CD synchronization and self-healing
- Kubernetes health probes, rolling updates, and pod distribution
- internal access through Traefik and WireGuard

Detailed cluster installation, networking, security, and recovery documentation belongs in the homelab MkDocs site.

## Prerequisites

This test assumes:

- the control-plane and two worker nodes are healthy;
- Argo CD reports `demo-app` as `Synced` and `Healthy`;
- the GHCR package is public and pullable by the workers;
- `k8s-demo.home` resolves while connected locally or through WireGuard;
- this repository is cloned onto the Debian 13 management terminal using SSH.

Never commit K3s tokens, kubeconfig files, GitHub credentials, Argo CD passwords, or live private addressing.

## Test the CI/CD workflow

Run these steps from the repository clone on the Debian management terminal.

### 1. Synchronize the repository

The workflow creates a bot commit when it updates the deployment manifest, so pull before starting another change:

```bash
cd ~/k8s-cicd-lab
git pull --ff-only
git status
```

The working tree should be clean.

### 2. Change the application

Edit the page:

```bash
vi app/index.html
```

Make a visible change, such as updating the version:

```html
<p class="version">Version 1.2.0</p>
<p>Automatically tested by GitHub Actions and deployed by Argo CD.</p>
```

Update the version expected by the test:

```bash
sed -i 's/Version 1\.1\.0/Version 1.2.0/' tests/test-app.sh
```

Use the actual old and new versions if they differ from this example.

### 3. Test locally

```bash
./tests/test-app.sh
git diff --check
git diff
```

Expected:

```text
Static application tests passed.
```

### 4. Push the release

```bash
git add app/index.html tests/test-app.sh
git commit -m "Release application version 1.2.0"
git push
```

## Watch the release

### GitHub Actions

Open the repository's **Actions** tab. The run should complete:

```text
Run static tests
Build test image
Run container smoke test
Build and publish image
Update Kubernetes image
Commit deployment update
```

The final step creates a bot commit similar to:

```text
Deploy image sha-<commit>
```

Changes limited to `k8s/**`, `argocd/**`, or `README.md` do not rebuild the application.

### Argo CD and Kubernetes

On the control plane:

```bash
alias kubectl='sudo /usr/local/bin/k3s kubectl'
kubectl get application demo-app -n argocd --watch
```

Argo CD polls Git, so detection can take a few minutes. The final state should be:

```text
Synced   Healthy
```

Watch the rolling update in another terminal:

```bash
kubectl get pods -n demo --watch
```

Kubernetes should create a new pod, wait for its readiness probe, remove an old pod, and repeat until both replicas use the new image.

Verify the result:

```bash
kubectl rollout status deployment/demo-app -n demo --timeout=300s

kubectl get pods -n demo \
  -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready'
```

Expected:

- two ready pods;
- one pod on each worker;
- both pods use the new SHA image;
- Argo CD reports `Synced` and `Healthy`.

### Validate the application

From an authorized internal or WireGuard-connected client:

```bash
curl -fsS http://k8s-demo.home/ | grep -E 'Version|GitHub Actions|Argo CD'
curl -fsS http://k8s-demo.home/healthz
```

The health endpoint should return `healthy`. Open `http://k8s-demo.home` in a browser and confirm the new version appears. Use a hard refresh if the browser displays a cached page.

## Troubleshooting

### CI fails

Run the local checks again:

```bash
./tests/test-app.sh
git diff --check
```

Use the failed GitHub Actions step to determine whether the failure occurred during testing, the container build, the smoke test, registry login, image publication, or the manifest commit.

### The image publishes but the manifest does not change

The publishing job requires:

```yaml
permissions:
  contents: write
  packages: write
```

Check the deployment history and image recorded in Git:

```bash
git pull --ff-only
git log --oneline -5 -- k8s/deployment.yaml
grep 'image:' k8s/deployment.yaml
```

The image tag should contain the full commit SHA.

### Argo CD is OutOfSync or Degraded

`OutOfSync` means the live Kubernetes specification differs from Git. `Degraded` means the resulting Kubernetes resources are unhealthy. An application can be `Synced` and still be `Degraded`.

Inspect the application and workload:

```bash
kubectl get application demo-app -n argocd
kubectl get deployment,replicaset,pods -n demo -o wide
kubectl describe deployment demo-app -n demo
kubectl get events -n demo --sort-by='.lastTimestamp' | tail -n 30
```

Inspect a failing pod when required:

```bash
kubectl describe pod POD_NAME -n demo
kubectl logs POD_NAME -n demo --tail=100
```

Confirm the deployed image:

```bash
kubectl get deployment demo-app \
  --namespace demo \
  --output=jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Common evidence includes:

- `ImagePullBackOff`: the image is missing, private, or incorrectly tagged;
- `CrashLoopBackOff`: the container starts and repeatedly exits;
- probe failures: the application is not answering its health endpoint;
- `FailedScheduling`: a resource, taint, selector, or topology rule blocks placement.

This lab previously encountered a `FailedScheduling` rollout because a surge pod conflicted with the strict topology-spread rule and the tainted control plane. The deployment now limits application pods to worker-labelled nodes:

```yaml
nodeSelector:
  node-role.kubernetes.io/worker: worker
```

## Production differences

This lab proves the workflow; it is not a production cluster. All VMs share one Proxmox host, the control plane is not highly available, ingress has no redundant virtual IP, the application uses internal HTTP, and CI commits directly to `main`. A production design would normally add reviewed promotion pull requests, a separate GitOps repository, private registry authentication, TLS, SSO and restricted Argo CD projects, policy enforcement, monitoring, and tested backup and disaster recovery.

