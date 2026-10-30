# 单一 sing-box 规则集（.srs）

把 [`appshubcc/bett-rules`](https://github.com/appshubcc/bett-rules) 在 `sing` 分支上发布的**上千个**分类规则集，收敛成**一个**远程 `.srs` 文件，供 sing-box 直接以 `remote` 方式引用。

- 内容：`geolocation-!cn`（GFWList + 社区规则 + 海外域名，已剔除国内直连子域）——即"**该走代理的域名总表**"
- 构建：每天 08:00（北京时间）自动跟随上游重建；也可在 Actions 里手动触发
- 格式：sing-box 二进制规则集，声明 `version: 2`，与上游自己发布的 `.srs` 一致

> 注意：`.srs` 只是"匹配集合"，不含动作。这个文件只回答"某个域名是否属于代理范围"，具体走哪个出站由你配置里的 `rules` 决定。

## 远程地址

| 通道 | URL |
| --- | --- |
| jsDelivr（推荐，国内较快） | `https://cdn.jsdelivr.net/gh/yuedaochangmendian/bett-rules@srs/bett.srs` |
| GitHub raw | `https://raw.githubusercontent.com/yuedaochangmendian/bett-rules/srs/bett.srs` |
| Release 资产 | `https://github.com/yuedaochangmendian/bett-rules/releases/download/srs-latest/bett.srs` |

同时发布的还有 `bett.json`（可读的源规则集）和 `meta.json`（上游 commit、构建时间、体积）。

## sing-box 配置片段

```json
{
  "route": {
    "rule_set": [
      {
        "type": "remote",
        "tag": "bett-proxy",
        "format": "binary",
        "url": "https://cdn.jsdelivr.net/gh/yuedaochangmendian/bett-rules@srs/bett.srs",
        "download_detour": "proxy",
        "update_interval": "1d"
      }
    ],
    "rules": [
      { "rule_set": ["bett-proxy"], "outbound": "proxy" }
    ],
    "final": "direct"
  }
}
```

- `download_detour` 指向一个已存在的出站 tag，避免规则集本身走代理时死循环；没有代理出站可删掉这一行
- 想同时判断 IP，可再加一条 `{"ip_is_private": true, "outbound": "direct"}` 之类的规则，或自行并入 `geoip:cn`
- `update_interval` 最短 `1m`；规则集文件约 180 KB

## 改动构建范围

`SETS` 环境变量决定合并哪些上游分类（空格分隔，不带 `.json`）：

```bash
SETS="geolocation-!cn category-ads-all" bash scripts/build-srs.sh
```

在 Actions 页面点 `Run workflow` 时也可以填 `sets` 输入框。

## 本地构建

```bash
SING_BOX_BIN=/path/to/sing-box bash scripts/build-srs.sh
```

产物在 `dist/`：`bett.srs`、`bett.json`、`meta.json`。脚本内置自检——默认要求 `google.com` 命中、`baidu.com` 不命中，不满足会直接失败。

## 首次使用需要做的事

1. 仓库 **Actions** 页面点一次 `I understand my workflows, go ahead and enable them`（fork 默认不启用）
2. **定时任务在 fork 里默认是关闭的**，需要在 Actions 里手动跑一次 `build-srs`，之后 `schedule` 才会生效
3. 建议把上游继承来的 `run` / `delete` 两个 workflow 禁用（`gh workflow disable run.yml`），否则它们会在你的 fork 里重复跑完整的 Go 构建并推送 `release`/`meta`/`sing` 分支

## 回滚

`dist/` 里的内容全部由脚本生成，删除 `srs` 分支和 `srs-latest` Release 即可，不影响上游任何分支。
