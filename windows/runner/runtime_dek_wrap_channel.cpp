#include "runtime_dek_wrap_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincrypt.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr char kChannelName[] = "com.prism.prism_plurality/runtime_dek_wrap";
constexpr int32_t kBlobVersion = 2;
constexpr size_t kRuntimeDekLength = 32;
constexpr uint8_t kEnvelopeMagic[] = {'P', 'R', 'I', 'S',
                                      'M', 'D', 'E', 'K'};
constexpr uint32_t kEnvelopeVersion = 1;

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_runtime_dek_wrap_channel;

struct CryptoResult {
  bool ok = false;
  std::vector<uint8_t> data;
  DWORD error = ERROR_SUCCESS;
};

DATA_BLOB BlobFromBytes(const std::vector<uint8_t>& bytes) {
  DATA_BLOB blob;
  blob.cbData = static_cast<DWORD>(bytes.size());
  blob.pbData = const_cast<BYTE*>(reinterpret_cast<const BYTE*>(bytes.data()));
  return blob;
}

DATA_BLOB BlobFromString(const std::string& value) {
  DATA_BLOB blob;
  blob.cbData = static_cast<DWORD>(value.size());
  blob.pbData = const_cast<BYTE*>(
      reinterpret_cast<const BYTE*>(value.data()));
  return blob;
}

void SecureZeroVector(std::vector<uint8_t>& bytes) {
  if (!bytes.empty()) {
    SecureZeroMemory(bytes.data(), bytes.size());
  }
}

std::string FormatWin32Error(DWORD error) {
  LPSTR message = nullptr;
  const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER |
                      FORMAT_MESSAGE_FROM_SYSTEM |
                      FORMAT_MESSAGE_IGNORE_INSERTS;
  const DWORD length = FormatMessageA(
      flags, nullptr, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPSTR>(&message), 0, nullptr);

  std::string formatted =
      length > 0 && message != nullptr ? std::string(message, length)
                                       : "Windows error";
  if (message != nullptr) {
    LocalFree(message);
  }
  while (!formatted.empty() &&
         (formatted.back() == '\r' || formatted.back() == '\n' ||
          formatted.back() == ' ')) {
    formatted.pop_back();
  }
  return formatted + " (" + std::to_string(error) + ")";
}

std::optional<std::string> Base64Encode(const std::vector<uint8_t>& bytes) {
  if (bytes.empty()) {
    return std::string();
  }

  DWORD length = 0;
  const DWORD flags = CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF;
  if (!CryptBinaryToStringA(bytes.data(), static_cast<DWORD>(bytes.size()),
                            flags, nullptr, &length)) {
    return std::nullopt;
  }

  std::string encoded(length, '\0');
  if (!CryptBinaryToStringA(bytes.data(), static_cast<DWORD>(bytes.size()),
                            flags, encoded.data(), &length)) {
    return std::nullopt;
  }
  if (length > 0 && encoded[length - 1] == '\0') {
    encoded.resize(length - 1);
  } else {
    encoded.resize(length);
  }
  return encoded;
}

std::optional<std::vector<uint8_t>> Base64Decode(const std::string& encoded) {
  if (encoded.empty()) {
    return std::vector<uint8_t>();
  }

  DWORD length = 0;
  if (!CryptStringToBinaryA(encoded.c_str(), static_cast<DWORD>(encoded.size()),
                            CRYPT_STRING_BASE64, nullptr, &length, nullptr,
                            nullptr)) {
    return std::nullopt;
  }

  std::vector<uint8_t> bytes(length);
  if (!CryptStringToBinaryA(encoded.c_str(), static_cast<DWORD>(encoded.size()),
                            CRYPT_STRING_BASE64, bytes.data(), &length,
                            nullptr, nullptr)) {
    return std::nullopt;
  }
  bytes.resize(length);
  return bytes;
}

void AppendUint32(std::vector<uint8_t>& out, uint32_t value) {
  out.push_back(static_cast<uint8_t>(value & 0xff));
  out.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
  out.push_back(static_cast<uint8_t>((value >> 16) & 0xff));
  out.push_back(static_cast<uint8_t>((value >> 24) & 0xff));
}

std::optional<uint32_t> ReadUint32(const std::vector<uint8_t>& bytes,
                                   size_t* offset) {
  if (*offset > bytes.size() || bytes.size() - *offset < 4) {
    return std::nullopt;
  }
  const uint32_t value =
      static_cast<uint32_t>(bytes[*offset]) |
      (static_cast<uint32_t>(bytes[*offset + 1]) << 8) |
      (static_cast<uint32_t>(bytes[*offset + 2]) << 16) |
      (static_cast<uint32_t>(bytes[*offset + 3]) << 24);
  *offset += 4;
  return value;
}

std::optional<std::vector<uint8_t>> BuildRuntimeDekEnvelope(
    const std::vector<uint8_t>& dek,
    const std::string& aad) {
  if (dek.size() != kRuntimeDekLength ||
      aad.size() > static_cast<size_t>(UINT32_MAX)) {
    return std::nullopt;
  }

  std::vector<uint8_t> envelope;
  envelope.reserve(sizeof(kEnvelopeMagic) + 12 + aad.size() + dek.size());
  envelope.insert(envelope.end(), kEnvelopeMagic,
                  kEnvelopeMagic + sizeof(kEnvelopeMagic));
  AppendUint32(envelope, kEnvelopeVersion);
  AppendUint32(envelope, static_cast<uint32_t>(aad.size()));
  envelope.insert(envelope.end(), aad.begin(), aad.end());
  AppendUint32(envelope, static_cast<uint32_t>(dek.size()));
  envelope.insert(envelope.end(), dek.begin(), dek.end());
  return envelope;
}

std::optional<std::vector<uint8_t>> ExtractRuntimeDekFromEnvelope(
    const std::vector<uint8_t>& envelope,
    const std::string& aad) {
  size_t offset = 0;
  if (envelope.size() < sizeof(kEnvelopeMagic)) {
    return std::nullopt;
  }
  for (size_t i = 0; i < sizeof(kEnvelopeMagic); ++i) {
    if (envelope[i] != kEnvelopeMagic[i]) {
      return std::nullopt;
    }
  }
  offset += sizeof(kEnvelopeMagic);

  const auto version = ReadUint32(envelope, &offset);
  if (!version.has_value() || version.value() != kEnvelopeVersion) {
    return std::nullopt;
  }

  const auto aad_length = ReadUint32(envelope, &offset);
  if (!aad_length.has_value() || aad_length.value() != aad.size() ||
      aad_length.value() > envelope.size() - offset) {
    return std::nullopt;
  }
  for (size_t i = 0; i < aad.size(); ++i) {
    if (envelope[offset + i] != static_cast<uint8_t>(aad[i])) {
      return std::nullopt;
    }
  }
  offset += aad.size();

  const auto dek_length = ReadUint32(envelope, &offset);
  if (!dek_length.has_value() || dek_length.value() != kRuntimeDekLength ||
      dek_length.value() != envelope.size() - offset) {
    return std::nullopt;
  }

  return std::vector<uint8_t>(
      envelope.begin() + static_cast<std::ptrdiff_t>(offset), envelope.end());
}

CryptoResult ProtectRuntimeDek(std::vector<uint8_t>& plaintext,
                               const std::string& aad) {
  DATA_BLOB input = BlobFromBytes(plaintext);
  DATA_BLOB entropy = BlobFromString(aad);
  DATA_BLOB output;

  if (!CryptProtectData(&input, L"Prism runtime DEK v1",
                        aad.empty() ? nullptr : &entropy, nullptr, nullptr,
                        CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    CryptoResult result;
    result.ok = false;
    result.error = GetLastError();
    SecureZeroVector(plaintext);
    return result;
  }

  CryptoResult result;
  result.ok = true;
  result.data.assign(output.pbData, output.pbData + output.cbData);
  SecureZeroVector(plaintext);
  LocalFree(output.pbData);
  return result;
}

CryptoResult UnprotectRuntimeDek(const std::vector<uint8_t>& encrypted,
                                 const std::string& aad) {
  DATA_BLOB input = BlobFromBytes(encrypted);
  DATA_BLOB entropy = BlobFromString(aad);
  DATA_BLOB output;

  if (!CryptUnprotectData(&input, nullptr, aad.empty() ? nullptr : &entropy,
                          nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                          &output)) {
    CryptoResult result;
    result.ok = false;
    result.error = GetLastError();
    return result;
  }

  CryptoResult result;
  result.ok = true;
  result.data.assign(output.pbData, output.pbData + output.cbData);
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
  return result;
}

std::string UnprotectErrorCode(DWORD error) {
  if (error == ERROR_INVALID_DATA || error == ERROR_INVALID_PARAMETER) {
    return "runtime_dek_wrap_terminal";
  }
  return "runtime_dek_wrap_failed";
}

const flutter::EncodableValue* FindValue(
    const flutter::EncodableMap& map,
    const char* key) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

const std::string* StringValue(const flutter::EncodableMap& map,
                               const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return nullptr;
  }
  return std::get_if<std::string>(value);
}

std::optional<int64_t> IntValue(const flutter::EncodableMap& map,
                                const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return *int64_value;
  }
  return std::nullopt;
}

const std::vector<uint8_t>* ByteListValue(const flutter::EncodableMap& map,
                                          const char* key) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) {
    return nullptr;
  }
  return std::get_if<std::vector<uint8_t>>(value);
}

void HandleWrapRuntimeDek(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* dek = ByteListValue(arguments, "dek");
  const auto* aad = StringValue(arguments, "aad");
  if (dek == nullptr || aad == nullptr || dek->size() != kRuntimeDekLength ||
      aad->empty()) {
    result->Error("runtime_dek_wrap_failed",
                  "wrapRuntimeDek requires a 32-byte dek and non-empty aad");
    return;
  }

  auto envelope = BuildRuntimeDekEnvelope(*dek, *aad);
  if (!envelope.has_value()) {
    result->Error("runtime_dek_wrap_failed",
                  "Failed to build runtime DEK envelope");
    return;
  }

  const CryptoResult protected_dek = ProtectRuntimeDek(envelope.value(), *aad);
  if (!protected_dek.ok) {
    result->Error("runtime_dek_wrap_failed",
                  "CryptProtectData failed: " +
                      FormatWin32Error(protected_dek.error));
    return;
  }

  const auto encoded = Base64Encode(protected_dek.data);
  if (!encoded.has_value()) {
    result->Error("runtime_dek_wrap_failed",
                  "Failed to base64-encode protected runtime DEK");
    return;
  }

  flutter::EncodableMap response;
  response[flutter::EncodableValue("version")] =
      flutter::EncodableValue(kBlobVersion);
  response[flutter::EncodableValue("platform")] =
      flutter::EncodableValue("windows");
  response[flutter::EncodableValue("protection")] =
      flutter::EncodableValue("dpapi_current_user");
  response[flutter::EncodableValue("ciphertext")] =
      flutter::EncodableValue(encoded.value());
  result->Success(flutter::EncodableValue(std::move(response)));
}

void HandleUnwrapRuntimeDek(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto version = IntValue(arguments, "version");
  const auto* platform = StringValue(arguments, "platform");
  const auto* protection = StringValue(arguments, "protection");
  const auto* aad = StringValue(arguments, "aad");
  const auto* ciphertext = StringValue(arguments, "ciphertext");
  if (!version.has_value() || version.value() != kBlobVersion ||
      platform == nullptr || *platform != "windows" ||
      protection == nullptr || *protection != "dpapi_current_user") {
    result->Error("runtime_dek_wrap_terminal",
                  "Unsupported Windows runtime DEK wrapper blob");
    return;
  }
  if (aad == nullptr || ciphertext == nullptr || aad->empty() ||
      ciphertext->empty()) {
    result->Error("runtime_dek_wrap_terminal",
                  "unwrapRuntimeDek requires non-empty ciphertext and aad");
    return;
  }

  const auto encrypted = Base64Decode(*ciphertext);
  if (!encrypted.has_value()) {
    result->Error("runtime_dek_wrap_terminal",
                  "Runtime DEK ciphertext is not valid base64");
    return;
  }

  CryptoResult envelope = UnprotectRuntimeDek(encrypted.value(), *aad);
  if (!envelope.ok) {
    result->Error(UnprotectErrorCode(envelope.error),
                  "CryptUnprotectData failed: " +
                      FormatWin32Error(envelope.error));
    return;
  }

  auto dek = ExtractRuntimeDekFromEnvelope(envelope.data, *aad);
  SecureZeroVector(envelope.data);
  if (!dek.has_value()) {
    result->Error("runtime_dek_wrap_terminal",
                  "Runtime DEK envelope validation failed");
    return;
  }

  result->Success(flutter::EncodableValue(std::move(dek.value())));
}

flutter::EncodableMap RuntimeDekDiagnostics() {
  flutter::EncodableMap key_security;
  key_security[flutter::EncodableValue("provider")] =
      flutter::EncodableValue("DPAPI");
  key_security[flutter::EncodableValue("scope")] =
      flutter::EncodableValue("CurrentUser");
  key_security[flutter::EncodableValue("user_prompt_required")] =
      flutter::EncodableValue(false);

  flutter::EncodableMap device_state;
  device_state[flutter::EncodableValue("protected_data_available")] =
      flutter::EncodableValue(true);

  flutter::EncodableMap build;
  build[flutter::EncodableValue("platform")] =
      flutter::EncodableValue("windows");

  flutter::EncodableMap diagnostics;
  diagnostics[flutter::EncodableValue("alias_present")] =
      flutter::EncodableValue(true);
  diagnostics[flutter::EncodableValue("key_security")] =
      flutter::EncodableValue(std::move(key_security));
  diagnostics[flutter::EncodableValue("device_state")] =
      flutter::EncodableValue(std::move(device_state));
  diagnostics[flutter::EncodableValue("build")] =
      flutter::EncodableValue(std::move(build));
  return diagnostics;
}

}  // namespace

void RegisterRuntimeDekWrapChannel(flutter::BinaryMessenger* messenger) {
  g_runtime_dek_wrap_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  g_runtime_dek_wrap_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());

        if (call.method_name() == "wrapRuntimeDek") {
          if (arguments == nullptr) {
            result->Error("runtime_dek_wrap_failed",
                          "wrapRuntimeDek requires map arguments");
            return;
          }
          HandleWrapRuntimeDek(*arguments, std::move(result));
          return;
        }

        if (call.method_name() == "unwrapRuntimeDek") {
          if (arguments == nullptr) {
            result->Error("runtime_dek_wrap_terminal",
                          "unwrapRuntimeDek requires map arguments");
            return;
          }
          HandleUnwrapRuntimeDek(*arguments, std::move(result));
          return;
        }

        if (call.method_name() == "deleteRuntimeDekWrappingKey") {
          result->Success();
          return;
        }

        if (call.method_name() == "getRuntimeDekDiagnostics") {
          result->Success(flutter::EncodableValue(RuntimeDekDiagnostics()));
          return;
        }

        result->NotImplemented();
      });
}
