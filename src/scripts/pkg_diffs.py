# /usr/bin/env python3

import os
import git
import yaml
import argparse


def load_from_commit(repo_path, sha, files):
    repo = git.Repo(repo_path)
    commit = repo.commit(sha)
    content = dict()
    for file in files:
        file_content = commit.tree / file
        content.update(yaml.safe_load(file_content.data_stream.read()))
    return content


def is_same(left, right):
    for key, val in left.items():
        if key not in right or left[key] != right[key]:
            return False
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Determine changed packages")
    parser.add_argument("sha", help="commit SHA to compare with")
    parser.add_argument(
        "files", nargs="*", default=["ros-one.repos"], help=".repos files to consider"
    )
    args = parser.parse_args()

    old = load_from_commit(os.getcwd(), args.sha, args.files)
    new = load_from_commit(os.getcwd(), "HEAD", args.files)

    try:
        del new["known_failures"]
    except KeyError:
        pass

    # Remove entries from new that already exist in old
    for key, val in old["repositories"].items():
        if key in new["repositories"] and is_same(new["repositories"][key], val):
            del new["repositories"][key]

    with open("/tmp/diff.repos", "w") as f:
        yaml.dump(new, f)
