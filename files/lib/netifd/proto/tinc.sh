#!/bin/sh

[ -x /usr/sbin/tincd ] || exit 0

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_tinc_append() {
	append "$3" "$1"
}

proto_tinc_init_config() {
	no_device=1
	available=1
	renew_handler=1

	proto_config_add_string ipaddr
	proto_config_add_string name
	proto_config_add_string bindtoaddr
	proto_config_add_string listen
	proto_config_add_string 'mode:or("router","switch","hub")'
	proto_config_add_string 'priority:or("low","normal","high")'
	proto_config_add_string 'strict_subnets:or("no","yes")'
	proto_config_add_array 'connect:list(string)'
	proto_config_add_array 'option:list(string)'
	proto_config_add_array 'subnet:list(string)'
	proto_config_add_array 'route:list(string)'
}

proto_tinc_setup() {
	local config="$1"

	local ipaddr name bindtoaddr listen connect connects mode priority strict_subnets option options subnet subnets route routes
	json_get_vars ipaddr name bindtoaddr mode priority strict_subnets
	json_for_each_item proto_tinc_append connect connects
	json_for_each_item proto_tinc_append option options
	json_for_each_item proto_tinc_append subnet subnets
	json_for_each_item proto_tinc_append route routes

	proto_export CONFIG="$config"
	proto_export IPADDR="$ipaddr"
	proto_export ROUTES="$routes"

	conf_dir="/etc/tinc/$config"
	conf_file="$conf_dir/tinc.conf"
	tmp_conf_dir="/tmp/tinc/$config"
	tmp_conf_file="$tmp_conf_dir/tinc.conf"

	rm -rf $tmp_conf_dir
	mkdir -p $conf_dir/hosts $tmp_conf_dir/hosts

	{
		echo -e "Name=$name\nInterface=tinc-$config\nMode=$mode"
		[ -z "$bindtoaddr" ] || echo "BindToAddress=$bindtoaddr"
		[ -z "$priority" ] || echo "ProcessPriority=$priority"
		[ -z "$strict_subnets" ] || echo "StrictSubnets=$strict_subnets"

		for host in $connects; do
			echo "ConnectTo=$host"
		done

		for option in $options; do
			echo "$option"
		done
	}  > $tmp_conf_file

	if [ ! -f $conf_dir/hosts/$name ]; then
		tincd -c $tmp_conf_dir -K
		cp -f $tmp_conf_dir/rsa_key.priv $conf_dir/
		cp -rf $tmp_conf_dir/hosts $conf_dir/
	fi

	cp -rf /etc/tinc/$config/* $tmp_conf_dir
	cp -f /lib/netifd/tinc.script $tmp_conf_dir/tinc-up

	{
		echo -e "\nSubnet=${ipaddr%%/*}/32"

		for subnet in $subnets; do
			echo "Subnet=$subnet"
		done
	} > $tmp_conf_dir/hosts/$name

	proto_run_command "$config" /usr/sbin/tincd \
		-c $tmp_conf_dir \
		--no-detach \
		--pidfile=/var/run/tinc.${config}.pid \
		--logfile=/tmp/log/tinc.${config}.log
}

proto_tinc_teardown() {
	local config="$1"
	logger -t tinc "stopping..."
	proto_kill_command "$config" 15
}

proto_tinc_renew() {
	local iface="$1"
	logger -t tinc "renew $iface ..."
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol tinc
}
