+++
date = "2017-01-04T08:34:34+01:00"
title = "Dora: Implementing a JIT-compiler with Rust"
draft = true

+++

I am writing [Dora](https://github.com/dinfuehr/dora) a simple [JIT-compiler](https://en.wikipedia.org/wiki/Just-in-time_compilation) with Rust.
Dora is both the name of the custom programming language and of the JIT-compiler.
After some time working on it, I want to write about the experiences I made.

### Architecture
The architecture is pretty simple: `dora hello.dora` parses the given input file into an [Abstract Syntax Tree (AST)](https://en.wikipedia.org/wiki/Abstract_syntax_tree). After parsing the whole AST is semantically checked, if this succeeds execution starts with the `main` function.

To execute `main`, machine-code is generated for that function by the baseline compiler by [traversing](https://github.com/dinfuehr/dora/blob/master/src/baseline/codegen.rs) the AST nodes of the function.
The function is traversed twice, first to generate information about the stack frame, the second traversal then generates the machine code.

The baseline compiler is a method-based compiler and not a [tracing JIT](https://en.wikipedia.org/wiki/Tracing_just-in-time_compilation) like for example [LuaJIT](http://luajit.org/).
The purpose of the baseline compiler in Dora is to generate code as fast as possible, not to generate the most efficient code.
Many VMs like the JVM pair the baseline compiler with one or more optimizing compilers that compile functions to more efficient machine-code if it detects a function to be hot.
The optimizing compiler needs longer to compile a given function, but generates more optimized machine-code.
This is acceptable since only hot code gets compiled by the optimizing compiler.
Dora doesn't have an optimizing compiler at the moment.

### Compilation
The baseline compiler uses the [MacroAssembler](https://github.com/dinfuehr/dora/blob/master/src/masm/mod.rs#L28) to generate machine code.
All differences between different Instruction Set Architectures (ISAs) are handled by the MacroAssembler.
Dora can generate machine-code for x86_64 and since about two weeks also for AArch64.
Adding other platforms should be possible without touching the baseline compiler.

Implementing the second ISA certainly helped making the architecture cleaner and unveiled two bugs I didn't notice on x86_64.
It was also pretty interesting to implement instruction encoding, both for [x86_64](https://github.com/dinfuehr/dora/blob/master/src/cpu/x64/asm.rs) and [AArch64](https://github.com/dinfuehr/dora/blob/master/src/cpu/arm64/asm.rs).
I didn't implement instruction decoding myself, for this purpose I used the [capstone](http://www.capstone-engine.org/) library.
The generated machine-code can be emitted with `dora --emit-asm=all hello.dora`.
There was already a [Rust wrapper](https://github.com/ebfe/rust-capstone) for the capstone libary.
Although the README states that the bindings are incomplete, the wrapper supports all the features I need.

### The Dora programming language
Here is a simple Hello world program:

```
fun main() {
    println("Hello World");
}
```

Dora is a custom-language with similarities to languages like Java, Kotlin and Rust (only syntactical).
The most important information is that Dora is statically-typed and garbage collected.
Dora is missing a lot of features, I planned to add more but writing a JIT is more than enough work.
Instead of adding more syntactic sugar, I preferred to implement features that are more interesting to implement in the JIT.

Dora has no floating point numbers, the only array it knows is `IntArray`.
So you see there are also no generics, interfaces or traits yet.
The only primitive datatypes Dora supports right now are `bool`, `int` and pointer-sized class references.

Why didn't I use an already existing language? Like I said, I originally planned designing my own language.
But even if I had used an already existing intermediate representation, bytecode or language, I certainly couldn't have implemented it fully either.

### Supported Features
So what are the features Dora actually supports?

Dora compiles functions on-demand, functions are not compiled if not executed.
I want to describe this mechanism in more detail in a later blog post.

Exceptions can be thrown with `throw`, while `do`, `catch` and `finally` can be used to catch exceptions.
Doras exception handling is similar to [Swift](https://developer.apple.com/library/content/documentation/Swift/Conceptual/Swift_Programming_Language/ErrorHandling.html), all functions that can throw exceptions need to be marked with `throws`:

```
fun foo() throws { /* ... */ }
```

Functions that can throw need to be invoked like `try foo()`, where `try` is just syntactic sugar that signals a potentially throwing invocation.

For runtime errors like failed assertions, the program is halted and the current stacktrace is printed.
Although exceptions and stacktraces sound quite unspectacular, I was quite happy when this first worked.

### Garbage Collection

Dora has an exact, tracing [Garbage Collector](https://en.wikipedia.org/wiki/Tracing_garbage_collection).
The GC's implementation is pretty simple: it uses a mark & sweep algorithm.
Each object stores a flag that the GC needs for bookkeeping.
The flag determines if the object is marked or unmarked respectively reachable or unreachable.
We only need this flag while collecting garbage.

Mark & sweep is separated into two phases:
*Marking* is the first phase that recursively marks all reachable objects, while *Sweeping* `free`s all unmarked (=unreachable) objects in the second phase.

The GC really just uses libc's `malloc` for allocating objects and `free` while *Sweeping*.
Collection of garbage starts when a certain threshold of bytes is allocated.
If after the collection still more than 75% of the threshold are used, the threshold is increased by dividing by 75%.
The threshold therefore grows exponentially when a lot of memory is allocated to avoid permanent collection of memory.
See the pseudo code for increasing the threshold:

```c
fn alloc(int size) -> *Object {
    if allocated + size > threshold {
        collect_garbage();

        if allocated + size > threshold * 0.75 {
            threshold = threshold / 0.75;
        }
    }

    allocated += size;
    return malloc(size);
}
```

All allocated objects are connected in a single linked list.
Each object has an additional storage for the pointer to the next allocated object in the object header.
While this increases the size of every object, we don't need to keep track of all objects in some external data structure.
Since all collected objects are part of this linked list, the *Sweeping* phase can run through all objects and free those that are not marked.
When the collector frees a object, it also gets removed from the linked list.

For exact GC to work, it is also essential to determine the root set.
The root set is the initial set of objects that gets marked in the marking phase.

```c
fn collect_garbage() {
    for root in root_set {
        mark(root);
    }

    sweep();
}
```

It usually consists of global variables, static fields and local variables.
(but keep in mind that Dora doesn't have global variables or static fields right now).
Within Dora string literals are also part of the root set, otherwise the GC would just free a String object that is still referenced in a compiled function.

The toughest part while gathering the root set is retrieving local variables.
For this we need working stack unwinding, Dora needs to examine the active functions from the stack.
Although we then know all local variables in these functions, there is one more complication:

```dora
fun foo() {
    let x = A(); // create object of class A
    bar1(); // GC Point 1

    let y = A(); // create another object of class A
    bar2(); // GC Point 2

    // use x and y
}
```

For determining local variables we also need to know where in a function we are.
The Dora function `foo` has two local variables, but when invoking `bar1` only `x` is initialized.
At this point there is already space reservered for `y` but the memory is still uninitialized and contains some random value.
`y` shouldn't be part of the root set at that point.
When invoking `bar2` both `x` and `y` are initialized and therefore belong to the root set.

The baseline compiler keeps track of initialized local variables and emits so called GC points for each function invocation.
The GC point stores which local variables are initialized.
Now there is enough information to collect all local variables from the stack.
To be more precise Dora not only keeps track of local variables but also of temporary values, but this values can just be treated like local variables.

To test garbage collection, I added a command line flag `--gc-stress` that forces garbage collection at every allocation.
There is also a function `forceCollect` that invokes garbage collection, that can be called from Dora code.

### Benchmark
I can't stop without showing some benchmark results.
There are two microbenchmarks Dora could run from the [Language Benchmarks Game](http://benchmarksgame.alioth.debian.org/): [fannkuch-redux](https://github.com/dinfuehr/dora/tree/master/bench/fannkuchredux) and [binarytrees](https://github.com/dinfuehr/dora/tree/master/bench/binarytrees).
I chose the fastest single-threaded Java implementation (dora does not support multi-threading yet) of these benchmarks and translated them to Dora.

![Benchmark results](/images/dora-bench-game.png)

For `fannkuch-redux` Dora is only 3.6 times slower than the Java equivalent running on OpenJDK (version 1.8.0_112), the benchmark results for `binarytrees` are way worse: Dora is 26x slower.
This is easily explained: `binarytrees` stresses the GC and the current implementation isn't the most efficient.
We will later look into this in more detail.

Nevertheless I am satisfied with these numbers.
Neither did I cheat nor am I expecting these numbers get worse when adding more features.

It should be clear but just to make sure: Please don't draw any conclusions on Rust's performance from these benchmarks.
All time is spent in the generated machine-code, Dora is at fault not Rust.

### binarytrees
We can look deeper into the `binarytrees` benchmark and run the program with [perf](https://perf.wiki.kernel.org/index.php/Main_Page).
perf can record stacktraces using sampling.
Thanks to [Brendan Gregg](http://www.brendangregg.com/) we can create [flame graphs](https://github.com/brendangregg/FlameGraph) as interactive SVGs, which is pretty cool:

<a href="/images/perf-binarytrees.svg"><img src="/images/perf-binarytrees.svg" alt="binarytrees flame graph"></a>

The nice thing is that this both shows user and kernel stack traces.
We also can observe that the memory allocator uses another thread, since there is a pretty wide column next to function `dora::main`, the `main` function in [binarytrees.dora](https://github.com/dinfuehr/dora/tree/master/bench/binarytrees/binarytrees.dora).
`perf` event emits the function names for the jitted functions, which was actually pretty easy to achieve.
All you need to do is to [create](https://github.com/dinfuehr/dora/blob/master/src/os/perf.rs) a file `/tmp/perf-<pid>.map` that consists of lines with this format:

```
<code address start> <length> <function name>
```

Dora just needs to emit such lines for every jitted function.
Dora also supports emitting garbage collection stats with `--gc-stats`:

```
GC stats:
	duration: 65394 ms
	malloc duration: 25462 ms
	collect duration: 17746 ms
		mark duration: 1422 ms
		sweep duration: 16323 ms
	75 collections
	29158805890 bytes allocated
```

We see that Dora spends 65 seconds just for allocating memory and collecting garbage.

### Using Rust
I started the project to try out Rust on a non-trivial project.
I knew some Rust but hadn't used it on a project before.
`cargo` and `rustup` are some great tools.
They also work on my Odroid C2 where I implemented AArch64 support.
Cross-compiling became pretty easy, although I just used it for making sure Dora still builds on AArch64
(I never bothered to try to get it to link).
Cross-building is as simple as `cargo build --target=aarch64-unknown-linux-gnu`.

What was especially hard for me to get used to was exclusive mutability, not really borrowing or ownership.
I am perfectly aware that this feature is the reason I don't have to worry about iterator invalidation or data races.
The good thing about that though, it forces you to think about organizing your data structures more thoroughly.
