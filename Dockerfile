FROM ubuntu:18.04 AS core

ENV DEBIAN_FRONTEND="noninteractive"

# Install git, SSH, and other utilities
RUN set -ex \
    && echo 'Acquire::CompressionTypes::Order:: "gz";' > /etc/apt/apt.conf.d/99use-gzip-compression \
    && apt-get update \
    && apt install -y apt-transport-https gnupg ca-certificates apt-utils \
    && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
    && echo "deb https://download.mono-project.com/repo/ubuntu stable-bionic main" | tee /etc/apt/sources.list.d/mono-official-stable.list \
    && apt-get install software-properties-common -y --no-install-recommends \
    && apt-add-repository -y ppa:git-core/ppa \
    && apt-get update \
    && apt-get install git=1:2.* -y --no-install-recommends \
    && git version \
    && apt-get install -y --no-install-recommends openssh-client \
    && mkdir ~/.ssh \
    && touch ~/.ssh/known_hosts \
    && ssh-keyscan -t rsa,dsa -H github.com >> ~/.ssh/known_hosts \
    && ssh-keyscan -t rsa,dsa -H bitbucket.org >> ~/.ssh/known_hosts \
    && chmod 600 ~/.ssh/known_hosts \
    && apt-get install -y --no-install-recommends \
          apt-utils asciidoc autoconf automake build-essential bzip2 \
          bzr curl cvs cvsps dirmngr docbook-xml docbook-xsl dpkg-dev \
          e2fsprogs expect fakeroot file g++ gcc gettext gettext-base \
          git groff gzip imagemagick iptables jq less libapr1 libaprutil1 \
          libargon2-0-dev libbz2-dev libc6-dev libcurl4-openssl-dev \
          libdb-dev libdbd-sqlite3-perl libdbi-perl libdpkg-perl \
          libedit-dev liberror-perl libevent-dev libffi-dev libgeoip-dev \
          libglib2.0-dev libhttp-date-perl libio-pty-perl libjpeg-dev \
          libkrb5-dev liblzma-dev libmagickcore-dev libmagickwand-dev \
          libmysqlclient-dev libncurses5-dev libncursesw5-dev libonig-dev \
          libpq-dev libreadline-dev libserf-1-1 libsqlite3-dev libssl-dev \
          libsvn1 libsvn-perl libtcl8.6 libtidy-dev libtimedate-perl \
          libtool libwebp-dev libxml2-dev libxml2-utils libxslt1-dev \
          libyaml-dev libyaml-perl llvm locales make mercurial mlocate mono-devel \
          netbase openssl patch pkg-config procps python-bzrlib \
          python-configobj python-openssl rsync sgml-base sgml-data subversion \
          tar tcl tcl8.6 tk tk-dev unzip wget xfsprogs xml-core xmlto xsltproc \
          libzip4 libzip-dev vim xvfb xz-utils zip zlib1g-dev netcat \
          default-mysql-client libldap2-dev libsasl2-dev dnsutils libraw-dev \
          libaio1 libaio-dev \
    && rm -rf /var/lib/apt/lists/*

RUN useradd codebuild-user

#=======================End of layer: core  =================

FROM core AS tools

# Install GitVersion
ENV GITVERSION_VERSION="5.1.2"
RUN set -ex \
    && wget -nv https://github.com/GitTools/GitVersion/archive/${GITVERSION_VERSION}.zip -O /tmp/GitVersion_${GITVERSION_VERSION}.zip \
    && mkdir -p /usr/local/GitVersion_${GITVERSION_VERSION} \
    && unzip /tmp/GitVersion_${GITVERSION_VERSION}.zip -d /usr/local/GitVersion_${GITVERSION_VERSION} \
    && rm /tmp/GitVersion_${GITVERSION_VERSION}.zip \
    && echo "mono /usr/local/GitVersion_${GITVERSION_VERSION}/GitVersion.exe \$@" >> /usr/local/bin/gitversion \
    && chmod +x /usr/local/bin/gitversion \
    && rm -rf /tmp/*

# Install stunnel
RUN set -ex \
   && STUNNEL_VERSION=5.56 \
   && STUNNEL_TAR=stunnel-$STUNNEL_VERSION.tar.gz \
   && STUNNEL_SHA256="7384bfb356b9a89ddfee70b5ca494d187605bb516b4fff597e167f97e2236b22" \
   && curl -o $STUNNEL_TAR https://www.usenix.org.uk/mirrors/stunnel/archive/5.x/$STUNNEL_TAR \
   && echo "$STUNNEL_SHA256 $STUNNEL_TAR" | sha256sum -c - \
   && tar xvfz $STUNNEL_TAR \
   && cd stunnel-$STUNNEL_VERSION \
   && ./configure \
   && make -j4 \
   && make install \
   && openssl genrsa -out key.pem 2048 \
   && openssl req -new -x509 -key key.pem -out cert.pem -days 1095 -subj "/C=US/ST=Washington/L=Seattle/O=Amazon/OU=Codebuild/CN=codebuild.amazon.com" \
   && cat key.pem cert.pem >> /usr/local/etc/stunnel/stunnel.pem \
   && cd .. ; rm -rf stunnel-${STUNNEL_VERSION}*

# AWS Tools
# https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_CLI_installation.html
RUN curl -sS -o /usr/local/bin/aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/aws-iam-authenticator \
    && curl -sS -o /usr/local/bin/kubectl https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/kubectl \
    && curl -sS -o /usr/local/bin/ecs-cli https://s3.amazonaws.com/amazon-ecs-cli/ecs-cli-linux-amd64-latest \
    && chmod +x /usr/local/bin/kubectl /usr/local/bin/aws-iam-authenticator /usr/local/bin/ecs-cli

# Configure SSM
RUN set -ex \
    && mkdir /tmp/ssm \
    && cd /tmp/ssm \
    && wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb \
    && dpkg -i amazon-ssm-agent.deb

# Install env tools for runtimes

#nodejs
ENV SRC_DIR="/usr/src"
ENV N_SRC_DIR="$SRC_DIR/n"
RUN git clone https://github.com/tj/n $N_SRC_DIR \
     && cd $N_SRC_DIR && make install 

#python
RUN curl https://pyenv.run | bash
ENV PATH="/root/.pyenv/shims:/root/.pyenv/bin:$PATH"

#=======================End of layer: tools  =================
FROM tools AS runtimes

#****************      NODEJS     ****************************************************

ENV NODE_12_VERSION="12.16.1" \
    NODE_10_VERSION="10.19.0"

RUN     n $NODE_10_VERSION && npm install --save-dev -g -f grunt && npm install --save-dev -g -f grunt-cli && npm install --save-dev -g -f webpack \
     && n $NODE_12_VERSION && npm install --save-dev -g -f grunt && npm install --save-dev -g -f grunt-cli && npm install --save-dev -g -f webpack \
     && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
     && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
     && apt-get update && apt-get install -y --no-install-recommends yarn \
     && yarn --version \
     && cd / && rm -rf $N_SRC_DIR;rm -rf /tmp/*

#****************      END NODEJS     ****************************************************

#**************** PYTHON *****************************************************
ENV PYTHON_38_VERSION="3.8.2" \
    PYTHON_37_VERSION="3.7.7"

ENV PYTHON_PIP_VERSION=20.0.2 \
    CONFIGURE_OPTS="--enable-shared --enable-loadable-sqlite-extensions"

RUN   pyenv install $PYTHON_37_VERSION; rm -rf /tmp/*
RUN   pyenv global  $PYTHON_37_VERSION
RUN set -ex \
    && pip3 install --no-cache-dir --upgrade --force-reinstall "pip==$PYTHON_PIP_VERSION" \
    && pip3 install --no-cache-dir --upgrade "PyYAML==5.1.2" \
    && pip3 install --no-cache-dir --upgrade setuptools wheel aws-sam-cli awscli boto3 pipenv virtualenv


RUN   pyenv install $PYTHON_38_VERSION; rm -rf /tmp/*
RUN   pyenv global  $PYTHON_38_VERSION
RUN set -ex \
    && pip3 install --no-cache-dir --upgrade --force-reinstall "pip==$PYTHON_PIP_VERSION" \
    && pip3 install --no-cache-dir --upgrade "PyYAML==5.1.2" \
    && pip3 install --no-cache-dir --upgrade setuptools wheel aws-sam-cli awscli boto3 pipenv virtualenv

#**************** END PYTHON *****************************************************


#=======================End of layer: runtimes  =================

FROM runtimes AS runtimes_n_corretto

#****************        DOCKER    *********************************************
ENV DOCKER_BUCKET="download.docker.com" \
    DOCKER_CHANNEL="stable" \
    DIND_COMMIT="3b5fac462d21ca164b3778647420016315289034" \
    DOCKER_COMPOSE_VERSION="1.24.0" \
    SRC_DIR="/usr/src"

ENV DOCKER_SHA256="c3c8833e227b61fe6ce0bc5c17f97fa547035bef4ef17cf6601f30b0f20f4ce5"
ENV DOCKER_VERSION="19.03.3"

# Install Docker
RUN set -ex \
    && curl -fSL "https://${DOCKER_BUCKET}/linux/static/${DOCKER_CHANNEL}/x86_64/docker-${DOCKER_VERSION}.tgz" -o docker.tgz \
    && echo "${DOCKER_SHA256} *docker.tgz" | sha256sum -c - \
    && tar --extract --file docker.tgz --strip-components 1  --directory /usr/local/bin/ \
    && rm docker.tgz \
    && docker -v \
# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
    && addgroup dockremap \
    && useradd -g dockremap dockremap \
    && echo 'dockremap:165536:65536' >> /etc/subuid \
    && echo 'dockremap:165536:65536' >> /etc/subgid \
    && wget -nv "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind" -O /usr/local/bin/dind \
    && curl -L https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-Linux-x86_64 > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/dind /usr/local/bin/docker-compose \
# Ensure docker-compose works
    && docker-compose version

VOLUME /var/lib/docker
#*********************** END  DOCKER  ****************************

FROM runtimes_n_corretto AS std_v4

# Activate runtime versions specific to image version.
RUN n $NODE_12_VERSION
RUN pyenv  global $PYTHON_38_VERSION

# Configure SSH
COPY ssh_config /root/.ssh/config
COPY runtimes.yml /codebuild/image/config/runtimes.yml
COPY dockerd-entrypoint.sh /usr/local/bin/
COPY amazon-ssm-agent.json          /etc/amazon/ssm/

#=========== mssql client ==========
RUN curl -s https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
  && curl -s https://packages.microsoft.com/config/debian/9/prod.list > /etc/apt/sources.list.d/mssql-release.list \
  && apt-get -qq update \
  && ACCEPT_EULA=Y apt-get -qq install msodbcsql17 2>&1 >/dev/null \
  && apt-get install -qq unixodbc-dev 2>&1 >/dev/null

ENTRYPOINT ["dockerd-entrypoint.sh"]

#=======================END of STD:4.0  =================
