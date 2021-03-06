

There are some basic design choices particular to music-pitch which I would like to retain:

- We allow intervals to be negative. This is necessary for the VectorSpace/AffineSpace instances to behave, and also makes intervals more mathematically tractable. (To make pitches a proper AffineSpace we must be able to pick any frequency as the origin.)

- All "literals", i.e. (c, cs, m3, _M3 etc) should be overloaded using the classes from 'music-pitch-literal'. This is because programs and musical compositions written using the suite should not be forced to use a particular representation. Thanks to the power of type classes in Haskell not only functions but *values* may be overloaded.

- The pitch representation should be as generic as possible, and all constructs specific to Common/Western music theory should clearly be labeled as such. Most operations should be done in terms of standard type classes such as Monoid and VectorSpace/AffineSpace. 

