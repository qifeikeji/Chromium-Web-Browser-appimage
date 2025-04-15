#!/bin/sh

APP=chromium

# TEMPORARY DIRECTORY
echo "Creating temporary directory..."
mkdir -p tmp
cd ./tmp || { echo "Error: Failed to change to tmp directory"; exit 1; }

# DOWNLOAD APPIMAGETOOL
if ! test -f ./appimagetool; then
    echo "Downloading appimagetool..."
    wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool || { echo "Error: Failed to download appimagetool"; exit 1; }
    chmod a+x ./appimagetool
fi

# CREATE CHROMIUM BROWSER APPIMAGES
_create_chromium_appimage() {
    echo "Processing channel: $CHANNEL"

    # DOWNLOAD THE SNAP PACKAGE
    if ! test -f ./*.snap; then
        echo "Downloading snap package for $CHANNEL..."
        SNAP_URL=$(curl -H 'Snap-Device-Series: 16' http://api.snapcraft.io/v2/snaps/info/chromium --silent | sed 's/\[{/\n/g; s/},{/\n/g' | grep -i "$CHANNEL" | head -1 | sed 's/[()",{} ]/\n/g' | grep "^http")
        if [ -z "$SNAP_URL" ]; then
            echo "Error: Failed to find snap URL for $CHANNEL"
            exit 1
        fi
        if wget --version | head -1 | grep -q ' 1.'; then
            wget -q --no-verbose --show-progress --progress=bar "$SNAP_URL" -O chromium.snap || { echo "Error: Failed to download snap package"; exit 1; }
        else
            wget "$SNAP_URL" -O chromium.snap || { echo "Error: Failed to download snap package"; exit 1; }
        fi
    fi

    # EXTRACT THE SNAP PACKAGE AND CREATE THE APPIMAGE
    echo "Extracting snap package..."
    unsquashfs -f ./chromium.snap || { echo "Error: Failed to extract snap package"; exit 1; }
    mkdir -p "$APP".AppDir
    VERSION=$(cat ./squashfs-root/snap/*.yaml | grep "^version" | head -1 | cut -c 10-)
    if [ -z "$VERSION" ]; then
        echo "Error: Failed to extract version from snap metadata"
        exit 1
    fi
    echo "Version: $VERSION"

    echo "Moving files to AppDir..."
    mv ./squashfs-root/etc ./"$APP".AppDir/ || { echo "Error: Failed to move etc"; exit 1; }
    mv ./squashfs-root/lib ./"$APP".AppDir/ || { echo "Error: Failed to move lib"; exit 1; }
    mv ./squashfs-root/usr ./"$APP".AppDir/ || { echo "Error: Failed to move usr"; exit 1; }
    mv ./squashfs-root/*.png ./"$APP".AppDir/ || { echo "Error: Failed to move png"; exit 1; }
    mv ./squashfs-root/bin/*"$APP"*.desktop ./"$APP".AppDir/ || { echo "Error: Failed to move desktop file"; exit 1; }
    sed -i 's#/chromium.png#chromium#g' ./"$APP".AppDir/*.desktop

    # 动态查找 chrome 二进制文件
    echo "Searching for chrome binary..."
    CHROME_PATH=$(find ./"$APP".AppDir/usr/lib -type f -name chrome | head -1)
    if [ -z "$CHROME_PATH" ]; then
        echo "Error: Could not find chrome binary in usr/lib"
        find ./"$APP".AppDir -type f -name chrome
        exit 1
    fi
    CHROME_DIR=$(dirname "$CHROME_PATH")
    echo "Chrome path: $CHROME_PATH"
    # 重命名 chrome 为 test
    mv "$CHROME_PATH" "$CHROME_DIR/test" || { echo "Error: Failed to rename chrome to test"; exit 1; }
    ls -l "$CHROME_DIR/test" || echo "Warning: test binary not found after rename"

    # 更新 .desktop 文件
    sed -i 's/Exec=chromium/Exec=AppRun/g' ./"$APP".AppDir/*.desktop

    # 生成 AppRun
    echo "Generating AppRun..."
    cat <<HEREDOC > ./"$APP".AppDir/AppRun
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\${0}")")"
export UNION_PRELOAD="\${HERE}"
export PATH="\${HERE}/usr/bin:\${HERE}/usr/sbin:\${HERE}/usr/games:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${HERE}/usr/lib/i386-linux-gnu:\${HERE}/usr/lib/x86_64-linux-gnu:\${HERE}/lib:\${HERE}/lib/i386-linux-gnu:\${HERE}/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH}"
export PYTHONPATH="\${HERE}/usr/share/pyshared:\${HERE}/usr/lib/python*:\${PYTHONPATH}"
export PYTHONHOME="\${HERE}/usr:\${HERE}/usr/lib/python*"
export XDG_DATA_DIRS="\${HERE}/usr/share:\${XDG_DATA_DIRS}"
exec "\${HERE}${CHROME_DIR#$APP.AppDir}/test" "\$@"
HEREDOC

    chmod a+x ./"$APP".AppDir/AppRun
    cat ./"$APP".AppDir/AppRun

    echo "Running appimagetool..."
    ARCH=x86_64 ./appimagetool --comp zstd --mksquashfs-opt -Xcompression-level --mksquashfs-opt 20 \
        -u "gh-releases-zsync|$GITHUB_REPOSITORY_OWNER|Chromium-Web-Browser-appimage|continuous|*-$CHANNEL-*x86_64.AppImage.zsync" \
        ./"$APP".AppDir Chromium-"$CHANNEL"-"$VERSION"-x86_64.AppImage || { echo "Error: Failed to run appimagetool"; exit 1; }
    ls -l Chromium-"$CHANNEL"-"$VERSION"-x86_64.AppImage || echo "Warning: AppImage not found after generation"
}

for CHANNEL in stable candidate beta edge; do
    echo "Building for $CHANNEL..."
    mkdir -p "$CHANNEL" && cp ./appimagetool ./"$CHANNEL"/appimagetool && cd "$CHANNEL" || { echo "Error: Failed to setup $CHANNEL directory"; exit 1; }
    _create_chromium_appimage
    cd ..
    echo "Moving AppImage for $CHANNEL..."
    mv ./"$CHANNEL"/*.AppImage* ./ || { echo "Error: Failed to move AppImage for $CHANNEL"; exit 1; }
    ls -l *.AppImage* || echo "Warning: No AppImage files found after move"
done

cd ..
echo "Final AppImage files:"
ls -l ./tmp/*.AppImage* || echo "No AppImage files in tmp/"
mv ./tmp/*.AppImage* ./ || { echo "Error: Failed to move final AppImage files"; exit 1; }
ls -l *.AppImage* || echo "No AppImage files in final directory"
