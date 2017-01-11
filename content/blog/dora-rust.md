+++
date = "2017-01-04T08:34:34+01:00"
title = "Dora: Implementing a JIT-compiler with Rust"
draft = false

+++

I am writing [Dora](https://github.com/dinfuehr/dora), a simple [JIT-compiler](https://en.wikipedia.org/wiki/Just-in-time_compilation) with Rust.
Dora is both the name of the custom programming language and of the JIT-compiler.
After some time working on it, I want to write about the experiences I made.

### Architecture
The architecture is pretty simple: `dora hello.dora` parses the given input file into an [Abstract Syntax Tree (AST)](https://en.wikipedia.org/wiki/Abstract_syntax_tree). After parsing the whole AST is semantically checked, if this succeeds execution starts with the `main` function.

To execute `main`, machine-code is generated for that function by the baseline compiler by [traversing](https://github.com/dinfuehr/dora/blob/master/src/baseline/codegen.rs) the AST nodes of the function.
The function is traversed twice, first to generate information (mostly about the stack frame), the second traversal then generates the machine code.

The baseline compiler is a method-based compiler and not a [tracing JIT](https://en.wikipedia.org/wiki/Tracing_just-in-time_compilation) like for example [LuaJIT](http://luajit.org/).
The purpose of the baseline compiler in Dora is to generate code as fast as possible, not to generate the most efficient code.
The sooner it finishes code generation, the sooner execution can start.

Many VMs like the JVM pair the baseline compiler with one or more optimizing compilers that compile functions to more efficient machine-code if it detects a function to be hot.
The optimizing compiler needs longer to compile a given function, but generates more optimized machine-code.
This is acceptable since not all code gets compiled by the optimizing compiler but only hot code/functions.
Dora doesn't have an optimizing compiler at the moment.

### Compilation
The baseline compiler uses the [MacroAssembler](https://github.com/dinfuehr/dora/blob/master/src/masm/mod.rs#L28) to generate machine code.
All differences between different Instruction Set Architectures (ISAs) are handled by the MacroAssembler.
Dora can generate machine-code for x86_64 and since about two weeks also for AArch64.
Adding other platforms should be possible without touching the baseline compiler.

Implementing the second ISA certainly helped making the architecture cleaner and unveiled two bugs I didn't notice on x86_64.
It was also pretty interesting to implement instruction encoding, both for [x86_64](https://github.com/dinfuehr/dora/blob/master/src/cpu/x64/asm.rs) and [AArch64](https://github.com/dinfuehr/dora/blob/master/src/cpu/arm64/asm.rs).
I didn't implement instruction decoding myself, for this purpose I used the [capstone](http://www.capstone-engine.org/) library.
The generated machine-code can be emitted with `dora --emit-asm=all hello-world.dora`.
A nice feature of the MacroAssembler is that comments can be added to the generated instructions.
When disassembling the comments are printed along the disassembled machine instructions:

```
fn main() 0x7f33bab6d010
  0x7f33bab6d010: pushq		%rbp
  0x7f33bab6d011: movq		%rsp, %rbp
  0x7f33bab6d014: subq		$0x10, %rsp
		  ; prolog end


		  ; load string
  0x7f33bab6d018: movq		-0x17(%rip), %rax
  0x7f33bab6d01f: movq		%rax, -8(%rbp)
  0x7f33bab6d023: movq		-8(%rbp), %rdi
		  ; call direct println(Str)
  0x7f33bab6d027: movq		-0x2e(%rip), %rax
  0x7f33bab6d02e: callq		*%rax

		  ; epilog
  0x7f33bab6d030: addq		$0x10, %rsp
  0x7f33bab6d034: popq		%rbp
  0x7f33bab6d035: retq
```

There already exists a [Rust wrapper](https://github.com/ebfe/rust-capstone) for the capstone libary.
Although the README states that the bindings are incomplete, the wrapper supported all the features I need.

### The Dora programming language
Here is a simple Hello world program:

```
fun main() {
    println("Hello World");
}
```

Dora is a custom-language with similarities to languages like Java, Kotlin and Rust (only syntactical).
Most important: Dora is statically-typed and garbage collected.
Dora is missing a lot of features, I planned to add more but writing a JIT is more than enough work.
Instead of adding more syntactic sugar, I preferred to implement features that are more interesting to implement in the JIT.

So Dora has no floating point numbers, the only array it knows is `IntArray`.
A class with the name `IntArray` almost reveals that there no generics, interfaces or traits yet.
The only primitive datatypes Dora supports right now are `bool`, `int` and pointer-sized class references.

Why didn't I use an already existing language? I originally planned designing my own language.
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

Functions that can throw need to be invoked like `try foo()` or `try obj.bar()`, where `try` is just syntactic sugar that signals a potentially throwing invocation.
I like this syntax because it makes it obvious in the caller that an exception could occur.

For runtime errors like failed assertions, the program is halted and the current stack trace is printed.
Although exceptions and stack traces sound quite unspectacular, I was quite happy when this worked for the first time.

Dora even supports classes and inheritance.
It has [primary](https://github.com/dinfuehr/dora/blob/master/tests/pctor1.dora) and [secondary](https://github.com/dinfuehr/dora/blob/master/tests/ctor3.dora) constructors like [Kotlin](https://kotlinlang.org/docs/reference/classes.html).
The keyword [`is`](https://github.com/dinfuehr/dora/blob/master/tests/is1.dora) is similar to Javas `instanceof`, while [`as`](https://github.com/dinfuehr/dora/blob/master/tests/as1.dora) is used for the checked cast (in Java you would write `(SomeClass) obj` for that).
I implemented this check as described in this great [paper](https://www.researchgate.net/publication/221552851_Fast_subtype_checking_in_the_HotSpot_JVM) from Cliff Click and John Rose.
Unfortunately I haven't benchmarked my implementation of the *fast subtype check* yet.
My implementation is a bit easier since Dora doesn't have interfaces or dynamically loaded classes.

### Garbage Collection

Dora has an exact, tracing [Garbage Collector](https://en.wikipedia.org/wiki/Tracing_garbage_collection).
The GC's implementation is pretty simple: it uses a mark & sweep algorithm.
Each object stores a flag that the GC needs for bookkeeping.
The flag determines if the object is marked or unmarked respectively reachable or unreachable.
We only need this flag while collecting garbage.

Mark & sweep is separated into two phases:
*Marking* is the first phase that recursively marks all reachable objects, while *Sweeping* `free`s all unmarked (=unreachable) objects in the second phase.
If you don't know how Mark & Sweep works, there is a nice GIF on [Wikipedia](https://en.wikipedia.org/wiki/Tracing_garbage_collection#Na.C3.AFve_mark-and-sweep) that shows how it works.
Marking one object means setting the mark-flag and recursively traversing through all subobjects and marking them too.
A nice property of the marking phase is that cycles in the object graph are no problem.
On the other hand you need to be careful to avoid stack overflows when you have deeply nested object graphs, so you probably shouldn't implement marking through an recursive function call.
That's the reason I just add the objects into a [Vec](https://doc.rust-lang.org/std/vec/struct.Vec.html) instead of using the stack.
When sweeping, the garbage collector simply runs through all allocated objects and frees unmarked objects.

The GC really just uses libc's `malloc` for allocating objects and `free` while *Sweeping*.
All allocated objects are connected in a single linked list.
For this to work, each object has an additional storage for the pointer to the next allocated object in the object header.
While this increases the size of every object, we don't need to keep track of all objects in some external data structure.
Since all collected objects are part of this linked list, the *Sweeping* phase can run through all objects and free those that are not marked.
When the collector frees a object, it also gets removed from the linked list.

For exact GC to work, it is also essential to determine the root set.
The root set is the initial set of objects that gets marked in the marking phase.

```rust
fn collect_garbage() {
    for root in root_set {
        mark(root);
    }

    sweep();
}
```

The set usually consists of global variables, static fields and/or local variables
(but keep in mind that Dora doesn't have global variables or static fields right now).
Within Dora string literals are also part of the root set, otherwise the GC would just free a String object that is still referenced in a compiled function.

The toughest part while gathering the root set is retrieving local variables.
For this we need working stack unwinding, Dora needs to examine the active functions on the stack.
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

For determining local variables we also need to know where in a function we currently are.
The Dora function `foo` has two local variables, but when invoking `bar1` only `x` is initialized.
At this point there is already space reservered for `y` but the memory is still uninitialized and contains some random value.
`y` shouldn't be part of the root set at that point.
When invoking `bar2` both `x` and `y` are initialized and therefore belong to the root set.

The baseline compiler keeps track of initialized local variables and emits so called GC points for each function invocation.
The GC point stores which local variables are initialized.
Now there is enough information to collect all local variables from the stack.
To be more precise Dora not only keeps track of local variables but also of temporary values, fortunately temporary values can just be treated like local variables.

To test garbage collection, I added a command line flag `--gc-stress` that forces garbage collection at every allocation.
There is also a function `forceCollect` that immediately forces garbage collection, that can be called from Dora code.

### Benchmark
I can't stop without showing some benchmark results.
There are two microbenchmarks Dora could run from the [Language Benchmarks Game](http://benchmarksgame.alioth.debian.org/): [fannkuch-redux](https://github.com/dinfuehr/dora/tree/master/bench/fannkuchredux) and [binarytrees](https://github.com/dinfuehr/dora/tree/master/bench/binarytrees).
I chose the fastest single-threaded Java implementation (dora does not support multi-threading yet) of these benchmarks and translated them to Dora.

![Benchmark results](/images/dora-bench-game.png)

For `fannkuch-redux` Dora is only 3.5 times (40s to 138s) slower than the Java equivalent running on OpenJDK (version 1.8.0_112), the benchmark results for `binarytrees` are worse: Dora is 14x slower (55s instead of 4s).
This is easily explained: `binarytrees` stresses the GC and the current implementation isn't really the most efficient.
We will later look into this benchmark in more detail.

Nevertheless I am satisfied with these numbers.
Neither did I cheat nor am I expecting these numbers to get worse when adding more features.

It should be clear but just to make sure: Please don't draw any conclusions on Rust's performance from these benchmarks.
All time is spent in the generated machine-code, Dora is at fault not Rust.

### binarytrees
We can look deeper into the `binarytrees` benchmark and run the program with [perf](https://perf.wiki.kernel.org/index.php/Main_Page).
perf can record stacktraces using sampling.
Thanks to [Brendan Gregg](http://www.brendangregg.com/) we can create [flame graphs](https://github.com/brendangregg/FlameGraph) as interactive SVGs from the collected stacktraces, which is pretty cool:

<a href="/images/perf-binarytrees.svg"><img src="/images/perf-binarytrees.svg" alt="binarytrees flame graph"></a>

What's also pretty nice is that perf shows both user and kernel stack traces.
We can observe that the memory allocator uses another thread, since there is a pretty wide column next to function `dora::main`, the `main` function in [binarytrees.dora](https://github.com/dinfuehr/dora/tree/master/bench/binarytrees/binarytrees.dora).
`perf` even emits the function names for the jitted functions, which was actually pretty easy to achieve.
All you need to do is to [create](https://github.com/dinfuehr/dora/blob/master/src/os/perf.rs) a file `/tmp/perf-<pid>.map` that consists of lines with this format:

```
<code address start> <length> <function name>
```

Dora just needs to emit such lines for every jitted function.
Dora also supports emitting garbage collection stats with `--gc-stats`:

```
GC stats:
	collect duration: 17715 ms
	607475118 allocations
	75 collections
	29158805890 bytes allocated
```

We see that Dora spends 17 seconds alone for collecting garbage, this benchmarks makes over 600 million allocations to allocate a total of about 27GB memory.
At first I also wanted to benchmark allocation duration but this was way too expensive.
Just by removing those `time::precise_time_ns` invocations reduced run-time from 110s to 55s.

### Using Rust
A few words on using Rust: I started the project to try out Rust on a non-trivial project.
I knew some Rust but hadn't used it on a project before.
Both `cargo` and `rustup` are great tools.
They also work on my Odroid C2 where I implemented AArch64 support.
Cross-compiling became pretty easy, although I just used it for making sure Dora still builds on AArch64
(I never bothered to try to get it to link).
Cross-building is as simple as `cargo build --target=aarch64-unknown-linux-gnu`.

What was especially hard for me to get used to was exclusive mutability, not really borrowing or ownership.
I am perfectly aware that this feature is the reason I don't have to worry about iterator invalidation or data races in safe rust code but still it takes some time getting used to.
The good thing about that though, it forces you to think about organizing your data structures more thoroughly.

### Conclusion
Implementing both a programming language and JIT is a LOT of work.
Nevertheless working on it was both fun and educational and there is still so much stuff that would be cool to implement or to improve.
The source is on [Github](https://github.com/dinfuehr/dora), contributions are welcome.
