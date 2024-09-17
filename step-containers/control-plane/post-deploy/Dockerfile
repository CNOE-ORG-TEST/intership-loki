FROM public.ecr.aws/docker/library/python:3.9-alpine
RUN apk -uv add --no-cache jq openssl bash curl tree
RUN apk --no-cache add binutils wget unzip && wget https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -O /tmp/awscli-bundle.zip && unzip /tmp/awscli-bundle.zip -d /tmp && /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws && rm -rf /tmp/awscli-bundle.zip /tmp/awscli-bundle
RUN wget -O kubectl https://storage.googleapis.com/kubernetes-release/release/v1.24.16/bin/linux/amd64/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/bin/kubectl
RUN apk add --update python3
RUN apk add --no-cache python3 py3-pip 
RUN pip3 install boto3
RUN cp /usr/bin/python3 /usr/bin/python

COPY automation_conf.json /automation_conf.json
COPY log.sh /log.sh
COPY functions.sh /functions.sh
COPY update_platform_dynamodb.py /update_platform_dynamodb.py
COPY script.sh /script.sh
COPY subSteps.sh /subSteps.sh
COPY empty_kubeconfig.yaml /empty_kubeconfig.yaml
ENTRYPOINT ["/bin/bash","-ec"]
CMD ["bash /script.sh"]