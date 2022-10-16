# bingo

bingo is not git ops

## What

This is for TKGs supervisor clusters. It's some light and dumb automation, to
manage some basics, namely guest clusters and base workloads on them.

It runs a vSphere pod which polls a git repo and applies the repos content.

It is absolutely not supported, just a PoC, and you should not use it.

## Why

I want some light automation to manage the guest clusters in git without the
need to apply things manually, with no external dependencies (e.g. running
concourse or argo somewhere).

Ideally, I'd have the kapp-controller or something similar running in the
supervisor cluster. I _think_ that will come eventually, but is not here yet.

Because I am not allowed to deploy CRDs into the supervisor cluster, I can't
deploy kapp-controller or someting similar. Thus, I opted for the next best
thing any experienced engineer would opt for: A bunch of shell scripts!

## How

The vSphere pod runs two containers:
- [git-sync] to pull in a git repo
- [kubectl] to apply the whole world when a change in the git repo is detected

[git-sync]: https://github.com/kubernetes/git-sync
[kubectl]: https://bitnami.com/stack/kubectl

The git-sync & kubectl containers share the git repo and a fifo. Once the
git-sync container discovers a change in the git repo, it notifies the other
container via that fifo. The kubectl container kicks in and `kubectl apply`s
and `kubectl delete`s some stuff in the following order:

1. `${BASE}/${NS}/${CLUSTER}/workload.yml.delete` will be `kubectl delete`d on the guest cluster named `$CLUSTER`
1. `${BASE}/${NS}/${CLUSTER}/cluster.yml.delete` will be `kubectl delete`d on the supervisor cluster
1. `${BASE}/${NS}/${CLUSTER}/cluster.yml` will be `kubectl apply`d on the supervisor cluster
1. `${BASE}/${NS}/${CLUSTER}/workload.yml` will be `kubectl apply`d on the guest cluster named `$CLUSTER`

where

- `$BASE` is a sub directory inside the git repo
- `$NS` is the workload namespace in vSphere, thus a namespace in the supervisor cluster  
  These namespaces need to be created and configured (VMClases, content
  library, ...) up front / out of band, bingo won't handle that. However, bingo
  needs to be configured to be allowed to run against each of those namespaces.
  Have a look at [./bingo.yml], you need to configure all namespaces
  there.
- `$CLUSTER` is the guest cluster's name, i.e. the `metadata.name` of a `TanzuKubernetesCluster`

`$NS` & `$CLUSTER` are especially important, because those will be used to pull
the kubeconfig of a guest cluster from secrets in the supervisor clusters. Thus
you need to ensure the directories in the git repo are named correctly, the
very same as you've named the workload namespaces and your clusters.

It runs everything in serial, and if there is an error on `apply` or `delete`
it will just 🤷 and try again on the next update of the repo.

## Issues

- It does not care about any ordering. If you need some ordering, e.g. delete
  the `pkgi` before deleting the `sa`, you need to figure that out on your own
  and slowly move objects from e.g. `workload.yml` to `workload.yml.delete`.
- As said, if there are errors in an `apply` or `delete`, bingo won't care or
  retry. You need to figure it out out-of-band or force a re-run.
- It only every runs once, when it gets notified by git-sync. It will then
  `apply` or `delete` everything, not just things that have changed. That is
  all left to k8s itself to figure out if things need to be done or not.
- Runs everything in serial
- Needs open firewalls, i.e. the supervisor cluster needs to be able to:
  - pull the [git-sync] & [kubectl] images
  - pull the git repo from wherever you host it
  - connect from the pod in the bingo namespace to the loadbalancer fronting
    the kube-api of the guest cluster
- if any of the scripts change, you need to manually restart bingo
- _... and a lot more ..._

## Deploy

Alright, you really still want to testdrive that thing? Be my guest, but don't
shout at me if it breaks and messes up your lovely guest clusters!

1. prepare your git repo with the directory/file structure layed out above (you
   can find an example in [./example/])
1. set up all your workload namespaces
1. configure [./bingo.yml]:
   - add your namespaces
   - configure `repo`, `dir`, and potentially other stuff in the `bingo-config` ConfigMap
   - add the ssh-key, which is allowed to pull the repo, in the `bingo-creds` Secret
1. deploy to the supervisor cluster
   ```bash
   ytt -f bingo.yml | kubectl apply -f -
   ```
1. check, if it actually works, e.g.:
   ```bash
   kubectl tail -n bingo
   ```

[./example/]: ./example/
[./bingo.yml]: ./bingo.yml

## Insider tips & tricks

- you can force a re-run with pushing some random commit to the repo, or:
  ```bash
  kubectl exec deploy/bingo -c bingo -- bash -c 'echo > /shared/pipe'
  ```
  Way nicer, init?
- After you fixed some major bugs in the scripts, you can reload the things by either `kubectl rollout restart deploy bingo` or by running
  ```bash
  kubectl exec deploy/bingo -c bingo -- bash -c 'echo -n reload > /shared/pipe'
  ```
  🤯🥷

## Improvements

First off, don't wait for any improvements.

Secondly, there is quite some stuff that could be done, which could make this
thing a bit better:

- Use `kapp` instead of `kubectl`, which would allow for ordering of objects
- Use `ytt` before applying the things, which would allow us to template some
  things (e.g. the clusters name and namespace could be inferred from the
  directory structure, ...)
- acutally test this thing
- publish container images with everything baked in, so we don't have maintain
  the scripts in a config map
- implement in a proper language
- run a reconcile every x minutes, kinda similar to what the kapp-controller does
