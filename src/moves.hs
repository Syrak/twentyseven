module Moves
  where

import Misc
import Cubie

-- Elementary moves

u' =
  mkCube ([1, 2, 3, 0] ++ [4..7])
         (replicate 8 0)
         ([1, 2, 3, 0] ++ [4..11])
         (replicate 12 0)

u  = u'
u2 = u ? u
u3 = u ? u2

r  = surf3 ?? u
r2 = r ? r
r3 = r ? r2

f  = surf3 ?? r
f2 = f ? f
f3 = f ? f2

-- Symmetries

surf3 =
  mkCube [4, 5, 2, 1, 6, 3, 0, 7]
         [2, 1, 2, 1, 2, 1, 2, 1]
         [5, 9, 1, 8, 7, 11, 3, 10, 6, 2, 4, 0]
         [1, 0, 1, 0, 1,  0, 1,  0, 1, 1, 1, 1]

sf2 =
  mkCube [6, 5, 4, 7, 2, 1, 0, 3]
         (replicate 8 0)
         [6, 5, 4, 7, 2, 1, 0, 3, 9, 8, 11, 10]
         (replicate 12 0)

su4 =
  mkCube [1, 2, 3, 0, 5, 6, 7, 4]
         (replicate 8 0)
         [1, 2, 3, 0, 5, 6, 7, 4, 9, 11, 8, 10]
         (replicate 8 0 ++ [1, 1, 1, 1])

slr2 =
  mkCube [3, 2, 1, 0, 5, 4, 7, 6]
         (replicate 8 3)
         [2, 1, 0, 3, 6, 5, 4, 7, 9, 8, 11, 10]
         (replicate 12 0)

