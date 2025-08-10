#!/bin/bash name=extract_split_apks.sh
#!/bin/bash
# Extract split APKs (Android App Bundles) and merge them

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

check_dependencies() {
    echo -e "${YELLOW}🔍 Checking dependencies...${NC}"
    
    # Check ADB
    if ! command -v adb &> /dev/null; then
        echo -e "${RED}❌ ADB not found. Please install Android SDK platform tools.${NC}"
        exit 1
    fi
    
    # Check Java
    if ! command -v java &> /dev/null; then
        echo -e "${RED}❌ Java not found. Please install Java JDK.${NC}"
        exit 1
    fi
    
    # Check for APK merging tools
    local merge_tools=()
    
    if command -v apktool &> /dev/null; then
        merge_tools+=("apktool")
    fi
    
    if command -v aapt &> /dev/null && command -v zipalign &> /dev/null; then
        merge_tools+=("aapt")
    fi
    
    if [ ${#merge_tools[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️ No APK merging tools found. Installing required tools...${NC}"
        install_merge_tools
    else
        echo -e "${GREEN}✅ Found merge tools: ${merge_tools[*]}${NC}"
        MERGE_METHOD="${merge_tools[0]}"
    fi
    
    echo -e "${GREEN}✅ Dependencies check completed${NC}"
}

install_merge_tools() {
    echo -e "${BLUE}📥 Installing APK merging tools...${NC}"
    
    # Install APKtool if not present
    if ! command -v apktool &> /dev/null; then
        echo "Installing APKtool..."
        
        # Get latest APKtool version
        APKTOOL_VERSION=$(curl -s https://api.github.com/repos/iBotPeaches/Apktool/releases/latest | grep tag_name | cut -d'"' -f4)
        
        # Download APKtool
        cd /tmp
        wget https://github.com/iBotPeaches/Apktool/releases/download/${APKTOOL_VERSION}/apktool_${APKTOOL_VERSION#v}.jar
        wget https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool
        
        # Install
        sudo mv apktool_${APKTOOL_VERSION#v}.jar /usr/local/bin/apktool.jar
        sudo mv apktool /usr/local/bin/
        sudo chmod +x /usr/local/bin/apktool
        
        echo -e "${GREEN}✅ APKtool installed${NC}"
        MERGE_METHOD="apktool"
    fi
}

extract_split_apk() {
    local package_name=$1
    local output_dir="./split_apks_${package_name}_$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$output_dir"
    
    echo -e "${BLUE}📦 Extracting split APKs for: $package_name${NC}"
    
    # Get package information
    local version_name=$(adb shell dumpsys package "$package_name" | grep "versionName" | head -1 | cut -d'=' -f2 | tr -d ' \r\n')
    local version_code=$(adb shell dumpsys package "$package_name" | grep "versionCode" | head -1 | cut -d'=' -f2 | awk '{print $1}')
    
    echo "📋 Package: $package_name"
    echo "📋 Version: $version_name ($version_code)"
    
    # Get all APK paths for the package
    local apk_paths=$(adb shell pm path "$package_name" | cut -d':' -f2 | tr -d '\r')
    local apk_count=$(echo "$apk_paths" | wc -l)
    
    echo "📱 Found $apk_count APK files"
    
    if [ "$apk_count" -eq 1 ]; then
        echo -e "${YELLOW}⚠️ This appears to be a single APK, not a split APK bundle${NC}"
    fi
    
    local count=0
    local base_apk=""
    local split_apks=()
    
    echo "$apk_paths" | while read apk_path; do
        if [ -n "$apk_path" ]; then
            count=$((count + 1))
            filename=$(basename "$apk_path")
            
            echo -e "${YELLOW}Pulling APK $count: $filename${NC}"
            
            # Determine APK type and create appropriate filename
            if [[ "$filename" == *"base.apk"* ]] || [ "$count" -eq 1 ]; then
                local output_file="$output_dir/${package_name}_base.apk"
                echo "$output_file" > "$output_dir/.base_apk"
            else
                local output_file="$output_dir/${package_name}_split_${count}.apk"
                echo "$output_file" >> "$output_dir/.split_apks"
            fi
            
            if adb pull "$apk_path" "$output_file"; then
                echo -e "${GREEN}✅ Successfully pulled: $(basename "$output_file")${NC}"
                
                # Get APK info using aapt if available
                if command -v aapt &> /dev/null; then
                    local split_name=$(aapt dump badging "$output_file" 2>/dev/null | grep "split=" | sed "s/.*split='\([^']*\)'.*/\1/")
                    if [ -n "$split_name" ]; then
                        echo "   Split name: $split_name"
                    fi
                fi
            else
                echo -e "${RED}❌ Failed to pull: $filename${NC}"
            fi
        fi
    done
    
    echo -e "${GREEN}✅ Split APKs extracted to: $output_dir${NC}"
    ls -la "$output_dir"
    
    # Store extraction info
    cat > "$output_dir/extraction_info.txt" <<EOF
Package: $package_name
Version Name: $version_name
Version Code: $version_code
Extraction Date: $(date)
Total APK Files: $apk_count
Output Directory: $output_dir
EOF
    
    echo "$output_dir"
}

merge_split_apks_apktool() {
    local source_dir="$1"
    local output_file="$2"
    local temp_dir="/tmp/apk_merge_$$"
    
    echo -e "${BLUE}🔧 Merging split APKs using APKtool method...${NC}"
    
    mkdir -p "$temp_dir"
    
    # Find base APK
    local base_apk=$(cat "$source_dir/.base_apk" 2>/dev/null)
    if [ -z "$base_apk" ] || [ ! -f "$base_apk" ]; then
        base_apk=$(find "$source_dir" -name "*base*.apk" | head -1)
        if [ -z "$base_apk" ]; then
            base_apk=$(find "$source_dir" -name "*.apk" | head -1)
        fi
    fi
    
    if [ -z "$base_apk" ] || [ ! -f "$base_apk" ]; then
        echo -e "${RED}❌ No base APK found${NC}"
        return 1
    fi
    
    echo "📱 Using base APK: $(basename "$base_apk")"
    
    # Decompile base APK
    echo "🔄 Decompiling base APK..."
    if ! apktool d "$base_apk" -o "$temp_dir/base" -f; then
        echo -e "${RED}❌ Failed to decompile base APK${NC}"
        return 1
    fi
    
    # Process split APKs
    local split_apks=($(find "$source_dir" -name "*.apk" ! -path "$base_apk"))
    
    if [ ${#split_apks[@]} -gt 0 ]; then
        echo "🔄 Processing ${#split_apks[@]} split APKs..."
        
        for split_apk in "${split_apks[@]}"; do
            echo "   Processing: $(basename "$split_apk")"
            
            # Decompile split APK
            local split_name=$(basename "$split_apk" .apk)
            apktool d "$split_apk" -o "$temp_dir/$split_name" -f
            
            # Merge resources and assets
            if [ -d "$temp_dir/$split_name/res" ]; then
                cp -r "$temp_dir/$split_name/res"/* "$temp_dir/base/res/" 2>/dev/null || true
            fi
            
            if [ -d "$temp_dir/$split_name/assets" ]; then
                mkdir -p "$temp_dir/base/assets"
                cp -r "$temp_dir/$split_name/assets"/* "$temp_dir/base/assets/" 2>/dev/null || true
            fi
            
            if [ -d "$temp_dir/$split_name/lib" ]; then
                mkdir -p "$temp_dir/base/lib"
                cp -r "$temp_dir/$split_name/lib"/* "$temp_dir/base/lib/" 2>/dev/null || true
            fi
            
            # Merge DEX files
            find "$temp_dir/$split_name" -name "classes*.dex" | while read dex_file; do
                dex_name=$(basename "$dex_file")
                if [ ! -f "$temp_dir/base/$dex_name" ]; then
                    cp "$dex_file" "$temp_dir/base/"
                fi
            done
        done
    fi
    
    # Rebuild APK
    echo "🔧 Rebuilding merged APK..."
    if apktool b "$temp_dir/base" -o "$output_file"; then
        echo -e "${GREEN}✅ Successfully created merged APK: $output_file${NC}"
        
        # Get file size
        local file_size=$(stat -c%s "$output_file" 2>/dev/null || echo "unknown")
        echo "📊 Merged APK size: $file_size bytes"
        
        # Clean up
        rm -rf "$temp_dir"
        return 0
    else
        echo -e "${RED}❌ Failed to rebuild merged APK${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
}

merge_split_apks_bundletool() {
    local source_dir="$1"
    local output_file="$2"
    
    echo -e "${BLUE}🔧 Merging split APKs using bundletool method...${NC}"
    
    # Download bundletool if not present
    local bundletool_jar="/tmp/bundletool.jar"
    if [ ! -f "$bundletool_jar" ]; then
        echo "📥 Downloading bundletool..."
        local bundletool_version=$(curl -s https://api.github.com/repos/google/bundletool/releases/latest | grep tag_name | cut -d'"' -f4)
        wget "https://github.com/google/bundletool/releases/download/${bundletool_version}/bundletool-all-${bundletool_version}.jar" -O "$bundletool_jar"
    fi
    
    # Create APKS from split APKs
    local apks_file="${output_file%.apk}.apks"
    
    echo "🔄 Creating APKS bundle..."
    
    # Build APKS command
    local apks_cmd="java -jar $bundletool_jar build-apks --bundle=$source_dir --output=$apks_file"
    
    # For this to work properly, we'd need the original AAB file
    # This is a simplified approach - in practice, you'd need the original Android App Bundle
    echo -e "${YELLOW}⚠️ Note: bundletool method requires original AAB file${NC}"
    echo -e "${YELLOW}⚠️ Using APKtool method instead...${NC}"
    
    merge_split_apks_apktool "$source_dir" "$output_file"
}

merge_split_apks_manual() {
    local source_dir="$1"
    local output_file="$2"
    local temp_dir="/tmp/manual_merge_$$"
    
    echo -e "${BLUE}🔧 Merging split APKs using manual method...${NC}"
    
    mkdir -p "$temp_dir"
    
    # Find base APK
    local base_apk=$(find "$source_dir" -name "*base*.apk" | head -1)
    if [ -z "$base_apk" ]; then
        base_apk=$(find "$source_dir" -name "*.apk" | head -1)
    fi
    
    if [ -z "$base_apk" ]; then
        echo -e "${RED}❌ No APK files found${NC}"
        return 1
    fi
    
    echo "📱 Using base APK: $(basename "$base_apk")"
    
    # Copy base APK
    cp "$base_apk" "$temp_dir/base.apk"
    
    # Extract base APK
    cd "$temp_dir"
    unzip -q base.apk -d base/
    
    # Process split APKs
    local split_apks=($(find "$source_dir" -name "*.apk" ! -path "$base_apk"))
    
    for split_apk in "${split_apks[@]}"; do
        echo "   Merging: $(basename "$split_apk")"
        
        local split_dir="split_$(basename "$split_apk" .apk)"
        unzip -q "$split_apk" -d "$split_dir/"
        
        # Merge contents
        find "$split_dir" -type f | while read file; do
            rel_path=${file#$split_dir/}
            target_path="base/$rel_path"
            
            if [ ! -f "$target_path" ]; then
                mkdir -p "$(dirname "$target_path")"
                cp "$file" "$target_path"
            fi
        done
    done
    
    # Repackage
    cd base
    zip -r "../merged.apk" . >/dev/null
    cd ..
    
    mv merged.apk "$output_file"
    
    # Clean up
    cd - >/dev/null
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ Manual merge completed: $output_file${NC}"
}

sign_apk() {
    local apk_file="$1"
    local signed_apk="${apk_file%.apk}_signed.apk"
    
    echo -e "${BLUE}🔐 Signing merged APK...${NC}"
    
    # Check for signing tools
    if command -v uber-apk-signer &> /dev/null; then
        echo "Using uber-apk-signer..."
        uber-apk-signer -a "$apk_file" --out "$(dirname "$apk_file")"
        
        # Find the signed APK
        local signed_file=$(find "$(dirname "$apk_file")" -name "*aligned-debugSigned.apk" | head -1)
        if [ -n "$signed_file" ]; then
            mv "$signed_file" "$signed_apk"
            echo -e "${GREEN}✅ APK signed: $signed_apk${NC}"
        fi
    elif command -v jarsigner &> /dev/null && command -v keytool &> /dev/null; then
        echo "Using jarsigner with debug keystore..."
        
        # Create debug keystore if it doesn't exist
        local debug_keystore="$HOME/.android/debug.keystore"
        if [ ! -f "$debug_keystore" ]; then
            mkdir -p "$(dirname "$debug_keystore")"
            keytool -genkeypair -v -keystore "$debug_keystore" -alias androiddebugkey \
                -keyalg RSA -keysize 2048 -validity 10000 \
                -keypass android -storepass android \
                -dname "CN=Android Debug,O=Android,C=US"
        fi
        
        # Sign APK
        cp "$apk_file" "$signed_apk"
        jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 \
            -keystore "$debug_keystore" -storepass android \
            "$signed_apk" androiddebugkey
        
        echo -e "${GREEN}✅ APK signed: $signed_apk${NC}"
    else
        echo -e "${YELLOW}⚠️ No signing tools available. APK not signed.${NC}"
        echo -e "${YELLOW}💡 Install uber-apk-signer or use Android SDK tools${NC}"
        cp "$apk_file" "$signed_apk"
    fi
    
    echo "$signed_apk"
}

main() {
    local action="$1"
    local package_name="$2"
    local merge_method="${3:-apktool}"
    
    case "$action" in
        "extract")
            if [ -z "$package_name" ]; then
                echo -e "${RED}Usage: $0 extract <package_name>${NC}"
                echo "Example: $0 extract com.google.android.gms"
                exit 1
            fi
            
            check_dependencies
            extract_split_apk "$package_name"
            ;;
            
        "merge")
            local source_dir="$package_name"  # In this case, it's the source directory
            local output_file="$3"
            
            if [ -z "$source_dir" ] || [ -z "$output_file" ]; then
                echo -e "${RED}Usage: $0 merge <source_directory> <output_apk_file> [method]${NC}"
                echo "Methods: apktool, manual"
                echo "Example: $0 merge ./split_apks_com.example_20250810_070000 merged_app.apk apktool"
                exit 1
            fi
            
            if [ ! -d "$source_dir" ]; then
                echo -e "${RED}❌ Source directory not found: $source_dir${NC}"
                exit 1
            fi
            
            check_dependencies
            
            case "$merge_method" in
                "apktool")
                    merge_split_apks_apktool "$source_dir" "$output_file"
                    ;;
                "manual")
                    merge_split_apks_manual "$source_dir" "$output_file"
                    ;;
                "bundletool")
                    merge_split_apks_bundletool "$source_dir" "$output_file"
                    ;;
                *)
                    echo -e "${RED}❌ Unknown merge method: $merge_method${NC}"
                    echo "Available methods: apktool, manual, bundletool"
                    exit 1
                    ;;
            esac
            
            # Sign the merged APK
            local signed_apk=$(sign_apk "$output_file")
            
            echo -e "${GREEN}🎉 Process completed!${NC}"
            echo -e "${BLUE}📱 Merged APK: $output_file${NC}"
            echo -e "${BLUE}🔐 Signed APK: $signed_apk${NC}"
            
            # Installation instructions
            echo ""
            echo -e "${YELLOW}📲 To install the merged APK:${NC}"
            echo "   adb install \"$signed_apk\""
            echo ""
            echo -e "${YELLOW}⚠️ Note: You may need to uninstall the original app first:${NC}"
            echo "   adb uninstall <package_name>"
            ;;
            
        "extract-and-merge")
            if [ -z "$package_name" ]; then
                echo -e "${RED}Usage: $0 extract-and-merge <package_name> [merge_method]${NC}"
                echo "Example: $0 extract-and-merge com.google.android.gms apktool"
                exit 1
            fi
            
            check_dependencies
            
            # Extract split APKs
            local output_dir=$(extract_split_apk "$package_name")
            
            # Merge split APKs
            local merged_apk="./${package_name}_merged.apk"
            
            case "$merge_method" in
                "apktool"|"")
                    merge_split_apks_apktool "$output_dir" "$merged_apk"
                    ;;
                "manual")
                    merge_split_apks_manual "$output_dir" "$merged_apk"
                    ;;
                *)
                    echo -e "${RED}❌ Unknown merge method: $merge_method${NC}"
                    exit 1
                    ;;
            esac
            
            # Sign the merged APK
            local signed_apk=$(sign_apk "$merged_apk")
            
            echo -e "${GREEN}🎉 Extract and merge completed!${NC}"
            echo -e "${BLUE}📂 Extracted files: $output_dir${NC}"
            echo -e "${BLUE}📱 Merged APK: $merged_apk${NC}"
            echo -e "${BLUE}🔐 Signed APK: $signed_apk${NC}"
            ;;
            
        "help"|"--help"|"-h"|"")
            echo -e "${BLUE}Split APK Extractor and Merger${NC}"
            echo "=============================="
            echo ""
            echo -e "${YELLOW}Usage:${NC}"
            echo "  $0 extract <package_name>"
            echo "  $0 merge <source_directory> <output_file> [method]"
            echo "  $0 extract-and-merge <package_name> [method]"
            echo ""
            echo -e "${YELLOW}Commands:${NC}"
            echo "  extract              - Extract split APKs from device"
            echo "  merge                - Merge extracted split APKs into single APK"
            echo "  extract-and-merge    - Extract and merge in one command"
            echo ""
            echo -e "${YELLOW}Merge Methods:${NC}"
            echo "  apktool              - Use APKtool for decompiling and rebuilding (recommended)"
            echo "  manual               - Manual zip/unzip method (basic)"
            echo "  bundletool           - Use Google's bundletool (requires original AAB)"
            echo ""
            echo -e "${YELLOW}Examples:${NC}"
            echo "  $0 extract com.google.android.gms"
            echo "  $0 merge ./split_apks_com.example_20250810_070000 merged.apk apktool"
            echo "  $0 extract-and-merge com.whatsapp"
            echo ""
            echo -e "${YELLOW}Requirements:${NC}"
            echo "  - ADB (Android Debug Bridge)"
            echo "  - Java JDK"
            echo "  - APKtool (will be installed automatically if missing)"
            echo "  - uber-apk-signer or jarsigner (for APK signing)"
            ;;
            
        *)
            echo -e "${RED}❌ Unknown command: $action${NC}"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check if running as script
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
