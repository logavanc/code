#!bash
# kc.bash - Kerberos credential cache juggler
#
# Must be 'source'd (ie. from bashrc) in order for cache switching to work.

# Translate Unix timestamp to relative time string
_kc_relative_time() {
	local expiry=$1 str=$2 now=$(date +%s)
	local diff=$(( expiry - now ))
	local diff_s=$(( diff % 60 ))
	diff=$(( (diff-diff_s) / 60 ))
	local diff_m=$(( diff % 60 ))
	diff=$(( (diff-diff_m) / 60 ))
	local diff_h=$(( diff % 24 ))
	local diff_d=$(( (diff-diff_h) / 24 ))
	if (( diff_d > 1 )); then
		str+=" ${diff_d} days"
	elif (( diff_h > 0 )); then
		str+=" ${diff_h}h ${diff_m}m"
	elif (( diff_m > 1 )); then
		str+=" ${diff_m} minutes"
	else
		str+=" a minute"
	fi
	echo $str
}

# Expand shortname to ccname
_kc_expand_ccname() {
	case $1 in
	"new")
		printf 'FILE:%s\n' "$(mktemp "${ccprefix}XXXXXX")";;
	""|"@")
		printf '%s\n' "$ccdefault";;
	[Kk][Cc][Mm])
		printf 'KCM:%d\n' "$UID";;
	[0-9]|[0-9][0-9])
		local i=$1
		if (( 0 < i && i <= ${#caches[@]} )); then
			printf '%s\n' "${caches[i]}"
		else
			printf '%s\n' "$current"
			echo >&2 "kc: cache #$i not in list"
			return 1
		fi;;
	^^*)
		printf 'KEYRING:%s\n' "${1#^^}";;
	^*)
		printf 'KEYRING:krb5cc.%s\n' "${1#^}";;
	:)
		printf 'DIR:%s\n' "$cccdir";;
	:*)
		printf 'DIR::%s/tkt%s\n' "$cccdir" "${1#:}";;
	*:*)
		printf '%s\n' "$1";;
	*/*)
		printf 'FILE:%s\n' "$1";;
	*)
		printf 'FILE:%s%s\n' "$ccprefix" "$1";;
	esac
}

# Collapse ccname to shortname
_kc_collapse_ccname() {
	local ccname=$1
	case $ccname in
	"$ccdefault")
		ccname="@";;
	"DIR::$cccdir/"*)
		ccname=":${ccname##DIR::$cccdir/tkt}";;
	"FILE:$ccprefix"*)
		ccname="${ccname#FILE:$ccprefix}";;
	"FILE:/"*)
		ccname="${ccname#FILE:}";;
	"API:$principal")
		ccname="${ccname%$principal}";;
	"KCM:$UID")
		ccname="KCM";;
	"KEYRING:krb5cc."*)
		ccname="${ccname/#KEYRING:krb5cc./^}";;
	"KEYRING:"*)
		ccname="${ccname/#KEYRING:/^^}";;
	esac
	printf '%s\n' "$ccname"
}

# Compare two ccnames, adding "FILE:" prefix if necessary
_kc_eq_ccname() {
	local a=$1 b=$2
	[[ $a == *:* ]] || a=FILE:$a
	[[ $b == *:* ]] || b=FILE:$b
	[[ $a == "$b" ]]
}

kc_list_caches() {
	local current="$(pklist -N)" have_current=
	local ccdefault="$(unset KRB5CCNAME; pklist -N)" have_default=
	local name=

	{
		pklist -l -N | tr '\n' '\0'
		# traditional
		find "/tmp" -maxdepth 1 -name "krb5cc*" \( -user "$UID" \
			-o -user "$USER" \) -printf "FILE:%p\0"
		# grawity's own convention
		# TODO: only check if different from current path
		if [[ "$XDG_RUNTIME_DIR" ]] && [[ -d "$XDG_RUNTIME_DIR/krb5cc" ]]; then
			find "$XDG_RUNTIME_DIR/krb5cc" -maxdepth 1 -type f -name "tkt*" \
			\( -user "$UID" -o -user "$USER" \) -printf "DIR::%p\0"
		fi
		# Heimdal kcmd
		if [[ -S /var/run/.heim_org.h5l.kcm-socket ]]; then
			printf "KCM:%d\0" "$UID"
		fi
		# kernel keyrings
		local s_keys=$(keyctl rlist @s 2>/dev/null)
		local u_keys=$(keyctl rlist @u 2>/dev/null)
		for key in $s_keys $u_keys; do
			local desc=$(keyctl rdescribe "$key")
			case $desc in
			keyring\;*\;*\;*\;krb5cc.*)
				printf "KEYRING:%s\0" "${desc#*;*;*;*;}"
				;;
			esac
		done
	} | sort -z -u | {
		while read -rd '' c; do
			if pklist -c "$c" >& /dev/null; then
				printf "%s\n" "$c"
				[[ $c == "$current" ]] && have_current=$c
				[[ $c == "$ccdefault" ]] && have_default=$c
			fi
		done
		if [[ ! $have_current ]]; then
			pklist >& /dev/null && printf "%s\n" "$current"
		fi
	}
}

kc() {
	if ! command -v pklist >&/dev/null; then
		echo "'pklist' not found in \$PATH" >&2
		return 2
	fi

	local cccurrent=$(pklist -N)
	local ccdefault=$(unset KRB5CCNAME; pklist -N)
	local ccprefix="/tmp/krb5cc_${UID}_"
	local cccdir=""
	local cccprimary=""
	if [[ -d "$XDG_RUNTIME_DIR/krb5cc" ]]; then
		cccdir="$XDG_RUNTIME_DIR/krb5cc"
	fi
	if [[ "$cccurrent" == DIR::* ]]; then
		cccdir=${cccurrent#DIR::}
		cccdir=${cccdir%/*}
		if [[ -f "$cccdir/primary" ]]; then
			cccprimary=$(<"$cccdir/primary")
		else
			cccprimary="tkt"
		fi
	fi
	local now=$(date +%s)
	local use_color=false

	declare -a caches=()
	readarray -t -O 1 -n 99 caches < <(kc_list_caches)

	[[ $TERM && -t 1 ]] &&
		use_color=true

	local cmd=$1; shift

	case $cmd in
	-h|--help)
		echo "Usage: kc [list]"
		echo "       kc <name>|\"@\" [kinit_args]"
		echo "       kc <number>"
		echo "       kc purge"
		echo "       kc destroy <name|number> ..."
		;;
	"")
		# list ccaches
		local i=

		for (( i=1; i <= ${#caches[@]}; i++ )); do
			local ccname=
			local ccdata=
			local shortname=
			local item=
			local rest=
			local principal=
			local ccrealm=
			local expiry=
			local expirystr=
			local tgtexpiry=
			local init=
			local initexpiry=
			local itemflag=
			local flagcolor=
			local namecolor=
			local princcolor=
			local expirycolor=

			ccname=${caches[i]}
			ccdata=$(pklist -c "$ccname") || continue
			while IFS=$'\t' read -r item rest; do
				case $item in
				principal)
					principal=$rest
					ccrealm=${rest##*@}
					;;
				ticket)
					local tktclient=
					local tktservice=
					local tktexpiry=
					local tktflags=

					IFS=$'\t' read -r tktclient tktservice _ tktexpiry _ tktflags _ <<< "$rest"
					if [[ $tktservice == "krbtgt/$ccrealm@$ccrealm" ]]; then
						tgtexpiry=$tktexpiry
					fi
					if [[ $tktflags == *I* ]]; then
						init=$tktservice
						initexpiry=$tktexpiry
					fi
					;;
				esac
			done <<< "$ccdata"

			shortname=$(_kc_collapse_ccname "$ccname")

			if (( tgtexpiry )); then
				expiry=$tgtexpiry
			elif (( initexpiry )); then
				expiry=$initexpiry
			fi

			if (( expiry )); then
				if (( expiry <= now )); then
					expirystr="(expired)"
					expirycolor='31'
					itemflag="x"
					flagcolor='31'
				else
					expirystr=$(_kc_relative_time "$expiry" "")
					if (( expiry > now+1200 )); then
						expirycolor=''
					else
						expirycolor='33'
					fi
				fi
			fi

			if [[ $ccname == "$cccurrent" ]]; then
				if [[ $ccname == "$KRB5CCNAME" ]]; then
					itemflag="»"
				else
					itemflag="*"
				fi

				if (( expiry <= now )); then
					flagcolor='1;31'
				else
					flagcolor='1;32'
				fi

				namecolor=$flagcolor
				princcolor=$namecolor
			fi

			printf '\e[%sm%1s\e[m %2d ' "$flagcolor" "$itemflag" "$i"
			printf '\e[%sm%-15s\e[m' "$namecolor" "$shortname"
			if (( ${#shortname} > 15 )); then
				printf '\n%20s' ""
			fi
			printf ' \e[%sm%-40s\e[m' "$princcolor" "$principal"
			printf ' \e[%sm%s\e[m' "$expirycolor" "$expirystr"
			printf '\n'
		done
		if (( i == 1 )); then
			echo "No Kerberos credential caches found."
			return 1
		fi
		;;
	purge)
		# purge expired ccaches
		local ccname=
		local ccdata=

		for ccname in "${caches[@]}"; do
			local principal=$(pklist -c "$ccname" -P)
			echo "Renewing credentials for $principal in $ccname"
			kinit -c "$ccname" -R || kdestroy -c "$ccname"
		done
		;;
	destroy)
		# destroy current ccache or argv
		local shortname=
		local ccname=
		local destroy=()

		for shortname; do
			if ccname=$(_kc_expand_ccname "$shortname"); then
				destroy+=("$ccname")
			fi
		done
		for ccname in "${destroy[@]}"; do
			kdestroy -c "$ccname"
		done
		;;
	clean)
		# destroy file ccaches at standard locations
		rm -vf "$ccdefault" "$ccprefix"*
		;;
	list)
		# list all found ccaches
		printf '%s\n' "${caches[@]}"
		;;
	expand)
		_kc_expand_ccname "$1"
		;;
	=*)
		local line= aliasfile=${XDG_CONFIG_HOME:-~/.config}/k5aliases

		if if [[ -e $aliasfile ]] &&
		line=$(grep -w "^${cmd#=}" "$aliasfile"); then
			true
		elif [[ -e ~/lib/dotfiles/k5aliases ]] &&
		line=$(grep -w "^${cmd#=}" ~/lib/dotfiles/k5aliases); then
			true
		else
			false
		fi; then
			eval kc "$line"
		fi
		;;
	?*@?*)
		# switch to a ccache for given principal
		local ccname=
		local maxexpiry=
		local maxccname=

		for ccname in "${caches[@]}"; do
			local ccdata=
			local item=
			local rest=
			local principal=
			local ccrealm=
			local tgtexpiry=
			local initexpiry=

			principal=$(pklist -Pc "$ccname") &&
				[[ $defprinc == $arg ]] || continue

			ccrealm=${principal##*@}

			ccdata=$(pklist -c "$ccname") || continue
			while IFS=$'\t' read -r item rest; do
				case $item in
				ticket)
					local tktclient=
					local tktservice=
					local tktexpiry=
					local tktflags=

					IFS=$'\t' read -r tktclient tktservice _ tktexpiry _ tktflags <<< "$rest"
					if [[ $tktservice == "krbtgt/$ccrealm@$ccrealm" ]]; then
						tgtexpiry=$tktexpiry
					fi
					if [[ $flags == *I* ]]; then
						initexpiry=$tktexpiry
					fi
					;;
				esac
			done <<< "$ccdata"

			if (( tgtexpiry )); then
				expiry=$tgtexpiry
			elif (( initexpiry )); then
				expiry=$initexpiry
			fi

			if (( expiry > maxexpiry )); then
				maxexpiry=$expiry
				maxccname=$ccname
			fi
		done

		if [[ $maxccname ]]; then
			ccname=$maxccname
			if [[ $ccname == DIR::* ]]; then
				ccname=${ccname/#DIR::/DIR:}
				ccname=${ccname%/*}
				export KRB5CCNAME=$ccname
				kswitch -c "$ccname"
			else
				export KRB5CCNAME=$ccname
			fi
			printf "Switched to %s\n" "$KRB5CCNAME"
		else
			export KRB5CCNAME=$(_kc_expand_ccname 'new')
			printf "Switched to %s\n" "$KRB5CCNAME"
			kinit "$cmd" "$@"
		fi
		;;
	*)
		# switch to a named or numbered ccache
		local ccname= ccdirname= keyname= keyring= princ=

		if ccname=$(_kc_expand_ccname "$cmd"); then
			case $ccname in
			DIR::*)
				ccdirname=${ccname%/*}
				ccdirname=${ccdirname/#DIR::/DIR:}
				export KRB5CCNAME=$ccdirname
				kswitch -c "$ccname"
				;;
			KEYRING:*)
				keyname=${ccname#KEYRING:}
				if ! keyctl request 'keyring' "$keyname" >&/dev/null; then
					# Hack around something that loses keys added to @s if it equals @us
					local sdesc=$(keyctl rdescribe @s 2>/dev/null)
					local ddesc=$(keyctl rdescribe @us 2>/dev/null)
					if [[ "$sdesc" == "$ddesc" ]]; then
						keyring='@us'
					else
						keyring='@s'
					fi
					keyctl newring "$keyname" "$keyring" >/dev/null
				fi
				export KRB5CCNAME=$ccname
				;;
			*)
				export KRB5CCNAME=$ccname
			esac
			if princ=$(pklist -P -c "$ccname" 2>/dev/null); then
				printf "Switched to \e[1m%s\e[m (%s)\n" \
					"$princ" "$ccname"
			else
				printf "New ccache (%s)\n" \
					"$ccname"
			fi
			[[ $1 ]] && kinit "$@"
		else
			return 1
		fi
		;;
	esac
	return 0
}

if [[ -t 0 && -t 1 && $- != *i* ]]; then
	echo "kc needs to be sourced (e.g. from your ~/.bashrc) for it to work."
	false
fi
