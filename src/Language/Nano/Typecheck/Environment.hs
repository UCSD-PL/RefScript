{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances  #-}
{-# LANGUAGE UndecidableInstances  #-}

module Language.Nano.Typecheck.Environment where

import qualified Language.Fixpoint.Types       as F
import           Language.Nano.ClassHierarchy
import           Language.Nano.Core.Env
import           Language.Nano.Environment
import           Language.Nano.Names
import           Language.Nano.Pretty
import           Language.Nano.Program
import           Language.Nano.Typecheck.Types ()
import           Language.Nano.Types
import           Text.PrettyPrint.HughesPJ

-------------------------------------------------------------------------------
-- | Typecheck Environment
-------------------------------------------------------------------------------

data TCEnv r  = TCE {
    tce_names  :: Env (EnvEntry r)
  , tce_bounds :: Env (RType r)
  , tce_ctx    :: IContext
  , tce_path   :: AbsPath
  , tce_cha    :: ClassHierarchy r
  }
  deriving (Functor) -- , Data, Typeable)


--   We define this alias as the "output" type for typechecking any entity
--   that can create or affect binders (e.g. @VarDecl@ or @Statement@)
--   @Nothing@ means if we definitely hit a "return"
--   @Just γ'@ means environment extended with statement binders

type TCEnvO r = Maybe (TCEnv r)


instance EnvLike r TCEnv where
  names     = tce_names
  bounds    = tce_bounds
  absPath   = tce_path
  context   = tce_ctx
  cha       = tce_cha

  -- parent          = tce_parent


instance (PP r, F.Reftable r) => PP (TCEnv r) where
  pp = ppTCEnv


ppTCEnv :: (PP r, F.Reftable r) => TCEnv r -> Doc
ppTCEnv g
  =   text "******************** Environment ************************"
  $+$ pp (names g)
  -- $+$ text "******************** Modules ****************************"
  -- $+$ pp (modules g)
  $+$ text "******************** Absolute path **********************"
  $+$ pp (absPath g)

