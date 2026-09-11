# XCD 中控 — 越狱 iPhone 的 Wi-Fi 投屏+控制

手机端守护进程：负责抓屏、H.264 推流、接收触摸指令。
针对 **iPhone 8 / iOS 13.6 / unc0ver 越狱 / arm64**。

---

## 第一步：把这些文件上传到你的 GitHub

1. 浏览器打开 <https://github.com/new>，新建一个仓库：
   - Repository name 填 `xcd-daemon`（随便）
   - 选 **Public**（公开，GitHub Actions 免费）
   - 不要勾选 "Add a README"
   - 点 **Create repository**
2. 在仓库页点 **Add file → Upload files**；
3. 把本文件夹里**所有文件**拖进去（包括 `.github` 这个隐藏文件夹、Makefile、control、所有 `.m/.h/.mm`）；
4. 拉到最下面点 **Commit changes**。

## 第二步：触发自动编译

1. 仓库页顶部点 **Actions** 标签；
2. 左边选 **Build XCD Daemon**；
3. 右边点 **Run workflow → 绿色 Run 按钮**；
4. 等 2~5 分钟，看到绿色 ✅ 就是编译成功。

## 第三步：下载编译好的 deb

1. 点进那次成功的运行；
2. 页面最下面 **Artifacts** 区域，点 **xcd-daemon-deb**，会下载一个 zip；
3. 解压，里面就是 `com.xcd.daemon_xxx_iphoneos-arm64.deb`。

## 第四步：装到手机（4 台都做）

方法 A（推荐，最简单）：手机装 **Filza**（Cydia 搜 Filza 安装），
把 deb 发到手机（微信/AirDrop/邮件都行），用 Filza 点开 deb → 安装。

方法 B：手机装了 OpenSSH 的话，用 Windows 的 scp 推上去再 `dpkg -i`。

装完后**完全关机再开机**（不是注销），让 daemon 自启。

## 第五步：连接

1. 手机和电脑连**同一个 Wi-Fi**；
2. 手机 设置 → Wi-Fi → 点当前网络 ⓘ，记下 **IP 地址**；
3. Windows 端运行客户端，选 **Wi-Fi 模式**，填这个 IP。

> 注意：daemon 默认监听 5901/23456 端口。首次连接后，按 iOS 安全机制，
> 要**先用手指在手机屏幕上真实点一下**，电脑鼠标注入的触摸才生效。

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `.github/workflows/build.yml` | GitHub 自动编译脚本 |
| `Makefile` / `control` | theos 编译配置 |
| `main.mm` | 守护进程入口（监听 Wi-Fi 端口） |
| `XCDScreenCapture.mm` | 抓屏 |
| `XCDVideoEncoder.mm` | H.264 硬编码 |
| `XCDTouchInjector.mm` | 触摸注入 |
| `XCDProtocol.h` | 与 Windows 端的通信协议 |

编译若报错，把 Actions 里红色的错误日志发我，我改。
