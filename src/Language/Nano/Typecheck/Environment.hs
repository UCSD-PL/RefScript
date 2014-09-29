{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE TypeSynonymInstances      #-}
{-# LANGUAGE DeriveFunctor             #-}
{-# LANGUAGE UndecidableInstances      #-}

module Language.Nano.Typecheck.Environment where

import           Data.Data                          (Data)
import           Data.Typeable                      (Typeable)
import           Language.Nano.Types
import           Language.Nano.Typecheck.Types()
import           Language.Nano.Env
import           Language.Nano.Environment
import           Language.Nano.Names

import           Language.ECMAScript3.PrettyPrint
import qualified Language.Fixpoint.Types        as F
import           Text.PrettyPrint.HughesPJ 

-------------------------------------------------------------------------------
-- | Typecheck Environment
-------------------------------------------------------------------------------

data TCEnv r  = TCE {
    tce_names       :: Env (RType r, Assignability)
  , tce_mod         :: QEnv (ModuleDef r)
  , tce_ctx         :: !IContext
  , tce_path        :: AbsPath
  , tce_parent      :: Maybe (TCEnv r)
  , tce_mutability  :: Mutability 
  }
  deriving (Functor, Data, Typeable)


--   We define this alias as the "output" type for typechecking any entity
--   that can create or affect binders (e.g. @VarDecl@ or @Statement@)
--   @Nothing@ means if we definitely hit a "return" 
--   @Just γ'@ means environment extended with statement binders

type TCEnvO r = Maybe (TCEnv r)


instance EnvLike r TCEnv where
  names           = tce_names
  modules         = tce_mod
  absPath         = tce_path
  context         = tce_ctx
  parent          = tce_parent
  mutability      = tce_mutability
 

instance (PP r, F.Reftable r) => PP (TCEnv r) where
  pp = ppTCEnv


ppTCEnv :: (PP r, F.Reftable r) => TCEnv r -> Doc
ppTCEnv g
  =   text "******************** Environment ************************"
  $+$ pp (names g)
  $+$ text "******************** Modules ****************************"
  $+$ pp (modules g)
  $+$ text "******************** Absolute path **********************"
  $+$ pp (absPath g)

