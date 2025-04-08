== Status

这部分涉及的代码为：
- `util/status.cc`

在LevelDB中，许多操作都需要通过返回码来表示操作的结果，并且通过返回码来决定下一步的工作。

LevelDB中通过`Status`来表示操作的结果，`Status`是一个类，它包含了一个状态码和一个消息。状态码是一个枚举类型，它表示了操作的结果，消息是一个字符串，它描述了操作的结果。

另外需要说明一下，在LevelDB中，`Code`是不支持拓展的。

`Status`中最主要的一个成员是`state_`，它是一个指向状态码和消息的指针。`state_`的结构如下：
#block(breakable: false, width: 100%)[
  #align(center)[
    ```cpp
    enum Code {
      kOk = 0,
      kNotFound = 1,
      kCorruption = 2,
      kNotSupported = 3,
      kInvalidArgument = 4,
      kIOError = 5
    };
    ```
    ```bash
              0                 4      5         ∞
              ┌─────────────────┬──────┬─────────┐
    state_ -> │ Length(message) │ Code │ Message │
              └─────────────────┴──────┴─────────┘
    ```

  ]
]

在看了`Status`的结构以后，我们可以看一下`Status`的几个函数的实现。

// #code("utils/status.cc", "Status的实现（部分）")[
//   ```cpp
//   // 这段代码相当于复制构造函数
//   const char* Status::CopyState(const char* state) {
//     uint32_t size;
//     // 将state的sizeof(size), 也就是前32位，拷贝到size中
//     // 类似 size = length(state.message)
//     std::memcpy(&size, state, sizeof(size));
//     char* result = new char[size + 5];
//     std::memcpy(result, state, size + 5);
//     return result;
//   }

//   Status::Status(Code code, const Slice& msg, const Slice& msg2) {
//     assert(code != kOk);
//     const uint32_t len1 = static_cast<uint32_t>(msg.size());
//     const uint32_t len2 = static_cast<uint32_t>(msg2.size());
//     // 计算总size, 如果第二个msg存在, 那么还需要加上另外的 ": " 两个字符
//     const uint32_t size = len1 + (len2 ? (2 + len2) : 0);
//     char* result = new char[size + 5];
//     // 填充[0, 4)的位置
//     std::memcpy(result, &size, sizeof(size));
//     // 填充[4, 5)的位置
//     result[4] = static_cast<char>(code);
//     // 填充[5, 5 + len1)的位置
//     std::memcpy(result + 5, msg.data(), len1);
//     // 如果msg2存在, 那么填充[5 + len1, 5 + len1 + 2)的位置
//     if (len2) {
//       result[5 + len1] = ':';
//       result[6 + len1] = ' ';
//       std::memcpy(result + 7 + len1, msg2.data(), len2);
//     }
//     state_ = result;
//   }

//   std::string Status::ToString() const {
//     if (state_ == nullptr) {
//       return "OK";
//     } else {
//       char tmp[30];
//       const char* type;
//       switch (code()) {
//         case kOk:
//           type = "OK";
//           break;
//         case kNotFound:
//           type = "NotFound: ";
//           break;
//         case kCorruption:
//           type = "Corruption: ";
//           break;
//         case kNotSupported:
//           type = "Not implemented: ";
//           break;
//         case kInvalidArgument:
//           type = "Invalid argument: ";
//           break;
//         case kIOError:
//           type = "IO error: ";
//           break;
//         default:
//           std::snprintf(tmp, sizeof(tmp),
//                         "Unknown code(%d): ", static_cast<int>(code()));
//           type = tmp;
//           break;
//       }
//       std::string result(type);

//       // 获取message的长度
//       uint32_t length;
//       std::memcpy(&length, state_, sizeof(length));

//       // 将state_的[5, length)拷贝到result中
//       result.append(state_ + 5, length);
//       return result;
//     }
//   }
//   ```
// ]

如果看懂了上面的这三个函数，那么关于`Status`的其他代码就不难理解了，这里就不多赘述了。