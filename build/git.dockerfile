FROM centos:7 as build

RUN yum install -y gcc make autoconf && \
    yum install -y curl-devel expat-devel gettext-devel openssl-devel perl-devel zlib-devel perl-ExtUtils-MakeMaker

RUN curl -L -o /usr/local/src/git-2.29.2.tar.xz https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.29.2.tar.xz && \
    tar xvf /usr/local/src/git-2.29.2.tar.xz -C /usr/local/src/

ARG homedir=/home/user

RUN cd /usr/local/src/git-2.29.2 && \
    make -j $(nproc) prefix=${homedir}/.local all && \
    make -j $(nproc) prefix=${homedir}/.local install

RUN cd ${homedir} && \
    tar cJvf /git.tar.xz .local

FROM scratch

COPY --from=build /git.tar.xz /