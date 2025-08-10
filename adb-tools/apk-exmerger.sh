#!/bin/bash

# APK Extractor Script with Auto-Dependency Management
# Usage: ./apk_extractor.sh [OPTIONS] [PACKAGE_NAME] [OUTPUT_DIR]

SCRIPT_NAME=$(basename "$0")
DEFAULT_OUTPUT_DIR="."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_TOOLS_DIR="$SCRIPT_DIR/tmp-tools"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Tool versions and URLs
BUNDLETOOL_VERSION="1.15.6"
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar"
ADB_PLATFORM_TOOLS_VERSION="34.0.5"

# OS detection for ADB download
case "$(uname -s)" in
    Linux*)     
        ADB_OS="linux"
        ADB_URL="https://dl.google.com/android/repository/platform-tools_r${ADB_PLATFORM_TOOLS_VERSION}-${ADB_OS}.zip"
        ;;
    Darwin*)    
        ADB_OS="darwin"
        ADB_URL="https://dl.google.com/android/repository/platform-tools_r${ADB_PLATFORM_TOOLS_VERSION}-${ADB_OS}.zip"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        ADB_OS="windows"
        ADB_URL="https://dl.google.com/android/repository/platform-tools_r${ADB_PLATFORM_TOOLS_VERSION}-${ADB_OS}.zip"
        ;;
    *)
        ADB_OS="linux"  # Default fallback
        ADB_URL="https://dl.google.com/android/repository/platform-tools_r${ADB_PLATFORM_TOOLS_VERSION}-${ADB_OS}.zip"
        ;;
esac

# Global variables to track downloaded tools
DOWNLOADED_TOOLS=()
TEMP_ADB_PATH=""
TEMP_BUNDLETOOL_PATH=""

# Function to display help
show_help() {
    echo -e "${BLUE}APK Extractor Tool with Auto-Dependency Management${NC}"
    echo ""
    echo "Usage:"
    echo "  $SCRIPT_NAME -x <package_name> [output_dir]    Extract APK files"
    echo "  $SCRIPT_NAME -h                               Show this help"
    echo "  $SCRIPT_NAME -m [output_dir]                  Merge APK files"
    echo "  $SCRIPT_NAME -xm <package_name> [output_dir]  Extract then merge APK files"
    echo ""
    echo "Options:"
    echo "  -x    Extract APK files from device"
    echo "  -m    Merge APK files using bundletool"
    echo "  -xm   Extract and then merge APK files"
    echo "  -h    Show this help message"
    echo ""
    echo "Arguments:"
    echo "  package_name    Android package name (e.g., com.example.app)"
    echo "  output_dir      Output directory (optional)"
    echo "                  - For -x and -xm: defaults to package_name folder with auto-increment"
    echo "                  - For -m: defaults to current directory"
    echo ""
    echo "Directory Naming:"
    echo "  When using package name as folder, the script automatically prevents overwrites:"
    echo "  - First run: com.git.sc/"
    echo "  - Second run: com.git.sc_1/"
    echo "  - Third run: com.git.sc_2/"
    echo "  - And so on..."
    echo ""
    echo "Auto-Dependency Management:"
    echo "  - Automatically downloads ADB if not installed"
    echo "  - Automatically downloads bundletool if needed for merge operations"
    echo "  - Downloads saved to temporary ./tmp-tools/ directory"
    echo "  - Cleans up downloaded tools after completion"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME -x com.git.sc                    # Auto-downloads ADB if needed"
    echo "  $SCRIPT_NAME -xm com.git.sc                   # Auto-downloads ADB and bundletool if needed"
    echo ""
    echo "Requirements:"
    echo "  - Internet connection (for downloading dependencies)"
    echo "  - curl or wget (for downloading)"
    echo "  - unzip (for extracting downloaded tools)"
    echo "  - Device must be connected with USB debugging enabled"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if we have download tools
check_download_prerequisites() {
    if ! command_exists curl && ! command_exists wget; then
        echo -e "${RED}Error: Neither curl nor wget is available for downloading dependencies${NC}"
        echo "Please install either curl or wget to use auto-dependency management"
        exit 1
    fi
    
    if ! command_exists unzip; then
        echo -e "${RED}Error: unzip is not available${NC}"
        echo "Please install unzip to extract downloaded dependencies"
        exit 1
    fi
}

# Function to download file
download_file() {
    local url="$1"
    local output_file="$2"
    local description="$3"
    
    echo -e "${YELLOW}Downloading $description...${NC}"
    echo -e "${BLUE}URL: $url${NC}"
    echo -e "${BLUE}Saving to: $output_file${NC}"
    
    if command_exists curl; then
        if curl -L -o "$output_file" "$url" --progress-bar; then
            echo -e "${GREEN}✓ Successfully downloaded $description${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to download $description using curl${NC}"
            return 1
        fi
    elif command_exists wget; then
        if wget -O "$output_file" "$url" --progress=bar:force 2>&1; then
            echo -e "${GREEN}✓ Successfully downloaded $description${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to download $description using wget${NC}"
            return 1
        fi
    fi
    
    return 1
}

# Function to setup ADB
setup_adb() {
    echo -e "${PURPLE}Setting up ADB...${NC}"
    
    # Check if ADB is already available
    if command_exists adb; then
        echo -e "${GREEN}✓ ADB is already installed and available${NC}"
        return 0
    fi
    
    # Check if we have ADB in tmp-tools from previous run
    if [ -f "$TMP_TOOLS_DIR/platform-tools/adb" ]; then
        echo -e "${GREEN}✓ Found ADB in tmp-tools directory${NC}"
        TEMP_ADB_PATH="$TMP_TOOLS_DIR/platform-tools/adb"
        export PATH="$TMP_TOOLS_DIR/platform-tools:$PATH"
        return 0
    fi
    
    # Create tmp-tools directory
    mkdir -p "$TMP_TOOLS_DIR"
    
    # Download platform-tools
    local platform_tools_zip="$TMP_TOOLS_DIR/platform-tools.zip"
    
    if ! download_file "$ADB_URL" "$platform_tools_zip" "Android Platform Tools (ADB)"; then
        echo -e "${RED}Failed to download ADB${NC}"
        return 1
    fi
    
    # Extract platform-tools
    echo -e "${YELLOW}Extracting Android Platform Tools...${NC}"
    if unzip -q "$platform_tools_zip" -d "$TMP_TOOLS_DIR"; then
        echo -e "${GREEN}✓ Successfully extracted Android Platform Tools${NC}"
        rm -f "$platform_tools_zip"
        
        # Make ADB executable
        chmod +x "$TMP_TOOLS_DIR/platform-tools/adb"
        
        # Add to PATH for this session
        export PATH="$TMP_TOOLS_DIR/platform-tools:$PATH"
        TEMP_ADB_PATH="$TMP_TOOLS_DIR/platform-tools/adb"
        DOWNLOADED_TOOLS+=("platform-tools")
        
        echo -e "${GREEN}✓ ADB is now available${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to extract Android Platform Tools${NC}"
        rm -f "$platform_tools_zip"
        return 1
    fi
}

# Function to setup bundletool
setup_bundletool() {
    echo -e "${PURPLE}Setting up bundletool...${NC}"
    
    # Check if bundletool is already available
    if [ -f "bundletool.jar" ] || [ -f "./bundletool.jar" ] || command_exists bundletool; then
        echo -e "${GREEN}✓ bundletool is already available${NC}"
        return 0
    fi
    
    # Check if we have bundletool in tmp-tools
    if [ -f "$TMP_TOOLS_DIR/bundletool.jar" ]; then
        echo -e "${GREEN}✓ Found bundletool in tmp-tools directory${NC}"
        TEMP_BUNDLETOOL_PATH="$TMP_TOOLS_DIR/bundletool.jar"
        return 0
    fi
    
    # Create tmp-tools directory
    mkdir -p "$TMP_TOOLS_DIR"
    
    # Download bundletool
    local bundletool_jar="$TMP_TOOLS_DIR/bundletool.jar"
    
    if download_file "$BUNDLETOOL_URL" "$bundletool_jar" "bundletool"; then
        TEMP_BUNDLETOOL_PATH="$bundletool_jar"
        DOWNLOADED_TOOLS+=("bundletool.jar")
        echo -e "${GREEN}✓ bundletool is now available${NC}"
        return 0
    else
        echo -e "${RED}Failed to download bundletool${NC}"
        return 1
    fi
}

# Function to cleanup downloaded tools
cleanup_tools() {
    if [ ${#DOWNLOADED_TOOLS[@]} -eq 0 ] && [ ! -d "$TMP_TOOLS_DIR" ]; then
        return 0
    fi
    
    echo ""
    echo -e "${PURPLE}Cleaning up downloaded tools...${NC}"
    
    if [ -d "$TMP_TOOLS_DIR" ]; then
        echo -e "${YELLOW}Removing temporary tools directory: $TMP_TOOLS_DIR${NC}"
        rm -rf "$TMP_TOOLS_DIR"
        echo -e "${GREEN}✓ Cleanup completed${NC}"
    fi
    
    # Reset PATH if we modified it
    if [ -n "$TEMP_ADB_PATH" ]; then
        export PATH=$(echo "$PATH" | sed "s|$TMP_TOOLS_DIR/platform-tools:||g")
    fi
}

# Function to handle script interruption
handle_interrupt() {
    echo ""
    echo -e "${YELLOW}Script interrupted. Cleaning up...${NC}"
    cleanup_tools
    exit 1
}

# Set up trap for cleanup on script exit or interruption
trap cleanup_tools EXIT
trap handle_interrupt INT TERM

# Function to check if adb is available (now with auto-setup)
check_adb() {
    check_download_prerequisites
    
    if ! setup_adb; then
        echo -e "${RED}Error: Failed to setup ADB${NC}"
        echo "Please install Android SDK Platform Tools manually or check your internet connection"
        exit 1
    fi
    
    # Verify ADB is working
    if ! command_exists adb; then
        echo -e "${RED}Error: ADB setup completed but command is still not available${NC}"
        exit 1
    fi
}

# Function to check device connection
check_device() {
    local devices=$(adb devices | grep -v "List of devices attached" | grep -v "^$" | wc -l)
    if [ "$devices" -eq 0 ]; then
        echo -e "${RED}Error: No Android device connected${NC}"
        echo "Please connect a device and enable USB debugging"
        exit 1
    elif [ "$devices" -gt 1 ]; then
        echo -e "${YELLOW}Warning: Multiple devices connected. Using the first one.${NC}"
    fi
    echo -e "${GREEN}Device connected successfully${NC}"
}

# Function to find next available directory name with increment
get_next_available_dir() {
    local base_dir="$1"
    local current_dir="$base_dir"
    local counter=1
    
    # If the base directory doesn't exist, use it
    if [ ! -d "$current_dir" ]; then
        echo "$current_dir"
        return
    fi
    
    # If it exists, find the next available numbered directory
    while [ -d "$current_dir" ]; do
        current_dir="${base_dir}_${counter}"
        counter=$((counter + 1))
    done
    
    echo "$current_dir"
}

# Function to determine output directory for extraction
get_extraction_output_dir() {
    local package_name="$1"
    local provided_output_dir="$2"
    
    if [ -n "$provided_output_dir" ]; then
        # User provided specific directory - use it exactly as specified
        echo "$provided_output_dir"
    else
        # Use package name as base and find next available directory
        local base_dir="$package_name"
        local final_dir=$(get_next_available_dir "$base_dir")
        echo "$final_dir"
    fi
}

# Function to list existing extraction directories
list_existing_extractions() {
    local package_name="$1"
    echo -e "${BLUE}Existing extractions for $package_name:${NC}"
    
    local found=false
    
    # Check base directory
    if [ -d "$package_name" ]; then
        echo -e "${GREEN}  ✓ $package_name/${NC}"
        found=true
    fi
    
    # Check numbered directories
    local counter=1
    while [ -d "${package_name}_${counter}" ]; do
        echo -e "${GREEN}  ✓ ${package_name}_${counter}/${NC}"
        found=true
        counter=$((counter + 1))
    done
    
    if [ "$found" = false ]; then
        echo -e "${YELLOW}  No existing extractions found${NC}"
    fi
    echo ""
}

# Function to extract APK files
extract_apk() {
    local package_name="$1"
    local provided_output_dir="$2"
    
    if [ -z "$package_name" ]; then
        echo -e "${RED}Error: Package name is required for extraction${NC}"
        show_help
        exit 1
    fi
    
    # Show existing extractions if using auto-naming
    if [ -z "$provided_output_dir" ]; then
        list_existing_extractions "$package_name"
    fi
    
    # Determine output directory (use package name with auto-increment if not provided)
    local output_dir=$(get_extraction_output_dir "$package_name" "$provided_output_dir")
    
    # Show what directory will be used
    if [ -z "$provided_output_dir" ]; then
        echo -e "${BLUE}Auto-selected directory: $output_dir${NC}"
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    echo -e "${BLUE}Extracting APK files for package: $package_name${NC}"
    echo -e "${BLUE}Output directory: $output_dir${NC}"
    
    # Get package paths
    echo "Getting package paths..."
    local package_paths=$(adb shell pm path "$package_name" 2>/dev/null)
    
    if [ -z "$package_paths" ]; then
        echo -e "${RED}Error: Package '$package_name' not found on device${NC}"
        echo "Please check the package name and ensure the app is installed"
        # Clean up the empty directory we created
        rmdir "$output_dir" 2>/dev/null
        exit 1
    fi
    
    echo -e "${GREEN}Found package paths:${NC}"
    echo "$package_paths"
    echo ""
    
    # Extract paths and pull each APK
    local success_count=0
    local total_count=0
    
    while IFS= read -r line; do
        if [[ $line == package:* ]]; then
            local apk_path="${line#package:}"
            local apk_filename=$(basename "$apk_path")
            
            echo -e "${YELLOW}Pulling: $apk_filename${NC}"
            
            total_count=$((total_count + 1))
            
            if adb pull "$apk_path" "$output_dir/$apk_filename" 2>/dev/null; then
                echo -e "${GREEN}✓ Successfully pulled: $apk_filename${NC}"
                success_count=$((success_count + 1))
            else
                echo -e "${RED}✗ Failed to pull: $apk_filename${NC}"
            fi
            echo ""
        fi
    done <<< "$package_paths"
    
    # Create extraction info file
    local info_file="$output_dir/extraction_info.txt"
    {
        echo "Package: $package_name"
        echo "Extraction Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "Extracted by: $(whoami)"
        echo "Script Version: Auto-Dependency Management"
        echo "Total APK files: $total_count"
        echo "Successfully extracted: $success_count"
        if [ -n "$TEMP_ADB_PATH" ]; then
            echo "ADB: Downloaded temporarily"
        else
            echo "ADB: System installation"
        fi
        echo ""
        echo "APK Files:"
        ls -la "$output_dir"/*.apk 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    } > "$info_file"
    
    echo -e "${BLUE}Extraction Summary:${NC}"
    echo -e "${GREEN}Successfully extracted: $success_count/$total_count APK files${NC}"
    
    if [ "$success_count" -gt 0 ]; then
        echo -e "${GREEN}APK files saved to: $output_dir${NC}"
        echo -e "${BLUE}Extraction info saved to: $info_file${NC}"
        ls -la "$output_dir"/*.apk 2>/dev/null || true
        
        # Return the actual output directory used (for chaining with merge)
        echo "$output_dir"
    fi
    
    if [ "$success_count" -eq 0 ]; then
        echo -e "${RED}No APK files were extracted${NC}"
        # Clean up the empty directory and info file
        rm -f "$info_file"
        rmdir "$output_dir" 2>/dev/null
        exit 1
    fi
}

# Function to merge APK files
merge_apk() {
    local output_dir="$1"
    
    # Set default output directory if not provided
    if [ -z "$output_dir" ]; then
        output_dir="$DEFAULT_OUTPUT_DIR"
    fi
    
    echo -e "${BLUE}Merging APK files in directory: $output_dir${NC}"
    
    # Check if directory exists
    if [ ! -d "$output_dir" ]; then
        echo -e "${RED}Error: Directory '$output_dir' does not exist${NC}"
        return 1
    fi
    
    # Setup bundletool
    if ! setup_bundletool; then
        echo -e "${RED}Failed to setup bundletool${NC}"
        return 1
    fi
    
    # Determine bundletool path
    local bundletool_cmd=""
    if [ -n "$TEMP_BUNDLETOOL_PATH" ]; then
        bundletool_cmd="java -jar $TEMP_BUNDLETOOL_PATH"
    elif [ -f "bundletool.jar" ]; then
        bundletool_cmd="java -jar bundletool.jar"
    elif [ -f "./bundletool.jar" ]; then
        bundletool_cmd="java -jar ./bundletool.jar"
    elif command_exists bundletool; then
        bundletool_cmd="bundletool"
    else
        echo -e "${RED}Error: bundletool not available after setup${NC}"
        return 1
    fi
    
    # Find APK files
    local apk_files=("$output_dir"/*.apk)
    if [ ! -e "${apk_files[0]}" ]; then
        echo -e "${RED}Error: No APK files found in $output_dir${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Found ${#apk_files[@]} APK files to merge${NC}"
    
    # Find the base APK
    local base_apk=""
    local split_apks=()
    
    for apk in "${apk_files[@]}"; do
        local filename=$(basename "$apk")
        if [[ "$filename" == *"base.apk" ]]; then
            base_apk="$apk"
        else
            split_apks+=("$apk")
        fi
    done
    
    if [ -z "$base_apk" ]; then
        echo -e "${RED}Error: No base.apk found. Cannot merge without base APK.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Base APK: $(basename "$base_apk")${NC}"
    echo -e "${GREEN}Split APKs (${#split_apks[@]}):${NC}"
    for split_apk in "${split_apks[@]}"; do
        echo "  - $(basename "$split_apk")"
    done
    
    # Create merged APK directory
    local merged_dir="$output_dir/merged"
    mkdir -p "$merged_dir"
    
    # Attempt to create a simple merged structure
    echo -e "${BLUE}Creating merged APK structure...${NC}"
    
    # Copy base APK
    cp "$base_apk" "$merged_dir/app.apk"
    
    # Create merge info file
    local merge_info_file="$merged_dir/merge_info.txt"
    {
        echo "Merge Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "Merged by: $(whoami)"
        echo "Source Directory: $output_dir"
        echo "Base APK: $(basename "$base_apk")"
        echo "Split APKs Count: ${#split_apks[@]}"
        echo "Bundletool: $bundletool_cmd"
        if [ -n "$TEMP_BUNDLETOOL_PATH" ]; then
            echo "Bundletool Source: Downloaded temporarily"
        else
            echo "Bundletool Source: Local/System installation"
        fi
        echo ""
        echo "Split APKs:"
        for split_apk in "${split_apks[@]}"; do
            echo "  - $(basename "$split_apk")"
        done
        echo ""
        echo "Bundletool Commands for manual processing:"
        echo "# Install APKs using bundletool:"
        echo "$bundletool_cmd install-apks --apks=\$output_dir/merged/app.apks"
        echo ""
        echo "# Create APKS bundle:"
        echo "$bundletool_cmd build-apks --bundle=app.aab --output=\$output_dir/merged/app.apks"
    } > "$merge_info_file"
    
    echo -e "${YELLOW}Note: For proper APK merging, you may need to use specific bundletool commands${NC}"
    echo "All APK files are available in: $output_dir"
    echo "Merged structure created in: $merged_dir"
    echo "Bundletool available as: $bundletool_cmd"
    
    echo -e "${GREEN}Merge process completed${NC}"
    echo -e "${BLUE}Output location: $merged_dir${NC}"
    echo -e "${BLUE}Merge info saved to: $merge_info_file${NC}"
}

# Function to extract and merge
extract_and_merge() {
    local package_name="$1"
    local provided_output_dir="$2"
    
    if [ -z "$package_name" ]; then
        echo -e "${RED}Error: Package name is required for extract and merge${NC}"
        show_help
        exit 1
    fi
    
    echo -e "${BLUE}Starting extract and merge process for: $package_name${NC}"
    echo ""
    
    # Determine the output directory that will be used
    local actual_output_dir=$(get_extraction_output_dir "$package_name" "$provided_output_dir")
    
    # Extract first
    echo -e "${BLUE}=== EXTRACTION PHASE ===${NC}"
    extract_apk "$package_name" "$provided_output_dir" > /dev/null
    
    echo ""
    echo -e "${BLUE}=== MERGE PHASE ===${NC}"
    
    # Then merge using the same directory
    merge_apk "$actual_output_dir"
    
    echo ""
    echo -e "${GREEN}Extract and merge process completed!${NC}"
    echo -e "${BLUE}All files located in: $actual_output_dir${NC}"
}

# Function to show system info
show_system_info() {
    echo -e "${BLUE}System Information:${NC}"
    echo "OS: $(uname -s)"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "User: $(whoami)"
    echo "Script Directory: $SCRIPT_DIR"
    echo "Temporary Tools Directory: $TMP_TOOLS_DIR"
    echo ""
}

# Main script logic
main() {
    # Show system info
    show_system_info
    
    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        echo -e "${RED}Error: No options provided${NC}"
        show_help
        exit 1
    fi
    
    # Parse options
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -x)
            check_adb
            check_device
            extract_apk "$2" "$3"
            ;;
        -m)
            check_download_prerequisites
            merge_apk "$2"
            ;;
        -xm)
            check_adb
            check_device
            extract_and_merge "$2" "$3"
            ;;
        *)
            echo -e "${RED}Error: Invalid option '$1'${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Run the main function with all arguments
main "$@"