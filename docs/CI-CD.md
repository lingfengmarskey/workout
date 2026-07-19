# CI/CD：测试、Dev IPA 与 DeployGate

## 工作流

仓库包含两个 GitHub Actions 工作流：

### `Test`

- 合并或直接推送到 `main` 后自动触发。
- Pull Request 也会执行同样的测试。
- 通过 `workflow_call` 暴露给打包工作流，确保打包前会对 tag 指向的提交重新执行测试。
- 使用 XcodeGen 生成 `Workout.xcodeproj`，再在 GitHub-hosted macOS runner 的 iOS Simulator 上执行 `WorkoutTests`。
- 模拟器测试设置 `CODE_SIGNING_ALLOWED=NO`，不需要 match 或真机证书。

### `Package and DeployGate (Dev)`
- 推送形如 `dev-v0.1.0` 的 tag 时触发。
- 先调用测试工作流；测试失败时不会进行签名、打包或上传。
- 使用 `fastlane match development --readonly` 从私有证书仓库拉取加密的开发证书和描述文件。
- 使用 `Debug` 配置生成 development IPA，匹配 `match Development com.lingfengmarskey.workout`。
- 只上传 `Workout.ipa`，不会上传源码。
- 通过 DeployGate Upload API 上传到指定 Project，并保留 14 天的 GitHub Actions IPA artifact。
- 上传成功后通过 SMTP 发邮件到 `lingfengmarskey@gmail.com`，邮件包含 DeployGate 链接和直接文件链接。

## GitHub Secrets

在仓库的 **Settings → Secrets and variables → Actions** 中配置：

| Secret | 说明 |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID，例如 `E393H8D2JP` |
| `MATCH_PASSWORD` | fastlane match 证书仓库的加密口令 |
| `MATCH_GIT_PRIVATE_KEY` | 对 `workout-certificates` 私有仓库具有只读权限的 SSH 私钥 |
| `DEPLOYGATE_API_TOKEN` | DeployGate 用户或 Project API token |
| `DEPLOYGATE_OWNER_NAME` | DeployGate 个人用户名或 Project 名称 |
| `DEPLOYGATE_DISTRIBUTION_KEY` | 可选；已有分发页的 key。设置后邮件会发送稳定的分发页链接 |
| `SMTP_SERVER` | SMTP 服务地址，例如 Gmail 的 `smtp.gmail.com` |
| `SMTP_PORT` | SMTP 端口，例如 `587` |
| `SMTP_USERNAME` | SMTP 登录用户名，通常是 `lingfengmarskey@gmail.com` |
| `SMTP_PASSWORD` | SMTP 密码；Gmail 建议使用 App Password，不要使用主账号密码 |

`MATCH_GIT_PRIVATE_KEY` 对应公钥需要添加到私有仓库 `lingfengmarskey/workout-certificates` 的 Deploy keys，并仅授予读取权限。不要把私钥、`MATCH_PASSWORD` 或 App Password 提交到任何仓库。

## 本地验证签名配置

在本机安装 fastlane 后，可以只读拉取 match 资产：

```bash
brew install fastlane
fastlane match development --readonly
fastlane match appstore --readonly
xcodegen generate
```

当前 `project.yml` 的签名映射为：

- Debug：`Apple Development` + `match Development com.lingfengmarskey.workout`
- Release：`Apple Distribution` + `match AppStore com.lingfengmarskey.workout`

## 发布 Dev 构建

确保 tag 指向已经通过 `main` 测试的提交，然后执行：

```bash
git checkout main
git pull --ff-only origin main
git tag dev-v0.1.0
git push origin dev-v0.1.0
```

Workflow 会在 tag 提交上重新测试。只有测试成功，才会继续生成 development IPA、调用 DeployGate API 并发送邮件。

## DeployGate 链接说明

若设置 `DEPLOYGATE_DISTRIBUTION_KEY`，邮件中的主链接为稳定的 DeployGate 分发页；否则使用 API 返回的 IPA 文件链接。DeployGate API 需要 Project 名称（或个人用户名）以及 API token，IPA 是通过 `file` 表单字段上传的。
