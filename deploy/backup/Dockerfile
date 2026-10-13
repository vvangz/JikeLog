# 即刻日志备份服务（ADR-012）：每天检查一次，距上次成功备份满 BACKUP_INTERVAL_DAYS 天就执行，
# 备份数据库、附件与 .env，用 age 公钥加密后保存在本地，并上传到异地 OSS。
FROM postgres:17-alpine

# 国内网络本地构建时可指定软件源，例如 --build-arg APK_MIRROR=mirrors.aliyun.com
ARG APK_MIRROR=
RUN if [ -n "$APK_MIRROR" ]; then sed -i "s#dl-cdn.alpinelinux.org#${APK_MIRROR}#g" /etc/apk/repositories; fi \
    && apk add --no-cache age rclone tzdata jq \
    && mkdir -p /backups

COPY backup.sh /usr/local/bin/backup.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh \
    && echo "30 3 * * * /usr/local/bin/backup.sh scheduled >> /proc/1/fd/1 2>&1" > /etc/crontabs/root

ENV TZ=Asia/Shanghai
VOLUME ["/backups"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["daemon"]
