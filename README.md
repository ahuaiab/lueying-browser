# jianyue-browser

简悦浏览器是一款基于 HarmonyOS 原生 ArkUI / ArkWeb 的移动端浏览器。

## AI 使用说明

本项目源码主要由 AI 根据项目发起人提供的产品创意和方向生成。项目发起人主要提供创意，不将 AI 生成内容表述为项目发起人的全部独立原创代码。

AI 输出的权利范围取决于所使用 AI 服务的条款和适用法律。贡献者和再分发者仍需自行核对源码、资源及依赖中可能存在的第三方权利内容；不能仅根据本节推断整个仓库的许可证。

## 开源说明

本仓库公开当前版本的完整工程源码，项目地址为 [GitHub 仓库](https://github.com/ahuaiab/jianyue-browser)。工程位于 `app/`，浏览器业务代码位于 `app/entry/src/main/ets/browser/`。

> [!IMPORTANT]
>
> “公开源码”表示源码可供开发者查看和构建。仓库根目录的 `LICENSE` 采用 Apache-2.0，但该许可证仅适用于项目所有者有权授权的内容，不覆盖第三方代码、模板代码或外部依赖的原有许可。

### 外部代码与依赖

- `EntryAbility.ets`、`EntryBackupAbility.ets`：基于 HarmonyOS/DevEco 工程模板，文件头标注 Apache License 2.0；请按文件头许可使用。
- `@ohos/hypium@1.0.25`：测试框架，来自 [OpenHarmony OHPM](https://ohpm.openharmony.cn/)。
- `@ohos/hamock@1.0.0`：测试 Mock 能力，来自 [OpenHarmony OHPM](https://ohpm.openharmony.cn/)。版本记录见 `app/oh-package.json5` 和 `app/oh-package-lock.json5`。
- HarmonyOS ArkUI / ArkWeb API：运行时由 HarmonyOS SDK 提供，SDK 不随本仓库分发。

截至当前修订版，除上述模板代码和外部依赖外，未发现其他以源码形式引入的第三方项目。后续引入第三方源码或依赖时，请补充名称、来源 URL、版本或 commit、许可证、用途及本地修改范围。

## 许可证

本项目中由项目所有者拥有或有权授权的内容采用 [Apache License 2.0](LICENSE)。再分发或修改时，请分别核对源文件头和外部依赖的上游许可证；Apache-2.0 不会替代这些独立许可。

## 从源码构建 HAP

项目工程位于 `app/` 目录。安装 DevEco Studio 或 DevEco CLI 后，在项目根目录执行：

```sh
cd app
devecocli build --modules entry --product default --build-mode debug
```

无签名构建产物位于 `app/entry/build/default/outputs/default/entry-default-unsigned.hap`（具体文件名以当前 DevEco 版本为准）。

公开源码不携带任何开发者个人签名材料。首次需要安装或签名部署时，请使用自己的华为开发者账号生成本机签名配置：

```sh
devecocli auth login
devecocli signature generate --product default
```

签名材料只保存在本机，不要提交到 Git。
