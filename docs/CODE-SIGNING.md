# 代码签名（fastlane match）

证书和描述文件通过 [fastlane match](https://docs.fastlane.tools/actions/match/) 管理，
加密存放在**私有仓库** `lingfengmarskey/workout-certificates` 中。本仓库只保存配置
（`fastlane/Matchfile`），不含任何证书或私钥。

- Apple Team：`E393H8D2JP`
- App Identifier：`com.lingfengmarskey.workout`
- 签名类型：`development`、`appstore`

## 安装 fastlane

本机用 Homebrew 安装的、自带 Ruby 的 fastlane（**不要用 bundler / rvm 的 Ruby**，原因见文末）：

```bash
brew install fastlane
```

装好后 `fastlane --version` 应显示 2.23x 以上。

## 首次初始化（生成并上传证书）

在项目根目录执行。第一次会提示设置**加密口令**（`MATCH_PASSWORD`）和 Apple 开发者账号：

```bash
fastlane match development
fastlane match appstore
```

> 妥善保管加密口令——它是解密证书仓库的唯一钥匙。丢失只能 `fastlane match nuke` 后重新生成。
> 想避免 Apple ID 双重认证，可改用 App Store Connect API Key，设置环境变量
> `APP_STORE_CONNECT_API_KEY_KEY_ID` / `_ISSUER_ID` / `_KEY` 后再运行。

## 在其它机器 / CI 上拉取证书（只读，不新建）

```bash
fastlane match development --readonly
fastlane match appstore --readonly
```

## 与 Xcode 工程的关系

当前 `project.yml` 已使用 match 管理的手动签名：

- Debug：`Apple Development` + `match Development com.lingfengmarskey.workout`
- Release：`Apple Distribution` + `match AppStore com.lingfengmarskey.workout`

运行 `xcodegen generate` 后，Xcode 工程会使用对应配置的 profile。DeployGate 的 Dev 工作流使用 Debug 配置，并在归档前执行 `fastlane match development --readonly`。

## 为什么不用 bundler / rvm 的 Ruby

本机的 rvm Ruby 是 **x86_64**（Rosetta），而 Xcode 26 的 clang 默认编 **arm64**，
两者不匹配：任何 native gem（如 `nkf`、`json`）都会编成 arm64，x86_64 的 Ruby 加载即报
`incompatible architecture` 而崩溃；`json` 新版还与已 EOL 的 Ruby 3.0 头文件冲突编不过。
Homebrew 的 fastlane 自带一套内部一致的 Ruby 运行时，预编译、不依赖本机 gem 编译，直接可用，
因此这里改用 `brew install fastlane`，不再提供 `Gemfile` / `bundle exec` 路径。
