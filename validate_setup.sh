#!/bin/bash

echo "Validating setup script..."

# Check if setup.sh exists
if [ ! -f "setup.sh" ]; then
    echo "❌ setup.sh not found"
    exit 1
fi

# Check syntax
echo "Checking bash syntax..."
if bash -n setup.sh; then
    echo "✅ Bash syntax is valid"
else
    echo "❌ Bash syntax errors found"
    exit 1
fi

# Check for common issues
echo "Checking for common issues..."

# Check for hardcoded storage
if grep -q "STORAGE=\"local\"" setup.sh; then
    echo "❌ Found hardcoded storage value"
else
    echo "✅ No hardcoded storage found"
fi

# Check for correct Ubuntu image
if grep -q "ubuntu-22.04-standard_22.04-1_amd64.tar.zst" setup.sh; then
    echo "✅ Correct Ubuntu 22.04 image found"
else
    echo "❌ Incorrect or missing Ubuntu 22.04 image"
fi

# Check for storage discovery logic
if grep -q "pvesm status -content rootdir" setup.sh; then
    echo "✅ Storage discovery logic found"
else
    echo "❌ Storage discovery logic missing"
fi

# Check for template download logic
if grep -q "pveam download" setup.sh; then
    echo "✅ Template download logic found"
else
    echo "❌ Template download logic missing"
fi

# Check for network auto-detection
if grep -q "ip route.*grep default" setup.sh; then
    echo "✅ Network auto-detection found"
else
    echo "❌ Network auto-detection missing"
fi

# Check for DHCP configuration
if grep -q "dhcp=1" setup.sh; then
    echo "✅ DHCP configuration found"
else
    echo "❌ DHCP configuration missing"
fi

# Check for error handling
if grep -q "fatal\|error\|warn" setup.sh; then
    echo "✅ Error handling functions found"
else
    echo "❌ Error handling functions missing"
fi

# Check for cleanup trap
if grep -q "trap cleanup EXIT" setup.sh; then
    echo "✅ Cleanup trap found"
else
    echo "❌ Cleanup trap missing"
fi

echo ""
echo "Validation complete!"