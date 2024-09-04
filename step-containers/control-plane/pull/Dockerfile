FROM public.ecr.aws/docker/library/python:3.9-alpine
RUN apk -uv add --no-cache jq openssl git bash openjdk8-jre curl
RUN apk --no-cache add binutils wget unzip && wget https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -O /tmp/awscli-bundle.zip && unzip /tmp/awscli-bundle.zip -d /tmp && /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws && rm -rf /tmp/awscli-bundle.zip /tmp/awscli-bundle

COPY automation_conf.json /automation_conf.json
COPY log.sh /log.sh
COPY cloudformation_for_role.yaml /cloudformation_for_role.yaml
COPY functions.sh /functions.sh
COPY script.sh /script.sh

ENTRYPOINT ["/bin/bash","-ec"]
CMD ["bash /script.sh"]