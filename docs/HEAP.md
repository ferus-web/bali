# Bali's Heap
When you create a `Runtime` object using the `newRuntime()` function, a `HeapManager` is initialized by Bali, and that manager context is set as the default heap manager for the thread the program is currently executing on.

It uses a bump allocator for the first 8 megabytes of allocations on 64-bit platforms and on 32-bit platforms, it uses it for the first 2 megabytes of allocations.
This means that a lot of programs never end up touching the garbage collector, and as a result, become much faster (and make way fewer syscalls!)

# Table of Contents
* [Allocating Memory](#allocation-memory)
  - [Behind the Scenes](#behind-the-scenes)

# Allocating Memory
If you wish to allocate memory with Bali, you need to have a handle to a valid `HeapManager` instance.
If you have a `Runtime` object with you, you can simply use the `heapManager` field.

```nim
import pkg/bali/runtime/vm/heap/manager

let v = runtime.heapManager.allocate("hello world!".len.uint())
```

## Behind the Scenes
When you call `allocate()`, the following logic is triggered:

1. Firstly, the `HeapManager` checks if there is enough memory in the bump allocator or not.
2. If there is, then allocate memory using that.
3. Otherwise, ask the GC to allocate the memory.
