-- 用户自定义头像元数据；图片二进制存对象存储（u/{userID}/avatar/{id}.{ext}），注销账号时随前缀一起清理。

-- +goose Up
ALTER TABLE users
    ADD COLUMN avatar_key  text,
    ADD COLUMN avatar_mime text,
    ADD COLUMN avatar_etag text;

-- +goose Down
ALTER TABLE users
    DROP COLUMN avatar_etag,
    DROP COLUMN avatar_mime,
    DROP COLUMN avatar_key;
