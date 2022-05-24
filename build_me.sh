#!/bin/bash

# The model
history="./hist_size.csv"
state_now="./state_now.dat"
artifact_names="./artifact_names.dat"


# Strip csd-genexus- and psuedo- prefixes away from working directory name
# to get the artifact name of project being build
# basedir="$(basename "$(pwd)")"
# artifact="$(echo "${basedir}" | sed 's/csd-genexus-//' | sed 's/pseudo-//')"
# echo "${artifact}"

# Inspect checked in state file to understand what version we are pretending
# to be building a component of the bundle for.
state_now="$(cat state_now.dat)"
echo "${state_now}"

build_num="${BUILD_NUMBER}"
build_date="$(date +%Y%m%d%H%M)"

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
		echo "${match_to}"
		if [[ "${match_to}" == "${state_now}" ]]
		then
			artifact_found=1
			url="$(echo "${line}" | awk -F, '{ print "http://lemon.itw/"$4"/TSDx/"$10"/updates/"$1"_"$2"_"$3".deb" }')"
			wget "${url}"
			file="$(basename "${url}")"
			mode="$(echo $line | awk -F, '{print $10}')"
			architecture="$(echo $line | awk -F, '{print $3}')"
			version="$(echo $line | awk -F, '{print $2}')"
			if [[ "$(echo "${artifact}" | head -3c)" == "ts-" ]]
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

			if [[ "${first_line}" -eq 0 ]]
			then
				echo "," >> uploadBuildSpec.json
			else
				first_line=0
			fi
			cat >> uploadBuildSpec.json << EOF
        {
            "pattern": "./${file}",
	    "target": "csd-genexus-debian-dev/pool/main/${artifact}/${file}",
            "props": "mode=${mode};deb.distribution=bionic;deb.component=main;deb.architecture=${architecture}"
        }
EOF
			break
		fi
	done
	if [[ "${artifact_found}" -eq 0 ]]
	then
		echo "artifact ${artifact} not found"
		exit 1
	fi
done

cat >> uploadBuildSpec.json << EOF
    ]
}
EOF
