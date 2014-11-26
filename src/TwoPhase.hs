{- | Two phase algorithm to solve a Rubik's cube -}
{-# LANGUAGE GeneralizedNewtypeDeriving, DeriveFoldable, DeriveFunctor #-}
module TwoPhase (
  twoPhase,

  twoPhaseTables,

  -- * Phase 1
  Phase1Coord (..),
  phase1Move18,
  phase1Dist,
  phase1,

  -- * Phase 2
  Phase2Coord (..),
  phase2Move10,
  phase2Dist,
  phase2,

  -- * Strict tuples
  Twice (..),
  Thrice (..),
  )
  where

import Prelude hiding ( maximum )

import Coord
import Cubie
import Distances
import IDA
import Moves
import Misc ( Vector, composeVector, Group (..) )

import Control.Applicative
import Control.DeepSeq
import Control.Monad

import Data.Foldable ( Foldable, maximum )
import Data.List hiding ( maximum )
import qualified Data.Vector.Unboxed as U

-- | Pairs
data Twice a = Pair !a !a
  deriving (Eq, Foldable, Functor, Show)

instance Applicative Twice where
  pure x = Pair x x
  (Pair f f') <*> (Pair x x') = Pair (f x) (f' x')

instance NFData a => NFData (Twice a) where
  rnf (Pair a a') = rnf a `seq` rnf a' `seq` ()

zipWithTwice :: (a -> b -> c) -> Twice a -> Twice b -> Twice c
{-# INLINE zipWithTwice #-}
zipWithTwice f (Pair a a') (Pair b b') = Pair (f a b) (f a' b')

transposeTwice :: Twice [a] -> [Twice a]
{-# INLINE transposeTwice #-}
transposeTwice (Pair as as') = zipWith Pair as as'

-- | Triples
data Thrice a = Triple !a !a !a
  deriving (Eq, Foldable, Functor, Show)

instance Applicative Thrice where
  pure x = Triple x x x
  (Triple f f' f'') <*> (Triple x x' x'') = Triple (f x) (f' x') (f'' x'')

instance NFData a => NFData (Thrice a) where
  rnf (Triple a a' a'') = rnf a `seq` rnf a' `seq` rnf a'' `seq` ()

zipWithThrice :: (a -> b -> c) -> Thrice a -> Thrice b -> Thrice c
{-# INLINE zipWithThrice #-}
zipWithThrice f (Triple a a' a'') (Triple b b' b'') = Triple (f a b) (f a' b') (f a'' b'')

transposeThrice :: Thrice [a] -> [Thrice a]
{-# INLINE transposeThrice #-}
transposeThrice (Triple as as' as'') = zipWith3 Triple as as' as''

-- | Phase 1 coordinate representation, a /pair/ (length-2 list) representing:
-- UD slice edge positions and edge orientations; corner orientations.
newtype Phase1Coord = Phase1Coord { phase1Unwrap :: Twice Int }
  deriving Eq

move18Coord :: CA a -> Coordinate a -> [Vector Coord]
move18Coord ca = moveTables ca move18

-- | Move tables
phase1Move18 :: Twice [Vector Coord]
phase1Move18 = Pair
  (move18Coord (CA2 CA1 CA1) coordFlipUDSlice)
  (move18Coord CA1 coordCornerOrien)

-- | Pruning tables
phase1Dist :: Twice (Vector Int)
phase1Dist = zipWithTwice tableToDistance
  (phase1Unwrap . phase1Encode $ iden)
  phase1Move18

-- | Phase 1 uses @FlipUDSlice@ and @CornerOrien@.
phase1Encode :: Cube -> Phase1Coord
phase1Encode = Phase1Coord . (<*>) (Pair
    (encode coordFlipUDSlice . fromCube) -- Cannot factor @fromCube@:
    (encode coordCornerOrien . fromCube) -- different instances involved
  ) . pure

gsPhase1 :: Cube -> GraphSearch (Int, String) Int Phase1Coord
gsPhase1 c = GS {
  root = phase1Encode c,
  goal = (== phase1Encode iden),
  estm = maximum . zipWithTwice (U.!) phase1Dist . phase1Unwrap,
  succs = zipWith (flip Succ 1) (zip [0 ..] move18Names)
          . (Phase1Coord <$>)
          . transposeTwice . zipWithTwice ((. pure) . liftA2 (U.!)) phase1Move18
          . phase1Unwrap
  }

-- | Phase 1: reduce to \<U, D, L2, F2, R2, B2\>.
phase1 :: Cube -> Maybe [(Int, String)]
phase1 c = snd <$> search' (gsPhase1 c)

--

newtype Phase2Coord = Phase2Coord { phase2Unwrap :: Thrice Int }
  deriving Eq

move10Coord :: CubeAction a => Coordinate a -> [Vector Coord]
move10Coord = moveTables CA1 move10

phase2Move10 :: Thrice [Vector Int]
phase2Move10 = Triple
  (move10Coord coordUDSlicePermu)
  (move10Coord coordUDEdgePermu)
  (move10Coord coordCornerPermu)

phase2Dist :: Thrice (Vector Int)
phase2Dist = zipWithThrice tableToDistance
  (phase2Unwrap . phase2Encode $ iden)
  phase2Move10

phase2Encode :: Cube -> Phase2Coord
phase2Encode = Phase2Coord . (<*>) (Triple
    (encode coordUDSlicePermu . fromCube)
    (encode coordUDEdgePermu  . fromCube)
    (encode coordCornerPermu  . fromCube)
  ) . pure

gsPhase2 :: Cube -> GraphSearch (Int, String) Int Phase2Coord
gsPhase2 c = GS {
  root = phase2Encode c,
  goal = (== phase2Encode iden),
  estm = maximum . zipWithThrice (U.!) phase2Dist . phase2Unwrap,
  succs = zipWith (flip Succ 1)
            (([0, 1, 2] ++ [15, 16, 17] ++ [4, 7 ..]) `zip` move10Names)
          . (Phase2Coord <$>)
          . transposeThrice . zipWithThrice (flip (map . flip (U.!))) phase2Move10
          . phase2Unwrap
  }

phase2 :: Cube -> Maybe [(Int, String)]
phase2 c = snd <$> search' (gsPhase2 c)

--

twoPhase :: Cube -> Maybe [(Int, String)]
twoPhase c = do
  s1 <- phase1 c
  let c' = foldl' (?) c (((move18 !!) . fst) <$> s1)
  s2 <- phase2 c'
  return (s1 ++ s2)

-- | Strict in the move tables and distance tables:
-- > phase1Move18
-- > phase1Dist
-- > phase2Move10
-- > phase2Dist
twoPhaseTables =
  phase1Move18 `deepseq`
  phase1Dist `deepseq`
  phase2Move10 `deepseq`
  phase2Dist `deepseq`
  ()

--

tableToDistance :: Coord -> [Vector Coord] -> Vector Int
tableToDistance root vs = distances (U.length (head vs)) root neighbors
  where neighbors = liftA2 (U.!) vs . pure

