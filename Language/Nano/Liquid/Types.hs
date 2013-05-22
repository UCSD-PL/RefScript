{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances    #-}

-- | Module pertaining to Refinement Type descriptions and conversions
--   Likely mergeable with @Language.Nano.Typecheck.Types@

module Language.Nano.Liquid.Types ( 
  
  -- * Refinement Types and Environments
    RefType 
  , REnv
  , NanoRefType

  -- * Constraint Environments
  , CGEnv (..)
  , emptyCGEnv

  -- * Constraint Information
  , Cinfo (..)
  , ci

  -- * Constraints
  , SubC (..) , WfC (..)
  , FixSubC   , FixWfC

  -- * Conversions
  , RefTypable (..)
  , eSingleton
  , pSingleton
  , shiftVVs

  -- * Manipulating RefType
  , rTypeReft
  , rTypeSort
  , rTypeSortedReft
  , rTypeValueVar

  -- * Predicates On RefType 
  , isBaseRType
  , isTrivialRefType

  -- * Monadic map (TODO: Applicative/Traversable)
  , mapReftM

  -- * Primitive Types
  , prefixOpRTy
  , infixOpRTy 
  ) where

import           Control.Applicative ((<$>), (<*>))
import           Data.Maybe             (fromMaybe, isJust)
import           Data.Monoid            hiding ((<>))            
import           Data.Ord               (comparing) 
import qualified Data.List               as L
import qualified Data.HashMap.Strict     as M
import           Data.Generics.Aliases
import           Data.Generics.Schemes

import           Language.ECMAScript3.Syntax
import           Language.ECMAScript3.Syntax.Annotations
import           Language.ECMAScript3.PrettyPrint

import           Language.Nano.Errors
import           Language.Nano.Types
import           Language.Nano.Env
import           Language.Nano.Typecheck.Types
import qualified Language.Fixpoint.Types as F
import           Language.Fixpoint.Misc
import           Language.Fixpoint.PrettyPrint
import           Text.PrettyPrint.HughesPJ
import           Text.Parsec.Pos    (initialPos)
import           Control.Applicative 

  
-------------------------------------------------------------------------------------
----- | Refinement Types and Environments -------------------------------------------
-------------------------------------------------------------------------------------

type RefType     = RType F.Reft
type REnv        = Env RefType
type NanoRefType = Nano AnnType RefType 

-------------------------------------------------------------------------------------
-- | Constraint Generation Environment  ---------------------------------------------
-------------------------------------------------------------------------------------

data CGEnv   
  = CGE { renv   :: !(Env RefType) -- ^ bindings in scope 
        , fenv   :: F.IBindEnv     -- ^ fixpoint bindings
        , guards :: ![F.Pred]      -- ^ branch target conditions  
        }

emptyCGEnv = CGE envEmpty F.emptyIBindEnv []

instance PP CGEnv where
  pp (CGE re _ gs) = vcat [pp re, pp gs] 

----------------------------------------------------------------------------
-- | Constraint Information ------------------------------------------------
----------------------------------------------------------------------------

newtype Cinfo = Ci SourcePos deriving (Eq, Ord, Show) 

emptyCinfo    = Ci $ initialPos ""

ci :: (IsLocated a) => a -> Cinfo
ci = Ci . srcPos 

instance PP Cinfo where
  pp (Ci l)   = text "CInfo:" <+> pp l 

instance IsLocated Cinfo where
  srcPos (Ci x) = x

instance F.Fixpoint Cinfo where 
  toFix = pp

-------------------------------------------------------------------------------------
-- | Constraints --------------------------------------------------------------------
-------------------------------------------------------------------------------------

-- | Subtyping Constraints

data SubC     
  = Sub { senv  :: !CGEnv      -- ^ Environment
        , sinfo :: !Cinfo      -- ^ Source Information
        , slhs  :: !RefType    -- ^ Subtyping LHS
        , srhs  :: !RefType    -- ^ Subtyping RHS   ... senv |- slhs <: srhs
        }

-- | Wellformedness Constraints

data WfC 
  = W { wenv  :: !CGEnv      -- ^ Scope/Environment
      , winfo :: !Cinfo      -- ^ Source Information
      , wtyp  :: !RefType    -- ^ Type to be Well-formed ... wenv |- wtyp
      }

instance PP F.Reft where 
  pp = pprint

instance PP SubC where
  pp (Sub γ t t' i) = pp (renv γ)   $+$ pp (guards γ) 
                        $+$ ((text "|-") <+> (pp t $+$ text "<:" $+$ pp t'))
                        $+$ ((text "from:") <+> pp i) 

instance PP WfC where
  pp (W γ t i)      = pp (renv γ) 
                        $+$ (text "|-" <+> pp t) 
                        $+$ ((text "from:") <+> pp i) 

-- | Aliases for Fixpoint Constraints

type FixSubC = F.SubC Cinfo
type FixWfC  = F.WfC  Cinfo

------------------------------------------------------------------------
-- | Embedding Values as RefTypes --------------------------------------
------------------------------------------------------------------------

class RefTypable a where
  rType :: a -> RefType 

instance RefTypable Type where
  rType = ofType

instance RefTypable RefType where
  rType = ofType . toType           -- removes all refinements

eSingleton      :: (F.Expression e) => RefType -> e -> RefType 
eSingleton t e  = t `strengthen` (F.exprReft e)

pSingleton      :: (F.Predicate p) => RefType -> p -> RefType 
pSingleton t p  = t `strengthen` (F.propReft p)


-- eSingleton      :: (F.Expression e) => Type -> e -> RefType 
-- eSingleton t e  = (rType t) `strengthen` (F.exprReft e)
-- 
-- pSingleton      :: (F.Predicate p) => Type -> p -> RefType 
-- pSingleton t p  = (rType t) `strengthen` (F.propReft p)

shiftVVs :: (F.Symbolic x) => [RefType] -> [x] -> (F.Subst, [RefType])
shiftVVs ts xs = (su, ts')
  where 
    ts'        = F.subst su $ safeZipWith "shiftVV1" shiftVV ts xs
    su         = F.mkSubst  $ safeZipWith "shiftVV2" (\t x -> (F.symbol t, F.eVar x)) ts xs 

shiftVV t@(TApp c ts r) x = TApp c ts $ r `F.shiftVV` (F.symbol x)
shiftVV t@(TVar a r)    x = TVar a    $ r `F.shiftVV` (F.symbol x)
shiftVV t _               = t


instance (F.Reftable r) => F.Symbolic (RType r) where 
  symbol = rTypeValueVar 


------------------------------------------------------------------------------
-- | Converting RType to Fixpoint --------------------------------------------
------------------------------------------------------------------------------

rTypeSortedReft   ::  (F.Reftable r) => RType r -> F.SortedReft
rTypeSortedReft t = F.RR (rTypeSort t) (rTypeReft t)

rTypeReft         :: (F.Reftable r) => RType r -> F.Reft
rTypeReft         = fromMaybe F.top . fmap F.toReft . stripRTypeBase 

rTypeValueVar     :: (F.Reftable r) => RType r -> F.Symbol
rTypeValueVar t   = vv where F.Reft (vv,_) =  rTypeReft t 

------------------------------------------------------------------------------------------
rTypeSort :: (F.Reftable r) => RType r -> F.Sort
------------------------------------------------------------------------------------------

rTypeSort (TApp TInt [] _) = F.FInt
rTypeSort (TVar α _)       = F.FObj $ F.symbol α 
rTypeSort t@(TAll _ _)     = rTypeSortForAll t 
rTypeSort (TFun ts t)      = F.FFunc 0 $ rTypeSort <$> ts ++ [t]
rTypeSort (TApp c ts _)    = rTypeSortApp c ts 


rTypeSortApp TInt [] = F.FInt
rTypeSortApp c ts    = F.FApp (tconFTycon c) (rTypeSort <$> ts) 

tconFTycon TInt      = F.intFTyCon
tconFTycon TBool     = F.stringFTycon "boolean"
tconFTycon TVoid     = F.stringFTycon "void"
tconFTycon (TDef s)  = F.stringFTycon $ F.symbolString s


rTypeSortForAll t    = genSort n θ $ rTypeSort tbody
  where 
    (αs, tbody)      = bkAll t
    n                = length αs
    θ                = M.fromList $ zip (F.symbol <$> αs) (F.FVar <$> [0..])
    
genSort n θ (F.FFunc _ t)  = F.FFunc n (F.sortSubst θ <$> t)
genSort n θ t              = F.FFunc n [F.sortSubst θ t]

------------------------------------------------------------------------------------------
stripRTypeBase :: RType r -> Maybe r 
------------------------------------------------------------------------------------------
stripRTypeBase (TApp _ _ r) = Just r
stripRTypeBase (TVar _ r)   = Just r
stripRTypeBase _            = Nothing
 
------------------------------------------------------------------------------------------
-- | Substitutions -----------------------------------------------------------------------
------------------------------------------------------------------------------------------

instance (F.Reftable r, F.Subable r) => F.Subable (RType r) where
  syms        = foldReft (\r acc -> F.syms r ++ acc) [] 
  substa      = fmap . F.substa 
  substf f    = emapReft (F.substf . F.substfExcept f) [] 
  subst su    = emapReft (F.subst  . F.substExcept su) []
  subst1 t su = emapReft (\xs r -> F.subst1Except xs r su) [] t

------------------------------------------------------------------------------------------
-- | Traversals over @RType@ -------------------------------------------------------------
------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
emapReft  :: (F.Reftable a) => ([F.Symbol] -> a -> b) -> [F.Symbol] -> RType a -> RType b
------------------------------------------------------------------------------------------
emapReft f γ (TVar α r)    = TVar α (f γ r)
emapReft f γ (TApp c ts r) = TApp c (emapReft f γ <$> ts) (f γ r)
emapReft f γ (TAll α t)    = TAll α (emapReft f γ t)
emapReft f γ (TFun ts t)   = TFun (emapReft f γ' <$> ts) (emapReft f γ' t) where γ' = (rTypeValueVar <$> ts) ++ γ 

------------------------------------------------------------------------------------------
mapReftM :: (Monad m, Applicative m) => (a -> m b) -> RType a -> m (RType b)
------------------------------------------------------------------------------------------
mapReftM f (TVar α r)      = TVar α <$> f r
mapReftM f (TApp c ts r)   = TApp c <$> mapM (mapReftM f) ts <*> f r
mapReftM f (TFun ts t)     = TFun   <$> mapM (mapReftM f) ts <*> mapReftM f t
mapReftM f (TAll α t)      = TAll α <$> mapReftM f t

------------------------------------------------------------------------------------------
-- | fold over @RType@ -------------------------------------------------------------------
------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
foldReft  :: (F.Reftable r) => (r -> a -> a) -> a -> RType r -> a
------------------------------------------------------------------------------------------
foldReft  f = efoldReft (\_ -> ()) (\_ -> f) F.emptySEnv 

------------------------------------------------------------------------------------------
efoldReft :: (F.Reftable r) => (RType r -> b) -> (F.SEnv b -> r -> a -> a) -> F.SEnv b -> a -> RType r -> a
------------------------------------------------------------------------------------------
efoldReft _ f γ z (TVar _ r)       = f γ r z
efoldReft g f γ z t@(TApp _ ts r)  = f γ r $ efoldRefts g f (efoldExt g t γ) z ts
efoldReft g f γ z (TFun ts t)      = efoldReft g f γ' (efoldRefts g f γ' z ts) t  where γ' = foldr (efoldExt g) γ ts
efoldReft g f γ z (TAll α t)       = efoldReft g f γ z t
efoldRefts g f γ z ts              = L.foldl' (efoldReft g f γ) z ts
efoldExt g t γ                     = F.insertSEnv (rTypeValueVar t) (g t) γ

------------------------------------------------------------------------------------------
isBaseRType :: RType r -> Bool
------------------------------------------------------------------------------------------
isBaseRType (TApp c [] _) = True
isBaseRType (TVar _ _)    = True
isBaseRType _             = False

------------------------------------------------------------------------------------------
isTrivialRefType :: RefType -> Bool
------------------------------------------------------------------------------------------
isTrivialRefType t     = foldReft (\r -> (f r &&)) True t
  where 
    f (F.Reft (_,ras)) = null ras



------------------------------------------------------------------------------------------
prefixOpRTy :: PrefixOp -> CGEnv -> RefType
------------------------------------------------------------------------------------------
prefixOpRTy o g = prefixOpTy o $ renv g

------------------------------------------------------------------------------------------
infixOpRTy :: InfixOp -> CGEnv -> RefType
------------------------------------------------------------------------------------------
infixOpRTy o g = infixOpTy o $ renv g






