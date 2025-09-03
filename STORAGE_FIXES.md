# Storage Discovery Fixes

## Problem Description
The original setup script was failing with the error:
```
[FATAL] Storage local-lvm is not accessible
```

This occurred because the storage discovery logic was not robust enough to handle various Proxmox storage configurations and didn't provide adequate error handling or troubleshooting information.

## Root Causes Identified

1. **Limited Storage Discovery**: The original script only used `pvesm status -content rootdir` which might not work in all Proxmox configurations
2. **Poor Error Handling**: When storage discovery failed, the script provided minimal information about what went wrong
3. **No Fallback Mechanisms**: No alternative storage detection methods when the primary method failed
4. **Insufficient Validation**: Storage validation was basic and didn't check for container support properly
5. **No Troubleshooting Help**: Users had no guidance on how to fix storage issues
6. **Incorrect pvesm Usage**: The script was calling `pvesm status "$STORAGE"` which causes "400 too many arguments" error

## Fixes Implemented

### 1. Enhanced Storage Discovery
- **Multiple Discovery Methods**: Added fallback methods for finding available storages
- **Content Type Filtering**: Properly filters storages that support containers (rootdir/vztmpl)
- **Accessibility Checking**: Verifies each storage is actually accessible before including it

### 2. Robust Storage Validation
- **Thorough Accessibility Check**: Multiple validation steps to ensure storage is usable
- **Container Support Verification**: Checks if storage supports the required content types
- **Content Listing Test**: Verifies ability to list storage contents
- **Detailed Error Messages**: Provides specific information about what validation failed

### 3. Fallback Mechanisms
- **Common Storage Names**: Tries common storage names (local, local-lvm, local-zfs, pve, storage) as fallback
- **Graceful Degradation**: Continues trying different methods instead of failing immediately
- **Multiple Content Type Support**: Handles both 'rootdir' and 'vztmpl' content types

### 4. Enhanced Error Handling
- **Detailed Error Messages**: Each error provides context about what went wrong
- **Available Storage Display**: Shows all available storages when discovery fails
- **Storage Details**: Displays detailed information about each storage for debugging

### 5. Troubleshooting Function
- **Built-in Help**: Added `troubleshoot_storage()` function with step-by-step guidance
- **Common Issues**: Lists typical storage problems and solutions
- **Proxmox Web Interface**: Guides users to check storage configuration in the web UI
- **Command Line Tools**: Suggests commands to run for debugging

### 6. Disk Space Monitoring
- **Space Checking**: Verifies available disk space before proceeding
- **Warning System**: Alerts users if disk space is low
- **Storage Path Detection**: Automatically finds storage paths for space checking

### 7. Fixed pvesm Command Usage
- **Corrected Command Syntax**: Changed from `pvesm status "$STORAGE"` to `pvesm status | grep "^$STORAGE[[:space:]]"`
- **Eliminated 400 Error**: The "400 too many arguments" error is now resolved
- **Proper Storage Filtering**: Uses grep to filter the output of `pvesm status` instead of passing arguments

## Code Changes Made

### Storage Discovery Logic
```bash
# Before: Single method
STORAGE_LIST=($(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))

# After: Multiple methods with fallbacks
STORAGE_LIST=($(pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
# Fallback to content-specific discovery
# Fallback to common storage names
```

### Storage Validation
```bash
# Before: Basic check with incorrect syntax
if ! pvesm status "$STORAGE" >/dev/null 2>&1; then
    fatal "Storage $STORAGE is not accessible"
fi

# After: Comprehensive validation with correct syntax
STORAGE_DETAILS=$(pvesm status 2>/dev/null | grep "^$STORAGE[[:space:]]")
if [ -z "$STORAGE_DETAILS" ]; then
    error "Storage $STORAGE not found in available storages"
    # ... detailed error handling
fi
```

### Error Handling
```bash
# Before: Simple fatal error
fatal "Storage $STORAGE is not accessible"

# After: Detailed error with troubleshooting
error "Storage $STORAGE not found in available storages"
error "Available storages:"
pvesm status 2>/dev/null || error "Could not get storage status"
troubleshoot_storage
fatal "Storage $STORAGE is not accessible"
```

## Critical Fix: pvesm Command Usage

### The Problem
The original code was incorrectly calling:
```bash
pvesm status "$STORAGE"  # This causes "400 too many arguments" error
```

### The Solution
Changed to the correct approach:
```bash
STORAGE_DETAILS=$(pvesm status 2>/dev/null | grep "^$STORAGE[[:space:]]")
```

### Why This Fixes the Error
- `pvesm status` expects no arguments and lists all storages
- We then use `grep` to filter for the specific storage we want
- This eliminates the "400 too many arguments" error
- The storage details are extracted from the filtered output

### Files Fixed
- `setup.sh` - Main setup script
- `test_storage_discovery.sh` - Test script for storage discovery

## Benefits of the Fixes

1. **Higher Success Rate**: Multiple discovery methods increase chances of finding usable storage
2. **Better User Experience**: Clear error messages and troubleshooting guidance
3. **Easier Debugging**: Detailed information about what's available and what's failing
4. **Robust Fallbacks**: Continues working even when primary methods fail
5. **Proactive Monitoring**: Checks disk space and warns about potential issues
6. **Self-Help**: Users can resolve many issues without external assistance
7. **No More 400 Errors**: The pvesm command usage is now correct and won't cause argument errors

## Testing the Fixes

The updated script now:
- ✅ Passes all validation checks
- ✅ Has proper bash syntax
- ✅ Includes comprehensive storage discovery
- ✅ Provides detailed error messages
- ✅ Offers troubleshooting guidance
- ✅ Monitors disk space
- ✅ Handles multiple storage types
- ✅ Uses correct pvesm command syntax
- ✅ Eliminates "400 too many arguments" errors

## Usage

The improved script will now:
1. Try multiple methods to discover available storages
2. Validate each storage thoroughly before use
3. Provide detailed error messages if issues occur
4. Offer troubleshooting steps for common problems
5. Check disk space and warn about low space
6. Fall back to common storage names if needed
7. Use correct pvesm commands without argument errors

This should resolve both the "Storage local-lvm is not accessible" error and the "400 too many arguments" error, providing a much more robust storage discovery experience.