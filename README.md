# ComeOnRemember

一个在 Mac 上离线使用的英语词汇练习工具。用「记忆」复习看到英文时能否想起词义，用「使用」练习在中文场景下想出合适的英文表达。

## 开始使用

- **下载安装包**：[下载 ComeOnRemember（Apple Silicon Mac）](https://github.com/iianding/ComeOnRemember/raw/refs/heads/main/ComeOnRemember-macOS-arm64.zip)。解压 ZIP 后，在访达中打开里面的应用。
- **Mac 应用**可以在访达里双击 `ComeOnRemember.app` 打开独立窗口。已打包的版本面向 Apple Silicon Mac。
- **浏览器版**可以直接打开 [src/index.html](src/index.html)。如果只想复制一个文件，使用嵌入了图标的 [src/compat/index.html](src/compat/index.html)。

两种版本都可以离线练习。Mac 应用调用系统英语语音，优先使用英式声线，找不到时使用美式声线。浏览器版的发音取决于浏览器能否调用本地英语声线。

## 复习方式

1. 在「今日复习」选择词库，点击「开始复习」。可在「每日计划」分别设置记忆和使用题数，保存前可查看当前词库的首轮预计完成时间。
2. **记忆**显示英文词条，先回想中文释义，再查看答案。**使用**从中文例句出题，翻卡后可查看中英对照、目标表达和该词的其他例句，并逐句播放。
3. 翻卡后选择「忘了」「模糊」或「记得」。它们分别对应本轮重练、次日再练和逐步拉长复习间隔。在「使用」中点过「给点提示」，本题可选「忘了」或「模糊」。

已标注的常用义项会显示「常用」。同一词既有常用例句也有其他例句时，每三次正式出题抽两次常用义、一次其他义项，顺序打乱。只有一类例句时，在可用例句中轮换。

## 词库与进度

- 内置 **10,758 个词条**，包括课程英语、日常英语、雅思、大学英语四级和六级、托福及考研英语。
- 内置词条都有至少一组中英例句。其中 4,638 个有三组，1,032 个有两组，5,088 个有一组。常见多义词优先提供不同义项的示例，部分词条采用「词义练习」。
- 支持自建词库、添加单词与例句，以及创建和切换本地用户。同一用户在不同词库里的同一英文词条共享复习进度，记忆和使用分别记录。
- Mac 应用将本地记录保存在 `~/Library/Application Support/ComeOnRemember/StudyData.json`。浏览器版用浏览器的本地存储。可在「词库管理」导出当前用户的 JSON 备份，导入时会提示确认替换当前用户的词库、计划和进度。

## 项目结构

| 路径 | 用途 |
| --- | --- |
| [src/index.html](src/index.html) | 网页源码，内置词库、例句、界面和复习逻辑 |
| [src/Launcher.m](src/Launcher.m) | macOS 独立窗口、本地进度、发音和导入导出 |
| [src/NativeBridge.js](src/NativeBridge.js) | 网页与 macOS 应用之间的接口 |
| [src/compat/index.html](src/compat/index.html) | 可单文件打开的浏览器版 |
| [src/licenses/](src/licenses/) | 第三方数据的授权与署名 |

<details>
<summary>在 macOS 上从源码构建</summary>

安装 Xcode 命令行工具后，从项目根目录执行下列命令。生成的应用可直接从访达打开。

```sh
app="build/ComeOnRemember.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"

xcrun clang -fobjc-arc src/Launcher.m \
  -framework AppKit -framework WebKit -framework AVFoundation \
  -framework UniformTypeIdentifiers -o "$contents/MacOS/ComeOnRemember"
cp src/index.html src/NativeBridge.js src/app-icon.png "$contents/Resources/"
cp src/licenses/*.txt "$contents/Resources/"

plist="$contents/Info.plist"
plutil -create xml1 "$plist"
plutil -insert CFBundleExecutable -string ComeOnRemember "$plist"
plutil -insert CFBundleIdentifier -string com.comeonremember.local "$plist"
plutil -insert CFBundleName -string ComeOnRemember "$plist"
plutil -insert CFBundlePackageType -string APPL "$plist"
plutil -insert CFBundleVersion -string 1 "$plist"
codesign --force --sign - "$app"
```

</details>

## 数据来源

词条、释义和音标主要来自 [ECDICT](src/licenses/ECDICT.txt)。双语例句包括 [Tatoeba](src/licenses/Tatoeba.txt)、[词光 Word Atlas](src/licenses/Word-Atlas.txt) 和项目自编内容。词义匹配参考 [Princeton WordNet](src/licenses/Princeton-WordNet.txt) 与 [Chinese Open WordNet](src/licenses/Chinese-Open-WordNet.txt)。第三方例句在卡片的「例句来源与署名」中也可查看。
