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
- [bingo] to apply the whole world when a change in the git repo is detected

[git-sync]: https://github.com/kubernetes/git-sync
[bingo]: ./Dockerfile

The git-sync & bingo containers share the git repo and a fifo. Once the
git-sync container discovers a change in the git repo, it notifies the other
container via that fifo. The bingo container kicks in and `kapp deploy`s
stuff in the following order:

1. `${BASE}/${NS}/${CLUSTER}/cluster.yml`  
   All those files will be collected and deployed as a `kapp`. Thus, if you
   remove a cluster by deleting such a file, `kapp` will make sure to delete
   the cluster from the supervisor.
1. `${BASE}/${NS}/${CLUSTER}/*workload*.yml`  
   A separate `kapp` will be deployed on each workload cluster with the files
   matching the above glob. Here too, when you remove a file or any object in
   any of those files, `kapp` will delete those objects from the respective
   workload cluster.

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

All files, the `cluster.yml` and the `*workload*.yml` will ran through `ytt`
before they get `kapp`lied. In those files you have accss to the following
variables, which are derived from the directory path in the git repo (i.e.
`$NS` & `$CLUSTER`)
- in `cluster.yml`:
  - `ns` the vSphere namespace the cluster is (about to) deployed into
  - `cluster` the name of the cluster that is (about to) deployed
- in `*workload*.yml`, if you load `ytt`'s `data` module:
  - `data.values.clusterNS` the vSphere namespace of the cluster
  - `data.values.cluster` the name of the cluster

It runs everything in serial, and if there is an error on `apply` or `delete`
it will just 🤷 and try again on the next update of the repo.

## Issues

- As said, if there are errors in an `kapp deploy` run, bingo won't care. It
  will tell you in the logs, but won't do much about it.
  However, it will periodically reapply, by default every 5min.
- Runs everything in serial:
  1. first runs all `cluster.yml`s
  2. runs all `*workload*yml`, for on cluster after the other
- Needs open firewalls, i.e. the supervisor cluster needs to be able to:
  - pull the [git-sync] & [bingo] images
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
1. configure bingo by setting up env vars:
   - `export BINGO_namespaces='[ "ns01", "ns02" ]'`  
     add all vSphere namespaces bingo should be able to deploy/manage clusters in
   - `export BINGO_repo='{"url": "git@ithub.com:hoegaarden/bingo", "dir": "example", "priv-key": "-----BEGIN OPENSSH PRIVATE KEY-----...."}'`  
     to specify which repo holds the cluster / workload, and the subdirectory
     these configs are in, and which key we use to pull it
1. deploy to the supervisor cluster
   ```bash
   make install
   ```
1. check, if it actually works, e.g.:
   ```bash
   kubectl tail -n bingo
   ```

An example `.envrc` to setup all variables to deploy bingo could look something like:
```bash
export BINGO_namespaces='[ "ns01" ]'

export BINGO_repo='
url: git@github.com:hoegaarden/bingo
dir: example
priv-key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
    nope nope nope
  Nonha/zPwQDL8AAAALaG9ybGhAYmx1cHA=
  -----END OPENSSH PRIVATE KEY-----
'
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

- acutally test this thing
- publish container images with everything baked in, so we don't have maintain
  the scripts in a config map
- implement in a proper language
