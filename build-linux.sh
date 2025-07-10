#!/bin/bash -e
# https://chromium.googlesource.com/chromium/third_party/ffmpeg/+/refs/heads/master/
# See BUILD.gn and chromium/config/Chrome/linux/x64/
declare -gA ffbuildflags=(
[linux]=
[linux-x86_32]='--arch=x86 --target-os=linux --cpu=x86 --enable-cross-compile'
[osx]='--arch=x86_64 --target-os=darwin --cpu=x86_64'
[win]='--arch=x86_64 --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32-'
[win-ia32]='--arch=x86 --target-os=mingw32 --cross-prefix=i686-w64-mingw32-'
)
declare -gA extcflags=(
[linux]='-fno-math-errno -fno-signed-zeros'
[linux-86_32]='-m32 -fno-math-errno -fno-signed-zeros'
[osx]=
[win]=
[win-ia32]=
)
declare -gA extldflags=(
[linux]='-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,-z,pack-relative-relocs'
[linux-x86_32]='-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now -Wl,-z,pack-relative-relocs'
[osx]=
[win]='-Wl,--nxcompat -Wl,--dynamicbase'
[win-ia32]='-Wl,--nxcompat -Wl,--dynamicbase'
)
srcdir=/tmp/nwff
mkdir -p ${srcdir}/chromium-ffmpeg
cd ${srcdir}/chromium-ffmpeg
# Fetch source
_chromium=$(curl -s https://nwjs.io/versions.json | jq -r ".versions[] | select(.version==\"v$1\") | .components.chromium")
_commit=$(curl -sL https://raw.githubusercontent.com/chromium/chromium/refs/tags/${_chromium}/DEPS | grep -oP "'ffmpeg_revision': '\K[0-9a-f]{40}'" | tr -d \')
git init
git remote add origin https://chromium.googlesource.com/chromium/third_party/ffmpeg
git fetch --depth=1 origin $_commit
git checkout $_commit
# Use ffmpeg's native opus decoder not in kAllowedAudioCodecs at https://github.com/chromium/chromium/blob/main/media/ffmpeg/ffmpeg_common.cc
sed '/^ *\.p\.name *=.*/c\.p.name="libopus",' libavcodec/opus/dec.c > libavcodec/opus/dec.c.patched
mv -f libavcodec/opus/dec.c.patched libavcodec/opus/dec.c
./configure \
  --disable-{debug,all,autodetect,doc,iconv,network,symver} \
  --disable-{error-resilience,faan,iamf} \
  --disable-{schannel,securetransport} \
  --enable-static --disable-shared \
  --enable-av{format,codec,util} \
  --enable-swresample \
  --enable-demuxer=ogg,matroska,webm,wav,flac,mp3,mov,aac \
  --enable-decoder=vorbis,opus,flac,pcm_s16le,mp3,aac,h264 \
  --enable-parser=aac,flac,h264,mpegaudio,opus,vorbis,vp9 \
  --extra-cflags="-O3 -pipe -fno-plt -flto=auto ${extcflags["$2"]}" \
  --extra-ldflags="${extldflags["$2"]}" \
  ${ffbuildflags["$2"]} \
  --enable-{pic,asm,hardcoded-tables} \
  --prefix="${srcdir}/release"

  make -j3 install

cd ../release
declare -gA cc=(
[linux]=gcc
[linux-x86_32]='gcc -m32'
[osx]=clang # unsupported
[win]=x86_64-w64-mingw32-gcc
[win-ia32]=i686-w64-mingw32-gcc
)
declare -gA strip=(
[linux]='strip --strip-unneeded'
[linux-x86_32]='strip --strip-unneeded'
[osx]='strip -x'
[win]='x86_64-w64-mingw32-strip --strip-unneeded'
[win-ia32]='i686-w64-mingw32-strip --strip-unneeded'
)
declare -gA gccflag=(
[linux]='-Wl,-u,avutil_version -lm -Wl,-Bsymbolic'
[linux-x86_32]='-Wl,-u,avutil_version -lm -Wl,-Bsymbolic'
[osx]=
[win]='-lbcrypt'
[win-ia32]='-lbcrypt'
)
declare -gA ldwholearchive=(
[linux]='whole-archive '
[linux-x86_32]='whole-archive '
[osx]='force_load,'
[win]='whole-archive '
[win-ia32]='whole-archive '
)
declare -gA ldnowholearchive=(
[linux]='--no-whole-archive'
[linux-x86_32]='--no-whole-archive'
[osx]=
[win]='--no-whole-archive'
[win-ia32]='--no-whole-archive'
)
declare -gA libext=(
[linux]=so
[linux-x86_32]=so
[osx]=dylib
[win]=dll
[win-ia32]=dll
)
${cc["$2"]} -shared  ${extldflags["$2"]} -flto=auto \
	-Wl,--${ldwholearchive["$2"]}lib/libavcodec.a lib/libavformat.a \
	-Wl,${ldnowholearchive["$2"]} lib/libavutil.a lib/libswresample.a \
	-lm ${gccflag["$2"]} \
	-o libffmpeg.${libext["$2"]}

 ${strip["$2"]} libffmpeg.${libext["$2"]}
