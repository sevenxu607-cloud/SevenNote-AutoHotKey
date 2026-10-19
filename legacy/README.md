# legacy · 拆分前源码快照

`SevenNote.v2.4.3.ahk` 是工作台化改造 Phase 2 之前的完整单文件源码。

- **只作对照与回退参考，不参与构建或运行。**
- 当前入口是根目录的 `SevenNote.ahk` 启动器，它把入口转给 `src/SevenNote.ahk`，再由后者装配 `src/WorkBench/` 与 `src/modules/`。
- 本目录不参与 `#Include`，也不要在它上面继续开发。
