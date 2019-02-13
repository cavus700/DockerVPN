# DockerVPN

Automatically host an OpenVPN server inside a docker container based on Debian 9.

## Requirements

- Docker
Make sure you have docker installed and accessible from the command line. To test it open a terminal and write `docker -v` otherwise have a look at the [Docker installation](https://docs.docker.com/v17.12/install/) 

## Installation

1. Download the repository.
2. Adapt the *setup.conf* file to your needs. 
  - ### Recommended Configurations
    - #### Certificate Configurations
    - CA_COUNTRY="DE" (Change it to your country code)
    - CA_PROVINCE="Germany" (Change it to your country)
    - CA_CITY="Dortmund" (Change it to your city)
    - CA_ORG="MyOrg" (Change it to your organization)
    - CA_MAIL="max.mustermann@tu-dortmund.de" (Change it to your mail)

    - #### VPN Configurations
    - VPN_KEYSIZE=2048  (1024:Should only be used for testing to make key generation faster. 2048:Good choice for a proper encryption. 4096:Really strong encryption which takes a long time an generation)
    - VPN_PROTO=udp (udp:Default choice. tcp:Implemented but not testes. Use **lowercase** for this option)
    - VPN_PORT=1194 (The port for your OpenVPN inside the container and your host)
    - VPN_DNS=DVPNHOST (DNS of your docker host or a static ip)
  - You can change the other option as well but it is not recommended and tested.
3. Make sure you have execution right for the DockerVPN.sh or give it the rights `chmod +x <USER>:<USER> DockerVPN.sh`
4. Run `./DockerVPN.sh` it will guide you through the installation.

## Supported OS
I have only tested it on **Debain 9 (stretch)** but it should not be a problem to run it on other linux distributions as long as you have a working docker installation, the [whiptail package](https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Whiptail) and the */den/net/tun* device. It is mapped inside the docker container because it is required by OpenVPN.

For an installtion on **Winodws** you can have a look at [this](https://openvpn.net/community-resources/the-standard-install-file-included-in-the-source-distribution/) to install the TUN driver and you have to run the docker commands manually.

## Docker Commands
- Exchange the variables by the values from your *setup.conf*
- Build the image: `docker build -t $DOCKER_IMG_NAME .`
- Run the Container: `docker run -d --name $DOCKER_CONT_NAME --sysctl net.ipv4.ip_forward=0 --cap-add=NET_ADMIN --device /dev/net/tun:/dev/net/tun -v ${PWD}/ovpn:/client-configs/files -p $VPN_PORT:$VPN_PORT/$VPN_PROTO $DOCKER_IMG_NAME:latest`
- Start/Stop the container: `docker container (start/stop) $DOCKER_CONT_NAME`
- Create a client: `docker exec $DOCKER_CONT_NAME ./setup.sh -c -n=$USER`
- Create a client with a password: `docker exec $DOCKER_CONT_NAME ./setup.sh -c -n=$USER -p=$PASSWORD1`
- Revoke a client: `docker exec $DOCKER_CONT_NAME ./setup.sh -r -n=$USER`
- List all clients: `docker exec $DOCKER_CONT_NAME ./setup.sh -l`
