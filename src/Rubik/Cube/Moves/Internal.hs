{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses, DeriveFunctor,
    ViewPatterns #-}
module Rubik.Cube.Moves.Internal where

import Rubik.Cube.Coord
import Rubik.Cube.Cubie.Internal
import Rubik.Misc

import Control.Applicative
import Control.Monad
import Control.Newtype

import Data.Char ( toLower )
import Data.Function ( on )
import Data.List
import Data.Maybe
import Data.Monoid
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as U

newtype MoveTag m a = MoveTag { unMoveTag :: a }
  deriving (Eq, Ord, Functor, Show)

instance Newtype (MoveTag m a) a where
  pack = MoveTag
  unpack = unMoveTag

data Move18
data Move10

-- | Associate every elementary move with an 'ElemMove'.
move18Names :: MoveTag Move18 [ElemMove]
move10Names :: MoveTag Move10 [ElemMove]
move18Names = MoveTag [ (n, m) | m <- [U .. D], n <- [1 .. 3] ]
move10Names
  = MoveTag $ [ (n, m) | m <- [U, D], n <- [1 .. 3] ] ++ [ (2, m) | m <- [L .. B] ]

-- Elementary moves

u_ =
  unsafeCube' ([1, 2, 3, 0] ++ [4..7])
          (replicate 8 0)
          ([1, 2, 3, 0] ++ [4..11])
          (replicate 12 0)

-- | Up
u  = u_
-- | Left
l  = surf3 ?? d
-- | Front
f  = surf3 ?? r
-- | Right
r  = surf3 ?? u
-- | Back
b  = surf3 ?? l
-- | Down
d  = sf2   ?? u

-- | List of the 6 generating moves.
--
-- > move6 = [u,l,f,r,b,d]
move6  = [u, l, f, r, b, d]

-- | List of the 18 elementary moves.
--
-- > move18 = [u, u <>^ 2, u <>^ 3, ...]
move18 :: MoveTag Move18 [Cube]
move18 = MoveTag $ move6 >>= \x -> [x, x <>^ 2, x <>^ 3]

-- | Generating set of @G1@
move6' = [u,d] ++ map (<>^ 2) [l, f, r, b]

-- | > G1 = <U, D, L2, F2, R2, B2>
move10 :: MoveTag Move10 [Cube]
move10 = MoveTag $ ([u, d] >>= \x -> [x, x <>^ 2, x <>^ 3]) ++ drop 2 move6'

-- Symmetries

-- | Rotation of the whole cube
-- around the diagonal axis through corners URF and LBD
surf3 =
  unsafeCube' [4, 5, 2, 1, 6, 3, 0, 7]
          [2, 1, 2, 1, 2, 1, 2, 1]
          [5, 9, 1, 8, 7, 11, 3, 10, 6, 2, 4, 0]
          [1, 0, 1, 0, 1,  0, 1,  0, 1, 1, 1, 1]

-- | Half-turn of the whole cube
-- around the FB axis
sf2 =
  unsafeCube' [6, 5, 4, 7, 2, 1, 0, 3]
          (replicate 8 0)
          [6, 5, 4, 7, 2, 1, 0, 3, 9, 8, 11, 10]
          (replicate 12 0)

-- | Quarter-turn around the UD axis
su4 =
  unsafeCube' [1, 2, 3, 0, 5, 6, 7, 4]
          (replicate 8 0)
          [1, 2, 3, 0, 5, 6, 7, 4, 9, 11, 8, 10]
          (replicate 8 0 ++ [1, 1, 1, 1])

-- | Reflection w.r.t. the RL slice plane
slr2 =
  unsafeCube' [3, 2, 1, 0, 5, 4, 7, 6]
          (replicate 8 5)
          [2, 1, 0, 3, 6, 5, 4, 7, 9, 8, 11, 10]
          (replicate 12 0)

-- | Index of a symmetry
newtype SymCode s = SymCode { unSymCode :: Int } deriving (Eq, Ord, Show)
data Symmetry sym = Symmetry
  { symAsCube :: Cube
  , symAsMovePerm :: [Int]
  }
data Symmetric sym a

rawMoveSym :: Symmetry sym -> [RawMove a] -> [RawMove (Symmetric sym a)]
rawMoveSym sym moves = fmap (RawMove . unRawMove) (composeList moves (symAsMovePerm sym))

rawCast :: RawCoord a -> RawCoord (Symmetric sym a)
rawCast = RawCoord . unRawCoord

symmetry_urf3 = Symmetry surf3 [ 3 * f + i | f <- [2, 5, 3, 0, 1, 4], i <- [0, 1, 2] ]
symmetry_urf3' = Symmetry (surf3 <>^ 2) (join composeList (symAsMovePerm symmetry_urf3))

mkSymmetry :: Cube -> Symmetry sym
mkSymmetry s = Symmetry s (fmap f moves)
  where
    f m = fromJust $ findIndex (== s <> m <> inverse s) moves
    MoveTag moves = move18

-- x <- [0..47]
-- 2 * 4 * 2 * 3 = 48
-- 2 * 4 * 2 = 16
-- | Translate an integer to a symmetry.
symDecode :: SymCode s -> Cube
symDecode = (es V.!) . unSymCode
  where es = V.generate 48 eSym'
        eSym' x = (surf3 <>^ x1)
               <> (sf2   <>^ x2)
               <> (su4   <>^ x3)
               <> (slr2  <>^ x4)
          where x4 =  x          `mod` 2
                x3 = (x `div` 2) `mod` 4
                x2 = (x `div` 8) `mod` 2
                x1 =  x `div` 16 -- < 3

data UDFix
-- | Octahedral group
data CubeSyms

-- | Symmetries which preserve the UD axis
-- (generated by 'sf2', 'su4' and 'slr2')
sym16Codes :: [SymCode UDFix]
sym16Codes = map SymCode [0..15]

sym16 :: [Symmetry UDFix]
sym16 = map mkSymmetry sym16'

sym16' = map symDecode sym16Codes

-- | All symmetries of the whole cube
sym48Codes :: [SymCode CubeSyms]
sym48Codes = map SymCode [0..47]

sym48 :: [Symmetry CubeSyms]
sym48 = map mkSymmetry sym48'

sym48' = map symDecode sym48Codes

--

composeSym :: SymCode sym -> SymCode sym -> SymCode sym
composeSym = \(SymCode i) (SymCode j) -> SymCode (symMatrix U.! flatIndex 48 i j)
  where
    symMatrix = U.fromList [ c i j | i <- [0 .. 47], j <- [0 .. 47] ]
    c i j = fromJust $ findIndex (== s i <> s j) sym48'
    s = symDecode . SymCode

invertSym :: SymCode sym -> SymCode sym
invertSym = \(SymCode i) -> SymCode (symMatrix U.! i)
  where
    symMatrix = U.fromList (fmap inv [0 .. 47])
    inv j = fromJust $ findIndex (== inverse (s j)) sym48'
    s = symDecode . SymCode

-- | Minimal set of moves
data BasicMove = U | L | F | R | B | D
  deriving (Enum, Eq, Ord, Show, Read)

-- | Quarter turns, clock- and anti-clockwise, half turns
type ElemMove = (Int, BasicMove)

-- | Moves generated by 'BasicMove', 'group'-ed
type Move = [ElemMove]

infixr 5 `consMove`

-- Trivial reductions
consMove :: ElemMove -> Move -> Move
consMove nm [] = [nm]
consMove nm@(n, m) (nm'@(n', m') : moves)
  | m == m' = case (n + n') `mod` 4 of
                0 -> moves
                p -> (p, m) : moves
  | oppositeAndGT m m' = nm' `consMove` nm `consMove` moves
consMove nm moves = nm : moves

-- | Relation between faces
--
-- @oppositeAndGT X Y == True@ if X and Y are opposite faces and @X > Y@.
oppositeAndGT :: BasicMove -> BasicMove -> Bool
oppositeAndGT = curry (`elem` [(D, U), (R, L), (B, F)])

-- | Perform "trivial" reductions of the move sequence.
reduceMove :: Move -> Move
reduceMove = foldr consMove []

-- | Scramble the solved cube.
moveToCube :: Move -> Cube
moveToCube = moveToCube' . reduceMove

moveToCube' :: Move -> Cube
moveToCube' [] = iden
moveToCube' (m : ms) = elemMoveToCube m <> moveToCube' ms

basicMoveToCube :: BasicMove -> Cube
basicMoveToCube = (move6 !!) . fromEnum

elemMoveToCube :: ElemMove -> Cube
elemMoveToCube (n, m) = unMoveTag move18 !! (fromEnum m * 3 + n - 1)

-- | Show the move sequence.
moveToString :: Move -> String
moveToString =
  intercalate " "
  . (mapMaybe $ \(n, m)
      -> (show m ++) <$> lookup (n `mod` 4) [(1, ""), (2, "2"), (3, "'")])

-- | Associates s character in @"ULFRBD"@ or the same in lowercase
-- to a generating move.
decodeMove :: Char -> Maybe BasicMove
decodeMove = (`lookup` zip "ulfrbd" [U .. D]) . toLower

-- | Reads a space-free sequence of moves.
-- If the string is incorrectly formatted,
-- the first wrong character is returned.
--
-- @([ulfrbd][23']?)*@
stringToMove :: String -> Either Char Move
stringToMove [] = return []
stringToMove (x : xs) = do
  m <- maybe (Left x) Right $ decodeMove x
  let (m_, next) =
        case xs of
          o   : next | o `elem` ['\'', '3'] -> ((3, m), next)
          '2' : next                        -> ((2, m), next)
          _                                 -> ((1, m), xs)
  (m_ :) <$> stringToMove next

-- | Remove moves that result in duplicate actions on the Rubik's cube
nubMove :: [Move] -> [Move]
nubMove = nubBy ((==) `on` moveToCube)

-- * Random cube

-- | Decode a whole @Cube@ from coordinates.
coordToCube
  :: RawCoord CornerPermu
  -> RawCoord CornerOrien
  -> RawCoord EdgePermu
  -> RawCoord EdgeOrien
  -> Cube
coordToCube n1 n2 n3 n4 = Cube (Corner cp co) (Edge ep eo)
  where
    cp = decode n1
    co = decode n2
    ep = decode n3
    eo = decode n4

-- | Generate a random 'Cube'.
--
-- Relies on 'randomRIO'.
randomCube :: IO Cube
randomCube = do
  c <- coordToCube
         <$> randomRaw
         <*> randomRaw
         <*> randomRaw
         <*> randomRaw
  if solvable c
    then return c
    else randomCube -- proba 1/2
