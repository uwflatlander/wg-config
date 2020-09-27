#!/usr/bin/env bash

cd `dirname ${BASH_SOURCE[0]}`

. wg.def
CLIENT_TPL_FILE=client.conf.tpl
SERVER_TPL_FILE=server.conf.tpl
SAVED_FILE=.saved
AVAILABLE_IP_FILE=.available_ip
WG_TMP_CONF_FILE=.$_INTERFACE.conf
WG_CONF_FILE="server/$_INTERFACE.conf"

dec2ip4() {
    local delim=''
    local ip dec=$@
    for e in {3..0}
    do
        ((octet = dec / (256 ** e) ))
        ((dec -= octet * 256 ** e))
        ip+=$delim$octet
        delim=.
    done
    printf '%s\n' "$ip"
}

# Sets server VPN address & builds IP cache if not present
generate_cidr_ip4_file_if() {
    local cidr=${_VPN_NET4}
    local ip mask a b c d

    IFS=$'/' read ip mask <<< "$cidr"
    IFS=. read -r a b c d <<< "$ip"
    local beg=$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))
    local end=$(( beg+(1<<(32-mask))-1 ))
    ip=$(dec2ip4 $((beg+1)))
    _SERVER_IP4="$ip/$mask"
    _SERVER_IP6="$(convert_ip4_to_ip6 $ip)"
    if [[ -f $AVAILABLE_IP_FILE ]]; then
        return
    fi

    > $AVAILABLE_IP_FILE
    local i=$((beg+2))
    while [[ $i -lt $end ]]; do
        ip=$(dec2ip4 $i)
        echo "$ip/$mask" >> $AVAILABLE_IP_FILE
        i=$((i+1))
    done

}

# Load one IP from the cache
get_vpn_ip4() {
    local ip=$(head -1 $AVAILABLE_IP_FILE)
    if [[ $ip ]]; then
    local mat="${ip/\//\\\/}"
        sed -i "/^$mat$/d" $AVAILABLE_IP_FILE
    fi
    echo "$ip"
}

# Add one user
#   User keys and QR image save to users/$user
add_user() {
    local user=$1
    local template_file=${CLIENT_TPL_FILE}
    local interface=${_INTERFACE}
    local userdir="users/$user"

    mkdir -p "$userdir"
    wg genkey | tee $userdir/privatekey | wg pubkey > $userdir/publickey

    # client config file
    _PRIVATE_KEY=`cat $userdir/privatekey`
    _VPN_IP4=$(get_vpn_ip4)
    if [[ -z $_VPN_IP4 ]]; then
        echo "no available ip"
        exit 1
    fi
    _VPN_IP6=$(convert_ip4_to_ip6 $_VPN_IP4)
    eval "echo \"$(cat "${template_file}")\"" > $userdir/wg0.conf
    qrencode -o $userdir/$user.png  < $userdir/wg0.conf

    local public_key=`cat $userdir/publickey`
    echo "$user $_VPN_IP4 $public_key $_VPN_IP6" >> ${SAVED_FILE} && echo "User $user is added. config dir is $userdir"
}

# Remove saved user
#  Delete files in users/$user
#  restores IP to pool
#  Clear $user from master list
del_user() {
    local user=$1
    local userdir="users/$user"
    local ip key
    local interface=${_INTERFACE}

    read ip key <<<"$(awk "/^$user /{print \$2, \$3}" ${SAVED_FILE})"

    sed -i "/^$user /d" ${SAVED_FILE}
    if [[ -n "$ip" ]]; then
        echo "$ip" >> ${AVAILABLE_IP_FILE}
    fi
    rm -rf $userdir && echo "User $user is deleted"
}

# Rebuild server conf with all clients in cache
generate_server_config_file() {
    local template_file=${SERVER_TPL_FILE}
    local allowedIp ipv6 user vpn_ipv4 vpn_ipv6
    
    if [[ -z $_SERVER_IP4 ]]; then
        generate_cidr_ip4_file_if
    fi

    # Gen baseline server config
    eval "echo \"$(cat "${template_file}")\"" > $WG_TMP_CONF_FILE
    
    # Parse SAVED_FILE users into server config 
    while read user vpn_ipv4 public_key vpn_ipv6; do
        allowedIp=${vpn_ipv4%/*}/32
        if [[ -n $vpn_ipv6 ]]; then
            allowedIp+=", "
            allowedIp+=${vpn_ipv6%/*}/128
        fi
        cat >> $WG_TMP_CONF_FILE <<EOF

[Peer]
PublicKey = $public_key
AllowedIPs = $allowedIp
EOF
    done < ${SAVED_FILE}
    
    if [[ ! -d "server" ]]; then
        mkdir "server"
    fi
    cp -f $WG_TMP_CONF_FILE $WG_CONF_FILE
}

# Nuke everything.
clear_all() {
    local interface=$_INTERFACE
    rm -f ${SAVED_FILE} ${AVAILABLE_IP_FILE} ${WG_CONF_FILE}
    rm -R "server"
    rm -rf users
}

do_user() {
    generate_cidr_ip4_file_if

    if [[ $action == "-a" ]]; then
        if [[ -d users/$user ]]; then
            echo "Error: $user exists."
            exit 1
        fi
        add_user $user
    elif [[ $action == "-d" ]]; then
        del_user $user
    fi

    generate_server_config_file
}


init_server() {
    local interface=$_INTERFACE
    local template_file=${SERVER_TPL_FILE}

    if [[ -s $WG_CONF_FILE ]]; then
        echo "$WG_CONF_FILE exist"
        exit 1
    fi
    generate_cidr_ip4_file_if
    
    if [[ ! -d "server" ]]; then
        mkdir "server"
    fi
    eval "echo \"$(cat "${template_file}")\"" > $WG_CONF_FILE
    chmod 600 $WG_CONF_FILE
}

# Generate IPV6 address 
#   Convert IPV4 to HEX, then append prefix
convert_ip4_to_ip6(){
    local groups=0
    local ip a b c d ip6Array ip6Prefix subnet ip4Addr

    IFS=$'/' read ip4Addr mask <<< $1
    IFS=$'/' read ip6Prefix mask <<< $_VPN_NET6_PREFIX
    IFS=. read -r a b c d <<< $ip4Addr
    IFS=: read -a ip6Array  <<< $ip6Prefix
    for i in ${ip6Array[@]}; do
      if [[ -z $i ]]; then
        break;
      elif [[ -n $ipv6 ]]; then
        ipv6+=":"
      fi
      ((groups++))
      ipv6+=$i
    done

    local delim=:
    if [[ $groups -lt 6 ]]; then delim+=:; fi
    ipv6+=$delim$(printf '%02x' $a $b):$(printf '%02x' $c $d)
    echo "$ipv6/$mask"
}

list_user() {
    cat ${SAVED_FILE}
}

usage() {
    echo "usage: $0 [-a|-d|-c|-g|-i] [username] [-r]

    -i: init server conf
    -a: add user
    -d: del user
    -l: list all users
    -c: clear all
    -g: generate ip file
    -s: regen server file
    -r: enable route all traffic(allow 0.0.0.0/0)
    "
}

# main
#if [[ $EUID -ne 0 ]]; then
#    echo "This script must be run as root"
#    exit 1
#fi

action=$1
user=$2
route=$3

if [[ $action == "-i" ]]; then
    init_server
elif [[ $action == "-c" ]]; then
    clear_all
elif [[ $action == "-l" ]]; then
    list_user
elif [[ $action == "-g" ]]; then
    generate_cidr_ip4_file_if
elif [[ $action == "-s" ]]; then
    generate_server_config_file
elif [[ ! -z "$user" && ( $action == "-a" || $action == "-d" ) ]]; then
    do_user
else
    usage
    exit 1
fi
