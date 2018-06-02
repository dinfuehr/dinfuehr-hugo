+++
title = "Non-Strong references in the JVM"
date = "2018-01-07T13:16:51+01:00"
draft = true

+++

The JVM supports a number of non-strong references: [SoftReference](https://docs.oracle.com/javase/9/docs/api/java/lang/ref/SoftReference.html), [WeakReference](https://docs.oracle.com/javase/9/docs/api/java/lang/ref/WeakReference.html), [PhantomReference](https://docs.oracle.com/javase/9/docs/api/java/lang/ref/PhantomReference.html) and [FinalReference](http://hg.openjdk.java.net/jdk10/jdk10/jdk/file/777356696811/src/java.base/share/classes/java/lang/ref/FinalReference.java) (which is internal to the JVM).
The GC never frees objects that are strongly (or *normal*) reachable.
If an object is only reachable through a non-strong reference then special rules apply.

The easiest to explain is the `WeakReference`: if an object is only reachable through a `WeakReference` it is always considered garbage.
`SoftReference` is quite similar to `WeakReference`: if an object is only reachable via a soft reference and therefore not strongly marked it can be kept alive if the GC decides so, but the GC guarantees to free soft-reachable objects before running out of memory.
A valid implementation could actually treat all soft references the same as weak references.

`PhantomReference` iss

The GC *knows* these classes and 