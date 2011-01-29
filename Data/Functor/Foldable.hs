{-# LANGUAGE TypeFamilies, Rank2Types, FlexibleContexts, FlexibleInstances, GADTs, StandaloneDeriving, UndecidableInstances #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Functor.Foldable
-- Copyright   :  (C) 2008 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable (rank-2 polymorphism)
-- 
----------------------------------------------------------------------------
module Data.Functor.Foldable
  ( 
  -- * Base functors for fixed points
    Base
  -- * Fixed points
  , Fix(..)
  , Mu(..)
  , Nu(..)
  , Prim(..)
  -- * Folding
  , Foldable(..)
  -- ** Combinators
  , gcata
  , zygo
  , gzygo
  , histo
  , ghisto
  -- ** Distributive laws
  , distCata
  , distPara
  , distParaT
  , distZygo
  , distZygoT
  , distHisto
  -- * Unfolding
  , Unfoldable(..)
  -- ** Combinators
  , gana
  -- ** Distributive laws
  , distAna
  , distApo
  , distGApo
  -- * Refolding
  , hylo
  , ghylo
  -- ** Changing representation
  , refix
  -- * Common names
  , fold, gfold
  , unfold, gunfold
  , refold, grefold
  ) where

import Control.Applicative
import Control.Comonad
import Control.Comonad.Trans.Class
import Control.Comonad.Trans.Env
import Control.Monad (liftM, join)
import Data.Functor.Identity
import Data.Function (on)
import qualified Data.Stream.Branching as Stream
import Data.Stream.Branching (Stream(..))
import Text.Read

type family Base t :: * -> *

data family Prim t :: * -> *
-- type instance Base (Maybe a) = Const (Maybe a) 
-- type instance Base (Either a b) = Const (Either a b)

class Functor (Base t) => Foldable t where
  project :: t -> Base t t

  cata :: (Base t a -> a) -- ^ a (Base t)-algebra
       -> t               -- ^ fixed point
       -> a               -- ^ result
  cata f = c where c = f . fmap c . project

  para :: Unfoldable t => (Base t (t, a) -> a) -> t -> a
  para = zygo embed

  gpara :: (Unfoldable t, Comonad w) => (forall b. Base t (w b) -> w (Base t b)) -> (Base t (EnvT t w a) -> a) -> t -> a
  gpara = gzygo embed


distPara :: Unfoldable t => Base t (t, a) -> (t, Base t a)
distPara = distZygo embed

distParaT :: (Unfoldable t, Comonad w) => (forall b. Base t (w b) -> w (Base t b)) -> Base t (EnvT t w a) -> EnvT t w (Base t a)
distParaT = distZygoT embed

class Functor (Base t) => Unfoldable t where
  embed :: Base t t -> t
  ana
    :: (a -> Base t a) -- ^ a (Base t)-coalgebra
    -> a               -- ^ seed
    -> t               -- ^ resulting fixed point
  ana g = a where a = embed . fmap a . g

  apo :: Foldable t => (a -> Base t (Either t a)) -> a -> t
  apo = gapo project

hylo :: Functor f => (f b -> b) -> (a -> f a) -> a -> b
hylo f g = h where h = f . fmap h . g

fold :: Foldable t => (Base t a -> a) -> t -> a
fold = cata

unfold :: Unfoldable t => (a -> Base t a) -> a -> t
unfold = ana

refold :: Functor f => (f b -> b) -> (a -> f a) -> a -> b
refold = hylo

data instance Prim [a] b = Cons a b | Nil deriving (Eq,Ord,Show,Read)
instance Functor (Prim [a]) where
  fmap f (Cons a b) = Cons a (f b)
  fmap _ Nil = Nil

type instance Base [a] = Prim [a] 
instance Foldable [a] where
  project (x:xs) = Cons x xs
  project [] = Nil

  para f (x:xs) = f (Cons x (xs, para f xs))
  para f [] = f Nil

instance Unfoldable [a] where
  embed (Cons x xs) = x:xs
  embed Nil = []

  apo f a = case f a of
    Cons x (Left xs) -> x : xs
    Cons x (Right b) -> x : apo f b 
    Nil -> []

-- | Example boring stub for non-recursive data types
type instance Base (Maybe a) = Const (Maybe a)
instance Foldable (Maybe a) where project = Const 
instance Unfoldable (Maybe a) where embed = getConst  

-- | Example boring stub for non-recursive data types
type instance Base (Either a b) = Const (Either a b)
instance Foldable (Either a b) where project = Const 
instance Unfoldable (Either a b) where embed = getConst  

-- | A generalized catamorphism
gfold, gcata
  :: (Foldable t, Comonad w)
  => (forall b. Base t (w b) -> w (Base t b)) -- ^ a distributive law
  -> (Base t (w a) -> a)                      -- ^ a (Base t)-w-algebra
  -> t                                        -- ^ fixed point 
  -> a
gcata k g = g . extract . c where 
  c = k . fmap (duplicate . fmap g . c) . project
gfold = gcata

distCata :: Functor f => f (Identity a) -> Identity (f a)
distCata = Identity . fmap runIdentity

-- | A generalized anamorphism
gunfold, gana
  :: (Unfoldable t, Monad m)
  => (forall b. m (Base t b) -> Base t (m b)) -- ^ a distributive law
  -> (a -> Base t (m a))                      -- ^ a (Base t)-m-coalgebra
  -> a                                        -- ^ seed
  -> t
gana k f = a . return . f where 
  a = embed . fmap (a . liftM f . join) . k
gunfold = gana

distAna :: Functor f => Identity (f a) -> f (Identity a)
distAna = fmap Identity . runIdentity

-- | A generalized hylomorphism
grefold, ghylo
  :: (Comonad w, Functor f, Monad m) 
  => (forall c. f (w c) -> w (f c)) 
  -> (forall d. m (f d) -> f (m d))
  -> (f (w b) -> b)
  -> (a -> f (m a))
  -> a
  -> b
ghylo w m f g = extract . h . return where 
  h = fmap f . w . fmap (duplicate . h . join) . m . liftM g
grefold = ghylo

newtype Fix f = Fix (f (Fix f))
deriving instance Eq (f (Fix f)) => Eq (Fix f)
deriving instance Ord (f (Fix f)) => Ord (Fix f)
deriving instance Show (f (Fix f)) => Show (Fix f)
deriving instance Read (f (Fix f)) => Read (Fix f)

type instance Base (Fix f) = f
instance Functor f => Foldable (Fix f) where
  project (Fix a) = a
instance Functor f => Unfoldable (Fix f) where
  embed = Fix

refix :: (Foldable s, Unfoldable t, Base s ~ Base t) => s -> t
refix = cata embed

toFix :: Foldable t => t -> Fix (Base t)
toFix = refix

fromFix :: Unfoldable t => Fix (Base t) -> t
fromFix = refix

newtype Mu f = Mu (forall a. (f a -> a) -> a)

instance (Functor f, Eq (Fix f)) => Eq (Mu f) where
  (==) = (==) `on` toFix

instance (Functor f, Ord (Fix f)) => Ord (Mu f) where
  compare = compare `on` toFix

instance (Functor f, Show (Fix f)) => Show (Mu f) where
  showsPrec d f = showParen (d > 10) $
    showString "fromFix " . showsPrec 11 (toFix f)

instance (Functor f, Read (Fix f)) => Read (Mu f) where
  readPrec = parens $ prec 10 $ do
    Ident "fromFix" <- lexP
    fromFix <$> step readPrec

type instance Base (Mu f) = f
instance Functor f => Foldable (Mu f) where
  project = fold (fmap embed) 
  cata f (Mu g) = g f
instance Functor f => Unfoldable (Mu f) where
  embed m = Mu (\f -> f (fmap (fold f) m))

data Nu f where Nu :: (a -> f a) -> a -> Nu f

instance (Functor f, Eq (Fix f)) => Eq (Nu f) where
  (==) = (==) `on` toFix

instance (Functor f, Ord (Fix f)) => Ord (Nu f) where
  compare = compare `on` toFix

instance (Functor f, Show (Fix f)) => Show (Nu f) where
  showsPrec d f = showParen (d > 10) $
    showString "fromFix " . showsPrec 11 (toFix f)

instance (Functor f, Read (Fix f)) => Read (Nu f) where
  readPrec = parens $ prec 10 $ do
    Ident "fromFix" <- lexP
    fromFix <$> step readPrec

type instance Base (Mu f) = f
type instance Base (Nu f) = f
instance Functor f => Unfoldable (Nu f) where
  embed = unfold (fmap project)
  ana = Nu 
instance Functor f => Foldable (Nu f) where
  project (Nu f a) = fmap (Nu f) (f a)

zygo :: Foldable t => (Base t b -> b) -> (Base t (b, a) -> a) -> t -> a
zygo f = gfold (distZygo f)

distZygo 
  :: Functor f 
  => (f b -> b)             -- An f-algebra 
  -> (f (b, a) -> (b, f a)) -- ^ A distributive for semi-mutual recursion
distZygo g m = (g (fmap fst m), fmap snd m)

gzygo 
  :: (Foldable t, Comonad w) 
  => (Base t b -> b)
  -> (forall c. Base t (w c) -> w (Base t c))
  -> (Base t (EnvT b w a) -> a)
  -> t
  -> a
gzygo f w = gfold (distZygoT f w)

distZygoT 
  :: (Functor f, Comonad w)           
  => (f b -> b)                        -- An f-w-algebra to use for semi-mutual recursion
  -> (forall c. f (w c) -> w (f c))    -- A base Distributive law
  -> f (EnvT b w a) -> EnvT b w (f a)  -- A new distributive law that adds semi-mutual recursion
distZygoT g k fe = EnvT (g (getEnv <$> fe)) (k (lower <$> fe))
  where getEnv (EnvT e _) = e 
    
gapo :: Unfoldable t => (b -> Base t b) -> (a -> Base t (Either b a)) -> a -> t
gapo g = gunfold (distGApo g)

distApo :: Foldable t => Either t (Base t a) -> Base t (Either t a)
distApo = distGApo project

distGApo :: Functor f => (b -> f b) -> Either b (f a) -> f (Either b a)
distGApo f = either (fmap Left . f) (fmap Right)

histo :: Foldable t => (Base t (Stream (Base t) a) -> a) -> t -> a
histo = gfold (distHisto id)

ghisto :: (Foldable t, Functor h) => (forall b. Base t (h b) -> h (Base t b)) -> (Base t (Stream h a) -> a) -> t -> a
ghisto g = gfold (distHisto g)

distHisto :: (Functor f, Functor h) => (forall b. f (h b) -> h (f b)) -> f (Stream h a) -> Stream h (f a)
distHisto k = Stream.unfold (\as -> (Stream.head <$> as, k (Stream.tail <$> as)))

-- TODO: futu & chrono, these require Free monads 
-- TODO: distGApoT, requires EitherT