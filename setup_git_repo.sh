#!/bin/bash

# Enable logging to a file and console
LOG_FILE="setup_git_repo.log"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

# Configuration files and size threshold for large files
CONFIG_FILE=".git_config"
LARGE_FILE_SIZE=100000000  # 100 MB for GitHub's file size limit
GIT_LFS_ENABLED=false

# Ensure Git and Git LFS are installed
install_dependencies() {
    if ! command -v git &> /dev/null; then
        echo "Git is not installed. Installing Git..."
        sudo apt-get update && sudo apt-get install -y git
    fi
    
    if ! command -v git-lfs &> /dev/null; then
        echo "Git LFS is not installed. Installing Git LFS..."
        sudo apt-get install -y git-lfs
        git lfs install
        GIT_LFS_ENABLED=true
    else
        GIT_LFS_ENABLED=true
    fi
    echo "Git and Git LFS are set up successfully."
}

# Load or prompt for GitHub user information
load_or_prompt_user_info() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Current Git configuration:"
        echo "GitHub Username: $GITHUB_USER"
        echo "GitHub Email: $GITHUB_EMAIL"
        echo "Repository Name: $REPO_NAME"
        echo "Remote URL: git@github.com:$GITHUB_USER/$REPO_NAME.git"
        echo -e "\nPress Enter to keep this configuration or type 'change' to update."
        read -p "" choice
    else
        choice="change"
    fi

    if [ "$choice" == "change" ] || [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_EMAIL" ] || [ -z "$REPO_NAME" ]; then
        while [[ -z "$GITHUB_USER" ]]; do
            read -p "Enter your GitHub username (e.g., username): " GITHUB_USER
        done
        while [[ -z "$GITHUB_EMAIL" ]]; do
            read -p "Enter your GitHub email (e.g., username@juniper.net): " GITHUB_EMAIL
        done
        while [[ -z "$REPO_NAME" ]]; do
            read -p "Enter the name of the repository (e.g., telemetry): " REPO_NAME
        done

        # Save new configuration to .git_config file
        echo "GITHUB_USER=\"$GITHUB_USER\"" > "$CONFIG_FILE"
        echo "GITHUB_EMAIL=\"$GITHUB_EMAIL\"" >> "$CONFIG_FILE"
        echo "REPO_NAME=\"$REPO_NAME\"" >> "$CONFIG_FILE"
        echo "Configuration saved to $CONFIG_FILE"
    fi

    git config --global user.name "$GITHUB_USER"
    git config --global user.email "$GITHUB_EMAIL"
}

# Set remote URL based on action type (HTTPS for pull, SSH for push)
set_remote_url() {
    if [ "$1" == "pull" ]; then
        REMOTE_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
    else
        REMOTE_URL="git@github.com:$GITHUB_USER/$REPO_NAME.git"
    fi
    git remote set-url origin "$REMOTE_URL"
}

# Automatically track large files with Git LFS
track_large_files() {
    if $GIT_LFS_ENABLED; then
        echo "Detecting files larger than $(($LARGE_FILE_SIZE / 1000000)) MB..."
        find . -type f -size +${LARGE_FILE_SIZE}c -not -path "./.git/*" | while read -r large_file; do
            echo "Tracking large file with Git LFS: $large_file"
            git lfs track "$large_file"
            git add .gitattributes "$large_file"
            git commit -m "Add large file $large_file with Git LFS" || {
                echo "Failed to commit $large_file due to GitHub size restrictions."
                echo "Consider compressing or moving the file to external storage."
            }
        done
    fi
}

# Check if SSH key exists; generate if missing
manage_ssh_key() {
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "No SSH key found. Generating a new SSH key..."
        ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$HOME/.ssh/id_ed25519" -q -N ""
        echo "SSH key generated at $HOME/.ssh/id_ed25519."
    fi

    echo "Copy the SSH key below and add it to your GitHub account under Settings > SSH and GPG keys > New SSH key:"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo -e "\nPress Enter after adding the SSH key to GitHub..."
    read -p ""

    # Test SSH connection to GitHub
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1)
    if [[ "$SSH_OUTPUT" != *"You've successfully authenticated"* ]]; then
        echo "SSH connection to GitHub failed. Ensure the SSH key is added to your GitHub account."
        exit 1
    fi
}

# Pull changes with automatic conflict resolution
pull_changes_with_conflict_handling() {
    set_remote_url "pull"
    if [ -n "$(git status --porcelain)" ]; then
        echo "Local changes detected. Stashing temporarily..."
        git stash push -m "Auto-stash before pull"
        echo "Pulling latest changes from remote..."
        git pull origin main --strategy-option=theirs || {
            echo "Conflict during pull. Resolving conflicts by accepting remote changes..."
            git reset --hard origin/main
        }
        echo "Applying stashed changes..."
        git stash pop || echo "No stash to apply."
    else
        echo "Updating local repository with latest changes from remote..."
        git pull origin main --strategy-option=theirs || {
            echo "Failed to pull changes. Resolving conflicts by accepting remote changes..."
            git reset --hard origin/main
        }
    fi
    echo "Local repository successfully updated."
}

# Push local changes to GitHub with automatic large file handling
push_changes() {
    set_remote_url "push"
    track_large_files

    # Check for any uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo "Staging and committing changes..."
        git add .
        git commit -m "Auto-commit: updating remote repository"
    else
        echo "No new changes to commit."
    fi

    # Push changes to GitHub
    echo "Pushing changes to GitHub..."
    git push origin main
    if [ $? -ne 0 ]; then
        echo "Failed to push changes. Please check your SSH key configuration and access rights."
        exit 1
    fi
    echo "Changes successfully pushed to the remote repository."
}

# Ensure dependencies and user configuration are set up
install_dependencies
load_or_prompt_user_info

# Prompt the user to choose pull or push
echo "Choose an action:"
echo "1) Update (pull latest changes)"
echo "2) Push new changes (requires SSH access)"
read -p "Enter your choice (1 for update, 2 for push): " user_action

# Run the appropriate function based on user action
if [ "$user_action" == "1" ]; then
    pull_changes_with_conflict_handling
    exit 0
elif [ "$user_action" == "2" ]; then
    manage_ssh_key
    push_changes
else
    echo "Invalid choice. Exiting."
    exit 1
fi


