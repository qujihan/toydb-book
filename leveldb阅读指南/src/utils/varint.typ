
== 变长编码 <varint>

这部分涉及的代码为：
- `util/coding.{h,cc}`

// #reference-block("什么是varint（变长编码）")[
//   Each byte in the varint has a continuation bit that indicates if the byte that follows it is part of the varint. This is the most significant bit (MSB) of the byte (sometimes also called the sign bit). The lower 7 bits are a payload; the resulting integer is built by appending together the 7-bit payloads of its constituent bytes.#footnote(link("https://protobuf.dev/programming-guides/encoding/#varints"))

//   每一个varint中的字节都有一个延续位，用来表示后面的字节是否是varint的一部分。这个位是字节的最高位（MSB），有时也被称为符号位。低7位是有效载荷；最终的整数是通过将其组成字节的7位有效载荷连接在一起构建的。

//   #align(right)[
//     -- Protocol Buffers Documentation
//   ]
// ]


下面使用一个例子来演示varint的编解码过程。

*编码*

下面这个表示将`123456`编码为`11000000 11000100 00000111`。
#align(
  center,
  block(breakable: false)[
    ```bash
    123456 = 1 11100010 01000000   # 十进制变成二进制
             111 1000100 1000000   # 分成7位一组
         1000000 1000100 0000111   # 变成小端编码(little-endian)
      11000000 11000100 00000111   # 添加msb
      ^msb     ^msb     ^msb
    ```
  ],
)

*解码*

下面这个表示的是将`10010110 00000001`解码为`150`。
#align(
  center,
  block(breakable: false)[
    ```bash
         10010110 00000001   # 原始数据
         ^ msb    ^ msb
          0010110  0000001   # 去掉 msb
          0000001  0010110   # 变成大端编码(big-endian)
      00000010010110 = 150   # 拼接且转换为十进制
    ```
  ],
)


在知道了什么是变长编码以后，另一个问题随之而来，那就是为什么使用变长编码？这个问题可以参看在stackoverflow中有一个问题：为什么Varint是一种高效的数据表示方式？#footnote(link("https://stackoverflow.com/questions/24614553/why-is-varint-an-efficient-data-representation"))

参考回答，可以总结出来几点：
- 优点：
  - 在实践中，大多数整数都是小整数，所以使用变长编码可以节省空间。
  - 由于变长编码是变长的，所以可以表示任意大小的整数。
- 缺点：
  - 由于变长编码是变长的，所以在解码的时候需要额外的计算。


下面来看一下LevelDB中是如何编码以及解码的。

// #code("util/coding.cc", "LevelDB的32位以及64位编码")[
//   ```cpp
//   // 这段代码简单粗暴
//   // 对32位uint进行编码
//   char* EncodeVarint32(char* dst, uint32_t v) {
//     // Operate on characters as unsigneds
//     uint8_t* ptr = reinterpret_cast<uint8_t*>(dst);
//     // 用于设置最高位
//     static const int B = 128;
//     // 根据v的大小来选择编码方式
//     if (v < (1 << 7)) {
//       // 如果v小于2^7，那么直接存储
//       *(ptr++) = v; // 存储低7位
//     } else if (v < (1 << 14)) {
//       // 如果v小于2^14，那么存储两个字节
//       *(ptr++) = v | B; // 存储低7位
//       *(ptr++) = v >> 7; // 存储高7位
//     } else if (v < (1 << 21)) {
//       // 如果v小于2^21，那么存储三个字节
//       *(ptr++) = v | B; // 存储低7位
//       *(ptr++) = (v >> 7) | B;
//       *(ptr++) = v >> 14; // 存储高7位
//     } else if (v < (1 << 28)) {
//       // 如果v小于2^28，那么存储四个字节
//       *(ptr++) = v | B; // 存储低7位
//       *(ptr++) = (v >> 7) | B;
//       *(ptr++) = (v >> 14) | B;
//       *(ptr++) = v >> 21; // 存储高7位
//     } else {
//       // 如果v大于等于2^28，那么存储五个字节
//       *(ptr++) = v | B; // 存储低7位
//       *(ptr++) = (v >> 7) | B;
//       *(ptr++) = (v >> 14) | B;
//       *(ptr++) = (v >> 21) | B;
//       *(ptr++) = v >> 28; // 存储高4位
//     }
//     return reinterpret_cast<char*>(ptr);
//   }

//   // 这段代码对64位uint进行编码
//   // 这段就优雅了许多
//   char* EncodeVarint64(char* dst, uint64_t v) {
//     // 用于设置最高位
//     static const int B = 128;
//     // 将目标缓冲区的指针转换成 uint8_t* 类型, 以便按照字节操作
//     uint8_t* ptr = reinterpret_cast<uint8_t*>(dst);
//     while (v >= B) {
//       *(ptr++) = v | B;
//       v >>= 7;
//     }
//     *(ptr++) = static_cast<uint8_t>(v);
//     return reinterpret_cast<char*>(ptr);
//   }
//   ```
// ]

上面两端代码其实完成了同一个功能，这两段代码的逻辑是一样的，但是64位整数的编码感觉更加优雅一些。

下面来看看解码过程。

// #code("util/coding.cc", "LevelDB的32位以及64位解码")[
//   ```cpp
//   // 从指针p开始解析一个varint32，并将解析结果存储在value中
//   // 这些函数只会查看[p..limit-1]范围内的字节
//   //
//   // 如果解析成功, 返回下一个字节的指针, 结果放在value中
//   // 如果解析失败, 返回nullptr
//   const char* GetVarint32PtrFallback(const char* p, const char* limit,
//                                      uint32_t* value) {
//     uint32_t result = 0;
//     for (uint32_t shift = 0; shift <= 28 && p < limit; shift += 7) {
//       // 从p中读取一个字节, 并且p指向下一个字节
//       uint32_t byte = *(reinterpret_cast<const uint8_t*>(p));
//       p++;

//       if (byte & 128) {
//         // More bytes are present
//         // msb为1，表示后面还有字节
//         result |= ((byte & 127) << shift);
//       } else {
//         // msb为0，表示这是最后一个字节
//         result |= (byte << shift);
//         *value = result;
//         return reinterpret_cast<const char*>(p);
//       }
//     }
//     return nullptr;
//   }

//   inline const char* GetVarint32Ptr(const char* p, const char* limit,
//                                     uint32_t* value) {
//     if (p < limit) {
//       uint32_t result = *(reinterpret_cast<const uint8_t*>(p));
//       // 这里只处理了一个字节的情况
//       // 当msb为0时，表示这是最后一个字节
//       // 直接返回result就可以了
//       if ((result & 128) == 0) {
//         *value = result;
//         return p + 1;
//       }
//     }
//     return GetVarint32PtrFallback(p, limit, value);
//   }

//   // 与上面的GetVarint32Ptr类似
//   const char* GetVarint64Ptr(const char* p, const char* limit, uint64_t* value) {
//     uint64_t result = 0;
//     for (uint32_t shift = 0; shift <= 63 && p < limit; shift += 7) {
//       uint64_t byte = *(reinterpret_cast<const uint8_t*>(p));
//       p++;
//       if (byte & 128) {
//         // More bytes are present
//         result |= ((byte & 127) << shift);
//       } else {
//         result |= (byte << shift);
//         *value = result;
//         return reinterpret_cast<const char*>(p);
//       }
//     }
//     return nullptr;
//   }
//   ```
// ]

在这里可以看到LevelDB的作者的巧思，`GetVarint32Ptr`与`GetVarint64Ptr`两个函数并没有写的相同，而是假设了大多数情况下处理的都是比较小的数字，在`GetVarint32Ptr`中直接处理了一个字节的情况。只有当处理不了的时候（也就是Varint大于1个字节的时候），才会调用与`GetVarint64Ptr`类似的`GetVarint32PtrFallback`函数。

关于编码的其他的部分都比较简单，就不再说明了。