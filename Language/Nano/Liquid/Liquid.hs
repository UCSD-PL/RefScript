module Language.Nano.Liquid.Liquid (main) where 

import           Control.Applicative                ((<$>), (<*>))
import           Control.Monad                
import qualified Data.HashSet as S 
import qualified Data.List as L
import           Data.Monoid
import           Data.Maybe                         (isJust, maybeToList)
import           Language.Nano.Files
import           Language.Nano.Errors
import           Language.Nano.Types

import           Language.Nano.Liquid.Types
import           Language.Nano.Liquid.Parse 
import           Language.Nano.Liquid.TCMonad
import           Language.Nano.Liquid.Substitution

import           Language.ECMAScript3.Syntax
import qualified Language.Fixpoint.Types as F
import           Language.Fixpoint.Interface        ({- checkValid,-} resultExit)
import           Language.Fixpoint.Misc             
import           Text.PrettyPrint.HughesPJ          (Doc, text, render, ($+$), (<+>))
import           Text.Printf                        (printf)
import           Language.ECMAScript3.PrettyPrint
import           Language.ECMAScript3.Parser        (parseJavaScriptFromFile)
import           System.Exit                        (exitWith)

main cfg 
  = do rs   <- mapM verifyFile $ files cfg
       let r = mconcat rs
       donePhase (F.colorResult r) (render $ pp r) 
       exitWith (resultExit r)

--------------------------------------------------------------------------------
-- | Top-level Verifier 
--------------------------------------------------------------------------------
verifyFile :: FilePath -> IO (F.FixResult SourcePos)
--------------------------------------------------------------------------------
verifyFile f 
  = do nano <- parseNanoFromFile f 
       putStrLn . render . pp $ nano
       r    <- verifyNano nano
       return r

-------------------------------------------------------------------------------
-- | Parse File and Type Signatures -------------------------------------------
-------------------------------------------------------------------------------

parseNanoFromFile :: FilePath -> IO Nano
parseNanoFromFile f 
  = do src   <- parseJavaScriptFromFile f
       spec  <- parseSpecFromFile f
       ispec <- parseSpecFromFile =<< getPreludePath
       return $ either err id (mkNano src (spec `mappend` ispec))
    where 
       err m  = errortext $ text ("Invalid Input file: " ++ f) $+$ m

-------------------------------------------------------------------------------
-- | Execute Type Checker -----------------------------------------------------
-------------------------------------------------------------------------------

verifyNano  :: Nano -> IO (F.FixResult SourcePos)
verifyNano  = either unsafe safe . execute . tcNano 
    
unsafe errs = do putStrLn "\n\n\nErrors Found!\n\n" 
                 forM_ errs $ \(loc, err) -> putStrLn $ printf "Error at %s\n  %s\n" (ppshow loc) err
                 return $ F.Unsafe (fst <$> errs)
    
safe _      = return F.Safe 

-------------------------------------------------------------------------------
-- | Type Check Environment ---------------------------------------------------
-------------------------------------------------------------------------------

--   We define this alias as the "output" type for typechecking any entity
--   that can create or affect binders (e.g. @VarDecl@ or @Statement@)
--   @Nothing@ means if we definitely hits a "return" 
--   @Just γ'@ means environment extended with statement binders

type TCEnv = Maybe (Env Type)

-------------------------------------------------------------------------------
-- | TypeCheck Nano Program ---------------------------------------------------
-------------------------------------------------------------------------------

tcNano     :: Nano -> TCM () 
tcNano pgm = forM_ fs $ tcFun γ0
  where
    γ0     = env pgm
    Src fs = code pgm

-------------------------------------------------------------------------------
-- | TypeCheck Function -------------------------------------------------------
-------------------------------------------------------------------------------

tcFun    :: Env Type -> FunctionStatement -> TCM ()
tcFun γ (FunctionStmt l f xs body) 
  = do γ' <- funEnv l γ f xs
       q  <- tcStmts γ' body
       maybe (return ()) (\_ -> assertTy l "Missing return" f tVoid (envFindReturn γ')) q

funEnv l γ f xs
  = case bkFun =<< envFindTy f γ of
      Nothing        -> tcError l $ errorNonFunction f
      Just (αs,ts,t) -> if length xs /= length ts 
                         then tcError l $ errorArgMismatch  
                         else return    $ envAddFun l f αs xs ts t γ

envAddFun l f αs xs ts t = envAdds tyBinds . envAdds varBinds . envAddReturn f t 
  where  
    tyBinds              = [(Loc l α, tVar α) | α <- αs]
    varBinds             = zip xs ts

--------------------------------------------------------------------------------
tcSeq :: (Env Type -> a -> TCM TCEnv) -> Env Type -> [a] -> TCM TCEnv
--------------------------------------------------------------------------------

tcSeq tc            = foldM step . Just 
  where 
    step Nothing _  = return Nothing
    step (Just γ) x = tc γ x

--------------------------------------------------------------------------------
tcStmts :: Env Type -> [Statement SourcePos]  -> TCM TCEnv
--------------------------------------------------------------------------------

tcStmts = tcSeq tcStmt

-------------------------------------------------------------------------------
tcStmt :: Env Type -> Statement SourcePos  -> TCM TCEnv  
-------------------------------------------------------------------------------

-- skip
tcStmt γ (EmptyStmt _) 
  = return $ Just γ

-- x = e
tcStmt γ (ExprStmt _ (AssignExpr l OpAssign (LVar lx x) e))   
  = tcAsgn γ l (Id lx x) e

-- e
tcStmt γ (ExprStmt _ e)   
  = tcExpr γ e >> return (Just γ) 

-- s1;s2;...;sn
tcStmt γ (BlockStmt _ stmts) 
  = tcStmts γ stmts 

-- if b { s1 }
tcStmt γ (IfSingleStmt l b s)
  = tcStmt γ (IfStmt l b s (EmptyStmt l))

-- if b { s1 } else { s2 }
tcStmt γ (IfStmt l e s1 s2)
  = do t     <- tcExpr γ e
       assertTy l "If condition" e t tBool
       γ1    <- tcStmt γ s1
       γ2    <- tcStmt γ s2
       envJoin l γ1 γ2

-- var x1 [ = e1 ]; ... ; var xn [= en];
tcStmt γ (VarDeclStmt _ ds)
  = tcSeq tcVarDecl γ ds

-- return e 
tcStmt γ (ReturnStmt l eo) 
  = do t  <- maybe (return tVoid) (tcExpr γ) eo 
       assertTy l "Return" eo t (envFindReturn γ) 
       return Nothing

-- OTHER (Not handled)
tcStmt γ s 
  = convertError "tcStmt" s

-------------------------------------------------------------------------------
tcVarDecl :: Env Type -> VarDecl SourcePos -> TCM TCEnv  
-------------------------------------------------------------------------------

tcVarDecl γ (VarDecl l x (Just e)) 
  = tcAsgn γ l x e  
tcVarDecl γ (VarDecl l x Nothing)  
  = return $ Just γ

------------------------------------------------------------------------------------
tcAsgn :: Env Type -> SourcePos -> Id SourcePos -> Expression SourcePos -> TCM TCEnv
------------------------------------------------------------------------------------

tcAsgn γ l x e 
  = do t <- tcExpr γ e
       return $ Just $ envAdd x t γ

-------------------------------------------------------------------------------
tcExpr :: Env Type -> Expression SourcePos -> TCM Type
-------------------------------------------------------------------------------

tcExpr _ (IntLit _ _)               
  = return tInt 

tcExpr _ (BoolLit _ _)
  = return tBool

tcExpr γ (VarRef l x)
  = maybe (tcError l $ errorUnboundId x) return $ envFindTy x γ

tcExpr γ (PrefixExpr l o e)
  = tcCall γ l o [e] (prefixOpTy o)

tcExpr γ (InfixExpr l o e1 e2)        
  = tcCall γ l o  [e1, e2] (infixOpTy o)

tcExpr γ (CallExpr l e es)
  = tcCall γ l e es =<< tcExpr γ e 

tcExpr γ e 
  = convertError "tcExpr" e

----------------------------------------------------------------------------------
-- tcCall :: Env Type -> SourcePos -> Type -> [Expression SourcePos] -> TCM Type
----------------------------------------------------------------------------------

tcCall γ l z es ft 
  = do t' <- instantiate $ bkAll ft 
       case bkFun t' of
         Nothing         -> logError tErr l $ errorNonFunction z
         Just (_,its,ot) -> do ua <- unifyArgs l γ es its 
                               case ua of 
                                 Nothing -> return tErr
                                 Just θ' -> return $ apply θ' ot

instantiate (αs, t) = do θ  <- fromList . zip αs . fmap tVar <$> fresh αs
                         return $ tracePP msg $ apply (tracePP "theta" θ) t
                      where 
                        msg = printf "instantiate [αs = %s] [t = %s] " (ppshow αs) (ppshow t)

unifyArgs l γ es ts 
  = if length es /= length ts 
      then logError Nothing l errorArgMismatch 
      else do tes <- mapM (tcExpr γ) es
              case unifys mempty ts tes of
                Left msg -> logError Nothing l msg
                Right θ  -> validSubst l γ $ tracePP "unifyArgs" θ

validSubst       :: SourcePos -> Env Type -> Subst -> TCM (Maybe Subst)
validSubst l γ θ = do oks   <- mapM (validTyBind l γ) (toList θ)
                      return $ if and oks then Just θ else Nothing

validTyBind l γ (α, t) 
  | bad1      = logError False l $ errorBoundTyVar α t 
  | bad2      = logError False l $ errorFreeTyVar t
  | otherwise = return True 
  where
    bad1      = envMem α γ                                  -- dom θ        \cap γ = empty 
    bad2      = not $ all (`envMem` γ) $ S.toList $ free t  -- free (rng θ) \subset γ

----------------------------------------------------------------------------------
envJoin :: SourcePos -> TCEnv -> TCEnv -> TCM TCEnv 
----------------------------------------------------------------------------------

envJoin _ Nothing x           = return x
envJoin _ x Nothing           = return x
envJoin l (Just γ1) (Just γ2) = envJoin' l γ1 γ2 

envJoin' l γ1 γ2  = forM_ ytts err >> return (Just (envFromList zts))  
  where 
    zts          = [(x,t)    | (x,t,t') <- xtts, t == t']
    ytts         = [(y,t,t') | (y,t,t') <- xtts, t /= t']
    xtts         = [(x,t,t') | (x,t)    <- envToList γ1, t' <- maybeToList (F.lookupSEnv x γ2)]
    err (y,t,t') = logError () l $ errorJoin y t t'

---------------------------------------------------------------------------------------
-- | Error Messages -------------------------------------------------------------------
---------------------------------------------------------------------------------------

assertTy l m e t t'     = when (t /= t') $ logError () l $ errorWrongType m e t t'

