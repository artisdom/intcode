module IntCode.IO
    ( IntMachine(..)
    , constructMachine
    , runMachine
    , getOutput
    , readMem
    ) where

import Data.Maybe (fromMaybe)
import Data.Functor ((<&>))
import Data.Array.IO
    ( IOArray
    , newListArray
    , readArray
    , writeArray
    )
import qualified Data.IntMap as Map

import Utils (digits, padR)


-- | The IntCode program itself - a mutable array
type Program = IOArray Int Int

{- | Memory outside of the intcode program - represents infinite memory using lazy map
All memory indices surpassing the length of the program itself are initialized to 0
This means - only the memory indices modified by the program should be kept track of
So, if the program tries to write to a index out of bound - store it in the map
Whenever, the program tries to read from an index out of bound - check if it exists in the map
If it does exist, return the value stored, otherwise - it's just 0 - the unmodified default
-}
type Memory = Map.IntMap Int

{- | The IntCode Machine - contains the actual program + relevant info about itself
This data structue itself is not mutable
A new version, with the necessary fields updated, is returned per recursion step
However, the intCode array itself is mutable - just to avoid extreme inefficiency
The oobMem Map is still immutable - mostly because this doesn't need access a whole lot
-}
data IntMachine = IntMachine
    { insPtr     :: {-# UNPACK #-} !Int  -- ^ The instruction pointer
    , relBasePtr :: {-# UNPACK #-} !Int  -- ^ The relative base pointer
    , programLen :: {-# UNPACK #-} !Int  -- ^ Length of the intcode program
    , intCode    :: !Program             -- ^ Actual intcode program (puzzle input)
    , oobMem     :: !Memory              -- ^ Memory outside of the intcode program
    }

-- | Construct an IntCode machine from a list of ints
constructMachine :: [Int] -> IO IntMachine
constructMachine l = do
    mutArr <- newListArray (0, lenArr - 1) l
    pure IntMachine
        { insPtr=0
        , relBasePtr=0
        , programLen=lenArr
        , intCode=mutArr
        , oobMem=Map.empty
        }
  where
    lenArr = length l

-- | Get the output of the mutated IntCode machine - i.e the value at index 0 of the program
getOutput :: IntMachine -> IO Int
getOutput = flip readArray 0 . intCode

-- | Read value of memory index - considers both the intcode program itself and the infinite memory band
readMem :: IntMachine -> Int -> IO Int
readMem mach i =
    if i < programLen mach
    -- If index is within bounds of the intcode program - get the value from there
    then flip readArray i . intCode $ mach
    -- Othewise, try to find the value in the oobMem map
    -- If that index is not found in the map - it means it is unmodified (i.e 0 by default)
    else pure $ fromMaybe 0 . Map.lookup i . oobMem $ mach

-- | Write value to memory index - considers both the intcode program itself and the infinite memory band
writeMem :: IntMachine -> Int -> Int -> IO IntMachine
writeMem mach i e = 
    if i < programLen mach
    -- If index is within bounds of the intcode program - mutate the array
    -- Return the same mach - since the IOArray has been modified internally
    then writeArray (intCode mach) i e >> pure mach
    -- Othewise, insert the value in the oobMem map
    -- Construct a new machine and return it - still has the same mutable array though
    else pure mach { oobMem = Map.insert i e . oobMem $ mach }

-- | Read the instruction given by the instruction pointer
readIns :: IntMachine -> IO Int
readIns mach = readArray (intCode mach) (insPtr mach)

{- |
Mutate the IntCode machine by running
its instructions

This essentially runs the intcode program and, as
a result, mutates the IntCode passed

After this function succeeds - the IntCode passed
will be mutated accordingly
-}
runMachine :: IntMachine -> IO IntMachine
runMachine mach = do
    -- Read the instruction
    -- If it is 99, halt - otherwise execute op and continue
    ins <- readIns mach
    if ins /=99
        -- Execute the opcode and continue using the modified machine returned
        then executeOp mach >>= runMachine
        -- Encountered 99 - halt and return machine
        else pure mach


{- |
Helper function to execute an operator
given its index

Reads the instruction from opIx
Parses it to get the actual opcode and operand modes
Then reads the operands according to opcode, respecting the operand modes
(unless the operand is for output index - in which case, it is always read directly)
Then the opcode is executed using the operands and output index (if any)
This mutates the array accordingly

The result returned is the next instruction index
-}
executeOp :: IntMachine -> IO IntMachine
executeOp mach = do
    -- Read the instruction - which is a number with param modes and opcode grouped up
    opGrp <- readArray (intCode mach) (insPtr mach)
    -- Parse the op group into opcode and operand modes
    let (opcode, oprnd1Mode, oprnd2Mode, oprnd3Mode) = parseOp opGrp
    -- Execute the opcode, using the operands and their respective modes
    case opcode of
        op
            | op `elem` [1, 2, 7, 8] -> do
            {-
            Common case for all opcodes that read 3 operands,
            where the third operand is the output index for the instruction
            to write to, and progress the instruction pointer by 4
            -}
                -- Read the operands according to modes
                [oprnd1, oprnd2, oprnd3] <- sequence
                    [ readFstOperand oprnd1Mode
                    , readSndOperand oprnd2Mode
                    -- The third one should be interpeted as an output operand
                    , readOutOperand (3 + insPtr mach) oprnd3Mode
                    ]
                -- Accordingly modify the machine
                newMach <- case op of
                    -- Add the operands and write to the machine memory
                    1 -> writeMem mach oprnd3 (oprnd1 + oprnd2)
                    -- Multiply the operands and write to the machine memory
                    2 -> writeMem mach oprnd3 (oprnd1 * oprnd2)
                    -- Write 1 to operand3 if oprnd1 is less than oprnd2, else 0
                    7 -> writeMem mach oprnd3 $ if oprnd1 < oprnd2 then 1 else 0
                    -- Write 1 to operand3 if oprnd1 is equal to oprnd2, else 0
                    8 -> writeMem mach oprnd3 $ if oprnd1 == oprnd2 then 1 else 0
                    _ -> error "Well that wasn't supposed to happen"
                -- Return the new machine - after bumping up its instruction pointer
                pure newMach { insPtr = 4 + insPtr mach }
            | op `elem` [3, 4] -> do
            {-
            Common case for all opcodes that read 1 operand
            (i.e I/O opcodes) and progress the instruction pointer by 2
            -}
                -- Read the only operand
                oprnd1 <- if opcode == 3
                    -- Read the operand as output index for opcode 3
                    then readOutOperand (1 + insPtr mach) oprnd1Mode
                    else readFstOperand oprnd1Mode
                -- Accordingly modify the machine
                newMach <-
                    if op == 3
                    then
                        -- Write input in the index given by oprnd1
                        readLn >>= writeMem mach oprnd1
                    else
                        -- Print output as given by oprnd1
                        print oprnd1 >> pure mach
                -- Return the new machine - after bumping up its instruction pointer
                pure newMach { insPtr = 2 + insPtr newMach }
            | op `elem` [5, 6] -> do
            {-
            Common case for all opcodes that read 2 operands
            and either progress the instruction pointer by 3
            or change it to a completely new instruction index
            according to the operand
            -}
                -- Read the operands according to modes
                [oprnd1, oprnd2] <- sequence [readFstOperand oprnd1Mode, readSndOperand oprnd2Mode]
                if op == 5
                then
                    -- Change insPtr to oprnd2 if oprn1 is non-zero - otherwise, change insPtr to the next instruction index
                    pure mach { insPtr = if oprnd1 /= 0 then oprnd2 else 3 + insPtr mach }
                else
                    -- Change insPtr to oprnd2 if oprn1 is zero - otherwise, change insPtr to the next instruction index
                    pure mach { insPtr = if oprnd1 == 0 then oprnd2 else 3 + insPtr mach }
            | op == 9 -> do
            {-
            Opcode 9 is for changing the relative base pointer
            Read the operand and add it to the relative base pointer
            progress the instruction pointer to the next instruction
            return the new machine with these updated values
            -}
                -- Read the only operand
                oprnd1 <- readFstOperand oprnd1Mode
                -- Add the operand to relBasePtr - also progress the insPtr
                pure mach { relBasePtr = oprnd1 + relBasePtr mach, insPtr = 2 + insPtr mach}
            | otherwise -> error "Fatal: Invalid opcode"
  where
    -- | Read the first operand right after opIx - according to its mode
    readFstOperand :: Int -> IO Int
    readFstOperand mode = flip readOperand mode . (+1) . insPtr $ mach
    -- | Read the second operand right after opIx - according to its mode
    readSndOperand :: Int -> IO Int
    readSndOperand mode = flip readOperand mode . (+2) . insPtr $ mach
    {- | Generic version of the above functions
    Reads operand from given index - according to the mode -}
    readOperand :: Int -> Int -> IO Int
    readOperand i mode = case mode of
            -- Mode 0 means, the value at i is the index of the actual operand
            0 -> readMem mach i >>= readMem mach
            -- Mode 1 means, the value at i is the actual operand
            1 -> readMem mach i
            -- Mode 2 means, the value at i + relBasePtr is the index of the actual operand
            2 -> readMem mach i >>= readMem mach . (+ relBasePtr mach)
            _ -> error "Fatal: Invalid operand mode"
    {- | Function to read the operand at index i as an output operand
    This means the operand to be read is an index where the instruction will write to 
    Mode 1 is unavailable for this -}
    readOutOperand :: Int -> Int -> IO Int
    readOutOperand i mode = case mode of
        -- Mode 0 means the output index is the value at i
        0 -> readMem mach i
        -- Mode 2 means the output index is the value at i + relative base pointer
        2 -> readMem mach i <&> (+ relBasePtr mach)
        _ -> error "Fatal: Invalid output operand mode"


{- |
Parse the op group to extract the opcode and parameter modes

For op group 1002, it'll return (0, 1, 0, 2)

This means, opcode == 2
            1st param mode == 0
            2nd param mode == 1
            3rd param mode == 0 (omitted due to being leading zero)
-}
parseOp :: Int -> (Int, Int, Int, Int)
parseOp opGrp = digsTuple digsL
  where
    -- Extract the first 2 digits (actual opcode)
    opcode = opGrp `mod` 100
    -- The rest digits should be extracted one by one
    rest = fromIntegral opGrp `div` 100
    -- Extract all the remaining digits and add them after opcode
    -- Then pad the resulting list to a length of 3 on the right side
    digsL = padR 4 0 $ opcode : reverse (digits rest)
    {-
    The resulting digsL will be an element with 3 numbers
    The first one is the actual opcode
    The next 2 are the modes of operand 1 and 2 respectively

    Turn this into a tuple and return it
    -}
    digsTuple [x, y, z, a] = (x, y, z, a)