#!/bin/bash -e
declare -A ffbuildflags=(
[osx-x64-at]='--arch=x86_64 --enable-cross-compile'
[osx-arm64-at]='--arch=arm64 --enable-audiotoolbox --enable-decoder=aac_at,mp3_at --disable-decoder=aac,mp3'
)
declare -A extcflags=(
[osx-x64-at]='-arch x86_64 --target=x86_64-apple-macosx'
[osx-arm64-at]=
)
declare -A extldflags=(
[osx-x64-at]=
[osx-arm64-at]=
)
declare -A cc=(
[osx-x64-at]='clang -arch x86_64'
[osx-arm64-at]=clang
)

$(command -v ggrep||command -v grep)  -oP '\bav[a-z0-9_]*(?=\s*\()' chromium/ffmpeg.sigs > sigs.txt
echo -e "avformat_version\navutil_version\nff_h264_decode_init_vlc" >> sigs.txt # only for opera
echo -e "{\nglobal:\n$(sed 's/$/;/' sigs.txt)\nlocal:\n*;\n};" | tee export.map
# Use ffmpeg's native opus decoder not in kAllowedAudioCodecs at https://github.com/chromium/chromium/blob/main/media/ffmpeg/ffmpeg_common.cc
sed -i.bak "s/^ *\.p\.name *=.*/.p.name=\"libopus\",/" libavcodec/opus/dec.c
diff libavcodec/opus/dec.c{.bak,} || :
# https://chromium.googlesource.com/chromium/third_party/ffmpeg/+/refs/heads/master/
# BUILD.gn and chromium/config/Chrome/linux/x64/
./configure \
  --disable-{debug,all,autodetect,doc,iconv,network,symver} \
  --disable-{error-resilience,faan,iamf} \
  --disable-{schannel,securetransport} \
  --enable-static --disable-shared \
  --enable-av{format,codec,util} \
  --enable-swresample \
  --enable-demuxer=ogg,matroska,wav,flac,mp3,mov,aac \
  --enable-decoder=vorbis,opus,flac,pcm_s16le,mp3,aac,h264 \
  --enable-parser=aac,flac,h264,mpegaudio,opus,vorbis,vp9 \
  --cc="${cc["$1"]}" \
  --extra-cflags="-DCHROMIUM_NO_LOGGING" \
  --extra-cflags="-O3 -pipe -fno-plt -flto=auto ${extcflags["$1"]}" \
  --extra-ldflags="${extldflags["$1"]}" \
  ${ffbuildflags["$1"]} \
  --enable-{pic,asm,hardcoded-tables} \
  --libdir=/

  make DESTDIR=. install
_symbols=$(awk '{print "-Wl,-u," $1}' sigs.txt | paste -sd ' ' -)
declare -A gccflag=(
[osx-x64-at]='-framework AudioToolbox'
[osx-arm64-at]='-framework AudioToolbox'
)
declare -A startgroup=(
[osx-x64-at]='-Wl,-force_load,'
[osx-arm64-at]='-Wl,-force_load,'
)
declare -A endgroup=(
[osx-x64-at]=
[osx-arm64-at]=
)
declare -A libname=(
[osx-x64-at]=libffmpeg.dylib
[osx-arm64-at]=libffmpeg.dylib
)
echo Unifying .a...
${cc["$1"]} -shared  ${extldflags["$1"]} -flto=auto \
	${startgroup["$1"]} libav{codec,format,util}.a libswresample.a ${endgroup["$1"]} \
	${gccflag["$1"]} -lm -Wl,-s \
	-o ${libname["$1"]}
