FROM public.ecr.aws/docker/library/python:3.9-alpine
RUN apk -uv add --no-cache jq git bash openssl curl
RUN apk --no-cache add binutils wget unzip && wget https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -O /tmp/awscli-bundle.zip && unzip /tmp/awscli-bundle.zip -d /tmp && /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws && rm -rf /tmp/awscli-bundle.zip /tmp/awscli-bundle

COPY log.sh /log.sh
COPY waiting_logs.py /waiting_logs.py
COPY script.sh /script.sh
COPY subSteps.sh /subSteps.sh

ENTRYPOINT ["/bin/bash","-ec"]
CMD ["bash /script.sh"]