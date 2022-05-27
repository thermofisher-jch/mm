#!/bin/bash

# This variant uses mode and target version to identify which output version it is
# meant to build for tagging, and it also applies the version number change by
# repackaging the debian artifact if is third argument is absent or "true", and
# leaves it as-is if that argument is "false".
mode="${1}"
target_version="${2}"
repack="${3}"
if [ "x${mode}" != "xAssayDev" ]
then
	if [ "x${mode}" != "xdx" ]
	then
		echo "Required argument: AssayDev or dx"
		exit 1
	else
		build_target_props="mode=dx;for_dx=1;for_${target_version}=1"
	fi
else
	build_target_props="mode=assaydev;for_assaydev=1;for_${target_version}=1"
fi

if [ "x${repack}" != "xfalse" ]
then
	if [ "x${repack}" != "xtrue" ]
	then
		if [ "x${repack}" == "x" ]
		then
			repack="true"
		else
			echo "Repack must be absent, true, or false"
			exit 2
		fi
	fi
fi

# The model
history="./hist_size.csv"
state_now="./state_now.dat"
artifact_names="./artifact_names.dat"

# Inspect checked in state file to understand what version we are pretending
# to be building a component of the bundle for.
state_now="$(cat state_now.dat)"
echo "${state_now}"

build_num="${BUILD_NUMBER}"
# build_date="$(date +%Y%m%d%H%M)"
build_date="$(("$(date +%s)" / 20))"


cat > uploadBuildSpec.json << EOF
{
    "files": [
EOF

# Find the line for the component that will belong in the bundle whose
# version was given by ${state_now} and pull it by FTP, simulating a genuine
# build.
first_line=1
for artifact in $(cat "${artifact_names}")
do
	artifact_found=0
	for line in $(grep "^${artifact}" "${history}")
	do
		echo "${line}"
		match_to="$(echo $line | awk -F, '{print $8}')"
		mode_to="$(echo $line | awk -F, '{print $10}')"
		echo "${match_to} ${mode_to}"
		if [ "${match_to}" == "${state_now}" -a "${mode}" == "${mode_to}" ]
		then
			artifact_found=1
			url="$(echo "${line}" | awk -F, '{ print "http://lemon.itw/"$4"/TSDx/"$10"/updates/"$1"_"$2"_"$3".deb" }')"
			wget "${url}"
			file="$(basename "${url}")"
			architecture="$(echo $line | awk -F, '{print $3}')"
			version="$(echo $line | awk -F, '{print $2}')"
			if [ "x${repack}" == "xtrue" ]
			then
				version="$(echo "${version}" | awk -F. '{print $1"."$2"."$3}')"
				version="${version}-${build_num}+${build_date}"
				mkdir temp
				dpkg-deb -R "${file}" temp
				cat temp/DEBIAN/control | sed "s/Version: .*/Version: ${version}/" > new_control
				mv new_control temp/DEBIAN/control
				file="${artifact}_${version}_${architecture}.deb"
				dpkg-deb -b temp "${file}"
				rm -rf temp
			fi

			if [ "${first_line}" -eq 0 ]
			then
				echo "," >> uploadBuildSpec.json
			else
				first_line=0
			fi
			cat >> uploadBuildSpec.json << EOF
        {
            "pattern": "./${file}",
	    "target": "csd-genexus-debian-dev/builds/${artifact}/${file}",
            "props": "deb.distribution=bionic;deb.component=main;deb.architecture=${architecture};${build_target_props}"
        }
EOF
			break
		fi
	done
	if [ "${artifact_found}" -eq 0 ]
	then
		echo "artifact ${artifact} not found"
		exit 1
	fi
done

cat >> uploadBuildSpec.json << EOF
    ]
}
EOF
