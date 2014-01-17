
{-# LANGUAGE
    MultiParamTypeClasses,
    TypeFamilies,
    DeriveFunctor,
    DeriveFoldable,
    DeriveTraversable,
    FlexibleInstances,
    FlexibleContexts,
    ConstraintKinds,
    NoMonomorphismRestriction,
    UndecidableInstances,
    RankNTypes,
    GeneralizedNewtypeDeriving #-}

module Update5 where
    
-- Copied from https://ghc.haskell.org/trac/ghc/wiki/Records/OverloadedRecordFields/Plan
-- Simplified to capture a single type
import Control.Applicative
import Control.Lens
import Data.Semigroup
import Data.Foldable
import Data.Traversable
import Data.AffineSpace -- tests
import Data.AffineSpace.Relative -- tests
import qualified Music.Pitch as M

class HasPitch s where
  type Pitch             (s :: *) :: *
  _pitch :: (a ~ Pitch s) => s -> a

class (HasPitch s, SetPitch (Pitch t) s ~ t) => HasSetPitch (s :: *) (t :: *) where
  type SetPitch (b :: *) (s :: *) :: *

  setPitch :: Pitch t -> s -> t
  setPitch x = mapPitch (const x)
  
  mapPitch :: (Pitch s -> Pitch t) -> s -> t
  mapPitch f x = setPitch p x where p = f (_pitch x)

type HasPitch' a    = HasSetPitch a a
type HasSetPitch' a = HasSetPitch a a
  
pitch' :: HasPitch' a => Lens' a (Pitch a)
pitch' = pitch

pitch :: HasSetPitch a b => Lens a b (Pitch a) (Pitch b)
pitch = lens _pitch (flip setPitch)

-- setPitch' :: HasSetPitch s s => Pitch s -> s -> s
-- setPitch' = setPitch

-- mapPitch' :: HasSetPitch s s => (Pitch s -> Pitch s) -> s -> s
-- mapPitch' = mapPitch

data PitchT f a = PitchT f a
    deriving (Show, Functor, Foldable, Traversable)

instance (Semigroup p, Monoid p) => Applicative (PitchT p) where
    pure = PitchT mempty
    PitchT pf vf <*> PitchT px vx = PitchT (pf <> px) (vf $ vx)

instance HasPitch (PitchT f a) where
    type Pitch      (PitchT f a) = f
    _pitch        (PitchT f a) = f

instance HasSetPitch (PitchT f a) (PitchT g a)  where
    type SetPitch g (PitchT f a) = PitchT g a 
    setPitch      g (PitchT f a) = PitchT g a

-- instance HasPitch a => HasPitch [a] where
--     type Pitch [a] = Pitch a
--     _pitch [x] = _pitch x
--     -- TODO crashes when updating longer lists etc
-- 
-- -- Undecidable
-- instance (HasSetPitch a b) => HasSetPitch [a] [b] where
--   type SetPitch b [a] = [SetPitch b a]
--   setPitch b = fmap (setPitch b)      

instance HasPitch a => HasPitch (c,a) where
    type Pitch (c,a) = Pitch a
    _pitch (c,a) = _pitch a

-- Undecidable ??
instance HasSetPitch a b => HasSetPitch (c,a) (c,b) where
  type SetPitch b (c,a) = (c,SetPitch b a)
  setPitch b = fmap (setPitch b)



-- instance HasPitch M.Pitch where
--     type Pitch M.Pitch = M.Pitch
--     _pitch = id
-- instance HasSetPitch M.Pitch a where
--     type SetPitch a M.Pitch = a
--     setPitch = const

instance HasPitch Int where
    type Pitch Int = Int
    _pitch = id
instance (a ~ Pitch a) => HasSetPitch Int a where
    type SetPitch a Int = a
    setPitch = const

instance HasPitch Bool where
    type Pitch Bool = Bool
    _pitch = id
instance (a ~ Pitch a) => HasSetPitch Bool a where
    type SetPitch a Bool = a
    setPitch = const

instance HasPitch M.Pitch where
    type Pitch M.Pitch = M.Pitch
    _pitch = id
instance (a ~ Pitch a) => HasSetPitch M.Pitch a where
    type SetPitch a M.Pitch = a
    setPitch = const



type Interval a = Diff (Pitch a)


x :: PitchT Int (Bool, Int)
x = PitchT 3 (True, 0)

y :: PitchT Float (Bool, Int)
y = x & pitch %~ fromIntegral

z :: PitchT Bool (Bool, Int)
z = x & pitch .~ True

up :: (HasPitch' a, AffineSpace (Pitch a)) => Interval a -> a -> a
up a = pitch %~ (.+^ a)

down :: (HasPitch' a, AffineSpace (Pitch a)) => Interval a -> a -> a
down a = pitch %~ (.-^ a)


type HasInterval a = (Floating (Interval a), M.InnerSpace (Interval a), M.Scalar (Interval a) ~ (Interval a))

interval :: (HasPitch' a, AffineSpace (Pitch a), HasInterval a) => a -> a -> Interval a
interval x y = (x^.pitch) `distance` (y^.pitch)

invert :: (HasPitch' a, AffineSpace (Pitch a)) => Pitch a -> a -> a
invert p = pitch %~ reflectAround p


--                         
