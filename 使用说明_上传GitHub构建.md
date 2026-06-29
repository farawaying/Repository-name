# 上传 GitHub 自动构建说明

1. 新建一个 GitHub 仓库。
2. 解压本项目 zip。
3. 把 `Makefile`、`control`、`SpringBoard`、`AppHook`、`Prefs`、`layout`、`.github` 等内容上传到仓库根目录。
4. 打开仓库的 `Actions`。
5. 选择 `Build rootless deb`。
6. 点击 `Run workflow`。
7. 构建结束后，在 Artifacts 下载 `OrbitWindow-rootless-deb`。
8. 解压 Artifact，得到 `.deb`。
9. 传到手机，用 Sileo 安装。
10. 安装后点击设置里的“注销应用插件效果”，或者手动注销 SpringBoard。

如果构建失败，把 GitHub Actions 最后 80 行红色日志发回来。
如果安装后进入安全模式，先卸载插件，再把 SpringBoard 崩溃日志发回来。
