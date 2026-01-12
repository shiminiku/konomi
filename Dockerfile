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
RUN aria2c -x10 https://github.com/tsukumijima/KonomiTV/releases/download/v0.12.0/thirdparty-linux.tar.xz
RUN tar xvf thirdparty-linux.tar.xz
## 開発版 (0.x.x-dev) 用
# RUN aria2c -x10 https://nightly.link/tsukumijima/KonomiTV/actions/runs/13269769043/thirdparty-linux.tar.xz.zip
# RUN unzip thirdparty-linux.tar.xz.zip && tar xvf thirdparty-linux.tar.xz

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
# Ubuntu 22.04 LTS をベースイメージとして利用
FROM ubuntu:22.04

# タイムゾーンを東京に設定
ENV TZ=Asia/Tokyo

# apt-get に対話的に設定を確認されないための設定
ENV DEBIAN_FRONTEND=noninteractive

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
