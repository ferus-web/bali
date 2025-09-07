import std/[unittest, atomics]
import pkg/bali/easy

test "running bali on another thread":
  var success: Atomic[bool]

  proc runThr(runtime: Runtime) {.thread.} =
    runtime.run()
    success.store(true)

  let runtime = createRuntimeForSource(
    """
  console.log("Hello from another thread, Bali!"); 
      """
  )
  var thr: Thread[Runtime]
  createThread(thr, runThr, runtime)
  joinThread(thr)

  check(success.load)
