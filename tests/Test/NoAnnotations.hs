{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
module Test.NoAnnotations where

-- import Control.Monad.State
import Data.Algorithm.Diff
import Data.Algorithm.DiffOutput
import Data.Data (Data, toConstr, showConstr, cast)
import Data.Generics (extQ, ext1Q, ext2Q, gmapQ)
import Data.List
-- import Data.Ord (comparing)
import qualified Data.ByteString as B

import Language.Haskell.GHC.ExactPrint
-- import Language.Haskell.GHC.ExactPrint.Annotate
import Language.Haskell.GHC.ExactPrint.Parsers
import Language.Haskell.GHC.ExactPrint.Pretty
import Language.Haskell.GHC.ExactPrint.Types
import Language.Haskell.GHC.ExactPrint.Utils

import qualified ApiAnnotation as GHC
import qualified Bag           as GHC
-- import qualified DynFlags      as GHC
import qualified FastString    as GHC
import qualified GHC           as GHC hiding (parseModule)
-- import qualified Lexer         as GHC
import qualified MonadUtils    as GHC
-- import qualified Name          as GHC
import qualified NameSet       as GHC
-- import qualified OccName       as GHC
import qualified Outputable    as GHC
-- import qualified Parser        as GHC
-- import qualified RdrName       as GHC
import qualified SrcLoc        as GHC
-- import qualified StringBuffer  as GHC
import qualified Var           as GHC

import qualified OccName(occNameString)

-- import qualified Data.Generics as SYB
-- import qualified GHC.SYB.Utils as SYB


import System.Directory
import System.FilePath
-- import System.FilePath.Posix
-- import System.IO
import qualified Data.Map as Map
-- import Data.List
-- import Data.Maybe

import Test.Common

import Test.HUnit

{-# ANN module "HLint: ignore Eta reduce" #-}

-- ---------------------------------------------------------------------

noAnnotationTests :: Test
noAnnotationTests = TestLabel "no annotation tests" $ TestList
  [
    TestLabel "no annotations"
       (TestList noAnnTests)
  ]

noAnnTests :: [Test]
noAnnTests = [
  
        ]

-- ---------------------------------------------------------------------

mkPrettyRoundtrip :: FilePath -> FilePath -> Test
mkPrettyRoundtrip dir fp = mkParsingTest prettyRoundtripTest dir fp

prettyRoundtripTest :: FilePath -> IO Report
prettyRoundtripTest origFile = do
      res <- parseModuleApiAnnsWithCpp defaultCppOptions origFile
      case res of
        Left (ss, m) -> return . Left $ ParseFailure ss m
        Right (apianns, injectedComments, _dflags, parsed)  -> do
          res2 <- GHC.liftIO (runPrettyRoundTrip origFile apianns parsed injectedComments)
          case res2 of
            Left (ss, m) -> return . Left $ ParseFailure ss m
            Right (_anns', parsed') -> do
              let
                originalStructure  = astStructure parsed []
                roundtripStructure = astStructure parsed' []
                (status,debugTxt') = if roundtripStructure == originalStructure
                  then (Success, "ok")
                  else (RoundTripFailure,diffText originalStructure roundtripStructure)
                cppStatus = Nothing
                inconsistent = Nothing
                !annsOrig = relativiseApiAnnsWithComments injectedComments parsed apianns
                debugTxt = intercalate sep [ debugTxt'
                                           , originalStructure
                                           , roundtripStructure
                                           , showAnnData annsOrig 0 parsed
                                           ]
                sep = "\n=====================================\n"
              return $ Right Report {debugTxt,status,cppStatus,inconsistent}

-- ---------------------------------------------------------------------

runPrettyRoundTrip :: FilePath -> GHC.ApiAnns -> GHC.ParsedSource
                   -> [Comment]
                   -> IO (Either (GHC.SrcSpan, String)(Anns, GHC.ParsedSource))
runPrettyRoundTrip origFile !anns !parsedOrig _cs = do
  let !newAnns = addAnnotationsForPretty [] parsedOrig mempty
  let comments = case Map.lookup GHC.noSrcSpan (snd anns) of
        Nothing -> []
        Just cl -> map tokComment $ GHC.sortLocated cl
  let pragmas = filter (\(Comment c _ _) -> isPrefixOf "{-#" c ) comments
  let pragmaStr = intercalate "\n" $ map commentContents pragmas

  let !printed = pragmaStr ++ "\n" ++ exactPrint parsedOrig newAnns
  -- let !printed = pragmaStr ++ "\n" ++ (showSDoc_ $ GHC.ppr parsedOrig)

  parseString origFile printed newAnns parsedOrig


parseString :: FilePath -> String -> Anns -> GHC.ParsedSource
            -> IO (Either (GHC.SrcSpan, String) (Anns, GHC.ParsedSource))
parseString origFile src newAnns origParsed = do
  tmpDir <- getTemporaryDirectory
  let workDir = tmpDir </> "ghc-exactprint" </> "noannotations"
  -- putStrLn $ "workDir=" ++ workDir
  createDirectoryIfMissing True workDir
  let fileName = workDir </> takeFileName origFile
  writeFile (workDir </> takeFileName origFile <.> ".anns")
      (showAnnData  newAnns 0 origParsed)
  writeFile fileName src
  parseModule fileName

-- ---------------------------------------------------------------------

diffText :: String -> String -> String
diffText f1 f2 = diff
  where
    d = getGroupedDiff (lines f1) (lines f2)
    diff = ppDiff d

-- ---------------------------------------------------------------------

-- |Convert an AST with comments into a string representing the structure only
-- (i.e. ignoring locations), to be used for comparisons between the original
-- AST and the one after pretty-print roundtripping.
-- Based on @showAnnData@
astStructure :: GHC.ParsedSource -> [Comment] -> String
astStructure parsed _cs = r
  where
    r = showAstData 0 parsed



-- | Show a GHC AST with interleaved Annotation information.
showAstData :: Data a => Int -> a -> String
showAstData n =
  generic -- `ext1Q` located
          `ext1Q` list
          `extQ` string `extQ` fastString `extQ` srcSpan
          `extQ` bytestring
          `extQ` name `extQ` occName `extQ` moduleName `extQ` var `extQ` dataCon
          `extQ` overLit
          `extQ` bagName `extQ` bagRdrName `extQ` bagVar `extQ` nameSet
          `extQ` fixity
          `ext2Q` located
  where generic :: Data a => a -> String
        generic t = indent n ++ "(" ++ showConstr (toConstr t)
                 ++ space (unwords (gmapQ (showAstData (n+1)) t)) ++ ")"
        space "" = ""
        space s  = ' ':s
        indent i = "\n" ++ replicate i ' '
        string     = show :: String -> String
        fastString = ("{FastString: "++) . (++"}") . show :: GHC.FastString -> String
        bytestring = show :: B.ByteString -> String
        list l     = indent n ++ "["
                              ++ intercalate "," (map (showAstData (n+1)) l) ++ "]"

        name       = ("{Name: "++) . (++"}") . showSDocDebug_ . GHC.ppr :: GHC.Name -> String
        occName    = ("{OccName: "++) . (++"}") .  OccName.occNameString
        moduleName = ("{ModuleName: "++) . (++"}") . showSDoc_ . GHC.ppr :: GHC.ModuleName -> String

        srcSpan :: GHC.SrcSpan -> String
        srcSpan _ss = "{ "++ "ss" ++"}"

        var        = ("{Var: "++) . (++"}") . showSDocDebug_ . GHC.ppr :: GHC.Var -> String
        dataCon    = ("{DataCon: "++) . (++"}") . showSDoc_ . GHC.ppr :: GHC.DataCon -> String

        overLit :: GHC.HsOverLit GHC.RdrName -> String
        overLit    = ("{HsOverLit:"++) . (++"}") . showSDoc_ . GHC.ppr

        bagRdrName:: GHC.Bag (GHC.Located (GHC.HsBind GHC.RdrName)) -> String
        bagRdrName = ("{Bag(Located (HsBind RdrName)): "++) . (++"}") . list . GHC.bagToList
        bagName   :: GHC.Bag (GHC.Located (GHC.HsBind GHC.Name)) -> String
        bagName    = ("{Bag(Located (HsBind Name)): "++) . (++"}") . list . GHC.bagToList
        bagVar    :: GHC.Bag (GHC.Located (GHC.HsBind GHC.Var)) -> String
        bagVar     = ("{Bag(Located (HsBind Var)): "++) . (++"}") . list . GHC.bagToList

        nameSet = ("{NameSet: "++) . (++"}") . list . GHC.nameSetElems

        fixity = ("{Fixity: "++) . (++"}") . showSDoc_ . GHC.ppr :: GHC.Fixity -> String

        located :: (Data b,Data loc) => GHC.GenLocated loc b -> String
        located (GHC.L ss a) =
          indent n ++ "("
            ++ case cast ss of
                    Just (s :: GHC.SrcSpan) ->
                      srcSpan s
                    Nothing -> "nnnnnnnn"
                  ++ showAstData (n+1) a
                  ++ ")"

-- ---------------------------------------------------------------------
