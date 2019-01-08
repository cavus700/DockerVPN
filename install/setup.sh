#!/usr/bin/env bash
DIR_CLIENT_CERT=/client-configs
KEY_DIR=$DIR_CLIENT_CERT/keys
OUTPUT_DIR=$DIR_CLIENT_CERT/files
BASE_CONFIG=$DIR_CLIENT_CERT/base.conf

INSTALL_TMP="/tmp/install"
WORKDIR=$PWD
SETUP_CONF=$PWD/setup.conf

EASY_RSA_VER=3.0.4
EASY_RSA_CA=$WORKDIR/ca/EasyRSA-$EASY_RSA_VER
EASY_RSA_SRV=$WORKDIR/srv/EasyRSA-$EASY_RSA_VER

function download_easy_rsa() {
    if [[ ! -d ${INSTALL_TMP} ]]; then
        mkdir -p $INSTALL_TMP
    fi
    echo "::: Download easy-rsa version $EASY_RSA_VER"
    wget -q -P $INSTALL_TMP "https://github.com/OpenVPN/easy-rsa/releases/download/v$EASY_RSA_VER/EasyRSA-$EASY_RSA_VER.tgz"
    cd $INSTALL_TMP
    tar xf EasyRSA-$EASY_RSA_VER.tgz

    #Init the ca host folder
    if [[ -d $EASY_RSA_CA ]];then
        rm -r $EASY_RSA_CA
    fi
    mkdir -p $EASY_RSA_CA

    #Init the server folder
    if [[ -d $EASY_RSA_SRV ]];then
        rm -r $EASY_RSA_SRV
    fi
    mkdir -p $EASY_RSA_SRV

    cp -R EasyRSA-$EASY_RSA_VER/* $EASY_RSA_CA
    cp -R EasyRSA-$EASY_RSA_VER/* $EASY_RSA_SRV

    #Cleanup
    rm -r EasyRSA-$EASY_RSA_VER
}

function generate_client_cert() {
    if [[ ! -d ${DIR_CLIENT_CERT} ]]; then
        mkdir -p $KEY_DIR
        mkdir -p $OUTPUT_DIR
        chmod -R 700 $DIR_CLIENT_CERT
    fi

    if [[ ! -f $KEY_DIR/ta.key ]]; then
        cp /etc/openvpn/ta.key $KEY_DIR
    fi

    if [[ ! -f $KEY_DIR/ca.crt ]]; then
        cp /etc/openvpn/ca.crt $KEY_DIR
    fi

    echo "::: Generating client cert..."
    cd $EASY_RSA_SRV
    if [[ $# == 1 ]];then
        ./easyrsa gen-req $1 nopass batch
    else
        expect << EOF
        set timeout -1
        spawn ./easyrsa gen-req $1 batch
        expect "Enter PEM pass phrase" { send -- "${2}\r" }
        expect "Verifying - Enter PEM pass phrase" { send -- "${2}\r" }
        expect eof
EOF
    fi

    cp pki/private/$1.key $KEY_DIR

    cd $EASY_RSA_CA
    ./easyrsa import-req $EASY_RSA_SRV/pki/reqs/$1.req $1
    ./easyrsa sign-req client $1
    cp pki/issued/$1.crt $KEY_DIR

    echo "::: Generation successfull!"

    echo "::: Generating .ovpn file for $1"

    cat ${BASE_CONFIG} \
        <(echo -e '<ca>') \
        ${KEY_DIR}/ca.crt \
        <(echo -e '</ca>\n<cert>') \
        ${KEY_DIR}/${1}.crt \
        <(echo -e '</cert>\n<key>') \
        ${KEY_DIR}/${1}.key \
        <(echo -e '</key>\n<tls-auth>') \
        ${KEY_DIR}/ta.key \
        <(echo -e '</tls-auth>') \
        > ${OUTPUT_DIR}/${1}.ovpn

    sed -i 's/#.*//g' ${OUTPUT_DIR}/${1}.ovpn
    sed -i 's/;.*//g' ${OUTPUT_DIR}/${1}.ovpn
    sed -i '/^[[:space:]]*$/d' ${OUTPUT_DIR}/${1}.ovpn

    echo "::: Generation complete!"
}

function init_client_configs() {
    mkdir -p $DIR_CLIENT_CERT/files
    mkdir -p $DIR_CLIENT_CERT/keys
    cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf $DIR_CLIENT_CERT/base.conf
    cd $DIR_CLIENT_CERT

    echo "::: Setting server and port for client to ${VPN_DNS}:${VPN_PORT}"
    sed -i "s/remote.*1194/remote ${VPN_DNS} ${VPN_PORT}/" base.conf

    echo "::: Setting client protocol to ${VPN_PROTO}"
    if [[ ${VPN_PROTO} == tcp ]];then
        sed -i 's/proto udp/;proto udp/g' base.conf
        sed -i 's/;proto tcp/proto tcp/g' base.conf
    fi

    sed -i 's/;user\s*nobody/user nobody/g' base.conf
    sed -i 's/;group nogroup/group nogroup/g' base.conf

    sed -i 's/ca\s*ca.crt/#ca ca.crt/g' base.conf
    sed -i 's/cert\s*client.cert/#cert client.cert/g' base.conf
    sed -i 's/key\s*client.cert/#key client.cert/g' base.conf

    sed -i 's/#tls-auth\s*ta.key\s*1/tls-auth ta.key 1/g' base.conf

    awk '/cipher AES-256-CBC/ { print; print "auth SHA256"; next }1' base.conf > base.tmp.conf
    rm base.conf
    mv base.tmp.conf base.conf

    echo "key-direction 1" >> base.conf
    echo "" >> base.conf
    echo "# script-security 2" >> base.conf
    echo "# up /etc/openvpn/update-resolv-conf" >> base.conf
    echo "# down /etc/openvpn/update-resolv-conf" >> base.conf

    echo "::: Creating client generation script..."
    if [[ -f gen_client_cert.sh ]];then
        echo "::: Cleaning up old script"
        rm gen_client_cert.sh
    fi

    touch gen_client_cert.sh
    chmod +x gen_client_cert.sh
    cat $WORKDIR/gen_client_cert.sh > gen_client_cert.sh
}

function help() {
    echo "This script installs the OpenVPN server and creates certificates for the clients."
    echo "setup.sh [mode] [option]"
    echo "    mode: [-s | --setup]  Installs the server."
    echo ""
    echo "          [-c | --client] Generate a client certificate"
    echo "          option: [-n | --name]=NAME"
    echo "                  [-p | --password]=PASSWORD"
    echo ""
    echo "Example: ./setup.sh -s -c -n=User1 -p=Password"
    echo "         Install the server and generate a certificate for User1 with password Password"
}

function main() {
    #Format and check parameters
    VPN_PROTO=$(echo "$VPN_PROTO" | awk '{print tolower($0)}')
    local INSTALL=false
    local GEN_CLIENT=false

    # Check arguments
    for var in "$@"; do
        case "$var" in
            -s|--setup)
                INSTALL=true;;
            -c|--client)
                GEN_CLIENT=true;;
        esac
    done

    if [[ ${INSTALL} == false && ${GEN_CLIENT} == false ]];then
        echo "To start the setup script provide at least one parameter: [--install] [--gen-client]"
        exit 1
    fi
    if [[ ${INSTALL} == true ]]; then
        source ${SETUP_CONF}

        if [[ ${VPN_DNS} == false ]];then
            echo "::: Error: You have to set a public dns name for your server."
            exit 1
        fi

        echo "::: Installing OpenVPN packages..."
        apt-get update -qq
        apt-get install -qq -y openvpn wget expect

        download_easy_rsa


        echo "::: Initialise the ca host"
        cd $EASY_RSA_CA

        cp vars.example vars

        sed -i 's/#set_var\s*EASYRSA_REQ_COUNTRY\s*"US"/set_var EASYRSA_REQ_COUNTRY    "$CA_COUNTRY"/g' vars
        sed -i 's/#set_var\s*EASYRSA_REQ_PROVINCE\s*"California"/set_var EASYRSA_REQ_PROVINCE   "$CA_PROVINCE"/g' vars
        sed -i 's/#set_var\s*EASYRSA_REQ_CITY\s*"San Francisco"/set_var EASYRSA_REQ_CITY       "$CA_CITY"/g' vars
        sed -i 's/#set_var\s*EASYRSA_REQ_ORG\s*"Copyleft Certificate Co"/set_var EASYRSA_REQ_ORG        "$CA_ORG"/g' vars
        sed -i 's/#set_var\s*EASYRSA_REQ_EMAIL\s*"me@example.net"/set_var EASYRSA_REQ_EMAIL      "$CA_MAIL"/g' vars
        sed -i 's/#set_var\s*EASYRSA_REQ_OU\s*"My Organizational Unit"/set_var EASYRSA_REQ_OU         "$CA_OU"/g' vars
        echo 'set_var EASYRSA_BATCH       "yes"' >> vars

        ./easyrsa init-pki

        echo "::: Creating certificate on ca host..."
        ./easyrsa build-ca nopass


        echo "::: Initialize the server"
        cd $EASY_RSA_SRV
        ./easyrsa init-pki

        echo "::: Generating server keys"
        ./easyrsa gen-req $HOST_NAME nopass batch
        #openssl version
        #openssl req -utf8 -new -newkey rsa:$VPN_KEYSIZE -keyout "$EASY_RSA_SRV/pki/private/$HOST_NAME.key" -out "$EASY_RSA_SRV/pki/reqs/$HOST_NAME.req" -batch -verbose

        echo "::: Copy server key"
        cp pki/private/$HOST_NAME.key /etc/openvpn

        echo "::: Importing and signing certificate"
        cd $EASY_RSA_CA
        ./easyrsa import-req $EASY_RSA_SRV/pki/reqs/$HOST_NAME.req $HOST_NAME
        ./easyrsa sign-req server $HOST_NAME

        echo "::: Copy certificate to OpenVPN"
        cp pki/issued/$HOST_NAME.crt /etc/openvpn
        cp pki/ca.crt /etc/openvpn

        echo "::: Generating key with size $VPN_KEYSIZE. This can take a while."
        cd $EASY_RSA_SRV
        ./easyrsa --keysize=$VPN_KEYSIZE gen-dh
        openvpn --genkey --secret ta.key

        cp ta.key /etc/openvpn/
        cp pki/dh.pem /etc/openvpn/


        #Copy the server configuration
        cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/
        gzip -d /etc/openvpn/server.conf.gz

        #Adapt the server.conf
        cd /etc/openvpn
        line=$(awk '/tls-auth/{ print NR; exit }' server.conf)
        sed -i "${line}s/.*/tls-auth ta.key 0/" server.conf
        awk '/tls-auth/ { print; print "key-direction 0"; next }1' server.conf > server.tmp.conf
        rm server.conf
        mv server.tmp.conf server.conf

        awk '/cipher AES-256-CBC/ { print; print "auth SHA256"; next }1' server.conf > server.tmp.conf
        rm server.conf
        mv server.tmp.conf server.conf

        sed -i 's/dh\s*dh2048.pem/dh dh.pem/g' server.conf
        sed -i 's/;user\s*nobody/user nobody/g' server.conf
        sed -i 's/;group\s*nogroup/group nogroup/g' server.conf
        sed -i "s/cert\s*server.crt/cert $HOST_NAME.crt/g" server.conf
        sed -i "s/key\s*server.key/key $HOST_NAME.key/g" server.conf

        if [[ ${LOGGING} == true ]];then
            sed -i "s@;log\s.*@log $LOG_DIR@g" server.conf
        fi

        #User defined adaptions to server conf
        #Check for port change
        if [[ ${VPN_PORT} == 1194 ]];then
            echo "::: Using default port 1194"
        else
            echo "::: Changing port to $VPN_PORT"
            sed -i "s/port\s*1194/port ${VPN_PORT}/g" server.conf
        fi

        #Check for porotocol change
        if [[ ${VPN_PROTO} == udp ]];then
            echo "::: Use default udp protocol"
        else
            sed -i 's/proto udp/;proto udp/g' server.conf
            sed -i 's/;proto tcp/proto tcp/g' server.conf
            sed -i 's/explicit-exit-notify 1/explicit-exit-notify 0/g' server.conf
        fi

        init_client_configs
    fi

    if [[ ${GEN_CLIENT} == true ]]; then
        NAME=false
        PASS=false

        for i in "$@"
        do
        case $i in
            -n=*|--name=*)
            NAME="${i#*=}"
            shift # past argument=value
            ;;
            -p=*|--password=*)
            PASS="${i#*=}"
            shift # past argument=value
            ;;
            *)
            shift      # unknown option
            ;;
        esac
        done

        if [[ ${NAME} == false ]];then
            echo ":::Error: You have to provide a username."
            help
            exit 1
        else
            if [[ ${PASS} == false ]];then
                echo "::: Generating client certificate without a password."
                generate_client_cert $NAME
            elif [[ ${#PASS} -lt 6 || ${#PASS} -gt 1000 ]];then
                echo "::: Error: Your password must contain between 6 and 1000 characters."
                exit 1
            else
                #Escape chars in PASS
                PASS=$(echo -n ${PASS} | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g' -e 's/\$/\\\$/g' -e 's/!/\\!/g' -e 's/\./\\\./g' -e "s/'/\\\'/g" -e 's/"/\\"/g' -e 's/\*/\\\*/g' -e 's/\@/\\\@/g' -e 's/\#/\\\#/g' -e 's/£/\\£/g' -e 's/%/\\%/g' -e 's/\^/\\\^/g' -e 's/\&/\\\&/g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/-/\\-/g' -e 's/_/\\_/g' -e 's/\+/\\\+/g' -e 's/=/\\=/g' -e 's/\[/\\\[/g' -e 's/\]/\\\]/g' -e 's/;/\\;/g' -e 's/:/\\:/g' -e 's/|/\\|/g' -e 's/</\\</g' -e 's/>/\\>/g' -e 's/,/\\,/g' -e 's/?/\\?/g' -e 's/~/\\~/g' -e 's/{/\\{/g' -e 's/}/\\}/g')

                generate_client_cert $NAME $PASS
            fi
        fi
    fi
}

main $@
