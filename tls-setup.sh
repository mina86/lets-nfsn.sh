#!/bin/sh

Help=no
Reinstall=no
Verbose=no

while [ ${#} -gt 0 ]
do
	Arg=${1}
	shift 1
	case ${Arg} in
	"-h"|"--help")
		Help=yes
		;;
	"-r"|"--reinstall")
		Reinstall=yes
		;;
	"-v"|"--verbose")
		Verbose=yes
		;;
	*)
		echo "Bad argument: ${Arg}"
		return 20
	esac
done

if [ "${Help}" = "yes" ]
then
	echo
	echo "YourPrompt> ${0} [-r|--reinstall] [-v|--verbose]"
	echo "YourPrompt> ${0} <-h|--help>"
	echo
	echo "Options:"
	echo "  -h, --help      = Display this output."
	echo "  -r, --reinstall = Reinstall existing certificates."
	echo "  -v, --verbose   = Don't suppress boring output."
	echo
	return 0
fi

. /usr/local/etc/dehydrated/config
if [ ! -d "${BASEDIR}" ]
then
	echo "Creating base directory for Dehydrated."
	mkdir "${BASEDIR}"
fi

if [ ! -d "${BASEDIR}/accounts" ]
then
	echo
	echo "To use Let's Encrypt you must agree to their Subscriber Agreement,"
	echo "which is linked from:"
	echo
	echo "    https://letsencrypt.org/repository/"
	echo
	echo -n "Do you accept the Let's Encrypt Subscriber Agreement (y/n)? "
	read yes
	case $yes in
		y|Y|yes|YES|Yes|yup)
			break 2
			;;
		*)
			echo "OK, tls-setup.sh will be aborted."
			return 30
	esac
	/usr/local/bin/dehydrated --register --accept-terms
fi

if [ ! -d "${WELLKNOWN}" ]
then
	echo "Creating well-known directory for Let's Encrypt challenges."
	mkdir -p "${WELLKNOWN}"
fi

/usr/local/bin/nfsn list-aliases >${BASEDIR}/domains.txt

if [ ! -s "${BASEDIR}/domains.txt" ]
then
	echo "There are no aliases for this site."
	return 10
fi

wk_dir=.well-known
acme_dir=acme-challenge

for Alias in `cat "${BASEDIR}/domains.txt"`
do
	if [ -d "/home/public/${Alias}" ]
	then
		if [ -h "/home/public/$Alias/$wk_dir" ]
		then
			: Symlink already set up
		elif [ ! -e "/home/public/$Alias/$wk_dir" ]
		then
			echo "Linking well-known for $Alias."
			ln -s "../$wk_dir" "/home/public/$Alias/$wk_dir"
		elif [ ! -d "/home/public/$Alias/$wk_dir" ]
		then
			echo "$Alias/$wk_dir exists but is not a (symbolic" \
			     'link to a) directory; aborting'
			# TODO: Should we ‘exit 1’?
		elif [ -h "/home/public/$Alias/$wk_dir/$acme_dir" ]
		then
			: Symlink already set up
		elif [ ! -e "/home/public/$Alias/$wk_dir/$acme_dir" ]
		then
			echo "Linking well-known/$acme_dir for $Alias."
			ln -s "../../$wk_dir/$acme_dir" \
			   "/home/public/$Alias/$wk_dir/$acme_dir"
		elif [ ! -d "/home/public/$Alias/$wk_dir/$acme_dir" ]
		then
			echo "$Alias/$wk_dir/$acme_dir exists but is not a" \
			     '(symbolic link to a) directory; aborting'
			# TODO: Should we ‘exit 1’?
		fi
	fi
	if [ "${Reinstall}" = "yes" ]
	then
		cat \
			"${BASEDIR}/certs/${Alias}/cert.pem" \
			"${BASEDIR}/certs/${Alias}/chain.pem" \
			"${BASEDIR}/certs/${Alias}/privkey.pem" \
		| /usr/local/bin/nfsn -i set-tls
	fi
done

if [ "${Reinstall}" = "yes" ]
then
	return 0
fi

/usr/local/bin/dehydrated --cron >${BASEDIR}/dehydrated.out

if fgrep -v INFO: "${BASEDIR}/dehydrated.out" | fgrep -v unchanged | fgrep -v 'Skipping renew' | fgrep -v 'Checking expire date' | egrep -q -v '^Processing' || [ "${Verbose}" = "yes" ]
then
	cat "${BASEDIR}/dehydrated.out"
fi

if ! /usr/local/bin/nfsn test-cron tlssetup | fgrep -q 'exists=true'
then
	echo Adding scheduled task to renew certificates.
	/usr/local/bin/nfsn add-cron tlssetup /usr/local/bin/tls-setup.sh me ssh '?' '*' '*'
fi
