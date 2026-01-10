# https://github.com/tsukumijima/KonomiTV/blob/63f8825d4accafc950922758e14f6f712eee0fad/Dockerfile
# --------------------------------------------------------------------------------------------------------------
# サードパーティーライブラリのダウンロードを行うステージ
# Docker のマルチステージビルドを使い、最終的な Docker イメージのサイズを抑え、ビルドキャッシュを効かせる
# --------------------------------------------------------------------------------------------------------------
# 念のため最終イメージに合わせて Ubuntu 22.04 LTS にしておく
## 中間イメージなので、サイズは（ビルドするマシンのディスク容量以外は）気にしなくて良い
FROM ubuntu:22.04 AS thirdparty-downloader

# apt-get に対話的に設定確認されないための設定
ENV DEBIAN_FRONTEND=noninteractive

# ダウンロード・展開に必要なパッケージのインストール
RUN apt-get update && apt-get install -y --no-install-recommends aria2 ca-certificates unzip xz-utils

# サードパーティーライブラリをダウンロード
## サードパーティーライブラリは変更が少ないので、先にダウンロード処理を実行してビルドキャッシュを効かせる
WORKDIR /
## リリース版用
# RUN aria2c -x10 https://github.com/tsukumijima/KonomiTV/releases/download/v0.12.0/thirdparty-linux.tar.xz
# RUN tar xvf thirdparty-linux.tar.xz
## 開発版 (0.xx.x-dev) 用
RUN aria2c -x10 https://nightly.link/tsukumijima/KonomiTV/actions/runs/20725734876/thirdparty-linux.tar.xz.zip
RUN unzip thirdparty-linux.tar.xz.zip && tar xvf thirdparty-linux.tar.xz

# --------------------------------------------------------------------------------------------------------------
# クライアントをビルドするステージ
# クライアントのビルド成果物 (dist) は Git に含まれているが、万が一ビルドし忘れたりや開発ブランチでの利便性を考慮してビルドしておく
# --------------------------------------------------------------------------------------------------------------
FROM node:20.16.0 AS client-builder

# 依存パッケージリスト (package.json/yarn.lock) だけをコピー
WORKDIR /code/client/
COPY ./client/package.json ./client/yarn.lock /code/client/

# 依存パッケージを yarn でインストール
RUN yarn install --frozen-lockfile

# クライアントのソースコードをコピー
COPY ./client/ /code/client/

# クライアントをビルド
# /code/client/dist/ に成果物が作成される
RUN yarn build

# --------------------------------------------------------------------------------------------------------------
# メインのステージ
# ここで作成された実行時イメージが docker compose up -d で起動される
# --------------------------------------------------------------------------------------------------------------
# Ubuntu 22.04 LTS (with CUDA) をベースイメージとして利用
## NVEncC の動作には CUDA ライブラリが必要なため、CUDA 付きのイメージを使う
## RTX 5090 (Blackwell) 世代をサポートする最低バージョンである CUDA 12.8.0 を指定している
## cuda:x.x.x-runtime 系イメージだと NVEncC で使わない余計なライブラリが付属して重いので、base イメージを使う
FROM ubuntu:22.04

# タイムゾーンを東京に設定
ENV TZ=Asia/Tokyo

# apt-get に対話的に設定を確認されないための設定
ENV DEBIAN_FRONTEND=noninteractive

# サードパーティーライブラリの依存パッケージをインストール
## libfontconfig1, libfreetype6, libfribidi0: フォント関連のライブラリ (なぜ必要だったか忘れたが多分ないと動かない)
## Zendriver: Twitter GraphQL API を叩くために必要な Google Chrome とサイズ小さめの日本語フォントをインストールする
RUN apt-get update && \
    # リポジトリ追加に必要な最低限のパッケージをインストール
    apt-get install -y --no-install-recommends ca-certificates curl git gpg tzdata && \
    # Google Chrome リポジトリ
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --yes --dearmor --output /usr/share/keyrings/google-chrome-keyring.gpg && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main' > /etc/apt/sources.list.d/google-chrome.list && \
    # リポジトリを更新し、この時点で利用可能なパッケージをアップグレード
    apt-get update && apt-get upgrade -y && \
    # 必要なパッケージをインストール
    apt-get install -y --no-install-recommends \
        # フォント関連のライブラリ
        libfontconfig1 libfreetype6 libfribidi0 \
        # Zendriver 用に Google Chrome と日本語フォントをインストール
        google-chrome-stable fonts-vlgothic && \
    # 実行時イメージなので RUN の最後に掃除する
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

# ダウンロードしておいたサードパーティーライブラリをコピー
WORKDIR /code/server/
COPY --from=thirdparty-downloader /thirdparty/ /code/server/thirdparty/

# Poetry の依存パッケージリストだけをコピー
COPY ./server/pyproject.toml ./server/poetry.lock ./server/poetry.toml /code/server/

# 依存パッケージを poetry でインストール
## 仮想環境 (.venv) をプロジェクト直下に作成する
RUN /code/server/thirdparty/Python/bin/python -m poetry env use /code/server/thirdparty/Python/bin/python && \
    /code/server/thirdparty/Python/bin/python -m poetry install --only main --no-root

# サーバーのソースコードをコピー
COPY ./server/ /code/server/

# クライアントのビルド成果物 (dist) だけをコピー
COPY --from=client-builder /code/client/dist/ /code/client/dist/

# config.example.yaml をコピー
COPY ./config.example.yaml /code/config.example.yaml

# KonomiTV サーバーを起動
ENTRYPOINT ["/code/server/.venv/bin/python", "KonomiTV.py"]
