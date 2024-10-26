#!/bin/bash

# Ensure Git is installed
if ! command -v git &> /dev/null; then
    echo "Git is not installed. Installing Git..."
    sudo apt-get update
    sudo apt-get install -y git
    if [ $? -ne 0 ]; then
        echo "Failed to install Git. Please check your network connection or permissions."
        exit 1
    fi
    echo "Git installed successfully."
else
    echo "Git is already installed."
fi

# Configuration files
CONFIG_FILE=".git_config"
DIR_CONFIG_FILE=".git_dir_config"
LARGE_FILE_SIZE=100000000  # Set the size threshold to 100 MB (GitHub's limit)

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
            read -p "Enter your GitHub username (e.g., surajnsharma): " GITHUB_USER
        done
        while [[ -z "$GITHUB_EMAIL" ]]; do
            read -p "Enter your GitHub email (e.g., surajshamra@juniper.net): " GITHUB_EMAIL
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

    # Set global Git configurations if not already set
    git config --global user.name "$GITHUB_USER"
    git config --global user.email "$GITHUB_EMAIL"
}

# Load or prompt for GitHub user information
load_or_prompt_user_info

# Check if SSH key exists; generate if missing
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -C "$GITHUB_EMAIL" -f "$HOME/.ssh/id_ed25519" -q -N ""
    if [ $? -ne 0 ]; then
        echo "Failed to generate SSH key. Please check your permissions and try again."
        exit 1
    fi
    echo "SSH key generated."
else
    echo "SSH key already exists. Key location: $HOME/.ssh/id_ed25519"
fi

# Display SSH key and prompt to add to GitHub if not added
echo "Copy the SSH key below and add it to your GitHub account under Settings > SSH and GPG keys > New SSH key:"
cat "$HOME/.ssh/id_ed25519.pub"
echo -e "\nPress Enter after adding the SSH key to GitHub..."
read -p ""

# Test SSH connection to GitHub
echo "Testing SSH connection to GitHub..."
SSH_OUTPUT=$(ssh -T git@github.com 2>&1)
if [[ "$SSH_OUTPUT" == *"You've successfully authenticated"* ]]; then
    echo "SSH connection to GitHub was successful."
elif [[ "$SSH_OUTPUT" == *"Permission denied (publickey)"* ]]; then
    echo "SSH connection to GitHub failed due to missing public key."
    echo "Please ensure your SSH key is added to your GitHub account under Settings > SSH and GPG keys > New SSH key."
    echo "Copy the SSH key below and add it to your GitHub account:"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo -e "\nAfter adding the SSH key, re-run the script.\n"
    exit 1
else
    echo "SSH connection to GitHub failed. Ensure the SSH key is added to your GitHub account."
    echo "Output from SSH: $SSH_OUTPUT"
    exit 1
fi



# Initialize Git repository if not already initialized
if [ ! -d ".git" ]; then
    echo "Initializing Git repository..."
    git init
    if [ $? -ne 0 ]; then
        echo "Failed to initialize Git repository. Check directory permissions."
        exit 1
    fi
fi

# Set remote URL to use SSH, or update it if it already exists
REMOTE_URL="git@github.com:$GITHUB_USER/$REPO_NAME.git"
if git remote get-url origin &> /dev/null; then
    echo "Updating existing remote URL to $REMOTE_URL"
    git remote set-url origin "$REMOTE_URL"
else
    echo "Setting remote URL to $REMOTE_URL"
    git remote add origin "$REMOTE_URL"
fi
git remote -v

# Load or prompt for directory to stage and commit files
load_or_prompt_directory() {
    if [ -f "$DIR_CONFIG_FILE" ]; then
        source "$DIR_CONFIG_FILE"
        echo "Default directory for staging files: $TARGET_DIR"
        echo -e "\nPress Enter to keep this directory or type a new directory path to change."
        read -p "" new_dir
        if [ ! -z "$new_dir" ]; then
            TARGET_DIR="$new_dir"
        fi
    else
        read -p "Enter the directory to stage and commit files (e.g., /home/user/project): " TARGET_DIR
    fi

    # Save chosen directory to .git_dir_config file
    echo "TARGET_DIR=\"$TARGET_DIR\"" > "$DIR_CONFIG_FILE"
    echo "Directory saved to $DIR_CONFIG_FILE"
}

# Load or prompt for staging directory
load_or_prompt_directory

# Navigate to the specified directory
cd "$TARGET_DIR" || { echo "Directory $TARGET_DIR does not exist. Exiting."; exit 1; }

# Check branch and set to main
echo "Setting branch to 'main'..."
git branch -M main

# Stage and commit files if there are changes
if [ -n "$(git status --porcelain)" ]; then
    echo "Staging and committing changes..."
    git add .
    git commit -m "Auto-commit: updates to repository"
else
    echo "No new changes to commit."
fi

# Install Git Large File Storage (LFS) if not already installed
if ! command -v git-lfs &> /dev/null; then
    echo "Installing Git LFS..."
    sudo apt-get install -y git-lfs
    git lfs install
    if [ $? -ne 0 ]; then
        echo "Failed to install Git LFS. Please check your network connection or permissions."
        exit 1
    fi
fi

# Automatically detect large files and attempt to track them with Git LFS
echo "Detecting files larger than $(($LARGE_FILE_SIZE / 1000000)) MB..."
find . -type f -size +${LARGE_FILE_SIZE}c -not -path "./.git/*" | while read -r large_file; do
    echo "Tracking large file with Git LFS: $large_file"
    git lfs track "$large_file"
    git add .gitattributes
    git add "$large_file"
    git commit -m "Add large file $large_file with Git LFS" || {
        echo "Failed to commit $large_file due to GitHub size restrictions."
        echo "Consider one of the following options for $large_file:"
        echo "1. Use an external storage solution (e.g., Google Drive, Dropbox) and link to the file."
        echo "2. Compress the file to reduce its size."
        echo "3. Remove the file from the repository and add it to .gitignore if it doesn't need to be versioned."
        echo "Skipping $large_file."
    }
done

# Push to GitHub
echo "Pushing to GitHub..."
git push -u origin main
if [ $? -ne 0 ]; then
    echo "Push failed. Please check your repository settings and access rights."
    exit 1
fi

echo "Repository setup and push complete. Any new changes have been committed and pushed."

