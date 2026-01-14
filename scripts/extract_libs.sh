#!/bin/bash
set -e
DEST_LIB="/rootfs/usr/lib"
DEST_SBIN="/rootfs/sbin"      
mkdir -p $DEST_LIB $DEST_SBIN

echo ">>> Generating ld.so.cache..."

if [ -f /sbin/ldconfig ]; then
    /sbin/ldconfig -r /rootfs
    echo "   -> Generated /rootfs/etc/ld.so.cache"
else
    echo "!!! Warning: ldconfig not found in builder."
fi


echo ">>> Library extraction and optimization complete."



if [ ! -f /usr/bin/lddtree ]; then
    wget -qO /usr/bin/lddtree https://raw.githubusercontent.com/ncopa/lddtree/master/lddtree.sh
    chmod +x /usr/bin/lddtree
fi

if [ ! -f /usr/bin/libtree ]; then
    ARCH=$(uname -m)
    VERSION="v3.1.1"
    BASE_URL="https://github.com/haampie/libtree/releases/download/${VERSION}"
    
    if [ "$ARCH" = "x86_64" ]; then
        wget -qO /usr/bin/libtree "${BASE_URL}/libtree_x86_64"
    elif [ "$ARCH" = "aarch64" ]; then
        wget -qO /usr/bin/libtree "${BASE_URL}/libtree_aarch64"
    fi

    if [ -f /usr/bin/libtree ]; then chmod +x /usr/bin/libtree; fi
fi

TARGETS="$@"

if [ -z "$TARGETS" ]; then
    exit 1
fi

TEMP_LIST=$(mktemp)

for FILE in $TARGETS; do
    lddtree -l "$FILE" 2>/dev/null >> $TEMP_LIST || true

    if [ -f /usr/bin/libtree ]; then
        libtree -p "$FILE" 2>/dev/null | grep -v "not found" >> $TEMP_LIST || true
    fi

    if command -v scanelf &> /dev/null; then
        NEEDED=$(scanelf --needed --nobanner --format '%n#p' "$FILE" | tr ',' ' ')
        for lib in $NEEDED; do
            ldd -r "$FILE" | grep "$lib" | awk '{print $3}' >> $TEMP_LIST || true
        done
    fi
done

cat $TEMP_LIST | sort -u | grep "^/" | while read -r lib_path; do
    if [ -f "$lib_path" ]; then
        IS_TARGET=0
        for target in $TARGETS; do
            if [ "$lib_path" == "$target" ]; then IS_TARGET=1; break; fi
        done

        if [ "$IS_TARGET" -eq 0 ]; then
            REAL_PATH=$(readlink -f "$lib_path")
            LIB_NAME=$(basename "$REAL_PATH")
            LINK_NAME=$(basename "$lib_path")

            if [ ! -f "$DEST_LIB/$LIB_NAME" ]; then
                cp "$REAL_PATH" "$DEST_LIB/"
                strip --strip-unneeded "$DEST_LIB/$LIB_NAME" 2>/dev/null || true
            fi

            if [ "$LIB_NAME" != "$LINK_NAME" ]; then
                ln -sf "$LIB_NAME" "$DEST_LIB/$LINK_NAME"
            fi
        fi
    fi
done

rm $TEMP_LIST
