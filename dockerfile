FROM debian:stretch

#Install required packages
ENV DEBIAN_FRONTEND=noninteractive

#Copy all files
RUN mkdir /install
ADD ./install/setup.sh /install
ADD ./install/setup.conf /install

WORKDIR /install

#Start installation of vpn server
RUN ./setup.sh --setup

ENTRYPOINT ["/usr/sbin/openvpn", "--cd", "/etc/openvpn", "--config", "/etc/openvpn/server.conf"]
