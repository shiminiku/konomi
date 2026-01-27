# konomi
**好みの [KonomiTV](https://github.com/tsukumijima/KonomiTV) をビルド**

エンコーダーは、ffmpeg のみ

CUDA なし、ハードウェアエンコード なし

## タグ

```sh
docker pull ghcr.io/shiminiku/konomi:latest
```

- v0.13.0
  標準リリース
- v0.13.0-browserless
  Twitter連携で使うブラウザを省いた

## 自慢

**1.85GB → 0.927GB (or 0.678GB in browserless)**

```
IMAGE                                          ID             DISK USAGE   CONTENT SIZE
ghcr.io/shiminiku/konomi:v0.13.0               5a3294197e1c       2.91GB          927MB
ghcr.io/shiminiku/konomi:v0.13.0-browserless   c80ced738a1e       2.01GB          678MB
ghcr.io/tsukumijima/konomitv:v0.13.0           23628a05adb0       6.05GB         1.85GB
```
