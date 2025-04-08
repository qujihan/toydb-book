== 跨平台以及可移植性 <env>

=== 关于符号导出

在这个commit中#footnote(link("https://github.com/google/leveldb/commit/4a7e7f50dcf661cfffe71737650b0fb18e195d18"))，定义了一个`LEVELDB_EXPORT`宏。并且在许多地方使用。

还有这个commit#footnote(link("https://github.com/google/leveldb/commit/aece2068d7375f987685b8b145288c5557f9ce50"))

在 Windows 平台上，我们需要在动态链接库中导出符号，以便于其他程序可以调用这些函数。在 Windows 平台上，我们需要使用 `__declspec(dllexport)` 来导出符号。在 Linux 平台上，我们需要使用 `__attribute__((visibility("default")))` 来导出符号。为了解决这个问题，我们可以使用 `#if` 来判断当前的编译环境，然后使用不同的宏来导出符号。