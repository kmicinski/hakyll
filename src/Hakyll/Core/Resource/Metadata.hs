--------------------------------------------------------------------------------
module Hakyll.Core.Resource.Metadata
    ( Metadata
    ) where


--------------------------------------------------------------------------------
import           Control.Applicative     ((<$>), (<*), (<*>))
import qualified Data.ByteString.Char8   as BC
import           Data.Map                (Map)
import qualified Data.Map                as M
import           System.FilePath         (addExtension)
import           System.IO               as IO
import           Text.Parsec             ((<?>))
import qualified Text.Parsec             as P
import           Text.Parsec.String      (Parser)


--------------------------------------------------------------------------------
import           Hakyll.Core.Resource
import           Hakyll.Core.Util.String


--------------------------------------------------------------------------------
type Metadata = Map String String


--------------------------------------------------------------------------------
loadMetadata :: Resource -> IO Metadata
loadMetadata = undefined


--------------------------------------------------------------------------------
metadataFilePath :: Resource -> FilePath
metadataFilePath = flip addExtension "metadata" . unResource


--------------------------------------------------------------------------------
loadMetadataHeader :: FilePath -> IO (Metadata, String)
loadMetadataHeader fp = do
    contents <- readFile fp
    case P.parse page fp contents of
        Left err      -> error (show err)
        Right (md, b) -> return (M.fromList md, b)


--------------------------------------------------------------------------------
loadMetadataFile :: FilePath -> IO Metadata
loadMetadataFile fp = do
    contents <- readFile fp
    case P.parse metadata fp contents of
        Left err  -> error (show err)
        Right md  -> return $ M.fromList md


--------------------------------------------------------------------------------
-- | Check if a file "probably" has a metadata header. The main goal of this is
-- to exclude binary files (which are unlikely to start with "---").
probablyHasMetadataHeader :: Resource -> IO Bool
probablyHasMetadataHeader rs = do
    handle <- IO.openFile (unResource rs) IO.ReadMode
    bs     <- BC.hGet handle 1024
    IO.hClose handle
    return $ isMetadataHeader bs
  where
    isMetadataHeader bs =
        let pre = BC.takeWhile (\x -> x /= '\n' && x /= '\r') bs
        in  BC.length pre > 3 && BC.all (== '-') pre


--------------------------------------------------------------------------------
-- | Space or tab, no newline
inlineSpace :: Parser Char
inlineSpace = P.oneOf ['\t', ' '] <?> "space"


--------------------------------------------------------------------------------
-- | Parse a single metadata field
metadataField :: Parser (String, String)
metadataField = do
    key <- P.manyTill P.alphaNum $ P.char ':'
    P.skipMany1 inlineSpace <?> "space followed by metadata for: " ++ key
    value     <- P.manyTill P.anyChar P.newline
    trailing' <- P.many trailing
    return (key, trim $ value ++ concat trailing')
  where
    trailing = (++) <$> P.many1 inlineSpace <*> P.manyTill P.anyChar P.newline


--------------------------------------------------------------------------------
-- | Parse a metadata block
metadata :: Parser [(String, String)]
metadata = P.many metadataField


--------------------------------------------------------------------------------
-- | Parse a metadata block, including delimiters and trailing newlines
metadataBlock :: Parser [(String, String)]
metadataBlock = do
    open      <- P.many1 (P.char '-') <* P.many inlineSpace <* P.newline
    metadata' <- metadata
    _         <- P.choice $ map (P.string . replicate (length open)) ['-', '.']
    P.skipMany inlineSpace
    P.skipMany1 P.newline
    return metadata'


--------------------------------------------------------------------------------
-- | Parse a page consisting of a metadata header and a body
page :: Parser ([(String, String)], String)
page = do
    metadata' <- P.option [] metadataBlock
    body      <- P.many P.anyChar
    return (metadata', body)