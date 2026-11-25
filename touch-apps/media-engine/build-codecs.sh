#!/bin/sh
# Build the separately executed FFmpeg converter with static x264.
set -eu
if [ "$#" -ne 5 ]; then
    echo "Usage: build-codecs.sh armhf|arm64 ZIG FFMPEG_SOURCE X264_SOURCE OUTPUT" >&2
    exit 2
fi
arch=$1
zig=$(realpath "$2")
ffmpeg=$(realpath "$3")
x264=$(realpath "$4")
output=$(realpath -m "$5")
case "$arch" in
    armhf) target=arm-linux-musleabihf; cpu=cortex_a7; ffarch=arm ;;
    arm64) target=aarch64-linux-musl; cpu=generic; ffarch=aarch64 ;;
    *) exit 2 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/cc" <<COMPILER
#!/bin/sh
exec "$zig" cc -target "$target" -mcpu="$cpu" "\$@"
COMPILER
chmod +x "$work/cc"
cp -a "$x264" "$work/x264"
cd "$work/x264"
CC="$work/cc" AR="$zig ar" RANLIB=true ./configure --host="$target" \
    --prefix="$work/prefix" --enable-static --disable-cli --disable-opencl \
    --disable-asm --bit-depth=8 > "$output.x264.log" 2>&1
make -j2 install >> "$output.x264.log" 2>&1

mkdir "$work/ffmpeg"
cd "$work/ffmpeg"
export PKG_CONFIG_PATH="$work/prefix/lib/pkgconfig"
"$ffmpeg/configure" --enable-cross-compile --target-os=linux --arch="$ffarch" \
    --cc="$work/cc" --ld="$work/cc" --ar="$zig ar" --ranlib=true \
    --strip='true' --pkg-config-flags=--static --extra-ldflags=-static \
    --disable-doc --disable-debug --disable-ffprobe --disable-ffplay \
    --disable-avdevice --disable-network --disable-autodetect --disable-asm \
    --disable-everything --enable-ffmpeg --enable-gpl --enable-libx264 --enable-small \
    --enable-protocol=file,pipe \
    --enable-demuxer=aac,ac3,aiff,amr,ape,asf,au,avi,caf,dts,eac3,flac,flv,matroska,m4v,mov,mp3,mpegps,mpegts,mpegvideo,ogg,rm,tta,wav,wv \
    --enable-decoder='aac,aac_latm,ac3,eac3,alac,amrnb,amrwb,ape,dca,flac,mp1,mp2,mp3,opus,vorbis,tta,wavpack,wmav1,wmav2,wmapro,wmalossless,wmavoice,pcm*,adpcm*,h264,hevc,av1,vp8,vp9,mpeg1video,mpeg2video,mpeg4,h263,h263i,flv,h263p,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,vc1,rv10,rv20,rv30,rv40,png,mjpeg,theora,cinepak,dvvideo' \
    --enable-parsers --enable-bsfs --enable-muxer=mp4 --enable-encoder=libx264,aac \
    --enable-filter=scale,format,aformat,fps,aresample,trim,atrim,transpose,hflip,vflip \
    > "$output.ffmpeg.log" 2>&1 || { tail -45 "$output.ffmpeg.log" >&2; exit 1; }
make -j2 ffmpeg_g >> "$output.ffmpeg.log" 2>&1 || { tail -45 "$output.ffmpeg.log" >&2; exit 1; }
"$zig" objcopy --strip-all ffmpeg_g "$output"
chmod 755 "$output"
