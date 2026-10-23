#ifndef RUNNER_DEVICE_CHANNEL_H_
#define RUNNER_DEVICE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// 平台通道 jikelog/device，与 Android 的 MainActivity 提供相同的方法：
//   timeZone  返回当前时区的 IANA 名称（如 Asia/Shanghai），读取失败时返回 null。
// 返回的通道须与引擎同生命周期保存。
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDeviceChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_DEVICE_CHANNEL_H_
