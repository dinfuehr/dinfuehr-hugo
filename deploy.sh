#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"
DESTINATION=../dinfuehr.github.io

# Build the project.
hugo --destination $DESTINATION

# Go To Public folder
cd $DESTINATION
echo "dinfuehr.com" > $DESTINATION/CNAME
# Add changes to git.
git add -A

# Commit changes.
msg="rebuilding site `date +\"%F %T\"`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

# Come Back
cd ..
