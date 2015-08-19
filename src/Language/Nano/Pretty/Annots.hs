{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverlappingInstances #-}

module Language.Nano.Pretty.Annots where

import           Control.Applicative         ((<$>))
import qualified Data.IntMap.Strict          as I
import           Language.Fixpoint.Misc
import qualified Language.Fixpoint.Types     as F
import           Language.Nano.Annots
import           Language.Nano.Pretty.Common
import           Language.Nano.Pretty.Errors ()
import           Language.Nano.Pretty.Types  ()
import           Language.Nano.Types
import           Prelude                     hiding (maybe)
import           Text.PrettyPrint.HughesPJ

instance (PP r, F.Reftable r) => PP (Cast r) where
  pp CNo         = text "No cast"
  pp (CDead e t) = text "Dead code:" <+> pp e <+> text "::" <+> pp t
  pp (CUp t1 t2) = text "<" <+> pp t1 <+> text "UP" <+> pp t2 <+> text ">"
  pp (CDn t1 t2) = text "<" <+> pp t1 <+> text "DN" <+> pp t2 <+> text ">"

instance PP SubTRes where
  pp EqT        = text "="
  pp (SubErr _) = text "dead"
  pp SubT       = text "UP"
  pp SupT       = text "DN"

instance PP (SsaInfo r) where
  pp (SI i) =  pp $ fmap (const ()) i

instance (F.Reftable r, PP r) => PP (Fact r) where
  pp (PhiVar x)                 = text "phi"             <+> pp x
  pp (PhiVarTy x)               = text "phi-ty"          <+> pp x
  pp (PhiVarTC x)               = text "phi-tc"          <+> pp x
  pp (PhiPost _)                = text "phi-post"
  pp (TypInst i ξ ts)           = text "inst"            <+> pp i <+> pp ξ <+> pp ts
  pp (Overload ξ i)             = text "overload"        <+> pp ξ <+> pp i
  pp (EltOverload ξ (MI _ _ t)) = text "elt_overload"    <+> pp ξ <+> pp t
  pp (TCast  ξ c)               = text "cast"            <+> pp ξ <+> pp c
  pp (VarAnn _ t)               = text "Var Ann"         <+> pp t
  pp (AmbVarAnn t)              = text "Amb Var Ann"     <+> pp t
  pp (ConsAnn c)                = text "Ctor Ann"        <+> pp c
  pp (UserCast c)               = text "Cast Ann"        <+> pp c
  pp (ExportedElt)              = text "Exported"
  pp (ReadOnlyVar)              = text "ReadOnlyVar"
  pp (FuncAnn t)                = text "Func Ann"        <+> pp t
  pp (FieldAnn _ t)             = text "Field Ann"       <+> pp t
  pp (MethAnn _ t)              = text "Method Ann"      <+> pp t
  pp (InterfaceAnn _)           = text "UNIMPLEMENTED:pp:InterfaceAnn"
  pp (ClassAnn _)               = text "UNIMPLEMENTED:pp:ClassAnn"
  pp (ModuleAnn s)              = text "module"          <+> pp s
  pp (EnumAnn s)                = text "enum"            <+> pp s
  pp (BypassUnique)             = text "BypassUnique"

instance (F.Reftable r, PP r) => PP (AnnInfo r) where
  pp             = vcat . (ppB <$>) . I.toList
    where
      ppB (x, t) = pp x <+> dcolon <+> pp t

instance (PP a, PP b) => PP (Annot b a) where
  pp (Ann _ x ys) = text "Annot: " <+> pp x <+> pp ys

instance PP SyntaxKind where
  pp FuncDefKind      = text "FuncDefKind"
  pp FuncOverloadKind = text "FuncOverloadKind"
  pp FuncAmbientKind  = text "FuncAmbientKind"
  pp MethDefKind      = text "MethDefKind"
  pp MethDeclKind     = text "MethDeclKind"
  pp FieldDefKind     = text "FieldDefKind"
  pp CtorDefKind      = text "CtorDefKind"
  pp VarDeclKind      = text "VarDeclKind"
  pp ClassDefKind     = text "ClassDefKind"
  pp ModuleDefKind    = text "ModuleDefKind"
  pp EnumDefKind      = text "EnumDefKind"
  pp AmbVarDeclKind   = text "AmbVarDeclKind"

