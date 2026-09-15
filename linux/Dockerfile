# Sizer Linux 빌드·테스트 환경(Ubuntu 24.04 + Swift 6.1).
# scripts/build_linux.sh --docker 가 이 이미지로 빌드/테스트/패키징한다. CI도 같은 구성을 쓴다.
FROM swift:6.1-noble

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ffmpeg libheif-examples libheif-plugin-x265 libheif-plugin-libde265 \
      python3 dpkg-dev file \
 && rm -rf /var/lib/apt/lists/*
