{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}
-- | An interface to bitcoind's available wallet-related RPC calls.
--   The implementation of these functions can be found at
--   <https://github.com/bitcoin/bitcoin/blob/master/src/rpcwallet.cpp>.
--
--   If any APIs are missing, patches are always welcome. If you look at the
--   source of this module, you'll see that the interface code is trivial.
--
--   Certain APIs were too complicated for me to write an interface for. If
--   you figure them out, then patches are always welcome! They're left in
--   the source as comments.
module Network.Bitcoin.Wallet ( Auth(..)
                              , BitcoindInfo(..)
                              , getBitcoindInfo
                              , getNewAddress
                              , getAccountAddress
                              , getAccount
                              , setAccount
                              , getAddressesByAccount
                              , sendToAddress
                              , AddressInfo(..)
                              , listAddressGroupings
                              , Signature
                              , signMessage
                              , verifyMessage
                              , getReceivedByAddress
                              , getReceivedByAddress'
                              , getReceivedByAccount
                              , getReceivedByAccount'
                              , getBalance
                              , getBalance'
                              , getBalance''
                              , moveBitcoins
                              , sendFromAccount
                              , sendMany
                              -- , createMultiSig
                              , ReceivedByAddress(..)
                              , listReceivedByAddress
                              , listReceivedByAddress'
                              , ReceivedByAccount(..)
                              , listReceivedByAccount
                              , listReceivedByAccount'
                              , listTransactions
                              , listTransactions'
                              , listAccounts
                              , SinceBlock(..)
                              , SimpleTransaction(..)
                              , TransactionCategory(..)
                              , listSinceBlock
                              , listSinceBlock'
                              , DetailedTransaction(..)
                              , DetailedTransactionDetails(..)
                              , getTransaction
                              , backupWallet
                              , keyPoolRefill
                              , unlockWallet
                              , lockWallet
                              , changePassword
                              , encryptWallet
                              , isAddressValid
                              ) where

import Control.Applicative
import Control.Monad
import Data.Aeson as A
import qualified Data.HashMap.Lazy as HM
import Data.Maybe
import Data.Text
import Data.Time.Clock.POSIX
import Data.Vector as V hiding ((++))
import Network.Bitcoin.BlockChain (BlockHash)
import Network.Bitcoin.Internal
import Network.Bitcoin.RawTransaction (RawTransaction)

-- | A plethora of information about a bitcoind instance.
data BitcoindInfo =
    BitcoindInfo {
                 -- | What version of bitcoind are we running?
                   bitcoinVersion :: Integer
                 -- | What is bitcoind's current protocol number?
                 , protocolVersion :: Integer
                 -- | What version is the wallet?
                 , walletVersion :: Integer
                 -- | How much money is currently in the wallet?
                 , balance :: BTC
                 -- | The number of blocks in our chain.
                 , numBlocks :: Integer
                 -- | How many peers are we connected to?
                 , numConnections :: Integer
                 -- | A blank string if we're not using a proxy.
                 , proxy :: Text
                 -- | The difficulty multiplier for bitcoin mining operations.
                 , generationDifficulty :: Double
                 -- | Are we on the test network (as opposed to the primary
                 --   bitcoin network)?
                 , onTestNetwork :: Bool
                 -- | The timestamp of the oldest key in the key pool.
                 , keyPoolOldest :: Integer
                 -- | The size of the key pool.
                 , keyPoolSize :: Integer
                 -- | How much do we currently pay as a transaction fee?
                 , transactionFeePaid :: BTC
                 -- | If the wallet is unlocked, the number of seconds until a
                 --   re-lock is needed.
                 , unlockedUntil :: Maybe Integer
                 -- | Any alerts will show up here. This should normally be an
                 --   empty string.
                 , bitcoindErrors :: Text
                 }
    deriving ( Show, Read, Ord, Eq )

instance FromJSON BitcoindInfo where
    parseJSON (Object o) = BitcoindInfo <$> o .:  "version"
                                        <*> o .:  "protocolversion"
                                        <*> o .:  "walletversion"
                                        <*> o .:  "balance"
                                        <*> o .:  "blocks"
                                        <*> o .:  "connections"
                                        <*> o .:  "proxy"
                                        <*> o .:  "difficulty"
                                        <*> o .:  "testnet"
                                        <*> o .:  "keypoololdest"
                                        <*> o .:  "keypoolsize"
                                        <*> o .:  "paytxfee"
                                        <*> o .:? "unlocked_until"
                                        <*> o .:  "errors"
    parseJSON _ = mzero

-- | Returns an object containing various state info.
getBitcoindInfo :: Auth -> IO BitcoindInfo
getBitcoindInfo auth = callApi auth "getinfo" []

-- | Returns a new bitcoin address for receiving payments.
--
--   If an account is specified (recommended), the new address is added to the
--   address book so payments received with the address will be credited to the
--   given account.
--
--   If no account is specified, the address will be credited to the account
--   whose name is the empty string. i.e. the default account.
getNewAddress :: Auth -> Maybe Account -> IO Address
getNewAddress auth ma = let acc = fromMaybe "" ma
                         in callApi auth "getnewaddress" [ tj acc ]

-- | Returns the current Bitcoin address for receiving payments to the given
--   account.
getAccountAddress :: Auth -> Account -> IO Address
getAccountAddress auth acc = callApi auth "getaccountaddress" [ tj acc ]

-- | Sets the account associated with the given address.
setAccount :: Auth -> Address -> Account -> IO ()
setAccount auth addr acc = unNil <$> callApi auth "setaccount" [ tj addr, tj acc ]

-- | Returns the account associated with the given address.
getAccount :: Auth -> Address -> IO Account
getAccount auth addr = callApi auth "getaccount" [ tj addr ]

-- | Returns the list of addresses for the given address.
getAddressesByAccount :: Auth -> Account -> IO (Vector Address)
getAddressesByAccount auth acc = callApi auth "getaddressesbyaccount" [ tj acc ]

-- | Sends some bitcoins to an address.
sendToAddress :: Auth
              -> Address
              -- ^ Who we're sending to.
              -> BTC
              -- ^ The amount to send.
              -> Maybe Text
              -- ^ An optional comment for the transaction.
              -> Maybe Text
              -- ^ An optional comment-to (who did we sent this to?) for the
              --   transaction.
              -> IO TransactionID
sendToAddress auth addr amount comm comm2 =
    callApi auth "sendtoaddress" [ tj addr, tj amount, tj comm, tj comm2 ]

-- | Information on a given address.
data AddressInfo = AddressInfo { -- | The address in question.
                                 aiAddress :: Address
                               -- | The address' balance.
                               , aiAmount  :: BTC
                               -- | The address' linked account.
                               , aiAccount :: Maybe Account
                               }
    deriving ( Show, Read, Eq, Ord )

-- | What a silly API.
instance FromJSON AddressInfo where
    parseJSON (A.Array a) | V.length a == 2 = AddressInfo <$> parseJSON (a ! 0)
                                                          <*> parseJSON (a ! 1)
                                                          <*> pure Nothing
                          | V.length a == 3 = AddressInfo <$> parseJSON (a ! 0)
                                                          <*> parseJSON (a ! 1)
                                                          <*> (Just <$> parseJSON (a ! 2))
                          | otherwise       = mzero
    parseJSON _ = mzero

-- | Lists groups of addresses which have had their common ownership made
--   public by common use as inputs or as the resulting change in past
--   transactions.
listAddressGroupings :: Auth
                     -> IO (Vector (Vector AddressInfo))
listAddressGroupings auth =
    callApi auth "listaddressgroupings" []

-- | A signature is a base-64 encoded string.
type Signature = HexString

-- | Sign a message with the private key of an address.
signMessage :: Auth
            -> Address
            -- ^ The address whose private key we'll use.
            -> Text
            -- ^ The message to sign.
            -> IO Signature
signMessage auth addr msg = callApi auth "signmessage" [ tj addr, tj msg ]

-- | Verifies a signed message.
verifyMessage :: Auth
              -> Address
              -- ^ The address of the original signer.
              -> Signature
              -- ^ The message's signature.
              -> Text
              -- ^ The message.
              -> IO Bool
              -- ^ Was the signature valid?
verifyMessage auth addr sig msg =
    callApi auth "verifymessage" [ tj addr, tj sig, tj msg ]

-- | Returns the total amount received by the given address with at least one
--   confirmation.
getReceivedByAddress :: Auth -> Address -> IO BTC
getReceivedByAddress auth addr =
    callApi auth "getreceivedbyaddress" [ tj addr ]

-- | Returns the total amount received by the given address, with at least the
--   give number of confirmations.
getReceivedByAddress' :: Auth
                      -> Address
                      -> Int -- ^ The minimum number of confirmations needed
                             --   for a transaction to to count towards the
                             --   total.
                      -> IO BTC
getReceivedByAddress' auth addr minconf =
    callApi auth "getreceivedbyaddress" [ tj addr, tj minconf ]

-- | Returns the total amount received by address with the given account.
getReceivedByAccount :: Auth -> Account -> IO BTC
getReceivedByAccount auth acc =
    callApi auth "getreceivedbyaccount" [ tj acc ]

-- | Returns the total amount received by addresses with the given account,
--   counting only transactions with the given minimum number of confirmations.
getReceivedByAccount' :: Auth
                      -> Account
                      -- ^ The account in question.
                      -> Int
                      -- ^ The minimum number of confirmations needed for a
                      --   transaction to count towards the total.
                      -> IO BTC
getReceivedByAccount' auth acc minconf =
    callApi auth "getreceivedbyaccount" [ tj acc, tj minconf ]

-- | Returns the server's total available balance.
getBalance :: Auth
           -> IO BTC
getBalance auth =
    callApi auth "getbalance" []

-- | Returns the balance in the given account, counting only transactions with
--   at least one confirmation.
getBalance' :: Auth
            -> Account
            -> IO BTC
getBalance' auth acc =
    callApi auth "getbalance" [ tj acc ]

-- | Returns the balance in the given account, counting only transactions with
--   at least the given number of confirmations.
getBalance'' :: Auth
             -> Account
             -> Int
             -- ^ The minimum number of confirmations needed for a transaction
             --   to count towards the total.
             -> IO BTC
getBalance'' auth acc minconf =
    callApi auth "getbalance" [ tj acc, tj minconf ]

-- | Move bitcoins from one account in your wallet to another.
--
--   If you want to send bitcoins to an address not in your wallet, use
--   'sendFromAccount'.
moveBitcoins :: Auth
             -> Account -- ^ From.
             -> Account -- ^ To.
             -> BTC     -- ^ The amount to transfer.
             -> Text    -- ^ A comment to record for the transaction.
             -> IO ()
moveBitcoins auth from to amt comm =
    stupidAPI <$> callApi auth "move" [ tj from, tj to, tj amt, tj one, tj comm ]
        where one = 1 :: Int -- needs a type, else default-integer warnings.
              stupidAPI :: Bool -> ()
              stupidAPI = const ()

-- | Sends bitcoins from a given account in our wallet to a given address.
--
--   A transaction and sender comment may be optionally provided.
sendFromAccount :: Auth
                -> Account
                -- ^ The account to send from.
                -> Address
                -- ^ The address to send to.
                -> BTC
                -- ^ The amount to send.
                -> Maybe Text
                -- ^ An optional transaction comment.
                -> Maybe Text
                -- ^ An optional comment on who the money is going to.
                -> IO TransactionID
sendFromAccount auth from to amount comm comm2 =
    callApi auth "sendfrom" [ tj from, tj to, tj amount, tj one, tj comm, tj comm2 ]
        where one = 1 :: Int -- needs a type, else default-integer warnings.

-- | Send to a whole bunch of address at once.
sendMany :: Auth
         -> Account
         -- ^ The account to send from.
         -> Vector (Address, BTC)
         -- ^ The address, and how much to send to each one.
         -> Maybe Text
         -- ^ An optional transaction comment.
         -> IO TransactionID
sendMany auth acc amounts comm =
    callApi auth "sendmany" [ tj acc, tj $ AA amounts, tj comm ]

-- TODO: createmultisig.
--
--       I have no idea what this is doing. Patches adding this function are
--       always welcome!

-- | Information on how much was received by a given address.
data ReceivedByAddress =
    ReceivedByAddress { -- | The address which the money was deposited to.
                        recvAddress :: Address
                      -- | The account which this address belongs to.
                      , recvAccount :: Account
                      -- | The amount received.
                      , recvAmount  :: BTC
                      -- | The number of confirmations of the most recent
                      --   included transaction.
                      , recvNumConfirmations :: Integer
                      }
    deriving ( Show, Read, Ord, Eq )

instance FromJSON ReceivedByAddress where
    parseJSON (Object o) = ReceivedByAddress <$> o .: "address"
                                             <*> o .: "account"
                                             <*> o .: "amount"
                                             <*> o .: "confirmations"
    parseJSON _ = mzero

-- | Lists the amount received by each address which has received money at some
--   point, counting only transactions with at least one confirmation.
listReceivedByAddress :: Auth -> IO (Vector ReceivedByAddress)
listReceivedByAddress auth = listReceivedByAddress' auth 1 False

-- | List the amount received by each of our addresses, counting only
--   transactions with the given minimum number of confirmations.
listReceivedByAddress' :: Auth
                       -> Int
                       -- ^ The minimum number of confirmations before a
                       --   transaction counts toward the total amount
                       --   received.
                       -> Bool
                       -- ^ Should we include addresses with no money
                       --   received?
                       -> IO (Vector ReceivedByAddress)
listReceivedByAddress' auth minconf includeEmpty =
    callApi auth "listreceivedbyaddress" [ tj minconf, tj includeEmpty ]

data ReceivedByAccount =
    ReceivedByAccount { raccAccount :: Account
                      -- ^ The account we received into.
                      , raccAmount  :: BTC
                      -- ^ The mount received.
                      -- ^ The number of confirmations of the most recent
                      --   included transaction.
                      , raccNumConfirmations :: Integer
                      }
    deriving ( Show, Read, Ord, Eq )

instance FromJSON ReceivedByAccount where
    parseJSON (Object o) = ReceivedByAccount <$> o .: "account"
                                             <*> o .: "amount"
                                             <*> o .: "confirmations"
    parseJSON _ = mzero

-- | Lists the amount received by each account which has received money at some
--   point, counting only transactions with at leaset one confirmation.
listReceivedByAccount :: Auth -> IO (Vector ReceivedByAccount)
listReceivedByAccount auth = listReceivedByAccount' auth 1 False

-- | List the amount received by each of our accounts, counting only
--   transactions with the given minimum number of confirmations.
listReceivedByAccount' :: Auth
                       -> Int
                       -- ^ The minimum number of confirmations before a
                       --   transaction counts toward the total received.
                       -> Bool
                       -- ^ Should we include the accounts with no money
                       --   received?
                       -> IO (Vector ReceivedByAccount)
listReceivedByAccount' auth minconf includeEmpty =
    callApi auth "listreceivedbyaccount" [ tj minconf, tj includeEmpty ]
    

data SinceBlock = 
    SinceBlock { strransactions :: Vector SimpleTransaction
               , sbLastBlockHash :: BlockHash
               }
    deriving ( Show, Ord, Eq )
    
instance FromJSON SinceBlock where
    parseJSON (Object o) = SinceBlock <$> o .:  "transactions"
                                      <*> o .:  "lastblock"
    parseJSON _ = mzero

-- | Data type for simple transactions. Rules involving 'Maybe' are 
--   indications of the most probable value only when the transaction is 
--   obtained from 'listTransactions' or 'listSinceBlock' are their associated
--   methods. They are never enforced on this side.
data SimpleTransaction =
    SimpleTransaction {
        -- | The account name associated with the transaction. The empty string 
        --   is the default account.
          stReceivingAccount :: Account
        -- | The bitcoin address of the transaction. Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , stAddress :: Maybe Address
        -- | The category of the transaction
        , stCategory :: TransactionCategory
        -- | The fees paid to process the transaction. Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , stFee :: Maybe BTC
        -- | The amount of bitcoins transferred.
        , stAmount :: BTC
        -- | The number of confirmations of the transaction. Is 'Nothing' unless
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , stConfirmations :: Maybe Integer
        -- | The hash of the block containing the transaction. Is 'Nothing' 
        --   unless 'trCategory' is 'TCSend' or 'TCReceive'.
        , stBlockHash :: Maybe BlockHash
        -- | The index of the the block containing the transaction. Is 'Nothing'
        --   unless  'trCategory' is 'TCSend' or 'TCReceive'.
        , stBlockIndex :: Maybe Integer
        -- | The block time in seconds since epoch (1 Jan 1970 GMT). Is 
        --   'Nothing' unless 'trCategory' is 'TCSend' or 'TCReceive'.
        , stBlockTime :: Maybe POSIXTime
        -- | The transaction id. Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , stTransactionId :: Maybe TransactionID
        -- | The list of transaction ids containing the same data as the 
        --   original transaction (See ID-malleation bug). Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , stWalletConflicts :: Maybe (Vector TransactionID)
        -- | The block time in seconds since epoch (1 Jan 1970 GMT).
        , stTime :: POSIXTime
        , stTimeReceived :: Maybe POSIXTime
        -- | Is 'Nothing' unless a comment is associated with the transaction.
        , stComment :: Maybe Text
        -- | Is 'Nothing' unless a \"to\" is associated with the transaction.
        , stTo :: Maybe Text
        -- | The account the funds came from (for receiving funds, positive 
        --   amounts), or went to (for sending funds, negative amounts). Is 
        --   'Nothing' unless 'trCategory' is 'TCMove'.
        , stOtherAccount :: Maybe Account
        }
    deriving ( Show, Ord, Eq )

instance FromJSON SimpleTransaction where
    parseJSON (Object o) =
      SimpleTransaction
        <$> o .:  "account"
        <*> o .:? "address"
        <*> o .:  "category"
        <*> o .:? "fee"
        <*> o .:  "amount"
        <*> o .:? "confirmations"
        <*> o .:? "blockhash"
        <*> o .:? "blockindex"
        <*> (fmap fromInteger <$> o .:? "blocktime")
        <*> o .:? "txid"
        <*> o .:? "walletconflicts"
        <*> (fromInteger <$> o .: "time")
        <*> (fmap fromInteger <$> o .:? "timereceived")
        <*> o .:? "comment"
        <*> o .:? "to"
        <*> o .:? "otheraccount"
    parseJSON _ = mzero

data TransactionCategory = TCSend
                         | TCOrphan
                         | TCImmature
                         | TCGenerate
                         | TCReceive
                         | TCMove
                         | TCErrorUnexpected Text
    deriving ( Show, Read, Ord, Eq )

instance FromJSON TransactionCategory where
    parseJSON (String s) = return $ createTC s
        where createTC :: Text -> TransactionCategory
              createTC "send"     = TCSend
              createTC "orphan"   = TCOrphan
              createTC "immature" = TCImmature
              createTC "generate" = TCGenerate
              createTC "receive"  = TCReceive
              createTC "move"     = TCMove
              createTC uc         = TCErrorUnexpected uc
    parseJSON _ = mzero
    
-- | Gets all transactions in blocks since the given block.
listSinceBlock :: Auth
               -> BlockHash
               -- ^ The hash of the first block to list.
               -> Maybe Int
               -- ^ The minimum number of confirmations before a
               --   transaction can be returned as 'sbLastBlockHash'. This does
               --   not in any way affect which transactions are returned 
               --   (see https://github.com/bitcoin/bitcoin/pull/199#issuecomment-1514952)
               -> IO (SinceBlock)
listSinceBlock auth blockHash conf =
    listSinceBlock' auth (Just blockHash) conf

-- | Gets all transactions in blocks since the given block, or all 
--   transactions if ommited.
listSinceBlock' :: Auth
                -> Maybe BlockHash
                -- ^ The hash of the first block to list.
                -> Maybe Int
                -- ^ The minimum number of confirmations before a
                --   transaction can be returned as 'sbLastBlockHash'. This does
                --   not in any way affect which transactions are returned 
                --   (see https://github.com/bitcoin/bitcoin/pull/199#issuecomment-1514952)
                -> IO (SinceBlock)
listSinceBlock' auth mblockHash mminConf =
    callApi auth "listsinceblock" $ tja mblockHash ++ tja mminConf
        
    
-- | Returns transactions from the blockchain.
listTransactions :: Auth
                 -> Account
                 -- ^ Limits the 'BlockTransaction' returned to those from or to 
                 --   the given 'Account'.
                 -> Int
                 -- ^ Limits the number of 'BlockTransaction' returned.
                 -> Int
                 -- ^ Number of most recent transactions to skip. 
                 -> IO (Vector SimpleTransaction)
listTransactions auth account size from =
    listTransactions' auth (Just account) (Just size) (Just from)

-- | Returns transactions from the blockchain.
listTransactions' :: Auth
                  -> Maybe Account
                  -- ^ Limits the 'BlockTransaction' returned to those from or to 
                  --   the given 'Account'. If 'Nothing' all accounts are 
                  --   included in the query.
                  -> Maybe Int
                  -- ^ Limits the number of 'BlockTransaction' returned. If 
                  --   'Nothing' all transactions are returned.
                  -> Maybe Int
                  -- ^ Number of most recent transactions to skip. 
                  -> IO (Vector SimpleTransaction)
listTransactions' auth maccount mcount mfrom =
    callApi auth "listtransactions" $ [ tjm "*" maccount ] ++ tja mcount ++ tja mfrom


-- | List accounts and their current balance.
listAccounts :: Auth
             -> Maybe Int
             -- ^ Minimum number of confirmations required before payments are 
             --   included in the balance.
             -> IO (HM.HashMap Account BTC)
listAccounts auth mconf = 
    callApi auth "listaccounts" [ tjm 1 mconf ]

-- | Data type for detailed transactions. Rules involving 'trCategory' are 
--   indications of the most probable value only when the transaction is 
--   obtained from 'listTransactions' or 'listSinceBlock' are their associated
--   methods.
data DetailedTransaction =
    DetailedTransaction {
        -- | The amount of bitcoins transferred.
          dtAmount :: BTC
        -- | The fees paid to process the transaction. Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , dtFee :: Maybe BTC
        -- | The number of confirmations of the transaction. Is 'Nothing' unless
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , dtConfirmations :: Maybe Integer
        -- | The transaction id. Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , dtTransactionId :: Maybe TransactionID
        -- | The list of transaction ids containing the same data as the 
        --   original transaction (See ID-malleation bug). Is 'Nothing' unless 
        --   'trCategory' is 'TCSend' or 'TCReceive'.
        , dtWalletConflicts :: Maybe (Vector TransactionID)
        -- | The block time in seconds since epoch (1 Jan 1970 GMT).
        , dtTime :: POSIXTime
        , dtTimeReceived :: Maybe POSIXTime
        -- | Is 'Nothing' unless a comment is associated with the transaction.
        , dtComment :: Maybe Text
        -- | Is 'Nothing' unless a \"to\" is associated with the transaction.
        , dtTo :: Maybe Text
        -- | The details of the transaction.
        , dtDetails :: Vector DetailedTransactionDetails
        -- | Raw data for the transaction.
        , dtHex :: RawTransaction
        }
    deriving ( Show, Ord, Eq )

instance FromJSON DetailedTransaction where
    parseJSON (Object o) =
      DetailedTransaction
        <$> o .:  "amount"
        <*> o .:? "fee"
        <*> o .:  "confirmations"
        <*> o .:? "txid"
        <*> o .:? "walletconflicts"
        <*> (fromInteger <$> o .: "time")
        <*> (fmap fromInteger <$> o .:? "timereceived")
        <*> o .:? "comment"
        <*> o .:? "to"
        <*> o .:  "details"
        <*> o .:  "hex"
    parseJSON _ = mzero
    
data DetailedTransactionDetails =
    DetailedTransactionDetails {
        -- | The account name associated with the transaction. The empty string 
        --   is the default account.
          dtdReceivingAccount :: Account
        -- | The bitcoin address of the transaction.
        , dtdAddress :: Address
        -- | The category of the transaction
        , dtdCategory :: TransactionCategory
        -- | The amount of bitcoins transferred.
        , dtdAmount :: BTC
        }
    deriving ( Show, Ord, Eq )
    
instance FromJSON DetailedTransactionDetails where
    parseJSON (Object o) = DetailedTransactionDetails <$> o .:  "account"
                                                      <*> o .:  "address"
                                                      <*> o .:  "category"
                                                      <*> o .:  "amount"
    parseJSON _ = mzero

getTransaction :: Auth 
               -> TransactionID
               -> IO (DetailedTransaction)
getTransaction auth txid = 
    callApi auth "gettransaction" [ tj txid ]


-- | Safely copies wallet.dat to the given destination, which can be either a
--   directory, or a path with filename.
backupWallet :: Auth
             -> FilePath
             -> IO ()
backupWallet auth fp =
    unNil <$> callApi auth "backupwallet" [ tj fp ]

-- | Fills the keypool.
keyPoolRefill :: Auth -> IO ()
keyPoolRefill auth = unNil <$> callApi auth "keypoolrefill" []

-- | Stores the wallet decryption key in memory for the given amount of time.
unlockWallet :: Auth
             -> Text
             -- ^ The decryption key.
             -> Integer
             -- ^ How long to store the key in memory (in seconds).
             -> IO ()
unlockWallet auth pass timeout =
    unNil <$> callApi auth "walletpassphrase" [ tj pass, tj timeout ]

-- | Changes the wallet passphrase.
changePassword :: Auth
               -> Text
               -- ^ The old password.
               -> Text
               -- ^ The new password.
               -> IO ()
changePassword auth old new =
    unNil <$> callApi auth "walletpassphrase" [ tj old, tj new ]

-- | Removes the wallet encryption key from memory, locking the wallet.
--
--   After calling this function, you will need to call 'unlockWallet' again
--   before being able to call methods which require the wallet to be unlocked.
--
--   Note: In future releases, we might introduce an "unlocked" monad, so
--         locking and unlocking is automatic.
lockWallet :: Auth -> IO ()
lockWallet auth = unNil <$> callApi auth "walletlock" []

-- | Encrypts the wallet with the given passphrase.
--
--   WARNING: bitcoind will shut down after calling this method. Don't say I
--            didn't warn you.
encryptWallet :: Auth -> Text -> IO ()
encryptWallet auth pass = stupidAPI <$> callApi auth "encryptwallet" [ tj pass ]
    where
        stupidAPI :: Text -> ()
        stupidAPI = const ()

-- | Just a handy wrapper to help us get only the "isvalid" field of the JSON.
--   The structure is much too complicated for what it needs to do.
data IsValid = IsValid { getValid :: Bool }

instance FromJSON IsValid where
    parseJSON (Object o) = IsValid <$> o .: "isvalid"
    parseJSON _ = mzero

-- | Checks if a given address is a valid one.
isAddressValid :: Auth -> Address -> IO Bool
isAddressValid auth addr = getValid <$> callApi auth "validateaddress" [ tj addr ]
