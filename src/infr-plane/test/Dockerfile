FROM public.ecr.aws/docker/library/python:3.9-alpine
RUN apk -uv add --no-cache jq openssl bash curl git
RUN apk --no-cache add binutils wget unzip && wget https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -O /tmp/awscli-bundle.zip && unzip /tmp/awscli-bundle.zip -d /tmp && /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws && rm -rf /tmp/awscli-bundle.zip /tmp/awscli-bundle

RUN curl -L "https://github.com/mikefarah/yq/releases/download/v4.11.0/yq_linux_amd64" -o /bin/yq && chmod +x /bin/yq
RUN wget -O kubectl https://storage.googleapis.com/kubernetes-release/release/v1.17.17/bin/linux/amd64/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/bin/kubectl


COPY test-connectivity-pod.yaml /test-connectivity-pod.yaml
COPY log.sh /log.sh
COPY functions.sh /functions.sh
COPY subSteps.sh /subSteps.sh
COPY script.sh /script.sh

ENTRYPOINT ["/bin/bash","-ec"]
CMD ["bash /script.sh"]