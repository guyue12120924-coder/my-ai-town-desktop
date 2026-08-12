# AI Town 桌面上下文桥

这个本地桥接进程只监听 `127.0.0.1` 上每次启动随机选择的高位端口，用于完成这些工作：

1. 调用未修改的 `vendor/unlimited-ai-first/src/context.js`，把居民资料、当前状态、记忆和世界约束整理为连续性上下文。
2. 在玩家启用独立增强模式时，接入未修改的 `prompts.js`、原版运行约束、😈/😇 Prompt、模型回退，以及适配 AI Town schema 的记忆提取和连续性分析。
3. 始终追加 AI Town JSON 决策合同，再把消息转发到固定的硅基流动 HTTPS 接口。

桥接进程不会保存或打印 API Key，也不接受用户提供的上游 URL。请求正文上限为 2 MiB，上游响应上限为 8 MiB，模型输出上限会限制在 4096 tokens。API Key 仍由 Godot 的加密凭据存储管理，只会在本次模型请求中通过本机回环地址传给桥接进程。

Godot 每次启动都会生成 256 位随机桥接令牌和随机端口，并在发送 API Key 前完成身份探测。桥接进程拒绝没有本次令牌的调用，端口被其他程序占用或探测失败时，Provider 会停止请求而不是把密钥发给未知本机服务。

## 开发环境

安装 Node.js 20 或更高版本，然后从 Godot 打开 `game/project.godot`。游戏启动时会自动运行：

```text
node desktop_bridge/server.mjs --port <随机端口> --parent-pid <Godot PID> --bridge-token <随机令牌>
```

必须使用递归子模块下载项目：

```bash
git clone --recurse-submodules <repository-url>
```

如果已经普通克隆，请执行：

```bash
git submodule update --init --recursive
```

## Windows 发布包

正式构建会把 `node.exe`、桥接脚本、固定版本的 `context.js`、`prompts.js` 及其许可证放在游戏程序旁边。玩家不需要另行安装 Node.js。

## 授权边界

`unlimited-ai-first` 固定在提交 `64409d7ad930e7ff5948f2c15764c440741d01ae`。本项目调用子模块中未修改的 `context.js` 与 `prompts.js`，并在本地适配层使用原版运行约束文本。其许可证禁止未经许可修改、改编和商业使用；分发或商用前必须确认已取得覆盖这种组合使用的授权，并遵守 `vendor/unlimited-ai-first/LICENSE`。
