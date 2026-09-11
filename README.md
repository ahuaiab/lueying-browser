# jianyue-browser

简悦浏览器是一款基于 HarmonyOS 原生 ArkUI / ArkWeb 的移动端浏览器。

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
