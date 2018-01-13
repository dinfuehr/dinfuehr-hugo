+++
title = "Non-Strong references in the JVM"
date = "2018-01-07T13:16:51+01:00"
draft = true

+++

The JVM supports a number of non-strong references: [SoftReference](https://docs.oracle.com/javase/9/docs/api/java/lang/ref/SoftReference.html), [WeakReference](https://docs.oracle.com/javase/9/docs/api/java/lang/ref/WeakReference.html), [PhantomReference](https://docs.oracle.com/javase/9/docs/api/java/lang/ref/PhantomReference.html) and [FinalReference](http://hg.openjdk.java.net/jdk10/jdk10/jdk/file/777356696811/src/java.base/share/classes/java/lang/ref/FinalReference.java) (which is internal to the JVM).
The GC never frees objects that are strongly (or *normal*) reachable.
If an object is only reachable through a non-strong reference then special rules apply.

The easiest to explain is `WeakReference`: an object that is only reachable through a `WeakReference` is always considered garbage. `SoftReference` is


The GC *knows* these classes and 