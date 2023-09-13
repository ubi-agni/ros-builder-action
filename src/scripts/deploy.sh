#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# shellcheck source=src/prepare.sh
source "${SRC_PATH}/prepare.sh"

function update_readme {
	local url=$1

	if [ -f "$DEBS_PATH/README.md.in" ] && [ ! -f "$DEBS_PATH/README.md" ]; then
		mv "$DEBS_PATH/README.md.in" "$DEBS_PATH/README.md"
		sed -e "s|@REPO_URL@|$url|g" \
			-e "s|@DISTRO_NAME@|$DEB_DISTRO-$ROS_DISTRO|g" \
			-i "$DEBS_PATH/README.md"
	fi
}

function cleanup_debs {
	# cleanup repository
	ici_step update_readme "$repo_url"
	cd "$DEBS_PATH" || return 1

	local remove_files=("./*.deb" "./*.ddeb" "./*.dsc" "./*.buildinfo" "./*.changes" "./*.log")
	for file in $DEPLOY_FILES; do # don't delete file type if listed in DEPLOY_FILES
		remove_files=( "${remove_files[@]/"./*.${file##*.}"}" )
	done

	echo "Removing files: ${remove_files[*]}"
	rm -f "${remove_files[@]}"

	# issue warning if .deb files are not deployed
	if echo "${remove_files[@]}" | grep -q -F -w "./*.deb"; then
		gha_warning "You requested to drop .deb files!"
	fi

	if [ -n "${DEPLOY_FILE_SIZE_LIMIT:-}" ]; then
		files=$(find . -type f -size "+$DEPLOY_FILE_SIZE_LIMIT" -printf "%p\t%s\n" | numfmt --field=2 --to=iec --suffix=B --padding=8 | sort)
		if [ -n "$files" ]; then
			gha_warning "Removing files >$DEPLOY_FILE_SIZE_LIMIT:\n${files[*]}"
			find . -type f -size "+$DEPLOY_FILE_SIZE_LIMIT" -delete
		fi
	fi
}

function deploy_git {
	local repo_url=$1
	local git_url=$2
	local git_branch=$3
	local fetch_error=0
	local files=()
	local commit_args=("-m" "$MESSAGE")
	local push_args=()

	cleanup_debs "100M"

	# setup new git repo, create desired branch and stage all (new) files
	ici_color_output BOLD "Setup git repository"
	git init .
	git checkout --orphan "$git_branch"
	git add ./*

	# add remote and fetch previous content
	git remote add origin "$git_url"
	ici_label git fetch --depth=1 origin "$git_branch" || fetch_error=$?

	# switch to remote branch, but keep working tree
	[ $fetch_error -eq 0 ] && ici_cmd git reset FETCH_HEAD
	git add ./* # add new files to index again (after reset)

	# restore files from original branch, if possible ($fetch_error=0)
	if [ "$CONTENT_MODE" != "replace" ] && [ $fetch_error -eq 0 ]; then
		mapfile -t files < <(git status --porcelain | sed -n 's#^ D \(.*\)#\1#p')
		ici_cmd git restore --source=FETCH_HEAD "${files[@]}"
	fi
	# update flat debian repository (considering old and new .debs)
	apt-ftparchive packages . > Packages
	apt-ftparchive release  . > Release
	git add . # stage all changes (including deleted files from original branch)

	# skip commit/push if only Release file has changed
	if ! git status --porcelain | grep -v "M..Release" ; then
		gha_warning "No changes in release repository. Skipping push."
		return 0
	fi

	if [ "$PUSH_MODE" = "amend" ] && [ $fetch_error -eq 0 ]; then
		commit_args=("--amend" "--no-edit")
		push_args+=("--force-with-lease")
	fi
	ici_cmd git commit "${commit_args[@]}"

	if [ "$PUSH_MODE" = "squash" ] ; then # squash all commits into one
		# https://stackoverflow.com/questions/1657017/how-to-squash-all-git-commits-into-one
		git reset "$(git commit-tree "HEAD^{tree}" "${commit_args[@]}")"
		push_args+=("--force-with-lease")
	fi

	# commit changes and push
	ici_cmd git push "${push_args[@]}" origin "$git_branch"
}

function require_token {
	test -z "$TOKEN" && gha_error "Secret TOKEN is not set" && exit 1
	true
}

function require_ssh_private_key {
	test -z "$SSH_PRIVATE_KEY" && gha_error "SSH_PRIVATE_KEY is not set" && exit 1

	ici_color_output BOLD "Setup ssh-agent"
	eval "$(ssh-agent -s)"
	ssh-add - <<< "$SSH_PRIVATE_KEY"
}

function deploy_github {
	local repo=$1
	local branch=$2
	local git_url

	# configure git
	if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
		git config --global init.defaultBranch main
		git config --global advice.detachedHead false
		git config --global user.name "$COMMIT_NAME"
		git config --global user.email "$COMMIT_EMAIL"
	fi

	if [ "$repo" = "${GITHUB_REPOSITORY:-}" ]; then
		require_token
		git_url="https://x-access-token:${TOKEN}@github.com/${repo}.git"
	else
		require_ssh_private_key
		git_url="git@github.com:$repo"
	fi

	DEPLOY_FILE_SIZE_LIMIT=${DEPLOY_FILE_SIZE_LIMIT:-100M}
	deploy_git "https://raw.githubusercontent.com/$repo/$branch" "$git_url" "$branch"
}

# Select deployment method based on $DEPLOY_URL
case "$DEPLOY_URL" in
	self)     deploy_github "$GITHUB_REPOSITORY" "$DEB_DISTRO-$ROS_DISTRO";;  # default branch
	"self#"*) deploy_github "$GITHUB_REPOSITORY" "${DEPLOY_URL##*#}";;        # custom branch
	pages)    gha_error "Not yet implemented" || exit 1; deploy_github "$GITHUB_REPOSITORY" gh-pages;;
	*)
		if ! ici_parse_url "$DEPLOY_URL"; then
			gha_error "URL '$1' does not match the pattern: <scheme>:<resource>[#<fragment>]"
		fi
		repo=${URL_RESOURCE%.git}
		case "$URL_SCHEME" in
			github | gh | git@github.com)
				deploy_github "${repo#//github.com/}" "${URL_FRAGMENT:-$DEB_DISTRO-$ROS_DISTRO}"
				;;
			'git+file'*|'git+http'*|'git+ssh'*|'https'*|'http'*)
				# ensure that $repo starts with github.com
				if [[ $repo =~ ^//github.com/ ]]; then
					deploy_github "${repo#//github.com/}" "${URL_FRAGMENT:-$DEB_DISTRO-$ROS_DISTRO}"
				else
					gha_error "Only github.com repositories are supported."
				fi
				;;
			*) gha_error "Unsupported scheme '$URL_SCHEME' in DEPLOY_URL '$url'" ;;
		esac
esac
