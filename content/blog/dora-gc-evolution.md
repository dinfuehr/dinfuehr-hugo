+++
date = "2019-08-10T08:34:34+01:00"
title = "Dora's GC Evolution"
draft = true

+++

[Dora](https://github.com/dinfuehr/dora) is a runtime for a statically typed programming language that uses [tracing garbage collection](https://en.wikipedia.org/wiki/Tracing_garbage_collection) for memory management.
This post describes the low-level details of Dora's current garbage collection (GC) implementation.
We will also take a look at the intermediate solutions used before arriving at the current approach.

### malloc & free
In its early incarnation Dora used `malloc` and `free` behind the scenes of its GC (although initially `free` wasn't even used at all).
Each time a new object was allocated, the runtime issued a call to `malloc` to reserve memory for the object.
This is certainly quite expensive but back then that was certainly an acceptable solution since it was so easy to implement.
More of a problem was how to keep track of all objects in the runtime:
Dora had to keep track of all allocations in a (potentially) huge linked list.

TODO: Insert image

The runtime issued a collection after a certain threshold of allocated bytes was reached.
A garbage collection was composed of two phases:
First mark all reachable objects starting from the root set (that is local and global variables).
Immediately after this, Dora traversed the linked list and removed unmarked objects from it.
While removing entries, memory was returned to the system by invoking `free` on each dead object.

Even though the solution was quite primitive, the compiler already needed to emit correct GC points.
GC points allow the runtime to find all active local variables with pointers into the heap and hence compute the root set.
Dora's GC was always [precise](https://en.wikipedia.org/wiki/Tracing_garbage_collection#Precise_vs._conservative_and_internal_pointers), that means it always knew what values on the stack where pointers into the heap as opposed to integer or double values.

Nevertheless it was always clear that this wasn't a viable long-term solution and Dora needed something better.
Interestingly my main beef with this approach was that it made testing a bit more difficult.
There was no cheap way of verifying whether an object was a valid pointer into the heap - this required a traversal of the linked list of objects.

### Copy Collection
Dora's first "real" GC was a simple [copy collector](https://en.wikipedia.org/wiki/Tracing_garbage_collection#Copying_vs._mark-and-sweep_vs._mark-and-don.27t-sweep) using the [Cheney algorithm](https://en.wikipedia.org/wiki/Cheney%27s_algorithm).
A copy or semi-space collector divides its heap into two equally-sized spaces: *from* and *to* space.
The application allocates objects right after each other in the *to* space.
When there is no more free memory in the *to* space left, garbage collection has to be performed.

At the beginning of a GC, *from* and *to* spaces switch roles (no memory is copied in this step).
This means that the *from* space is now full, while the *to* space is completely empty.
During the collection, Dora copies all surviving (this means reachable) objects from *from* into the *to* space.
After all live objects were copied, memory in the *from* space is not needed anymore and can be considered garbage.
The application resumes and can again allocate objects in the *to* space.

The implementation might even be simpler than the previous `malloc/free` solution.
The full [file](https://github.com/dinfuehr/dora/blob/master/src/gc/copy.rs) is about 240 LOC in total, the core algorithm does not even have [40](https://github.com/dinfuehr/dora/blob/master/src/gc/copy.rs#L156-L176) [LOC](https://github.com/dinfuehr/dora/blob/master/src/gc/copy.rs#L207-L223).
If you haven't seen a GC implementation before, it is definitely worth a quick look.
The copy collector can be enabled in Dora with the `--gc=copy` argument.

Copy collection has this amazing property that it only performs work proportional to the live set size.
This means that if no object in the heap is live, the GC doesn't need to perform any work at all - regardless of the size of the heap.
The way copy collection copies objects might also benefit locality: as was already mentioned the GC marks and copies objects in a single phase.
Therefore related objects in the object graph tend to be close to each other after a collection.
[Aleksey Shipilëv](https://shipilev.net/) has already written a nice blog [post](https://shipilev.net/jvm/anatomy-quarks/11-moving-gc-locality/) on this, so I am not going to cover this again.

### Mark-Compact

### TLAB allocation

### Generational GC

### Parallel Collection

