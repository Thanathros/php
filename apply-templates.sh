#!/usr/bin/env bash
set -Eeuo pipefail

[ -f versions.json ] # run "versions.sh" first

jqt='.jq-template.awk'
if [ -n "${BASHBREW_SCRIPTS:-}" ]; then
	jqt="$BASHBREW_SCRIPTS/jq-template.awk"
elif [ "$BASH_SOURCE" -nt "$jqt" ]; then
	wget -qO "$jqt" 'https://github.com/docker-library/bashbrew/raw/5f0c26381fb7cc78b2d217d58007800bdcfbcfa1/scripts/jq-template.awk'
fi

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

for version; do
	export version

	variants="$(jq -r '.[env.version].variants | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	for dir in "${variants[@]}"; do
		suite="$(dirname "$dir")" # "buster", etc
		variant="$(basename "$dir")" # "cli", etc
		export suite variant

		alpineVer="${suite#alpine}" # "3.12", etc
		template='Dockerfile-ubuntu.template'
		from="ubuntu:$suite"
		export from

		case "$variant" in
			fpm) cmd='["php-fpm"]' ;;
			*) cmd='["php", "-a"]' ;;
		esac
		export cmd

		echo "processing $version/$dir ..."

		variantBlock1="$(if [ -f "Dockerfile-$variant-block-1.template" ]; then gawk -f "$jqt" "Dockerfile-$variant-block-1.template"; fi)"
		variantBlock2="$(if [ -f "Dockerfile-$variant-block-2.template" ]; then gawk -f "$jqt" "Dockerfile-$variant-block-2.template"; fi)"
		export variantBlock1 variantBlock2

		{
			generated_warning
			gawk -f "$jqt" "$template"
		} > "$version/$dir/Dockerfile"

		cp -a \
			docker-php-entrypoint \
			docker-php-ext-* \
			docker-php-source \
			"$version/$dir/"

		cmd="$(jq <<<"$cmd" -r '.[0]')"
		if [ "$cmd" != 'php' ]; then
			sed -i -e 's! php ! '"$cmd"' !g' "$version/$dir/docker-php-entrypoint"
		fi
	done
done
