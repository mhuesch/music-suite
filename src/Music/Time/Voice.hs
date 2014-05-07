
{-# LANGUAGE CPP                        #-}
{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE ViewPatterns               #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveFoldable             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveTraversable          #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoMonomorphismRestriction  #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012-2014
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
--
-------------------------------------------------------------------------------------

module Music.Time.Voice (
    -- * Music.Time.Voice
    Voice,

    -- ** Substructure
    voice,
    stretcheds,
    eventsV,
    
    singleStretched,

    -- *** Unsafe operations
    unsafeStretcheds,
    unsafeEventsV,

    -- ** Fusion
    fuse,
    fuseBy,

    -- ** Zips
    zipVoice,
    zipVoiceWith,
    -- dzipVoiceWith,
    zipVoiceWith',
    zipVoiceWithNoScale,
    
    -- ** Separating rhythms and values
    vrhythm,
    vvalues,
    rotateRhythm,
    rotateValues,
    reverseRhythm,
    reverseValues,
  ) where

import           Data.AffineSpace
import           Data.AffineSpace.Point
import           Data.Map               (Map)
import qualified Data.Map               as Map
import           Data.Ratio
import           Data.Semigroup
import           Data.Set               (Set)
import qualified Data.Set               as Set
import           Data.VectorSpace

import           Music.Time.Reverse
import           Music.Time.Split
import           Music.Time.Stretched

import           Control.Applicative
import           Control.Lens           hiding (Indexable, Level, above, below,
                                         index, inside, parts, reversed,
                                         transform, (<|), (|>))
import           Control.Monad
import           Control.Monad.Compose
import           Control.Monad.Plus
import           Data.Foldable          (Foldable)
import qualified Data.Foldable          as Foldable
import qualified Data.List
import           Data.List.NonEmpty     (NonEmpty)
import           Data.Traversable       (Traversable)
import qualified Data.Traversable       as T
import           Data.Typeable
import           Music.Dynamics.Literal
import           Music.Pitch.Literal
import           Music.Time.Util

-- |
-- A 'Voice' is a sequential composition of values. Events may not overlap.
--
-- @
-- type Voice a = [Stretched a]
-- @
--
newtype Voice a = Voice { getVoice :: VoiceList (VoiceEv a) }
  deriving (Functor, Foldable, Traversable, Semigroup, Monoid, Typeable, Show, Eq)

-- A voice is a list of events with explicit duration. Events can not overlap.
--
-- Voice is a 'Monoid' under sequential composition. 'mempty' is the empty part and 'mappend'
-- appends parts.
--
-- Voice is a 'Monad'. 'return' creates a part containing a single value of duration
-- one, and '>>=' transforms the values of a part, allowing the addition and
-- removal of values under relative duration. Perhaps more intuitively, 'join' scales
-- each inner part to the duration of the outer part, then removes the
-- intermediate structure.

-- Can use [] or Seq here
type VoiceList = []

-- Can use any type as long as voiceEv provides an Iso
type VoiceEv a = Stretched a

voiceEv :: Iso (Stretched a) (Stretched b) (VoiceEv a) (VoiceEv b)
voiceEv = id

instance Applicative Voice where
  pure  = return
  (<*>) = ap

instance Alternative Voice where
  (<|>) = (<>)
  empty = mempty

instance Monad Voice where
  return = view _Unwrapped . return . return
  xs >>= f = view _Unwrapped $ (view _Wrapped . f) `mbind` view _Wrapped xs

-- | Unsafe: Do not use 'Wrapped' instances
instance Wrapped (Voice a) where
  type Unwrapped (Voice a) = (VoiceList (VoiceEv a))
  _Wrapped' = iso getVoice Voice

instance Rewrapped (Voice a) (Voice b)

instance Transformable (Voice a) where
  transform s = over _Wrapped' (transform s)

instance HasDuration (Voice a) where
  _duration = Foldable.sum . fmap _duration . view _Wrapped'

instance Splittable a => Splittable (Voice a) where
  -- TODO

instance Reversible a => Reversible (Voice a) where
  rev = over _Wrapped' (fmap rev) -- TODO OK?


-- Lifted instances

instance IsPitch a => IsPitch (Voice a) where
  fromPitch = pure . fromPitch

instance IsInterval a => IsInterval (Voice a) where
  fromInterval = pure . fromInterval

instance IsDynamics a => IsDynamics (Voice a) where
  fromDynamics = pure . fromDynamics

-- | Bogus instance, so we can use [c..g] expressions
instance Enum a => Enum (Voice a) where
  toEnum = return . toEnum
  fromEnum = list 0 (fromEnum . head) . Foldable.toList

-- | Bogus instance, so we can use numeric literals
instance Num a => Num (Voice a) where
  fromInteger = return . fromInteger
  abs    = fmap abs
  signum = fmap signum
  (+)    = error "Not implemented"
  (-)    = error "Not implemented"
  (*)    = error "Not implemented"

-- | Bogus instance, so we can use c^*2 etc.
instance AdditiveGroup (Voice a) where
  zeroV   = error "Not implemented"
  (^+^)   = error "Not implemented"
  negateV = error "Not implemented"

instance VectorSpace (Voice a) where
  type Scalar (Voice a) = Duration
  d *^ s = d `stretch` s

{-
instance HasMeta (Voice a) where
  meta = _Wrapped . _1
-}


-- |
-- Create a score from a list of notes.
--
-- This is a getter (rather than a function) for consistency:
--
-- @
-- [ (0 '<->' 1, 10)^.'note',
--   (1 '<->' 2, 20)^.'note',
--   (3 '<->' 4, 30)^.'note' ]^.'score'
-- @
--
-- @
-- 'view' 'score' $ 'map' ('view' 'note') [(0 '<->' 1, 1)]
-- @
--
-- Se also 'notes'.
--
voice :: Getter [Stretched a] (Voice a)
voice = from unsafeStretcheds
-- voice = to $ flip (set stretcheds) empty
{-# INLINE voice #-}

stretcheds :: Lens (Voice a) (Voice b) [Stretched a] [Stretched b]
stretcheds = unsafeStretcheds
{-# INLINE stretcheds #-}

-- TODO meta-data
eventsV :: Lens (Voice a) (Voice b) [(Duration, a)] [(Duration, b)]
eventsV = unsafeEventsV
{-# INLINE eventsV #-}
  --(stretcheds.through (from stretched) (from stretched))

unsafeEventsV :: Iso (Voice a) (Voice b) [(Duration, a)] [(Duration, b)]
unsafeEventsV = iso (map (^.from stretched).(^.stretcheds)) ((^.voice).map (^.stretched))
{-# INLINE unsafeEventsV #-}



singleStretched :: Prism' (Voice a) (Stretched a)
singleStretched = unsafeStretcheds . single
{-# INLINE singleStretched #-}

unsafeStretcheds :: Iso (Voice a) (Voice b) [Stretched a] [Stretched b]
unsafeStretcheds = _Wrapped
{-# INLINE unsafeStretcheds #-}

{-
-- |
-- Voice
--
voiceNotes :: Lens (Voice a) (Voice b) [Note a] [Note b]

-- TODO requires some @Prism (Note a) (Note b) (Stretched a) (Stretched b)@
-}

-- |
-- Join the given voices by multiplying durations and pairing values.
--
zipVoice :: Voice a -> Voice b -> Voice (a, b)
zipVoice = zipVoiceWith (,)

-- |
-- Join the given voices by multiplying durations and combining values using the given function.
--
zipVoiceWith :: (a -> b -> c) -> Voice a -> Voice b -> Voice c
zipVoiceWith = zipVoiceWith' (*)

-- |
-- Join the given voices by combining durations and values using the given function.
--
dzipVoiceWith :: (Duration -> Duration -> a -> b -> (Duration, c)) -> Voice a -> Voice b -> Voice c
dzipVoiceWith = error "Not implemented: dzipVoiceWith"

-- TODO not simple
-- TODO unsafe (meta...)
voiceList :: Iso' (Voice a) [(Duration, a)]
voiceList = iso (map (view (from stretched)) . view stretcheds) (view voice . map (view stretched))

-- |
-- Merge consecutive equal notes.
--
fuse :: Eq a => Voice a -> Voice a
fuse = fuseBy (==)
  
fuseBy :: (a -> a -> Bool) -> Voice a -> Voice a
fuseBy p = fuseBy' p head

fuseBy' :: (a -> a -> Bool) -> ([a] -> a) -> Voice a -> Voice a
fuseBy' p g = over voiceList $ fmap foldNotes . Data.List.groupBy (inspectingBy snd p)
  where
    -- Add up durations and use a custom function to combine notes
    -- Typically, the combination function us just 'head', as we know that group returns
    -- non-empty lists of equal elements.
    foldNotes (unzip -> (ds, as)) = (sum ds, g as)



zipVoiceWithNoScale :: (a -> b -> c) -> Voice a -> Voice b -> Voice c
zipVoiceWithNoScale f a b = zipVoiceWith' (\x y -> x) f a b

-- TODO more elegant definition using indexed traversal or similar?
vrhythm :: Lens' (Voice a) [Duration]
vrhythm = lens getDurs (flip setDurs)
  where
    getDurs :: Voice a -> [Duration]
    getDurs = map fst . view eventsV

    setDurs :: [Duration] -> Voice a -> Voice a
    setDurs ds as = zipVoiceWith' (\a b -> a) (\a b -> b) (mconcat $ map durToVoice ds) as

    durToVoice d = stretch d $ pure ()

-- TODO more elegant definition using indexed traversal or similar?
vvalues :: Lens' (Voice a) [a]
vvalues = lens getValues (flip setValues)
  where
    getValues :: Voice a -> [a]
    getValues = map snd . view eventsV

    setValues :: [a] -> Voice a -> Voice a
    setValues as bs = zipVoiceWith' (\a b -> b) (\a b -> a) (listToVoice as) bs

    listToVoice = mconcat . map pure

rotateRhythm :: Int -> Voice a -> Voice a
rotateRhythm n = over vrhythm (rotate n)

rotateValues :: Int -> Voice a -> Voice a
rotateValues n = over vvalues (rotate n)

reverseRhythm :: Voice a -> Voice a
reverseRhythm = over vrhythm reverse

reverseValues :: Voice a -> Voice a
reverseValues = over vvalues reverse


zipVoiceWith' :: (Duration -> Duration -> Duration) -> (a -> b -> c) -> Voice a -> Voice b -> Voice c
zipVoiceWith' f g
  ((unzip.view eventsV) -> (ad, as))
  ((unzip.view eventsV) -> (bd, bs))
  = let cd = zipWith f ad bd
        cs = zipWith g as bs
     in view (from unsafeEventsV) (zip cd cs)

--
-- TODO
-- Implement meta-data
-- Separate safe/unsafe Isos (see voiceList...)
--

