+++
date = "2019-08-10T08:34:34+01:00"
title = "Dora's GC Evolution"
draft = true

+++

[Dora](https://github.com/dinfuehr/dora) is a statically typed programming language that uses [tracing garbage collection](https://en.wikipedia.org/wiki/Tracing_garbage_collection) for memory management.
This post describes the low-level details of Dora's current GC implementation.
We will also take a look at the intermediate solutions used before arriving at the current approach.

### malloc & free
