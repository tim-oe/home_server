FROM ubuntu:22.04

LABEL maintainer="tcronin"
LABEL version="0.1"
LABEL description="utility image doing maintainance and troubleshooting"

SHELL ["/bin/bash", "-c"]

RUN apt update
# install base deps
RUN apt install -y bash cifs-utils sudo curl nano gnupg2 bzip2 zip unzip

RUN mkdir -p /mnt/clones

RUN echo '//tec-nas/clones /mnt/clones cifs guest,iocharset=utf8,file_mode=0777,dir_mode=0777,noperm 0 0' > /etc/fstab

#ENV PATH=$PATH:

# http port
#EXPOSE 8080

# provides debugging
#ENTRYPOINT ["/opt/tomcat/bin/run.sh"]
