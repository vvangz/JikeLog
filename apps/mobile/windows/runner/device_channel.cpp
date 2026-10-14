#include "device_channel.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/base.h>

#include <string>

namespace {

// Windows.Globalization.Calendar 给出的就是 IANA 时区名，不需要从 Windows 时区 ID 转换。
std::string CurrentTimeZone() {
  try {
    return winrt::to_string(
        winrt::Windows::Globalization::Calendar().GetTimeZone());
  } catch (...) {
    return std::string();
  }
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDeviceChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "jikelog/device",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "timeZone") {
          result->NotImplemented();
          return;
        }
        const std::string tz = CurrentTimeZone();
        if (tz.empty()) {
          result->Success();
        } else {
          result->Success(flutter::EncodableValue(tz));
        }
      });
  return channel;
}
