FROM moby/buildkit:v0.4.0

RUN mkdir example-build
COPY Dockerfile.example ./example-build
WORKDIR ./example-build
