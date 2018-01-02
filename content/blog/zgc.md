+++
date = "2017-04-20T20:33:37+02:00"
title = "A first look into ZGC"
draft = true

+++

[ZGC](http://cr.openjdk.java.net/~pliden/zgc/) is a new garbage collector recently open-sourced by Oracle for the OpenJDK.
ZGC is similar to [Shenandoah](https://wiki.openjdk.java.net/display/shenandoah/Main) or Azul's C4 that focuses on reducing pause-times while still [compacting](https://en.wikipedia.org/wiki/Mark-compact_algorithm) the heap.
Although I won't give a full introduction here, "compacting the heap" just means moving the still-alive objects to the start (or some other region) of the heap.
This helps to reduce fragmentation but usually this also means that the whole application (that means all of its threads) needs to be halted while the GC does its magic, this is usually referred to as *stopping the world*.
Only when the GC is finished, the application can be resumed. 
Depending on the size of the heap this pause could take several seconds, which could be quite problematic for interactive applications.

There are several ways to reduce pause times:

* The GC can employ multiple threads while compacting (*parallel* compaction).
* Compaction work can also be split across multiple pauses (*incremental* compaction).
* Compact the heap concurrently to the running application without stopping it (or just for a short time) (*concurrent* compaction).
* Go's GC simply deals with it by not compacting the heap at all.

As already mentioned ZGC does concurrent compaction, this is certainly not a simple feature to implement so I want to describe how this works.
I should also mention that although concurrent compaction seems to be the best solution of the alternatives given above, there are definitely some tradeoffs involved.
So if you don't care about pause times, you might be better off using a GC that focuses on throughput instead.

### Pointer tagging

### GC cycle
A GC cycle consists of multiple phases:

* Start marking the root set (all objects referenced from the application thread stacks). This action is executed in a Safepoint, that means there is a pause, but we don't need to mark the whole heap - only the thread stacks. Therefore increasing the heap size doesn't increase pause times.
* Concurrently mark all reachable objects starting from the root set. There is no pause needed here.
* After marking stacks are emptied, the world is stopped again. Application threads could still have thread-local marking stacks, which still need to be traced. Since this could uncover a large untraced sub graph, this phase could take way longer than the start marking phase. ZGC tries to avoid this by cancelling this phase after 1 milliseconds. If this phase doesn't finish within this timeframe, ZGC gets back into the concurrent marking phase.
* Process and enqueue non-strong references.
* Reset relocation set from previous GC cycle. That means clearing the forwarding table.
* Free the memory from empty pages.
* Select the new relocation set: Prefer pages with the least amount of live objects, since the less live objects a page has, the less data need to be relocated (and copied). Pages without any live objects can be reclaimed immediately.
* Prepare the relocation set: Allocate the forwarding table for the pages in the relocation set.
* Start relocation by relocating all objects referenced by the root set. This phase again needs to stop the world.
* Concurrent relocation of all live objects in the relocation set. Although all live objects have been relocated after this phase, there might still be references into the relocation set after this phase finished. ZGC's load barrier or the next marking cycle will take care of those references.

### Load-Barrier
Test.