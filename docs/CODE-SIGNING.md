# 代码签名（fastlane match）

证书和描述文件通过 [fastlane match](https://docs.fastlane.tools/actions/match/) 管理，
加密存放在**私有仓库** `lingfengmarskey/workout-certificates` 中。本仓库只保存配置
（`fastlane/Matchfile`、`Gemfile`），不含任何证书或私钥。

- Apple Team：`E393H8D2JP`
- App Identifier：`com.lingfengmarskey.workout`
- 签名类型：`development`、`appstore`

## 首次初始化（生成并上传证书）

在项目根目录执行。第一次会提示设置**加密口令**（`MATCH_PASSWORD`）和 Apple 开发者账号：

```bash
bundle install
bundle exec fastlane match development
bundle exec fastlane match appstore
```

> 妥善保管加密口令——它是解密证书仓库的唯一钥匙。丢失只能 `match nuke` 后重新生成。
> 想避免 Apple ID 双重认证，可改用 App Store Connect API Key，设置环境变量
> `APP_STORE_CONNECT_API_KEY_KEY_ID` / `_ISSUER_ID` / `_KEY` 后再运行。

## 在其它机器 / CI 上拉取证书（只读，不新建）

```bash
bundle exec fastlane match development --readonly
bundle exec fastlane match appstore --readonly
```

## 与 Xcode 工程的关系

当前 `project.yml` 使用 `CODE_SIGN_STYLE: Automatic`。match 生成的描述文件命名为
`match Development com.lingfengmarskey.workout` 等。若要让构建改用 match 管理的手动签名，
需在 `project.yml` 中把对应 target 切换为 `CODE_SIGN_STYLE: Manual` 并指定
`PROVISIONING_PROFILE_SPECIFIER`，再 `xcodegen generate`。这一步尚未做，等需要稳定
CI/归档流程时再切换。
