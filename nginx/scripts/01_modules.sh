get_section_modules() {
    local section=$1
    awk -v sec="[$section]" '$0==sec{flag=1;next} /^\[/{flag=0} flag {print}' "$PROFILES_DEF_FILE" | grep -v "^#" | tr '\n' ' '
}

if [ "$MODE" == "custom" ]; then
    FINAL_MODULES_LIST="$CUSTOM_LIST"
else
    FINAL_MODULES_LIST=$(get_section_modules "$MODE")
    if [ -z "$FINAL_MODULES_LIST" ] && [ "$MODE" != "core" ]; then
        echo "Error: Profile [$MODE] not found or empty."
        exit 1
    fi
fi

if [ -n "$FINAL_MODULES_LIST" ]; then
    IFS=' ' read -r -a MOD_ARRAY <<< "$FINAL_MODULES_LIST"
    
    for mod_name in "${MOD_ARRAY[@]}"; do
        [ -z "$mod_name" ] && continue

        LINE=$(grep "^$mod_name[[:space:]]*|" "$MODULES_DEF_FILE" | head -n 1)

        if [ -z "$LINE" ]; then
            echo "WARNING: Module '$mod_name' defined in profile but not found in modules.conf"
            continue
        fi

        IFS='|' read -r _name _type _url _sha _flag <<< "$LINE"
        
        _name=$(echo "$_name" | xargs)
        _type=$(echo "$_type" | xargs)
        _url=$(echo "$_url" | xargs)
        _sha=$(echo "$_sha" | xargs)
        _flag=$(echo "$_flag" | xargs)

        if [ "$_type" == "internal" ]; then
            set -- "$@" "$_flag"

        elif [ "$_type" == "external" ]; then
            MOD_DIR="/src/modules/$_name"
            mkdir -p "$MOD_DIR"
            
            FILENAME="$MOD_DIR.tar.gz"
            wget -qO "$FILENAME" "$_url"

            if [ "$_sha" != "-" ] && [ -n "$_sha" ]; then
                echo "$_sha  $FILENAME" | sha256sum -c -
            fi

            tar -xzf "$FILENAME" -C "$MOD_DIR" --strip-components=1
            rm "$FILENAME"

            FINAL_FLAG="${_flag//\{\{DIR\}\}/$MOD_DIR}"
            set -- "$@" "$FINAL_FLAG"
        fi
    done
fi