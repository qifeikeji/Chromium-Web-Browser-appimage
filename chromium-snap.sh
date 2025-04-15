_create_chromium_appimage() {
	# 下载和解压 Snap 包
	if ! test -f ./*.snap; then
		if wget --version | head -1 | grep -q ' 1.'; then
			wget -q --no-verbose --show-progress --progress=bar "$(curl -H 'Snap-Device-Series: 16' http://api.snapcraft.io/v2/snaps/info/chromium --silent | sed 's/\[{/\n/g; s/},{/\n/g' | grep -i "$CHANNEL" | head -1 | sed 's/[()",{} ]/\n/g' | grep "^http")"
		else
			wget "$(curl -H 'Snap-Device-Series: 16' http://api.snapcraft.io/v2/snaps/info/chromium --silent | sed 's/\[{/\n/g; s/},{/\n/g' | grep -i "$CHANNEL" | head -1 | sed 's/[()",{} ]/\n/g' | grep "^http")"
		fi
	fi

	# 解压 Snap 包并创建 AppDir
	unsquashfs -f ./*.snap
	mkdir -p "$APP".AppDir
	VERSION=$(cat ./squashfs-root/snap/*.yaml | grep "^version" | head -1 | cut -c 10-)

	mv ./squashfs-root/etc ./"$APP".AppDir/
	mv ./squashfs-root/lib ./"$APP".AppDir/
	mv ./squashfs-root/usr ./"$APP".AppDir/
	mv ./squashfs-root/*.png ./"$APP".AppDir/
	mv ./squashfs-root/bin/*"$APP"*.desktop ./"$APP".AppDir/
	sed -i 's#/chromium.png#chromium#g' ./"$APP".AppDir/*.desktop

	# 动态查找 chrome 二进制文件
	CHROME_PATH=$(find ./"$APP".AppDir/usr/lib -type f -name chrome | head -1)
	if [ -z "$CHROME_PATH" ]; then
		echo "Error: Could not find chrome binary in usr/lib"
		exit 1
	fi
	CHROME_DIR=$(dirname "$CHROME_PATH")
	# 重命名 chrome 为 test
	mv "$CHROME_PATH" "$CHROME_DIR/test" || { echo "Error: Failed to rename chrome to test"; exit 1; }

	# 更新 .desktop 文件
	sed -i 's/Exec=chromium/Exec=AppRun/g' ./"$APP".AppDir/*.desktop

	# 生成 AppRun，使用动态路径
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

	ARCH=x86_64 ./appimagetool --comp zstd --mksquashfs-opt -Xcompression-level --mksquashfs-opt 20 \
	-u "gh-releases-zsync|$GITHUB_REPOSITORY_OWNER|Chromium-Web-Browser-appimage|continuous|*-$CHANNEL-*x86_64.AppImage.zsync" \
	./"$APP".AppDir Chromium-"$CHANNEL"-"$VERSION"-x86_64.AppImage || exit 1
}
