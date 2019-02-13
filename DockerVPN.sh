#!/bin/bash
SCREEN_HEIGHT=20
SCREEN_WIDTH=70

SETUP_CONF=$PWD/install/setup.conf
INSTALL_LOG=DockerVPN.log

UNSAVED_CHANGES=false

NO_LOGGING=false

function die() {
    log "::: Exiting with code: $1"
    log ""
    log ""
    log ""

    if [[ $UNSAVED_CHANGES == true ]];then
         if (whiptail --title "DockerVPN Changes" --yesno "You have unsaved changes. Save them before you leave?\nYou can save it later but make sure to do it before you restart the container." ${SCREEN_HEIGHT} ${SCREEN_WIDTH}); then
             save_changes
         fi
    fi
    exit $1
}

function log() {
    [[ $NO_LOGGING == true ]] && return 0
    [[ $# == 0 ]] && while read data; do echo "$data" >> $INSTALL_LOG; done || echo $@ >> $INSTALL_LOG
}

function init_whiptail() {
    local size=$(stty size 2>/dev/null || echo 24 80)
    local rows=$(echo $size | awk '{print $1}')
    local cols=$(echo $size | awk '{print $2}')

    SCREEN_HEIGHT=$(( rows / 2 ))
    SCREEN_WIDTH=$(( cols / 2 ))

    SCREEN_HEIGHT=$(( SCREEN_HEIGHT < 20 ? 20 : SCREEN_HEIGHT ))
    SCREEN_WIDTH=$(( SCREEN_WIDTH < 70 ? 70 : SCREEN_WIDTH ))
}

function check_installed() {
    if [[ "$(docker images -q "$DOCKER_IMG_NAME" 2> /dev/null)" == "" ]]; then
        # Image does not exist
        log "::: Image does not exist"
        return 1
    else
        # Image exists
        log "::: Image exists skip installation"
        return 0
    fi
}

function check_running() {
    #Check if container is running
    [[ "$(docker inspect -f "{{.State.Running}}" "$DOCKER_CONT_NAME" 2> /dev/null)" != true ]] && return 1 || return 0
}

function install_image() {
    local msg="Do you want to install the DockerVPN image?\n\nThis can take a long time depending on your internet connection and your selected key size ($VPN_KEYSIZE)."
    if (whiptail --title "DockerVPN installation" --yesno "$msg" ${SCREEN_HEIGHT} ${SCREEN_WIDTH}); then
        LOG=$(docker build -t $DOCKER_IMG_NAME .)
        EXIT=$?
        log $LOG
        return $EXIT
    else
        die 0
    fi
}

function start_container() {
    if [ ! "$(docker ps -a | grep $DOCKER_CONT_NAME)" ];then
        [[ -d ${PWD}/ovpn ]] || mkdir ovpn
        LOG=$(docker run -d --name $DOCKER_CONT_NAME --sysctl net.ipv4.ip_forward=0 --cap-add=NET_ADMIN --device /dev/net/tun:/dev/net/tun -v ${PWD}/ovpn:/client-configs/files -p $VPN_PORT:$VPN_PORT/$VPN_PROTO $DOCKER_IMG_NAME:latest)
    else
        LOG=$(docker container start $DOCKER_CONT_NAME)
    fi
    EXIT=$?
    log $LOG
    return $EXIT
}

function stop_container() {
    if [[ $UNSAVED_CHANGES == true ]];then
         if (whiptail --title "DockerVPN Changes" --yesno "You have unsaved changes. Save them before you leave?\nYou can save it later but make sure to do it before you restart the container." ${SCREEN_HEIGHT} ${SCREEN_WIDTH}); then
             save_changes
         else
             UNSAVED_CHANGES=false
         fi
    fi
    LOG=$(docker container stop $DOCKER_CONT_NAME)
    EXIT=$?
    log $LOG
    return $EXIT
}

function get_msg() {
    check_running
    [[ $? -eq 0 ]] && echo "Docker container $DOCKER_CONT_NAME: Running\n\n$@" || echo "Docker container $DOCKER_CONT_NAME: Not running\n\n$@"
}

function create_client() {
    USER=$(whiptail --inputbox "Please choose a name for your client." ${SCREEN_HEIGHT} ${SCREEN_WIDTH} --title "DockerVPN Client" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    if [[ ! -n $USER ]];then
        whiptail --title "Invalid User" --msgbox "Your user can not be empty." ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
        return 1
    fi

    PASSWORD1=$(whiptail --passwordbox "Enter your password. Leave it empty for no password." ${SCREEN_HEIGHT} ${SCREEN_WIDTH} --title "DockerVPN Client" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1

    if [[ -n $PASSWORD1 ]];then
        PASSWORD2=$(whiptail --passwordbox "Verify your password" ${SCREEN_HEIGHT} ${SCREEN_WIDTH} --title "DockerVPN Client" 3>&1 1>&2 2>&3)
        [[ $? -ne 0 ]] && return 1

        if [[ $PASSWORD1 != $PASSWORD2 ]];then
            whiptail --title "Invalid Password" --msgbox "You second password didn't match the first one." ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
            return 1
        fi

        if [[ ${#PASSWORD1} -lt 6 || ${#PASSWORD1} -gt 1000 ]];then
            whiptail --title "Invalid Password" --msgbox "Your password must contain between 6 and 1000 characters." ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
            return 1
        fi
    fi

    [[ -n $PASSWORD ]] && LOG=$(docker exec $DOCKER_CONT_NAME ./setup.sh -c -n=$USER -p=$PASSWORD1) || LOG=$(docker exec $DOCKER_CONT_NAME ./setup.sh -c -n=$USER)

    EXIT=$?
    log $LOG
    [[ $EXIT -eq 0 ]] && UNSAVED_CHANGES=true
    [[ $EXIT -eq 0 ]] && res="Successfully created certificate." || res="Could not create certificate. See $INSTALL_LOG for more details."
    whiptail --title "DockerVPN Client" --msgbox "$res" ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
}

function revoke_client() {
    USER=$(whiptail --inputbox "Please choose a client you want to revoke." ${SCREEN_HEIGHT} ${SCREEN_WIDTH} --title "DockerVPN Client" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    if [[ ! -n $USER ]];then
        whiptail --title "Invalid User" --msgbox "Your client can not be empty." ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
        return 1
    fi

    LOG=$(docker exec $DOCKER_CONT_NAME ./setup.sh -r -n=$USER)
    EXIT=$?
    log $LOG
    [[ $EXIT -eq 0 ]] && UNSAVED_CHANGES=true
    [[ $EXIT -eq 0 ]] && res="Successfully revoked certificate." || res="Could not revoke certificate. See $INSTALL_LOG for more details."
    whiptail --title "DockerVPN Client" --msgbox "$res" ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
}

function list_clients() {
    LIST=$(docker exec dvpn-container ./setup.sh -l)
    log $LIST
    whiptail --title "DockerVPN Client" --msgbox "$LIST" ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
}

function save_changes() {
    LOG=$(docker commit $DOCKER_CONT_NAME $DOCKER_IMG_NAME:latest)
    EXIT=$?
    log $LOG
    [[ $EXIT -eq 0 ]] && UNSAVED_CHANGES=false
    [[ $EXIT -eq 0 ]] && res="Successfully saved changes." || res="Could not save changes. See $INSTALL_LOG for more details."
    whiptail --title "DockerVPN Client" --msgbox "$res" ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
}

function clean_up() {
    if (whiptail --title "DockerVPN installation" --yesno "Do you really want to delete your container and the image?" ${SCREEN_HEIGHT} ${SCREEN_WIDTH});then
        LOG=$(docker container rm -f $DOCKER_CONT_NAME)
        LOG+=$(docker image rm -f $DOCKER_IMG_NAME)
        log $LOG
        die 0
    fi
}

function main(){

    if [[ $1 == "--run-only" ]];then
        NO_LOGGING=true
        start_container
        exit 0
    fi

    datum=$(date +'%Y.%m.%d-%H:%M')
    log "   ########################"
    log "   ###" $datum "###"
    log "   ########################"

    log "::: Load configs..."
    source ${SETUP_CONF}

    log "::: Init DockerVPN..."
    init_whiptail
    check_installed
    if [[ $? -ne 0 ]];then
        log "::: Installing..."
        install_image
        SUCC=$?
        [[ $SUCC ]] && msg="Installation successfull" || msg="Installation failed. Please see the log file."
        log "::: $msg"
        whiptail --title "DockerVPN installation" --msgbox "$msg" ${SCREEN_HEIGHT} ${SCREEN_WIDTH}
        [[ $SUCC ]] || die 1
    fi

    while true; do
        local menu_msg="Please choose an option from the menu below:"
        CHOICE=$(whiptail --title "DockerVPN Menu" --menu "$(get_msg $menu_msg)" ${SCREEN_HEIGHT} ${SCREEN_WIDTH} 10 \
            "1)" "Start container." \
            "2)" "Stop container." \
            "3)" "Create client certificate." \
            "4)" "Revoke client certificate." \
            "5)" "List client certificates." \
            "6)" "Save changes." \
            "7)" "Clean up" \
            "0)" "Exit" 3>&2 2>&1 1>&3
        )
        [ $? -ne 0 ] && die 0

        check_running
        STATUS=$?
        case $CHOICE in
            "1)")
                log ":::Starting container..."
	        [[ $STATUS -ne 0 ]] && start_container || log "::: ERROR: Container already running."
            ;;
            "2)")
                log "::: Stopping container..."
                [[ $STATUS -eq 0 ]] && stop_container || log "::: ERROR: Container already stopped."
            ;;

            "3)")
                log "::: Creating client certificate..."
                [[ $STATUS -eq 0 ]] && create_client || log "::: ERROR: Container not running."
            ;;

            "4)")
                log "::: Revoking client certificate..."
	        [[ $STATUS -eq 0 ]] && revoke_client || log "::: ERROR: Container not running."
            ;;

            "5)")
                log "::: Listing clients..."
		[[ $STATUS -eq 0 ]] && list_clients || log "::: ERROR: Container not running."
            ;;

            "6)")
                log "::: Saving changes to docker image..."
		save_changes
            ;;

            "7)")
                log "::: Cleaning up container and images..."
		clean_up
            ;;

            "0)") die 0
            ;;
        esac
    done
    die 0
}

main $@
