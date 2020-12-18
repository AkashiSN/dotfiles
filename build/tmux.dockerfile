FROM centos:7 as build

RUN yum install -y gcc make autoconf && \
    yum install -y curl-devel openssl-devel

RUN curl -L -o /usr/local/src/libevent-2.1.12-stable.tar.gz https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz && \
    tar xvf /usr/local/src/libevent-2.1.12-stable.tar.gz -C /usr/local/src/

RUN curl -L -o /usr/local/src/ncurses-6.2.tar.gz http://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.2.tar.gz && \
    tar xvf /usr/local/src/ncurses-6.2.tar.gz -C /usr/local/src/

RUN curl -L -o /usr/local/src/tmux-3.1c.tar.gz https://github.com/tmux/tmux/releases/download/3.1c/tmux-3.1c.tar.gz && \
    tar xvf /usr/local/src/tmux-3.1c.tar.gz -C /usr/local/src/

ARG homedir=/home/user

RUN cd /usr/local/src/libevent-2.1.12-stable && \
    ./configure --prefix=${homedir}/.local && \
    make -j $(nproc) && \
    make -j $(nproc) install

RUN cd /usr/local/src/ncurses-6.2 && \
    ./configure --enable-pc-files --prefix=${homedir}/.local --with-pkg-config-libdir=${homedir}/.local/lib/pkgconfig --with-termlib && \
    make -j $(nproc) && \
    make -j $(nproc) install

RUN cd /usr/local/src/tmux-3.1c && \
    PKG_CONFIG_PATH=${homedir}/.local/lib/pkgconfig ./configure --prefix=${homedir}/.local LDFLAGS="-L${homedir}/.local/lib" CFLAGS="-I${homedir}/.local/include" && \
    make -j $(nproc) && \
    make -j $(nproc) install

RUN cd ${homedir} && \
    tar cJvf /tmux.tar.xz .local

FROM scratch

COPY --from=build /tmux.tar.xz /
