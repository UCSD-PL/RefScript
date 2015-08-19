{-# LANGUAGE DeriveDataTypeable   #-}
{-# LANGUAGE DeriveFunctor        #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverlappingInstances #-}

module Language.Nano.Annots (

  -- * SSA
    SsaInfo(..), Var

  -- * Annotations
  , NodeId, Annot (..), UFact, FactQ (..), Fact, phiVarsAnnot, MemberMod (..)

  , SyntaxKind(..), MemberKind(..)

  , scrapeVarDecl

  -- * Casts
  , CastQ(..), Cast, SubTRes(..), castType

  -- * Aliases for annotated Source
  , AnnQ, AnnR, AnnRel, AnnBare, UAnnBare, AnnSSA , UAnnSSA
  , AnnType, UAnnType, AnnInfo, UAnnInfo

  -- Options
  , RscOption (..)

) where

import           Data.Default
import           Data.Generics
import qualified Data.IntMap.Strict            as I
import           Data.Monoid
import           Language.Fixpoint.Errors
import qualified Language.Fixpoint.Types       as F
import           Language.Nano.AST
import           Language.Nano.Names
import           Language.Nano.Typecheck.Types
import           Language.Nano.Types


-----------------------------------------------------------------------------
-- | Casts
-----------------------------------------------------------------------------

data CastQ q r = CNo                                            -- .
               | CDead { err :: [Error]   , tgt :: RTypeQ q r } -- |dead code|
               | CUp   { org :: RTypeQ q r, tgt :: RTypeQ q r } -- <t1 UP t2>
               | CDn   { org :: RTypeQ q r, tgt :: RTypeQ q r } -- <t1 DN t2>
               deriving (Data, Typeable, Functor)

type Cast  = CastQ AK   -- Version with absolute types

castType CNo = tNull
castType c   = tgt c


data SubTRes = EqT              -- .
             | SubErr  [Error]   -- |dead code|
             | SubT              -- <UP>
             | SupT              -- <DN>
             deriving (Eq, Ord, Show, Data, Typeable)

instance Monoid SubTRes where
 mempty                          = EqT
 mappend (SubErr e1) (SubErr e2) = SubErr $ e1 ++ e2
 mappend _           (SubErr e2) = SubErr e2
 mappend (SubErr e1) _           = SubErr e1
 mappend SubT        SupT        = SubErr []
 mappend SupT        SubT        = SubErr []
 mappend SupT        _           = SupT
 mappend _           SupT        = SupT
 mappend SubT        _           = SubT
 mappend _           SubT        = SubT
 mappend EqT        EqT          = EqT


-----------------------------------------------------------------------------
-- | Facts
-----------------------------------------------------------------------------

data FactQ q r
  -- SSA
  = PhiVar        [Var r]
  | PhiVarTC      (Var r)
  | PhiVarTy      (Var r, RTypeQ q r)
  | PhiPost       [(Var r, Var r, Var r)]

  -- Unification
  | TypInst       Int IContext [RTypeQ q r]

  -- Overloading
  | EltOverload   IContext (MethodInfoQ q r)
  | Overload      IContext (RTypeQ q r)

  -- Type annotations
  | VarAnn        Assignability (Maybe (RTypeQ q r))
  | AmbVarAnn     (RTypeQ q r)

  -- Class member annotations
  | FieldAnn      [MemberMod] (RTypeQ q r)
  | MethAnn       [MemberMod] (RTypeQ q r)
  | ConsAnn       (RTypeQ q r)

  | UserCast      (RTypeQ q r)
  | FuncAnn       (RTypeQ q r)
  | TCast         IContext (CastQ q r)

  -- Named type annotation
  | ClassAnn      (TypeSigQ q r)
  | InterfaceAnn  (TypeDeclQ q r)

  | ExportedElt
  | ReadOnlyVar
  | ModuleAnn     (F.Symbol)
  | EnumAnn       (F.Symbol)

  -- Auxiliary
  | BypassUnique
    deriving (Data, Typeable)

data MemberMod = Optional | Private | MM MutabilityMod
                 deriving ( Eq, Data, Typeable )
type Fact      = FactQ AK
type UFact     = Fact ()

type NodeId    = Int

data Annot b a = Ann { ann_id   :: NodeId
                     , ann      ::  a
                     , ann_fact :: [b] } deriving (Show, Data, Typeable)

type AnnQ q  r = Annot (FactQ q r) SrcSpan
type AnnR    r = AnnQ AK r                      -- absolute paths,
type AnnRel  r = AnnQ RK r                      -- relative paths, NO facts, parsed versioin
type AnnBare r = AnnR r                         -- absolute paths, NO facts
type AnnSSA  r = AnnR r                         -- absolute paths, Phi facts
type AnnType r = AnnR r                         -- absolute paths, Phi + t. annot. + Cast facts
type AnnInfo r = I.IntMap [Fact r]

type UAnnBare  = AnnBare ()
type UAnnSSA   = AnnSSA  ()
type UAnnType  = AnnType ()
type UAnnInfo  = AnnInfo ()


newtype SsaInfo r = SI (Var r) deriving (Ord, Typeable, Data)

instance Eq (SsaInfo r) where
  SI i1 == SI i2 =  i1 == i2

type Var r = Id (AnnSSA r)


instance Annotated (Annot b) where
  getAnnotation = ann

instance Default a => Default (Annot b a) where
  def = Ann def def []

instance Ord (AnnSSA  r) where
  compare (Ann i1 s1 _) (Ann i2 s2 _) = compare (i1,s1) (i2,s2)

instance Eq (Annot a SrcSpan) where
  (Ann i1 s1 _) == (Ann i2 s2 _) = (i1,s1) == (i2,s2)


phiVarsAnnot l = concat [xs | PhiVar xs <- ann_fact l]


-- | scrapeVarDecl: Scrape a variable declaration for annotations
----------------------------------------------------------------------------------
scrapeVarDecl :: VarDecl (AnnSSA r) -> [(SyntaxKind, Assignability, Maybe (RType r))]
----------------------------------------------------------------------------------
scrapeVarDecl (VarDecl l _ _)
  = [ (VarDeclKind, a, t) | VarAnn a t <- ann_fact l ]
 ++ [ (AmbVarDeclKind, Ambient, Just t) | AmbVarAnn t <- ann_fact l ]
 ++ [ (FieldDefKind, Ambient, Just t) | FieldAnn _ t <- ann_fact l ] -- Assignability value is dummy


-----------------------------------------------------------------------------
-- | RSC Options
-----------------------------------------------------------------------------

data RscOption = RealOption
    deriving (Eq, Show, Data, Typeable)

