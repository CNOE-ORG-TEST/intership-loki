FROM public.ecr.aws/docker/library/python:3.9-alpine
RUN apk -uv add --no-cache jq openssl bash curl git unzip
RUN apk add --update make
RUN apk add bind-tools
RUN apk add --update coreutils
RUN apk add --update python3
#RUN apk add --no-cache python3 py3-pip
#RUN pip3 install requests argparse pytz
#RUN cp /usr/bin/python3 /usr/bin/python
RUN apk --no-cache add binutils wget unzip && wget https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -O /tmp/awscli-bundle.zip && unzip /tmp/awscli-bundle.zip -d /tmp && /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws && rm -rf /tmp/awscli-bundle.zip /tmp/awscli-bundle

RUN curl -L "https://github.com/mikefarah/yq/releases/download/v4.11.0/yq_linux_amd64" -o /bin/yq && chmod +x /bin/yq
RUN curl -L "https://github.com/mikefarah/yq/releases/download/v4.30.4/yq_linux_amd64" -o /bin/yq4_30_4 && chmod +x /bin/yq4_30_4
RUN wget -O kubectl https://storage.googleapis.com/kubernetes-release/release/v1.25.16/bin/linux/amd64/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/bin/kubectl

RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh

COPY log.sh /log.sh
COPY cluster-autoscaler-priority-expander.yaml /cluster-autoscaler-priority-expander.yaml
COPY vpa-coredns.yaml /vpa-coredns.yaml
COPY functions.sh /functions.sh
COPY script.sh /script.sh
COPY setHelmVariables.sh /setHelmVariables.sh
COPY subSteps.sh /subSteps.sh

ENTRYPOINT ["/bin/bash","-ec"]
CMD ["bash /script.sh"]