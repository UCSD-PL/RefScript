{-# LANGUAGE ScopedTypeVariables #-}

import qualified Language.Nano.Typecheck.Typecheck  as TC 
import qualified Language.Nano.Liquid.Liquid        as LQ
import qualified Language.Nano.Liquid.Types         as L 

import           Language.Nano.CmdLine              (getOpts)
import           Language.Nano.Errors
import           Language.Nano.Types
import           Language.Nano.Annots
import           Control.Exception                  (catch)
import           Data.Monoid
import           System.Exit
import           System.Directory                   (createDirectoryIfMissing)
import           System.Process
import           System.FilePath.Posix
import           Language.Fixpoint.Interface        (resultExit)
import qualified Language.Fixpoint.Types as F
import           Language.Fixpoint.Misc             
import           Language.Fixpoint.Errors
import           Language.Fixpoint.Files
-- import           Text.PrettyPrint.HughesPJ          (Doc, text, render, ($+$), (<+>))
import           Text.PrettyPrint.HughesPJ          (render)
import           Language.ECMAScript3.PrettyPrint
import qualified Data.ByteString.Lazy               as B

main = do cfg  <- getOpts
          run (verifier cfg) cfg
    
-------------------------------------------------------------------------------
verifier           :: Config -> FilePath -> IO (UAnnSol L.RefType, F.FixResult Error)
-------------------------------------------------------------------------------
verifier (TC     {} ) f = TC.verifyFile =<< json f
verifier (Liquid {} ) f = LQ.verifyFile =<< json f

json :: FilePath -> IO FilePath
json f | ext == ".json" = return f
       | ext == ".ts"   = execCmd  (tsCmd ++ f) >> return (toJSONExt f)
       | otherwise      = error $ "Unsupported input file format: " ++ ext
  where ext             = takeExtension f
        toJSONExt       = (`addExtension` ".json") . dropExtension
        tsCmd           = "tsc --nano "

run verifyFile cfg 
  = do mapM_ (createDirectoryIfMissing False) $ map tmpDir $ files cfg
       rs   <- mapM (runOne verifyFile) $ files cfg
       let r = mconcat rs
       donePhaseWithOptStars False (F.colorResult r) (render $ pp r) 
       exitWith (resultExit r)
    where
       tmpDir    = tempDirectory

runOne verifyFile f 
  = do createDirectoryIfMissing False tmpDir
       (u, r) <- verifyFile f `catch` handler 
       renderAnnotations f r u
       return r
    where
       handler e = return (NoAnn, F.Crash [e] "") 
       tmpDir    = tempDirectory f

execCmd cmd               = putStrLn ("EXEC: " ++ cmd) >> system cmd >>= check
  where 
    check (ExitSuccess)   = return ()
    check (ExitFailure n) = error $ "cmd: " ++ cmd ++ " failure code " ++ show n 

----------------------------------------------------------------------------------
renderAnnotations :: PP t => FilePath -> F.FixResult Error -> UAnnSol t -> IO () 
----------------------------------------------------------------------------------
renderAnnotations srcFile res (NoAnn :: UAnnSol t)
  = do B.writeFile jsonFile    $ annotByteString res (mempty :: UAnnInfo t) 
       writeFile   vimFile     $ annotVimString res (mempty :: UAnnInfo t) 
    where 
       jsonFile = extFileName Json  srcFile
       vimFile  = extFileName Annot (srcFile ++ ".vim")
    
renderAnnotations srcFile res (SomeAnn ann sol)
  = do writeFile   annFile  $ wrapStarsWithOptStars False "Constraint Templates" ++ "\n" 
       appendFile  annFile  $ ppshow ann
       appendFile  annFile  $ wrapStarsWithOptStars False "Inferred Types"       ++ "\n" 
       appendFile  annFile  $ ppshow ann'
       B.writeFile jsonFile $ annotByteString res ann' 
       writeFile   vimFile  $ annotVimString res ann'
       donePhaseWithOptStars False Loud "Written Inferred Annotations"
    where 
       jsonFile = extFileName Json  srcFile
       vimFile  = extFileName Annot (srcFile ++ ".vim")
       annFile  = extFileName Annot srcFile
       ann'     = sol ann

