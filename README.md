# MTG Proxy 一键安装脚本

基于 [MTG](https://github.com/9seconds/mtg) 的 Telegram 代理一键安装脚本，专为 Ubuntu 24.04 LTS 优化。

## 特性

- 🚀 一键安装，自动配置
- 🔒 支持 FakeTLS 流量伪装
- 🎯 交互式配置，简单易用
- 🔄 自动开机启动
- 📊 完整的日志管理
- 🛡️ 内置安全防护（防重放攻击、IP 黑名单）
- ⚡ 性能优化配置

## 系统要求

- Ubuntu 24.04 LTS (x64)
- 其他使用 systemd 的 Linux 发行版也可能支持
- Root 权限

## 快速安装

```bash
wget -O install.sh https://raw.githubusercontent.com/interesmazing/mtg-proxy-installer/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

或者一键执行：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/interesmazing/mtg-proxy-installer/main/install.sh)
```

## 安装过程

脚本会提示你输入以下信息：

1. **服务端口**（默认：8440）
2. **伪装域名**（默认：azure.microsoft.com）
3. **密钥**（默认：自动生成）
4. **Telegram 频道**（可选，用于推广）

所有选项都有默认值，直接回车即可使用默认配置。

## 管理命令

安装完成后，可以使用以下命令管理服务：

```bash
# 查看服务状态
systemctl status mtg

# 启动服务
systemctl start mtg

# 停止服务
systemctl stop mtg

# 重启服务
systemctl restart mtg

# 查看实时日志
journalctl -u mtg -f

# 查看最近日志
journalctl -u mtg -n 100

# 查看访问链接
mtg access /etc/mtg.toml
```

## 卸载

```bash
# 停止并禁用服务
systemctl stop mtg
systemctl disable mtg

# 删除相关文件
rm -f /usr/local/bin/mtg
rm -f /etc/systemd/system/mtg.service
rm -f /etc/mtg.toml

# 重载 systemd
systemctl daemon-reload
```

## 配置文件

配置文件位置：`/etc/mtg.toml`

主要配置项：

- `secret`: 代理密钥
- `bind-to`: 监听地址和端口（默认：0.0.0.0:8440）
- `concurrency`: 最大并发连接数（2048）
- `tcp-buffer`: TCP 缓冲区大小（256kb）
- `doh-ip`: DNS over HTTPS 服务器（1.1.1.1 - Cloudflare）

## 性能优化

脚本已针对中等配置服务器进行优化：

- 并发连接数：2048
- TCP 缓冲区：256KB
- 连接超时：3秒
- HTTP 超时：5秒
- 空闲超时：30秒

## 安全特性

- ✅ 防重放攻击保护
- ✅ IP 黑名单自动更新（每 12 小时）
- ✅ FakeTLS 流量伪装
- ✅ DNS over HTTPS 加密查询

## 故障排查

### 服务无法启动

```bash
# 查看详细错误日志
journalctl -u mtg -n 50 --no-pager

# 检查配置文件
cat /etc/mtg.toml

# 手动测试运行
mtg run /etc/mtg.toml
```

### 端口被占用

```bash
# 查看端口占用
netstat -tlnp | grep :8440

# 或使用 ss 命令
ss -tlnp | grep :8440
```

### 时间同步问题

如果出现时间偏差错误：

```bash
# 安装 NTP 客户端
apt install -y systemd-timesyncd

# 启用时间同步
timedatectl set-ntp true

# 检查时间状态
timedatectl status
```

## 升级

重新运行安装脚本即可升级到最新版本：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/interesmazing/mtg-proxy-installer/main/install.sh)
```

脚本会自动检测现有配置并保留。

## 相关链接

- [MTG 项目](https://github.com/9seconds/mtg)
- [MTG 配置文档](https://github.com/9seconds/mtg/blob/master/example.config.toml)
- [Telegram 代理设置](https://telegram.org/blog/proxy-revolution)

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 免责声明

本脚本仅供学习和研究使用，请遵守当地法律法规。使用本脚本所产生的任何后果由使用者自行承担。