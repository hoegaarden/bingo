# What if we had the kapp-controller on the supervisor cluster?

Here, I am exploring how to gitops everything, if you have the kapp-controller
on the supervisor cluster. Without the need of any external system to run your
automation.

I explored two different approaches:
- Install the kapp-controller on all workload clusters: "in-cluster"
- Manage everything on the workload clusters from the kapp-controller on the supervisor cluster: "in-supervisor"

In both cases, to start off, "just" deploy the [`init.yml`](./init.yml) to the supervisor.
That will instruct the kapp-controller on the supervisor to pull the repo and
apply it.

What will it apply?

At first, an `App` "all-clusters". This `App`'s main purpose is to manage all
`tkc`s and one additional `App` "base" for each of those clusters.

```console
: kapp --kubeconfig-context 10.220.3.194 -n bingo inspect -a all-clusters.app
Target cluster 'https://10.220.3.194:6443' (nodes: 4201b7c9e6f89610c36082a0b120aa48, 3+)

Resources in app 'all-clusters.app'

Namespace  Name               Kind                    Owner  Rs  Ri  Age
ns01       horlh-w4           TanzuKubernetesCluster  kapp   ok  -   23h
^          horlh-w4-base      App                     kapp   ok  -   23h
^          horlh-w5           TanzuKubernetesCluster  kapp   ok  -   1h
^          horlh-w5-base      App                     kapp   ok  -   1h
^          horlh-w5-deployer  Role                    kapp   ok  -   1h
^          horlh-w5-deployer  RoleBinding             kapp   ok  -   1h
^          horlh-w5-deployer  ServiceAccount          kapp   ok  -   1h

Rs: Reconcile state
Ri: Reconcile information

7 resources

Succeeded
```

In this example there are 2 clusters and workloads (packages and other things) on them being managed:
- `horlh-w4` with the "in-cluster" mode
- `horlh-w5` with the "in-supervisor" mode

## in-cluster

You can find the config for the "horlh-w4" in
[`clusters/horlh-w4.yml`](./clusters/horlh-w4.yml). You'll see a plain old
`tkc` in there, and also another `App`.

This `App`, by setting `spec.cluster` instead of `spec.serviceAccountName`, is
not deployed locally (on the supervisor) but remotely on the workload cluster.
So the `App`'s definition resides on the supervisor, the reconciliation loop
will run on the supervisor, but the actual objects get deployed to the workload
cluster.

This `App` then
- pulls the git repo (on a subpath)
- templates some directories (e.g. [`workloads/in-cluster/common/`](./workloads/in-cluster/common/))
- uses some data values (e.g. from [`configs/ns01/horlh-w4/`](./configs/ns01/horlh-w4/))
- and deploys it on the workload cluster

Let's check what's in [`workloads/in-cluster/common/`](./workloads/in-cluster/common)
- the kapp-controller for the workload cluster ([`.../kapp-controller.yml`](./workloads/in-cluster/common/kapp-controller.yml))
- the package repo for the workload cluster ([`.../package-repo.yml`](./workloads/in-cluster/common/package-repo.yml))
- a namespace we deploy all `App`s & `PackageInstall`s and other things into ([`.../base-ns.yml`](./workloads/in-cluster/common/base-ns.yml))
- cert-manager package install ([`.../cert-manager.yml`](./workloads/in-cluster/common/cert-manager.yml))

We can inspect this `App` on the workload cluster to see what it deploys:

```bash
: kapp --kubeconfig-context horlh-w4 -n default inspect -a horlh-w4-base.app
Target cluster 'https://10.220.3.204:6443' (nodes: horlh-w4-control-plane-t7j5j, 1+)

Resources in app 'horlh-w4-base.app'

Namespace                  Name                                                    Kind                      Owner    Rs  Ri  Age
(cluster)                  apps.kappctrl.k14s.io                                   CustomResourceDefinition  kapp     ok  -   7m
^                          base                                                    Namespace                 kapp     ok  -   7m
^                          cert-manager-installer                                  ClusterRole               kapp     ok  -   7m
^                          cert-manager-installer                                  ClusterRoleBinding        kapp     ok  -   7m
^                          internalpackagemetadatas.internal.packaging.carvel.dev  CustomResourceDefinition  kapp     ok  -   7m
^                          internalpackages.internal.packaging.carvel.dev          CustomResourceDefinition  kapp     ok  -   7m
^                          kapp-controller-cluster-role                            ClusterRole               kapp     ok  -   7m
^                          kapp-controller-cluster-role-binding                    ClusterRoleBinding        kapp     ok  -   7m
^                          packageinstalls.packaging.carvel.dev                    CustomResourceDefinition  kapp     ok  -   7m
^                          packagerepositories.packaging.carvel.dev                CustomResourceDefinition  kapp     ok  -   7m
^                          pkg-apiserver:system:auth-delegator                     ClusterRoleBinding        kapp     ok  -   7m
^                          tanzu-package-repo-global                               Namespace                 kapp     ok  -   7m
^                          tanzu-system-kapp-ctrl-restricted                       PodSecurityPolicy         kapp     ok  -   7m
^                          tkg-system                                              Namespace                 kapp     ok  -   7m
^                          v1alpha1.data.packaging.carvel.dev                      APIService                kapp     ok  -   7m
base                       cert-manager                                            PackageInstall            kapp     ok  -   6m
^                          cert-manager-installer                                  ServiceAccount            kapp     ok  -   7m
kube-system                pkgserver-auth-reader                                   RoleBinding               kapp     ok  -   7m
tanzu-package-repo-global  tkg-1.6                                                 PackageRepository         kapp     ok  -   7m
tkg-system                 kapp-controller                                         Deployment                kapp     ok  -   7m
^                          kapp-controller-7567d687b7                              ReplicaSet                cluster  ok  -   7m
^                          kapp-controller-7567d687b7-t2szz                        Pod                       cluster  ok  -   7m
^                          kapp-controller-config                                  ConfigMap                 kapp     ok  -   7m
^                          kapp-controller-sa                                      ServiceAccount            kapp     ok  -   7m
^                          packaging-api                                           Endpoints                 cluster  ok  -   7m
^                          packaging-api                                           Service                   kapp     ok  -   7m
^                          packaging-api-8ptkf                                     EndpointSlice             cluster  ok  -   7m

Rs: Reconcile state
Ri: Reconcile information

27 resources

Succeeded
```

So in this mode, all the above resources are in control of the supervisor
cluster. If users would change or delete those on the workload cluster, the
kapp-controller on the supervisor would revert that eventually.

But now, because this `App` also deploys e.g. the `cert-manager`
`PackageInstall` the kapp-controller on the workload cluster kicks in, and
reconciles that. Any other object that is part of the
"base" `App` would be reconciled by the kapp-controller on the workload
cluster.

This leaves us with a couple of effects, pros and cons:
- Each workload cluster has the kapp-controller installed
- The supervisor manages the kapp-controller, PackageRepositories, PackagesInstalls, ...
- The reconiciliation of the PackageRepository, PackageInstalls, ... happens on the workload clusters

## in-supervisor

Here, the `tkc`s get deployed the same way as in "in-cluster". However, we
don't deploy kapp-controller, the PackageRepository, ... on the workload
cluster; the kapp-controller handles all that.

If we check [`clusters/horlh-w5.yml`](./clusters/horlh-w5.yml) we see that the
following things will be deployed *on the supervisor*:
- a ServiceAccount, Role & Rolebinding per `tkc`
  - which allows the SA to do CRUD on PackageInstalls & Apps
- the "base" `App`

This "base" `App` however works different as in the "in-cluster" case:
- it pulls in the git repo
- templates some directories (e.g. [`workloads/in-supervisor/common/`](./workloads/in-supervisor/common/))
- uses some data values (e.g. from [`configs/ns01/horlh-w5/`](./configs/ns01/horlh-w5/))
- and deploys it on the **supervisor** cluster

Wait, what? On the supervisor? WAT?

Yes!

The Apps & PackageInstalls get deployed on the supervisor, however their
`spec.cluster` will be set to the secret holding the kubeconfig for the
respective workload cluster. Only when the actual objects are to be deployed,
the supervisor's kapp-controller talks to the workload cluster.

So on the supervisor we end up with something like:

```bash
: kapp --kubeconfig-context 10.220.3.194 -n ns01 inspect -a horlh-w5-base.app
Target cluster 'https://10.220.3.194:6443' (nodes: 4201b7c9e6f89610c36082a0b120aa48, 3+)

Resources in app 'horlh-w5-base.app'

Namespace  Name                        Kind            Owner  Rs  Ri  Age
ns01       horlh-w5-base-cert-manager  PackageInstall  kapp   ok  -   5h
^          horlh-w5-base-ns            App             kapp   ok  -   4h

Rs: Reconcile state
Ri: Reconcile information

2 resources

Succeeded
```

And we won't see any `App`s or `PackageInstall`s on the workload cluster; in
fact those resource types don't even exist on the workload clusters, because
kapp-controller & its CRDs are not even installed there:
```bash
: k --context horlh-w5 get app,pkgi -A
error: the server doesn't have a resource type "app"
```

However, we see them all on the supervisor:
```bash
: k --context 10.220.3.194 get pkgi,app -A | grep -iE '(^NAME|horlh-w5)'
NAMESPACE   NAME                                                             PACKAGE NAME                    PACKAGE VERSION        DESCRIPTION           AGE
ns01        packageinstall.packaging.carvel.dev/horlh-w5-base-cert-manager   cert-manager.tanzu.vmware.com   1.7.2+vmware.1-tkg.1   Reconcile succeeded   5h7m
NAMESPACE   NAME                                              DESCRIPTION           SINCE-DEPLOY   AGE
ns01        app.kappctrl.k14s.io/horlh-w5-base                Reconcile succeeded   5s             5h30m
ns01        app.kappctrl.k14s.io/horlh-w5-base-cert-manager   Reconcile succeeded   4m27s          5h7m
ns01        app.kappctrl.k14s.io/horlh-w5-base-ns             Reconcile succeeded   26s            4h58m
```

Effects, pros & cons:
- Way more objects in the supervisor clusters
  - that the single kapp-controller needs to reconcile
  - with potentially weird naming, e.g. `horhl-w5-base-cert-manager`
- Pretty much nothing in the workload clusters, no kapp-controller, no repos,
  no packages, ... just the "actual objects"
- Heavier networking between the kapp-controller and the individual workload
  clusters, because way more stuff needs to be reconciled across cluster
  boundaries
- Deploying anything else than `App`s and `PackageInstall`s becomes a bit
  weird, because all those resources need to be wrapped in an `App` (or
  `Package`); see the [`.../base-ns.yml`](./workloads/in-supervisor/common/base-ns.yml)
  - Ordering things might become even weirder, because you might end up needing
    to break out each object into an individual `App`, so that you can order
    them on the supervisor
