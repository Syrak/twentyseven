{- |
   Encoding cube projections as @Int@ coordinates.

   Explicit dictionary passing style:
   using a class would require explicit type annotations /anyway/.
-}

{-# LANGUAGE ViewPatterns, GADTs #-}
module Coord (
  -- * Dictionaries
  Coord,
  Coordinate (..),
  range,
  encode,
  decode,

  -- ** Instances
  -- | The number of elements of every set is given.
  coordCornerPermu,
  coordCornerOrien,
  coordEdgePermu,
  coordEdgeOrien,

  coordUDSlice,
  coordUDSlicePermu,
  coordUDEdgePermu,
  coordFlipUDSlice,

  -- ** Other instances
  coordOrien,
  coordCOUDSlice,
  coordEdgePermu2,
  coordCAndUDSPermu,

  -- * Table building
  Endo (..),
  endo,
  endoVector,

  CA (..),
  cubeActionToEndo,

  moveTables,

  -- * Miscellaneous
  checkCoord,

  -- * Helper
  -- | Helper functions to define the dictionaries

  -- ** Fixed base
  encodeBase,
  decodeBase,

  -- ** Factorial radix
  encodeFact,
  decodeFact,

  -- ** Binomial enumeration
  -- $binom
  encodeCV,
  decodeCV,
  ) where

import Cubie
import Misc

import Control.Applicative
import Control.Arrow
import Control.Monad.ST.Safe

import Data.List
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Unboxed.Mutable as MU

-- MaxInt 2^29 = 479001600
-- | Encoding to an efficient datatype
-- for which it is possible to build tables
-- instead of computing functions.
type Coord = Int

-- | Encoding dictionary.
--
-- Synonymous with instances for both
-- @(Enum a, Bounded a)@.
--
-- > inRange (range d) $ encode x
-- > encode . decode == id
-- > decode . encode == id
--
data Coordinate a where
  SingleCoord :: { range1 :: Coord,
              encode1 :: a -> Coord,
              decode1 :: Coord -> a } -> Coordinate a
  PairCoord :: Coordinate a -> Coordinate b -> Coordinate (a, b)

range :: Coordinate a -> Coord
range (SingleCoord { range1 = r }) = r
range (PairCoord a b) = range a * range b

encode :: Coordinate a -> a -> Coord
encode (SingleCoord { encode1 = e }) = e
encode (PairCoord a b) = \(ya, yb) -> encode a ya * range b + encode b yb

decode :: Coordinate a -> Coord -> a
decode (SingleCoord { decode1 = d }) = d
decode (PairCoord a b) = (decode a *** decode b) . (`divMod` range b)

-- Fixed base representation

-- | If
-- @all (0 <=) v && all (< b) v@
-- then @v@ is the base @b@ representation of
-- @encode b v@
-- such that its least significant digit is @head v@.
encodeBase :: Int -> [Int] -> Coord
encodeBase b = foldr1 (\x y -> x + b * y)

encodeBaseV :: Int -> Vector Int -> Coord
encodeBaseV b = U.foldr1' (\x y -> x + b * y)

-- | @len@ is the length of the resulting vector
--
-- > encodeBase b . decodeBase b len == id
-- > decodeBase b len . encodeBase b == id
--
decodeBase :: Int -> Int -> Coord -> [Int]
decodeBase b len = take len . unfoldr (\x -> Just (x `modDiv` b))
  where modDiv = ((.).(.)) (\(x,y) -> (y,x)) divMod

-- Factorial radix representation

-- | Input list must be a permutation of @[0 .. n - 1]@
encodeFact :: Int -> [Int] -> Coord
encodeFact n = encode' n . mixedRadix n
  where
    mixedRadix 1 [_] = []
    mixedRadix n l = k : digits
      where
        Just k = elemIndex (n - 1) l
        digits = mixedRadix (n - 1) $ delete (n - 1) l
    encode' _ [] = 0
    encode' n (h : t) = h + n * encode' (n - 1) t

-- |
--
-- > encodeFact n . decodeFact n == id
-- > decodeFact n . encodeFact n == id
--
decodeFact :: Int -> Coord -> [Int]
decodeFact 0 _ = []
decodeFact 1 _ = [0]
decodeFact n x = insert' k (n - 1) l
  where (l, k) = decodeFact (n - 1) `first` (x `divMod` n)

-- $binom
-- Bijection between @[0 .. choose n (k - 1)]@
-- and @k@-combinations of @[0 .. n - 1]@.

-- | > cSum k z == sum [y `choose` k | y <- [k .. z-1]]
--
-- requires @k < cSum_mMaz@ and @z < cSum_nMaz@.
cSum :: Int -> Int -> Int
cSum = \k z -> v U.! (k * n + z)
  where
    cSum' k z = sum [y `choose` k | y <- [k .. z-1]]
    v = U.generate (n * m) (uncurry cSum' . (`divMod` n))
    m = cSum_mMax
    n = cSum_nMax

-- | Bound on arguments accepted by @cSum@
cSum_mMax, cSum_nMax :: Int
cSum_mMax = 4
cSum_nMax = 16

-- | > encodeCV <y 0 .. y k> == encodeCV <y 0 .. y (k-1)> + cSum k (y k)
--
-- where @c@ is a @k@-combination,
-- that is a sorted list of @k@ nonnegative elements.
--
-- @encodeCV@ is in fact a bijection between increasing lists and integers.
--
-- Restriction: @k < cSum_mMax@, @y k < cSum_nMax@.
encodeCV :: Vector Int -> Coord
encodeCV = U.sum . U.imap cSum

-- | Inverse of @encodeCV@.
-- The length of the resulting list must be supplied as a hint
-- (although it could technically be guessed).
decodeCV :: Int -> Coord -> Vector Int
decodeCV k x = U.create (do
  v <- MU.new k
  let
    decode' (-1) _ _ = return ()
    decode' k z x
      | s <= x    = MU.write v k z >> decode' (k-1) (z-1) (x-s)
      | otherwise =                   decode'  k    (z-1)  x
      where
        s = cSum k z
  decode' (k-1) (cSum_nMax-1) x
  return v)

--

memoCoord :: MU.Unbox a => Coordinate a -> Coordinate a
memoCoord (SingleCoord r e d) = SingleCoord r e (a U.!)
  where a = U.generate r d

-- | @8! = 40320@
coordCornerPermu :: Coordinate CornerPermu
coordCornerPermu =
  SingleCoord {
    range1 = 40320,
    encode1 = \(fromCornerPermu -> p) -> encodeFact numCorners $ U.toList p,
    decode1 = unsafeCornerPermu . U.fromList . decodeFact numCorners
  }

-- | @12! = 479001600@
--
-- A bit too much to hold in memory.
--
-- Holds just right in a Haskell @Int@ (@maxInt >= 2^29 - 1@).
coordEdgePermu :: Coordinate EdgePermu
coordEdgePermu =
  SingleCoord {
    range1 = 479001600,
    encode1 = \(fromEdgePermu -> p) -> encodeFact numEdges $ U.toList p,
    decode1 = unsafeEdgePermu . U.fromList . decodeFact numEdges
  }

-- | @3^7 = 2187@
coordCornerOrien :: Coordinate CornerOrien
coordCornerOrien =
  SingleCoord {
    range1 = 2187,
    encode1 = \(fromCornerOrien -> o) -> encodeBaseV 3 . U.tail $ o,
    -- The first orientation can be deduced from the others in a solvable cube
    decode1 = decode'
  }
  where
    decode' x = unsafeCornerOrien . U.fromList $ h : t
      where h = (3 - sum t) `mod` 3
            t = decodeBase 3 (numCorners - 1) x

-- | @2^11 = 2048@
coordEdgeOrien :: Coordinate EdgeOrien
coordEdgeOrien =
  SingleCoord {
    range1 = 2048,
    encode1 = \(fromEdgeOrien -> o) -> encodeBaseV 2 . U.tail $ o,
    decode1 = decode'
  }
  where
    decode' x = unsafeEdgeOrien . U.fromList $ h : t
      where h = sum t `mod` 2
            t = decodeBase 2 (numEdges - 1) x

-- | @12C4 = 495@
coordUDSlice :: Coordinate UDSlice
coordUDSlice =
  SingleCoord {
    range1 = 495,
    encode1 = \(fromUDSlice -> s) -> encodeCV s,
    decode1 = unsafeUDSlice . decodeCV numUDSEdges
  }

-- | @4! = 24@
coordUDSlicePermu :: Coordinate UDSlicePermu
coordUDSlicePermu =
  SingleCoord {
    range1 = 24,
    encode1 = \(fromUDSlicePermu -> sp) -> encodeFact numUDSEdges $ U.toList sp,
    decode1 = unsafeUDSlicePermu . U.fromList . decodeFact numUDSEdges
  }

-- | @8! = 40320@
coordUDEdgePermu :: Coordinate UDEdgePermu
coordUDEdgePermu =
  SingleCoord {
    range1 = 40320,
    encode1 = \(fromUDEdgePermu -> e) -> encodeFact numE $ U.toList e,
    decode1 = unsafeUDEdgePermu . U.fromList . decodeFact numE
  }
  where numE = numEdges - numUDSEdges

-- | @495 * 2048 = 1013760@
coordFlipUDSlice :: Coordinate FlipUDSlice
coordFlipUDSlice = PairCoord coordEdgeOrien coordUDSlice

--

-- | @2187 * 2048 = 4478976@
--
-- All cubie orientations.
coordOrien :: Coordinate (CornerOrien, EdgeOrien)
coordOrien = PairCoord coordCornerOrien coordEdgeOrien

-- | @2187 * 495 = 1082565@
coordCOUDSlice :: Coordinate (CornerOrien, UDSlice)
coordCOUDSlice = PairCoord coordCornerOrien coordUDSlice

-- | @24 * 40320 = 967680@
coordEdgePermu2 :: Coordinate (UDEdgePermu, UDSlicePermu)
coordEdgePermu2 = PairCoord coordUDEdgePermu coordUDSlicePermu

-- | @24 * 40320 = 967680@
coordCAndUDSPermu :: Coordinate (CornerPermu, UDSlicePermu)
coordCAndUDSPermu = PairCoord coordCornerPermu coordUDSlicePermu

--

-- | Checks over the range @range@ that:
--
-- > encode . decode == id
--
checkCoord :: Coordinate a -> Bool
checkCoord (PairCoord a b) = checkCoord a && checkCoord b
checkCoord (SingleCoord ran enc dec) = and [k == enc (dec k) | k <- [0 .. ran-1]]

--

-- | Endofunctions, with a constructor for
-- endofunctions on pairs which act on every projection separately.
data Endo a where
  Endo :: (a -> a) -> Endo a
  PairEndo :: Endo a -> Endo b -> Endo (a, b)

endo :: Endo a -> a -> a
endo (Endo f) = f
endo (PairEndo f g) = endo f *** endo g

-- | Lift an endofunction to its coordinate representation,
-- the dictionary provides a @Coord@ encoding.
endoVector :: Coordinate a -> Endo a -> Vector Coord
endoVector c@(PairCoord a b) (PairEndo f g) =
  va `seq` vb `seq`
  U.generate (range c) $ \((`divMod` range b) -> (i, j)) ->
    (va U.! i) * range b + vb U.! j
  where
    va = endoVector a f
    vb = endoVector b g
endoVector c (endo -> f) = U.generate (range c) $ encode c . f . decode c

-- | Reify the CubeAction type class.
data CA a where
  CA1 :: CubeAction a => CA a
  CA2 :: CA a -> CA b -> CA (a,b)

cubeActionToEndo :: CA a -> Cube -> Endo a
cubeActionToEndo CA1 c = Endo (`cubeAction` c)
cubeActionToEndo (CA2 a b) c = PairEndo (cubeActionToEndo a c) (cubeActionToEndo b c)

moveTables :: CA a -> [Cube] -> Coordinate a -> [Vector Coord]
moveTables ca moves coord =
  (endoVector coord . cubeActionToEndo ca) <$> moves

--moveTableSingle :: CubeAction a => Coordinate a -> Cube -> Vector Coord
--moveTableSingle a cube = U.generate (range a) $ encode a . (`cubeAction` cube) . decode a
--
--moveTablePair :: (CubeAction a, CubeAction b) => Coordinate (a,b) -> Cube -> Vector Coord
--moveTablePair c@(PairCoord a b) cube =
--  va `seq` vb `seq` U.generate (range c) $ \((`divMod` range b) -> (i, j)) ->
--    (va U.! i) * range b + vb U.! j
--  where
--    va = moveTableSingle a cube
--    vb = moveTableSingle b cube

