FROM centos:7 as build

RUN yum install -y gcc make autoconf && \
    yum install -y ncurses-devel

RUN curl -L -o /usr/local/src/zsh-5.8.tar.xz https://jaist.dl.sourceforge.net/project/zsh/zsh/5.8/zsh-5.8.tar.xz && \
    tar xvf /usr/local/src/zsh-5.8.tar.xz -C /usr/local/src/

ARG homedir=/home/user

RUN cd /usr/local/src/zsh-5.8 && \
    ./Util/preconfig && \
    ./configure --prefix=${homedir}/.local --enable-locale --enable-multibyte --with-tcsetpgrp && \
    make clean && \
    make -j $(nproc) && \
    make -j $(nproc) install

RUN cd ${homedir} && \
    tar cJvf /zsh.tar.xz .local

FROM scratch

COPY --from=build /zsh.tar.xz /
