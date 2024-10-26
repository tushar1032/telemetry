#!/bin/bash

# Set variables for gnmic binary, download URL, and file paths
GNMIC_BINARY="gnmic"
LOCAL_GNMIC_PACKAGE="gnmic_0.38.2_linux_x86_64.tar.gz"  # Adjust version as needed
DOWNLOAD_URL="https://github.com/openconfig/gnmic/releases/download/v0.38.2/$LOCAL_GNMIC_PACKAGE"
GNMIC_PATH="/usr/local/bin/$GNMIC_BINARY"
DEVICES_FILE="devices.text"
SENSOR_FILE="sensor.text"
OUTPUT_FILE="gnmic_telemetry.log"

# Function to download gnmic from local package if available, else download from the web
download_gnmic() {
    if [[ -f "$GNMIC_PATH" ]]; then
        echo "gnmic is already installed at $GNMIC_PATH."
    elif [[ -f "$LOCAL_GNMIC_PACKAGE" ]]; then
        echo "Local gnmic package found. Installing gnmic from local file..."
        sudo tar -xzf "$LOCAL_GNMIC_PACKAGE" -C /usr/local/bin
        if [[ -f "$GNMIC_PATH" ]]; then
            echo "gnmic installed successfully from local package."
        else
            echo "Failed to install gnmic from local package."
            exit 1
        fi
    else
        echo "Local package not found. Downloading gnmic from the web..."
        curl -sLO $DOWNLOAD_URL
        if [[ -f "$LOCAL_GNMIC_PACKAGE" ]]; then
            sudo tar -xzf "$LOCAL_GNMIC_PACKAGE" -C /usr/local/bin
            echo "gnmic downloaded and installed successfully."
        else
            echo "Failed to download gnmic."
            exit 1
        fi
    fi
}

# Function to uninstall gnmic
uninstall_gnmic() {
    if [[ -f "$GNMIC_PATH" ]]; then
        echo "Uninstalling gnmic..."
        sudo rm -f "$GNMIC_PATH"
        
        if [[ ! -f "$GNMIC_PATH" ]]; then
            echo "gnmic uninstalled successfully."
        else
            echo "Failed to uninstall gnmic."
            exit 1
        fi
    else
        echo "gnmic is not installed."
    fi
}

# Function to read device credentials and addresses from devices.text
read_devices_and_credentials() {
    if [[ ! -f "$DEVICES_FILE" ]]; then
        echo "Devices file $DEVICES_FILE not found!"
        exit 1
    fi

    # Extract credentials
    username=$(grep -oP '(?<=username=)[^,]*' $DEVICES_FILE)
    password=$(grep -oP '(?<=password=)[^,]*' $DEVICES_FILE)

    # Display devices excluding lines with credentials
    echo "Available devices:"
    grep -Ev "username|password" $DEVICES_FILE | cat -n
    read -p "Select device(s) to subscribe (enter 'all' for all devices): " device_choice

    if [[ "$device_choice" == "all" ]]; then
        selected_devices=($(grep -Ev "username|password" $DEVICES_FILE))
    else
        selected_devices=($(grep -Ev "username|password" $DEVICES_FILE | sed -n "${device_choice}p"))
    fi
}

# Function to read sensor paths from sensor.text
read_sensors() {
    if [[ ! -f "$SENSOR_FILE" ]]; then
        echo "Sensors file $SENSOR_FILE not found!"
        exit 1
    fi

    echo "Available sensor paths:"
    cat -n $SENSOR_FILE
    read -p "Select sensor path(s) (enter 'all' for all paths): " sensor_choice

    if [[ "$sensor_choice" == "all" ]]; then
        selected_sensors=($(cat $SENSOR_FILE))
    else
        selected_sensors=($(sed -n "${sensor_choice}p" $SENSOR_FILE))
    fi
}

# Function to execute a single subscribe RPC and save the output
execute_subscribe_once() {
    : > $OUTPUT_FILE  # Clear the output file if it exists
    for device in "${selected_devices[@]}"; do
        echo "Subscribing to device: $device" | tee -a $OUTPUT_FILE
        paths=""
        for sensor in "${selected_sensors[@]}"; do
            paths+=" --path $sensor"
        done
        # Run the subscription and save to file
        $GNMIC_PATH -a $device -u $username -p $password --insecure subscribe $paths --encoding json --once >> $OUTPUT_FILE 2>&1
        echo "Subscription for $device completed and saved to $OUTPUT_FILE."
    done
}

# User menu
echo "Choose an action:"
echo "1) Download gnmic"
echo "2) Uninstall gnmic"
echo "3) Subscribe to telemetry data and save to file"
echo "4) Exit"
read -p "Enter your choice: " choice

case $choice in
    1) download_gnmic ;;
    2) uninstall_gnmic ;;
    3) 
        read_devices_and_credentials
        read_sensors
        execute_subscribe_once
        ;;
    4) echo "Exiting." ;;
    *) echo "Invalid choice. Exiting." ;;
esac

