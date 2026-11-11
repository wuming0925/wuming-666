# AwemeComment.dylib —— 抖音评论区蓝字 + 定位

抖音 **40.7.0** / iOS 15.0+ / arm64（含 arm64e 设备兼容）

## 现在能做什么

| 功能 | 状态 |
|---|---|
| 蓝字（关键词染色） | ✅ 完整可用 |
| 探测（扫出评论模型类名/字段） | ✅ 完整可用 |
| 定位（按 IP 属地过滤） | ⚠️ 需要先在探测结果里拿到真实字段名，下一版开启 |

## 使用三步

### 1. 编译（2 分钟，浏览器操作）

1. 打开 https://github.com/new ，仓库名填 `aweme-comment`，选 Public，点 Create
2. 点 **uploading an existing file**，把本目录下所有文件**连文件夹一起**拖进去
   - 注意：`.github/workflows/build.yml` 这个路径必须保持原样
3. 点 **Commit changes**
4. 点顶部 **Actions** → 左侧 **build** → 右侧 **Run workflow** → 绿色按钮
5. 等约 2 分钟，刷新页面，点进最新那次运行，页面底部 **Artifacts** 下载 `AwemeComment-dylib`

解压得到的 `AwemeComment.dylib` 就是成品。

### 2. 注入

LCsign → 打开你那个抖音 40.7.0 项目 → **+ 添加** → 选中 `AwemeComment.dylib` → 签名并安装。

> ⚠️ 你那个包里 `DYKiller.dylib` 显示「待处理」，如果装完闪退，先把它删了再试。

### 3. 验收

打开抖音 → 随便刷到一个有评论的视频 → 打开评论区。

**成功标志**：评论里出现「抽奖」「福利」「包邮」「免费送」这几个词的，文字会变成蓝色。

**没蓝字的话**，说明 hook 没生效，看下一步。

## 拿探测结果（关键）

评论区里 **三指长按** 任意位置 1.5 秒 → 弹出探测窗口。

窗口里会列出所有名字含 `Comment` 的类的字段，例如：

```
[CLASS] AWEMEContentCommentModel  (ivars=42, strings=9)
    mText
    mIpLocation
    mUid
    mAuthorUid
    mAvatarUrl
```

**把这个窗口截图发我**，我就能把定位过滤的字段锁定，出下一版。

如果弹窗没出来，探测结果也会写到这三个位置，用 Filza 的「应用数据 → 抖音 → Documents」找 `acprobe.txt`：

```
<抖音沙盒>/Documents/acprobe.txt
/tmp/acprobe.txt
/var/mobile/Documents/acprobe.txt
```

## 配置（可选）

不配也能用，默认词表是 `抽奖 / 福利 / 包邮 / 免费送`，颜色 `#FF2B7FFF`。

想改的话，把配置放到：

```
/var/mobile/Library/Preferences/com.aweme.comment.plist
```

```xml
<dict>
  <key>keywords</key>
  <array><string>抽奖</string><string>福利</string></array>
  <key>regions</key>
  <array><string>北京</string><string>上海</string><string>广东</string></array>
  <key>drop</key>
  <array><string>http://</string><string>加V</string></array>
  <key>color</key><string>#FF2B7FFF</string>
  <key>whole_text</key><integer>1</integer>
  <key>hide_location</key><integer>1</integer>
</dict>
```

| 键 | 说明 |
|---|---|
| `keywords` | 命中就染色 |
| `regions` | 地区白名单，空数组=不过滤 |
| `drop` | 命中就丢弃该评论 |
| `whole_text` | 1=整条染色，0=只染关键词 |
| `hide_location` | 1=去掉"IP属地：xx"尾巴 |
| `color` | `#AARRGGBB` |

## 技术说明（给后续维护）

- **不依赖 CydiaSubstrate**：用 `method_setImplementation` 做链式 hook，所以未越狱签名环境也能跑
- **不硬编码类名**：抖音版本变动时，蓝字走的是 `UILabel/UITextView` 这层的通用 hook，不依赖评论模型类
- **hook 时机**：`constructor` 里延迟 2 秒装 hook，避开和其他插件抢顺序
- **探测时机**：延迟 6 秒在后台线程跑 `objc_copyClassList`，不阻塞启动
- **兼容的 UI 类**：`UILabel` / `UITextView` / `YYLabel`（抖音历史上三个都用过）
