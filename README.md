# BuildKit example for in-cluster build

This project provides a simple example, using [BuildKit](https://github.com/moby/buildkit) to provide in-cluster
build capabilities without the use of a host-provided Docker runtime (or
having to rely on a Docker-in-Docker configuration).

## Background

One recurring pattern in the Kubernetes world involves a potential need
to build containers within the cluster (versus using an out-of-cluster service).
When 99.9% of Kubernetes clusters were built with the Docker
engine backing each node of the cluster, one common "hack" of the wall
between Kubernetes and the host was to use a privileged pod with the Docker API
socket mounted, allowing a container to perform `docker build` commands
against the host-installed Docker engine. Of course once a
container has access to the Docker socket, there are other worrying security
concerns given the capability for that special container to now interfere and
interact with all other containers on the host. One potential mitigation is
extra isolation, like a Docker-in-Docker (DinD)-based solution.

Fast forward to today and Docker is not necessarily the default container
runtime underneath many Kubernetes clusters and is potentially not even
installed on cluster worker nodes given the advancement of CRI-compliant runtimes
like containerd and cri-o, among others. This anti-pattern of mounting the
Docker socket in a pod can be replaced with tools like BuildKit, which require
no Docker API socket and can depend on simply the OCI-compliant `runc` executor,
or containerd.

This repository provides a small skeleton example, providing an in-cluster
buildkitd pod listening on a TCP port so that in-cluster builds can
use a rootless, unprivileged BuildKit to perform container builds.

## Other Options

While I wanted to learn more about BuildKit internals and usage specifically, don't
ignore that there are other more polished frameworks that provide this at a higher
level already. Many of them build on BuildKit, or at least provide BuildKit as an
option. Here is a short list of other projects to consider if you are looking for
more complete solutions:

 - [img](https://github.com/genuinetools/img) from [jessfraz](https://github.com/jessfraz). Related [blog post](https://blog.jessfraz.com/post/building-container-images-securely-on-kubernetes/)
 - [Kaniko](https://github.com/GoogleContainerTools/kaniko) from [Google's ContainerTools](https://github.com/GoogleContainerTools) project.
 - [Knative build](https://github.com/knative/build), part of the [Knative](https://cloud.google.com/knative/) project. [Nice blog](https://starkandwayne.com/blog/build-docker-images-inside-kubernetes-with-knative-build/) on using it from [DrNic](https://github.com/drnic).
 - More details on different in-cluster build options within Knative in this [blog post](https://www.morethanseven.net/2018/07/29/knative-build-with-docker-buildkit-img/) from Gareth Rushgrove

## Using this example repository

### Expectations

You have a Kubernetes cluster for which you have administrative access to
deploy a pod. The underlying runtime backing your worker nodes is immaterial as
BuildKit will not use that runtime in this example.

This example will have you deploy the BuildKit daemon, relying on `runc` as the
build worker, using the pre-built DockerHub image for rootless BuildKit [v0.4.0](https://github.com/moby/buildkit/releases/tag/v0.4.0),
released in March 2019.

You will then build an image based off the existing v0.4.0 BuildKit image to
have the `buildctl` command and a simple `Dockerfile.example` in a single image
for use within a Kubernetes batch job to demonstrate calling the BuildKit daemon
pod over TCP to build a container. You can tag and push this image to a registry
as long as you provide the proper secrets to log into your registry, using
BuildKit's support for registry authentication and push. The example will use a
manually created secret to demonstrate this with DockerHub, but can be used with
any registry.

### Demonstration steps

Steps below assume you have cloned this repository and your current working directory is in this repository.

1. Deploy the buildkitd pod in your cluster. No modifications should be necessary to [`buildkitd.yaml`](https://github.com/estesp/buildkit-cluster-example/blob/master/buildkitd.yaml):

```
$ kubectl apply -f buildkitd.yaml
```

**NOTE:** *For a discussion on why this pod is still privileged, please [read this document](https://github.com/moby/buildkit/blob/v0.4.0/docs/rootless.md#security-consideration) from the BuildKit maintainers. TL;DR work is underway to remove this requirement.*

2. Create a secret with any required Docker credentials from a local Docker installation where you already are logged in to desired registries:

```
  $ kubectl create secret generic dockerconfig --from-file=/home/<user>/.docker/config.json
```

**NOTE:** *This will not work if done from a Mac OS "Docker Desktop" installation where system credential helpers are used for storing your credentials.*

3. Modify the [`build-example.yaml`](https://github.com/estesp/buildkit-cluster-example/blob/master/build-example.yaml) batch job spec for your desired settings for (a) the image you want to use, and (b) the push target in the `args` section, after the `--exporter-opt` field. You can either build the [`Dockerfile`](https://github.com/estesp/buildkit-cluster-example/blob/master/Dockerfile) in the root of this
repo with your own `Dockerfile.example` (or any other changes you wish to make) or simply use the `estesp/buildexample:1.0` already listed, which has been built from that `Dockerfile` already.

4. When you are satisfied with your copy of the `build-example.yaml` you can apply it to your cluster to run a build against the BuildKit daemon already running, and push an image to your desired target:

```
$ kubectl apply -f build-example.yaml
```

5. You can `kubectl get po` to see that your batch job ran properly, and use `kubectl logs` to show the output from your BuildKit run.

In my case:

```
$ kubectl get po
NAME                             READY   STATUS      RESTARTS   AGE
builder-d44n9                    0/1     Completed   0          88m
buildkitd-765fcc4854-htxbt       1/1     Running     0          3h41m
```

And my successful image build and push:

```
$ kubectl logs builder-d44n9
time="2019-03-22T19:46:01Z" level=warning msg="--exporter <exporter> is deprecated. Please use --output type
=<exporter>[,<opt>=<optval>] instead."
time="2019-03-22T19:46:01Z" level=warning msg="--frontend-opt <opt>=<optval> is deprecated. Please use --opt
 <opt>=<optval> instead."

#2 [internal] load build definition from Dockerfile.example
#2       digest: sha256:e323acd1c1ceb435985588acb4550e981ed92f1a820e72beea0350fe50ffa621
#2         name: "[internal] load build definition from Dockerfile.example"
#2      started: 2019-03-22 19:46:01.065994531 +0000 UTC
#2    completed: 2019-03-22 19:46:01.066102728 +0000 UTC
#2     duration: 108.197µs
#2      started: 2019-03-22 19:46:01.066222014 +0000 UTC
#2    completed: 2019-03-22 19:46:01.079980927 +0000 UTC
#2     duration: 13.758913ms
#2 transferring dockerfile: 39B done


#1 [internal] load .dockerignore
#1       digest: sha256:acce6bf27717d36e9a4ea09664e3d0b1342bce019e65d1b679f46203bbcf43b4
#1         name: "[internal] load .dockerignore"
#1      started: 2019-03-22 19:46:01.065710708 +0000 UTC
#1    completed: 2019-03-22 19:46:01.065791408 +0000 UTC
#1     duration: 80.7µs
#1      started: 2019-03-22 19:46:01.06590812 +0000 UTC
#1    completed: 2019-03-22 19:46:01.076959812 +0000 UTC
#1     duration: 11.051692ms
#1 transferring context: 2B done


#3 [internal] load metadata for docker.io/library/alpine:latest
#3       digest: sha256:d4fb25f5b5c00defc20ce26f2efc4e288de8834ed5aa59dff877b495ba88fda6
#3         name: "[internal] load metadata for docker.io/library/alpine:latest"
#3      started: 2019-03-22 19:46:01.101981096 +0000 UTC
#3    completed: 2019-03-22 19:46:01.538928609 +0000 UTC
#3     duration: 436.947513ms


#4 [1/2] FROM docker.io/library/alpine:latest@sha256:644fcb1a676b5165371437...
#4       digest: sha256:d170cf83c5743380c000554f8ece996d64f35677d36744df8b470ff41cfded6a
#4         name: "[1/2] FROM docker.io/library/alpine:latest@sha256:644fcb1a676b5165371437feaa922943aaf7afcf
a8bfee4472f6860aad1ef2a0"
#4      started: 2019-03-22 19:46:01.539572137 +0000 UTC
#4    completed: 2019-03-22 19:46:01.539856953 +0000 UTC
#4     duration: 284.816µs
#4 resolve docker.io/library/alpine:latest@sha256:644fcb1a676b5165371437feaa922943aaf7afcfa8bfee4472f6860aad
1ef2a0 done
#5 [2/2] RUN touch .i-was-here
#5       digest: sha256:711798196f4307d0c80e356059f32e62ac46653449125c1c65f467b64f19e658
#5         name: "[2/2] RUN touch .i-was-here"
#5      started: 2019-03-22 19:46:01.540170107 +0000 UTC
#5    completed: 2019-03-22 19:46:01.540209588 +0000 UTC
#5     duration: 39.481µs
#5       cached: true


#6 exporting to image
#6       digest: sha256:b77b4e1dd2dfbd75d86a8ab4d3a2911fab70ec665fb2a05cb3a5de4f8a048e42
#6         name: "exporting to image"
#6      started: 2019-03-22 19:46:01.540282029 +0000 UTC
#6 exporting layers done
#6 exporting manifest sha256:d2138b9afd64b4f11e89469538ebb158d63087b8b8a42aab9a22d680aceffb9e done
#6 exporting config sha256:846f932de93756f788053508a6e162c026f2fddbdd22cfe37646a85c07c5ba1d 0.0s done
#6 pushing layers
#6 pushing layers 0.4s done
#6 pushing manifest for docker.io/estesp/mybkimg:latest
#6    completed: 2019-03-22 19:46:02.070280786 +0000 UTC
#6     duration: 529.998757ms
#6 pushing manifest for docker.io/estesp/mybkimg:latest 0.1s done
```
