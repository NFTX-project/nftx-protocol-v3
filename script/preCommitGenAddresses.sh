#!/bin/sh

# Check if any files in 'deployments' folder are staged for commit
if git diff --cached --name-only | grep -q 'deployments/'
then
    echo "Changes detected in 'deployments' folder. Running 'yarn gen:addresses'..."
    yarn gen:addresses

    # Check if the script was successful
    if [ $? -ne 0 ]; then
        echo "Script failed. Aborting commit."
        exit 1
    fi

    echo "Adding updated address.json to the commit..."
    git add addresses.json

    echo "Continuing with commit..."
fi
