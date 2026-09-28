# SkanaTwiee

[English](README.md) · **简体中文**

> **非官方应用。** 本应用与 Twitch Interactive, Inc. 没有任何关联、背书或授权关系。"Twitch" 是 Twitch Interactive, Inc. 的商标。本仓库中的名称、图标与素材均为项目自有。

一个用 ArkTS 写的原生 HarmonyOS Twitch 客户端：直播、视频、聊天、下载与后台播放，全部直接构建在系统 Kit 之上（`AVPlayer`、`AVSession`、ArkWeb、ArkUI），没有任何第三方运行时依赖。

移植自 [Xtra for Twitch](https://github.com/andreyasadchy/xtra)（Android）——下文所有 API 流程都以那份实现为参考。

---

## 功能

**浏览**
- 关注：你关注的直播频道，以及它们的视频
- 搜索：直播频道、视频、用户，带最近搜索
- 频道主页：直播状态、关注数/观看数、近期视频、未开播横幅
- 视频：往期直播、精彩片段、上传视频

**播放**
- 同一个播放器播 HLS 直播与 VOD，可选清晰度（自动 / 源 / 1080p / 720p / 480p / 360p / 160p），倍速 0.5×–3×
- 清晰度按**分辨率**匹配，所以"720p"能找到"720p60"；直播没有该档位时回落到自动，而不是直接失败
- 全屏、无边框控件、双击快进、记住播放进度
- 已下载文件的"仅音频"播放页，按音乐播放器的布局排布

**聊天**
- 直播聊天走 Twitch 的 IRC WebSocket，表情来自 Helix
- VOD 评论随视频回放，按 Twitch 的 replay API 分页

**资料库**
- 收藏与下载都保存在本机，两者都不需要登录
- 下载：可选清晰度、可暂停续传、跑在 `dataTransfer` 长时任务下、离线可播

**系统集成**
- 每个进程一个长期存活的 `AVSession`，驱动播控中心卡片、状态栏胶囊和锁屏（标题、频道、封面、进度条）
- 后台播放在 `audioPlayback` 长时任务下运行，锁屏、播控中心和耳机都能控制

**语言**
- 英文（默认文案表）与简体中文（`resources/zh_Hans`）
- 设置 → 语言：跟随系统（默认）、简体中文、English；切换后应用会自行重启，立即生效

---

## 环境要求

| | |
|---|---|
| IDE | DevEco Studio |
| SDK | HarmonyOS 6.1.1 (API 24) 及以上——`compatibleSdkVersion` 6.1.1(24)，`targetSdkVersion` 26.0.0 |
| 目标设备 | 运行 HarmonyOS 的手机或平板 |
| 运行时依赖 | 无（只用系统 Kit） |

声明的权限：`ohos.permission.INTERNET`、`ohos.permission.GET_NETWORK_INFO`、`ohos.permission.KEEP_BACKGROUND_RUNNING`。后台模式：`audioPlayback`、`dataTransfer`。

## 构建

```shell
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物在 `entry/build/default/outputs/default/entry-default-signed.hap`。

**签名。** `build-profile.json5` 里的 `default` 签名配置指向创建它的那台机器上的证书文件。换机器时先生成自己的签名：DevEco Studio → *File → Project Structure → Signing Configs → Automatically generate signature*，否则签名这一步会失败。

## 安装

```shell
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

或者在 DevEco Studio 里选好设备直接 Run。

---

## 目录结构

```
AppScope/                      应用级配置与资源（应用名、分层图标）
entry/
  src/main/
    module.json5               ability、权限、后台模式
    ets/
      common/                  Const（接口地址、preference 键）、Prefs、Nav、Immersive、Language
      model/                   纯数据类型（Video、ChannelInfo、Quality、DownloadEntry……）
      network/                 Http、GqlClient、Queries、GqlTypes
      pages/                   Index、Player、AudioPlayer、Channel、Library、Login、Settings
      player/                  PlaybackSession（AVSession + 长时任务）、HlsParser、LiveWindow
      repository/              Auth、Playback、Video、Channel、Download、Favourite、
                               Comment、Settings、SettingsFile、LibraryMigration
      util/                    ImageLoader、TwitchHelper、PagedDataSource、ChatText
      view/                    卡片、头部、MenuChoice、SettingRow
    resources/
      base/element/string.json     英文文案（默认表）
      zh_Hans/element/string.json  简体中文
      base/media/                  分层图标（background + foreground）、startIcon
      dark/element/                深色模式配色
  src/test/                    本地单元测试（hypium）
  src/ohosTest/                仪器化测试
scripts/                       图标生成与检查脚本（Swift）
```

## 工作原理

- **Twitch API** —— 大部分走 GraphQL persisted queries，表情集合走 Helix，播放令牌与 HLS 播放列表走 usher。关注/取关会带上 Twitch 要求的 Client-Integrity 签名。
- **登录** —— 在 WebView（ArkWeb）里用 Twitch 自己的网页登录。OAuth token 与 Client-Integrity 签名是从页面自身发出的请求里读到的，应用全程不接触密码。
- **播放** —— `AVPlayer` 搭配 `XComponent` 的 SURFACE；`player/HlsParser.ets` 把播放列表解析成清晰度菜单用的档位。
- **媒体会话** —— `player/PlaybackSession.ets` 持有唯一的 app 级 `AVSession`，按 kind 引用计数，所以卡片或胶囊不会被页面切换拆掉。会话类型跟随播放内容（"仅音频"页用 `audio`，其余用 `video`），并开启 `setBackgroundPlayMode(ENABLE_BACKGROUND_PLAY)`——这正是系统愿意为 **video** 会话展示自己那套媒体界面的前提。
- **本地状态** —— 只用 preferences（`common/Prefs`，键定义在 `common/Const.ets`），没有数据库。收藏、下载、播放进度和设置都存在里面，设置文件导入导出读写的也是同一批记录。
- **文案** —— 所有面向用户的文字都是资源；语言存在 `app_language` 下，每次启动都会重新下发给 `i18n.System.setAppPreferredLanguage`。

## 测试与静态检查

- 本地单元测试：`entry/src/test`（hypium）——在 DevEco Studio 里对单个文件运行
- 仪器化测试：`entry/src/ohosTest`
- Code Linter：规则见 `code-linter.json5`（performance、TypeScript、security 三套规则集），在 DevEco Studio 里运行

## 脚本

```shell
swift scripts/gen-icons.swift <输出目录>          # 重新生成 background/foreground/startIcon
swift scripts/inspect-icon.swift <png> [列数]    # 打印 ASCII 预览 + alpha 包围盒
```

`gen-icons.swift` 画的是本应用的标记——紫底上一个像素风对话气泡，中间镂空一个播放三角，右上切 45°，左下带一条尾巴。想改配色或比例，改文件顶部的常量即可，然后把三张 PNG 分别拷进 `AppScope/resources/base/media/` 和 `entry/src/main/resources/base/media/`。

---

## 已知限制

- **状态栏胶囊 / 锁屏** 来自媒体会话（`AVSession`），不是实况窗。`player/LiveWindow.ets` 也尝试了实况窗，但它的场景都是任务型（配送、航班、健身……），且每个都要华为授予权限，所以拿不到权限时会安静放弃。
- **视频播放跟随页面生命周期**：离开应用（回桌面、锁屏）会继续播，但在应用内离开播放页会释放播放器。"仅音频"播放同理。
- **下载只存在应用沙箱内** —— 只能从资料库播放，不会导出到系统文件管理或图库。

## 致谢

- API 流程、功能范围与界面行为参考 [Xtra for Twitch](https://github.com/andreyasadchy/xtra)。
- 构建在 HarmonyOS 系统 Kit 之上：Media Kit、AVSession Kit、ArkWeb、ArkUI、Background Tasks Kit、Notification Kit、Localization Kit。

## 许可证

GNU Affero 通用公共许可证第 3 版 —— 全文见 [LICENSE](LICENSE)。

Xtra for Twitch 采用 AGPL-3.0，本项目是它的移植，因此同样采用 AGPL-3.0，并承担同样的义务：

- 拿到应用的人有权获得相同许可证下的对应源码；
- 源码中要保留醒目的声明，说明这是经过修改的移植版本以及修改时间（源码文件里的注释和 `git log` 就是这类声明）；
- 软件不提供任何担保。

不要在源码闭源的情况下发布本应用的构建产物。若要改用其他许可证，代码必须是**净室重写**，不含任何源自 Xtra 的代码。
