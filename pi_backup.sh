#!/bin/bash

# =================================================================
# Automated System Backup Script
# Description: Automated backup script with rotation and logging
# Version: 1.0
# =================================================================

# =================================================================
# CONFIGURATION - MODIFY THESE PATHS TO MATCH YOUR SYSTEM
# =================================================================

# Basic Configuration (Required) - Change these values
# ------------------------------------------------------------------
readonly HOSTNAME="system-name"                              # Change this to your system name
readonly SOURCE_DIR="/path/to/your/backup/directory"         # Directory for new backups
readonly ARCHIVE_DIR="/path/to/your/archive/directory"       # Directory for backup archives
readonly DEVICE_TO_BACKUP="/dev/sdX"                         # Change to your device (e.g., /dev/sda, /dev/mmcblk0)

# Advanced Configuration (Optional) - Modify if needed
# ------------------------------------------------------------------
readonly BACKUP_DATE=$(date +"%m-%d-%Y")
readonly LOG_DIR="${SOURCE_DIR}/backup_logs"
readonly BACKUP_FILE="${SOURCE_DIR}/${HOSTNAME}_backup_${BACKUP_DATE}.img"
readonly LOG_FILE="${LOG_DIR}/backup_${BACKUP_DATE}.log"
readonly LOG_RETAIN_DAYS=30
readonly SLEEP_DURATION=300  # 5 minutes in seconds

# =================================================================
# SCRIPT BEGINS HERE - DO NOT MODIFY UNLESS YOU KNOW WHAT YOU'RE DOING
# =================================================================

# Set strict error handling
set -euo pipefail

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local message="$1"
    local log_time="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "${log_time} $message" | tee -a "$LOG_FILE"
}

# Function to rotate old logs
rotate_logs() {
    log "Starting log rotation"
    find "$LOG_DIR" -name "backup_*.log" -type f -mtime +"$LOG_RETAIN_DAYS" -exec rm {} \;
    log "Completed log rotation - removed logs older than $LOG_RETAIN_DAYS days"
}

# Function to verify mount points
check_mounts() {
    local mount_points=("$SOURCE_DIR" "$ARCHIVE_DIR")
    for mount in "${mount_points[@]}"; do
        if ! mountpoint -q "$mount"; then
            log "ERROR: $mount is not mounted"
            return 1
        fi
    done
    log "All mount points verified"
    return 0
}

# Function to create backup using dd
create_backup() {
    log "Starting backup creation to $BACKUP_FILE"
    if sudo dd bs=4M if="$DEVICE_TO_BACKUP" of="$BACKUP_FILE" status=progress 2>> "$LOG_FILE"; then
        log "Backup created successfully"
        sync  # Ensure all data is written to disk
        return 0
    else
        log "ERROR: Backup creation failed"
        return 1
    fi
}

# Function to check if directories exist
check_directories() {
    for dir in "$ARCHIVE_DIR" "$SOURCE_DIR" "$LOG_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log "ERROR: Directory $dir does not exist"
            exit 1
        fi
    done
}

# Function to check available disk space
check_disk_space() {
    local required_space=$((10 * 1024 * 1024)) # 10GB in KB
    local available_space=$(df -k "$SOURCE_DIR" | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        log "ERROR: Insufficient disk space. Required: 10GB, Available: $((available_space/1024/1024))GB"
        return 1
    fi
    
    log "Disk space check passed. Available: $((available_space/1024/1024))GB"
    return 0
}

# Function to create summary report
create_summary() {
    local summary_file="${LOG_DIR}/backup_summary_${BACKUP_DATE}.txt"
    {
        echo "Backup Summary - ${BACKUP_DATE}"
        echo "----------------------------------------"
        echo "System: $HOSTNAME"
        echo "Backup File: $BACKUP_FILE"
        echo "Backup Size: $(du -h "$BACKUP_FILE" 2>/dev/null | cut -f1 || echo 'N/A')"
        echo "Available Space: $(df -h "$SOURCE_DIR" | awk 'NR==2 {print $4}')"
        echo "Archive Space: $(df -h "$ARCHIVE_DIR" | awk 'NR==2 {print $4}')"
        echo "----------------------------------------"
    } > "$summary_file"
    log "Created backup summary at $summary_file"
}

# Main script
main() {
    log "Starting backup script"
    log "----------------------------------------"
    
    # Initial checks
    check_mounts || exit 1
    check_directories
    check_disk_space || exit 1
    rotate_logs
    
    # Find existing backups
    local archive_file=$(find "$ARCHIVE_DIR" -name "${HOSTNAME}*.img" -print -quit)
    local source_file=$(find "$SOURCE_DIR" -name "${HOSTNAME}*.img" -print -quit)

    # Case 1: Only archive backup exists
    if [[ -n "$archive_file" && -z "$source_file" ]]; then
        log "Current backup missing, archive exists. Making current backup."
        create_backup
        create_summary

    # Case 2: Only source backup exists
    elif [[ -z "$archive_file" && -n "$source_file" ]]; then
        log "Archive backup does not exist"
        log "Moving current backup to archive: $source_file"
        mv "$source_file" "$ARCHIVE_DIR/"
        log "Creating new backup"
        create_backup
        create_summary

    # Case 3: Both backups exist
    elif [[ -n "$archive_file" && -n "$source_file" ]]; then
        log "All backups exist! Starting rotation process"
        log "Removing old archive: $archive_file"
        rm "$archive_file"
        
        log "Waiting $SLEEP_DURATION seconds before proceeding..."
        sleep "$SLEEP_DURATION"
        
        log "Moving recent backup to archive"
        mv "$source_file" "$ARCHIVE_DIR/"
        
        log "Creating new backup"
        create_backup
        create_summary

    # Case 4: No backups exist
    else
        log "No backups exist! Creating initial backup."
        create_backup
        create_summary
    fi

    log "Backup script completed successfully"
    log "----------------------------------------"
}

# Trap for cleanup on script exit
trap 'log "Script interrupted. Cleaning up..."; exit 1' INT TERM

# Run main function
main "$@" || {
    exit_code=$?
    log "Script failed with exit code $exit_code"
    exit $exit_code
}
