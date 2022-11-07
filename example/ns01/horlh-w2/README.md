# Files

## [`cluster.yml`](./cluster.yml)

This will be consumed by `bingo` and applied to the supervisor cluster

## [`10.workload.kapp-controller.yml`](./10.workload.kapp-controller.yml)

This will be consumed by `bingo`, and applied to the workload cluster. For
bingo to be able to do that, it will read the secret `${cluster}-kubeconfig` in
the supervisor cluster, in the respective namespace, and will use that to point
`bingo`'s `kapp` at the workload cluster.

This installs the `kapp-controller` on the workload cluster.

## [`20.workload.cluster-packages-app.yml`](./20.workload.cluster-packages-app.yml)

This will be consumed by `bingo`, and applied to the workload cluster.

This deploys a single `kappctrl.k14s.io/App`. This app is deployed on the
workload cluster. So whatever config is in that app will be handled by the
just-before-deployed kapp-controller in the workload cluster.

This is the point where the hand-off from `bingo` in the supervisor cluster to
the `kapp-controller` in the workload cluster happens.

`bingo` tells the `kapp-controller` in the workload cluster what to do, but it
will be done by the `kapp-controller` in the workload cluster.

In this specific example, the app instructs the `kapp-controller` in the workload cluster to
- fetch this very repo
- run the directory [`example/apps/common`](../../apps/common) through `ytt`
- with `values.yml` as data-values

## [`values.yml`](./values.yml)

This holds the data-values for the "base app" that is deployed to the
workload cluster. It will be fetched and interpreted by the `kapp-controller`
in the workload cluster. `bingo` does not care about this file.
