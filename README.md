# NetBar

功能:复刻MacOS原生Wi-Fi菜单,增加MenuBar热点蜂窝信号显示功能

![菜单](docs/menu.png)

## 安装

用 Homebrew 安装预编译版本:

```sh
brew tap Steve5wutongyu6/netbar https://github.com/Steve5wutongyu6/NetBar.git
brew install --cask netbar
```

需要本机编译:

```sh
brew install --build-from-source netbar
```

也可以从 [Releases](../../releases) 下载 zip,解压后把 `NetBar.app` 拖入「应用程序」。

## 构建

```sh
make build      # 编译引擎与 App
make test       # 引擎与 App 单元测试
make run        # 构建并启动
make snapshot   # 把菜单渲染成 build/menu.png
make project    # 改动源文件清单后重新生成 Xcode 工程
```
