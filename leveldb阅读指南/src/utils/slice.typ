== Slice <slice>

这部分涉及的代码为：
- `include/leveldb/slice.h`

在LevelDB中并没有使用C++自带的`std::string`，而是封装了一个`Slice`类，用于表示字符串片段。

`Slice`包含了一个指向字符串的指针`data_`和字符串的长度`size_`。它不管理内存，只是对现有数据进行轻量级封装。正是因为不管理内存，所以`Slice`对象可以被轻松地拷贝和赋值，不回引入额外的内存开销，这对于高性能的数据库来说是非常重要的。



// #code("include/leveldb/slice.h", "Slice代码")[
//   ```cpp
//   class LEVELDB_EXPORT Slice {
//    public:
//     // Create an empty slice.
//     Slice() : data_(""), size_(0) {}

//     // Create a slice that refers to d[0,n-1].
//     Slice(const char* d, size_t n) : data_(d), size_(n) {}

//     // Create a slice that refers to the contents of "s"
//     Slice(const std::string& s) : data_(s.data()), size_(s.size()) {}

//     // Create a slice that refers to s[0,strlen(s)-1]
//     Slice(const char* s) : data_(s), size_(strlen(s)) {}

//     // Intentionally copyable.
//     Slice(const Slice&) = default;
//     Slice& operator=(const Slice&) = default;

//     // Return a pointer to the beginning of the referenced data
//     const char* data() const { return data_; }

//     // Return the length (in bytes) of the referenced data
//     size_t size() const { return size_; }

//     // Return true iff the length of the referenced data is zero
//     bool empty() const { return size_ == 0; }

//     const char* begin() const { return data(); }
//     const char* end() const { return data() + size(); }

//     // Return the ith byte in the referenced data.
//     // REQUIRES: n < size()
//     char operator[](size_t n) const {
//       assert(n < size());
//       return data_[n];
//     }

//     // Change this slice to refer to an empty array
//     void clear() {
//       data_ = "";
//       size_ = 0;
//     }

//     // Drop the first "n" bytes from this slice.
//     void remove_prefix(size_t n) {
//       assert(n <= size());
//       data_ += n;
//       size_ -= n;
//     }

//     // Return a string that contains the copy of the referenced data.
//     std::string ToString() const { return std::string(data_, size_); }

//     // Three-way comparison.  Returns value:
//     //   <  0 iff "*this" <  "b",
//     //   == 0 iff "*this" == "b",
//     //   >  0 iff "*this" >  "b"
//     int compare(const Slice& b) const;

//     // Return true iff "x" is a prefix of "*this"
//     bool starts_with(const Slice& x) const {
//       return ((size_ >= x.size_) && (memcmp(data_, x.data_, x.size_) == 0));
//     }

//    private:
//     const char* data_;
//     size_t size_;
//   };

//   inline bool operator==(const Slice& x, const Slice& y) {
//     return ((x.size() == y.size()) &&
//             (memcmp(x.data(), y.data(), x.size()) == 0));
//   }

//   inline bool operator!=(const Slice& x, const Slice& y) { return !(x == y); }

//   inline int Slice::compare(const Slice& b) const {
//     const size_t min_len = (size_ < b.size_) ? size_ : b.size_;
//     int r = memcmp(data_, b.data_, min_len);
//     if (r == 0) {
//       if (size_ < b.size_)
//         r = -1;
//       else if (size_ > b.size_)
//         r = +1;
//     }
//     return r;
//   }
//   ```
// ]

整个`Slice`的代码非常简单，主要有两个比较需要注意的函数：
- `remove_prefix`：删除前`n`个字节。
- `start_with`：判断是否以某个字符串开头。