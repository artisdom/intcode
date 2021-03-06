# intcode
Interpreter for the aoc2019 intcode esolang, written in haskell.

Just trying to learn """pure mutability""" in practice.

# Features
* Interprets intcode
* Absolutely nothing else

# Usage
The `IntCode` module exports a canonical IntCode interpreter. That is, it uses actual stdin and stdout for I/O - as instructed. It's essentially a re-export of `IntCode.IO`.

That's all fine and dandy, except in later days - you're asked to use that I/O with mass amount of inputs. Which means, you need to automate it - interactively automating stdio is a bit of a pain so there's also `IntCode.ST`

`IntCode.ST` exports functions with the same names as `IntCode`/`IntCode.IO` - except there's no stdio here - the inputs should be provided as a list to `constructMachine`. The outputs will be present in the `outs` property of the `IntMachine` (accesible using the `outs` function)

# API - Module `IntCode`
## `IntMachine` - The Intcode machine
```hs
type Program = IOArray Int Int
type Memory = Map.IntMap Int

data IntMachine = IntMachine
    { insPtr     :: {-# UNPACK #-} !Int  -- ^ The instruction pointer
    , relBasePtr :: {-# UNPACK #-} !Int  -- ^ The relative base pointer
    , programLen :: {-# UNPACK #-} !Int  -- ^ Length of the intcode program
    , intCode    :: !Program             -- ^ Actual intcode program (puzzle input)
    , oobMem     :: !Memory              -- ^ Memory outside of the intcode program
    }
```

## `constructMachine :: [Int] -> IO IntMachine`
Takes a list of integers (the intcode puzzle input) and returns an intcode machine

```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99]
```
## `readIns :: IntMachine s -> IO (Int, Int, Int, Int)`
Takes an intcode machine and reads the instruction currently pointed by the instruction pointer

The instruction is then parsed into a tuple of structure ()

If the instruction pointer pointed to the value of 1002, `readIns` will return (2, 0, 1, 0)

This means, opcode == 2
            1st param mode == 0
            2nd param mode == 1
            3rd param mode == 0 (omitted due to being leading zero)
```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= readIns
```
## `runIns :: IntMachine -> IO (Maybe IntMachine)`
Takes an intcode machine and runs the instruction currently pointed at by the instruction pointer

This will accordingly modify the machine and progress the instruction pointer to the next instruction

If the instruction currently pointed at by the instruction pointer is `99` - returns `Nothing`

Otherwise, the modified machine is returned - ready to be used by `runIns` again (after unwrapping from `Maybe`)
```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= runIns
```
## `runMachine :: IntMachine -> IO IntMachine`
A quality of life version of `runIns` - repeatedly runs `runIns` until the program halts
```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= runMachine
```
## `getOutput :: IntMachine -> IO Int`
Takes the intcode machine and returns the value at memory index 0
```hs
-- This returns 30
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= runMachine >>= getOutput
-- This returns 1
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= getOutput
```
## `readMem :: IntMachine -> Int -> IO Int`
A general version of `getOutput` - return the value of the given index from the machine's memory

Canonically, the intcode machine employs a von neumann architecture - which means infinite memory indices. So you can access any memory index an `Int` can represent.
```hs
-- This returns 30
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= runMachine >>= flip readMem 0
-- This returns 1
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= flip readMem 0
-- This returns 99
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= flip readMem 4
-- This returns 0 (untouched memory cell in the infinite band)
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= flip readMem 42
-- This returns 0 (untouched memory cell in the infinite band)
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] >>= runMachine >>= flip readMem 42
```

# API - Module `IntCode.ST`
## `IntMachine` - The Intcode machine
```hs
type Program = STArray s Int Int
type Memory = Map.IntMap Int

data IntMachine s = IntMachine
    { insPtr     :: {-# UNPACK #-} !Int  -- ^ The instruction pointer
    , relBasePtr :: {-# UNPACK #-} !Int  -- ^ The relative base pointer
    , programLen :: {-# UNPACK #-} !Int  -- ^ Length of the intcode program
    , intCode    :: !(Program s)         -- ^ Actual intcode program (puzzle input)
    , oobMem     :: !Memory              -- ^ Memory outside of the intcode program
    , inps       :: !(Seq.Seq Int)       -- ^ Sequence of inputs to feed to the program
    , outs       :: !(Seq.Seq Int)       -- ^ Sequence of outputs produced by the program
    }
```

## `constructMachine :: [Int] -> [Int] -> IO IntMachine`
Takes a list of integers (the intcode puzzle input) and a list of inputs - returns an intcode machine

The list of inputs should be sequential. That is, if the list was `[4, 5, 6, 7, 8]` - At the first input (opcode 3), the program is given 4, at the next one, it is given 5, then 6 and so on

Once all inputs from this list runs out and the program encounters *another* input instruction (opcode 3) - it fails with an exception

Consider `4, 0, 3, 1, 99` - where input list is `[]` (no input provided by user)
* Encounter `4, 0` - output the value at index `0` - i.e `4`
  This value is appended (right side) to the output sequence (`outs`) **and** the `inps` sequence
* Encounter `3, 0` - read input from `inps` and store it at index `0`
  The leftmost value from `inps` is popped off from the sequence and used for the input

If at any point, `inps` is an empty sequence during the input instruction (opcode 3) - the machine halts with an exception
```hs
-- Make an intcode machine that takes 1 as its input in its first encounter with opcode 3 (input op)
constructMachine [3, 12, 6, 12, 15, 1, 13, 14, 13, 4, 13, 99, -1, 0, 1, 9] [1]
```
## `addInput :: IntMachine s -> Int -> ST s (IntMachine s)`
Add an input to be used by opcode 3

The element is *appended* to the already existing input sequence

```hs
-- The machine now has [1, 42] in its input sequence
-- i.e it will use 1 as its first input to opcode 3 and 42 as its second
constructMachine [3, 12, 6, 12, 15, 1, 13, 14, 13, 4, 13, 99, -1, 0, 1, 9] [1] >>= flip addInput 42
```
## `addInputs :: IntMachine s -> [Int] -> ST s (IntMachine s)`
Add multiple inputs to be used by opcode 3

Each element is *appended* to the already existing input sequence in the same order as the list

```hs
-- The machine now has [1, 42, 13] in its input sequence
-- i.e it will use 1 as its first input to opcode 3 and 2 as its second and 13 as its third
constructMachine [3, 12, 6, 12, 15, 1, 13, 14, 13, 4, 13, 99, -1, 0, 1, 9] [1] >>= flip addInput [42, 13]
```
## `viewInputs :: IntMachine s -> ST s [Int]`
```hs
-- This returns [8]
constructMachine [3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8] [8] >>= viewInputs
```
## `getOutputs :: IntMachine s -> ST s [Int]`
Get the output sequence (outputs from opcode 4) from the machine

The list of outputs is in the order they were outputted - from left to right
```hs
-- This returns [1]
constructMachine [3, 9, 8, 9, 10, 9, 4, 9, 99, -1, 8] [8] >>= runMachine >>= getOutputs
```
## `readIns :: IntMachine s -> ST s (Int, Int, Int, Int)`
Takes an intcode machine and reads the instruction currently pointed by the instruction pointer

The instruction is then parsed into a tuple of structure ()

If the instruction pointer pointed to the value of 1002, `readIns` will return (2, 0, 1, 0)

This means, opcode == 2
            1st param mode == 0
            2nd param mode == 1
            3rd param mode == 0 (omitted due to being leading zero)
```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= readIns
```
## `runIns :: IntMachine -> ST s (Maybe (IntMachine s))`
Takes an intcode machine and runs the instruction currently pointed at by the instruction pointer

This will accordingly modify the machine and progress the instruction pointer to the next instruction

If the instruction currently pointed at by the instruction pointer is `99` - returns `Nothing`

Otherwise, the modified machine is returned - ready to be used by `runIns` again (after unwrapping from `Maybe`)
```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= runIns mach
```
## `runMachine :: IntMachine -> ST s (IntMachine s)`
A quality of life version of `runIns` - repeatedly runs `runIns` until the program halts
```hs
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= runMachine
```
## `readMem :: IntMachine -> Int -> IO Int`
A general version of `getOutput` - return the value of the given index from the machine's memory

Canonically, the intcode machine employs a von neumann architecture - which means infinite memory indices. So you can access any memory index an `Int` can represent.
```hs
-- This returns 30
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= runMachine >>= flip readMem 0
-- This returns 1
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= flip readMem 0
-- This returns 99
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= flip readMem 4
-- This returns 0 (untouched memory cell in the infinite band)
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= flip readMem 42
-- This returns 0 (untouched memory cell in the infinite band)
constructMachine [1, 1, 1, 4, 99, 5, 6, 0, 99] [] >>= runMachine >>= flip readMem 42
```

# Solutions to aoc2019 problems

## Day 2 solution
```hs
import IntCode (constructMachine, runMachine, readMem)

solution :: [Int] -> IO Int
solution inpl =
    -- Construct the mutable IntCode array 
    constructMachine inpl
    -- Run the machine
    >>= runMachine
    -- Get the final output (result at index 0)
    >>= flip readMem 0
```
`inpl` is the puzzle input as a list of ints, returned value is the answer

## Day 5 solution (using `IntCode.IO`/`IntCode`)
```hs
import Control.Monad (void)

import IntCode (constructMachine, runMachine)

solution :: [Int] -> IO ()
solution inpl = void $
    -- Construct the mutable IntCode array 
    constructMachine inpl
    -- Run the machine
    >>= runMachine
```

`inpl` is the puzzle input as a list of ints, the user should enter 1 to stdin for part 1 and 5 for part 2 - the result will be printed in stdout

## Day 5 solution (using `IntCode.ST`)
```hs
import Control.Monad.ST (stToIO)
import Data.Functor ((<&>))
import Data.Sequence (Seq)

import IntCode.ST (constructMachine, runMachine, getOutputs)

solution :: [Int] -> Int -> IO (Seq Int)
solution inpl progInp = stToIO $
    -- Construct the mutable IntCode array 
    constructMachine inpl [progInp]
    -- Run the machine
    >>= runMachine
    -- Get the outputs as a list
    >>= getOutputs
    -- Return the last element of said list
    <&> last
```
`inpl` is the puzzle input as a list of ints, `progInp` is the list of stdin inputs (for part 1, this is `[1]` and `[5]` for part 2) - the returned value is a sequence of outputs - the final of which is the answer.

No stdio interaction is necessary.

## Day 7 solution (using `IntCode.ST`)
This one is only reasonably doable using the `ST` version

Before getting to the actual `solution`, some utility functions are required

First, `scanlM`, which is just `scanl` for monadic actions
```hs
scanlM :: Monad m => (b -> a -> m b) -> b -> [a] -> m [b]
scanlM _ q [] = pure [q]
scanlM f q (x:xs) = f q x >>= flip (scanlM f) xs <&> (q:)
```
Then, a function that takes an `IntMachine` and runs it until it either it halts, or it encounters an input instruction (opcode 3) with no inputs left to feed in
```hs
import Control.Monad.ST (ST)
import Data.Functor ((<&>))

import IntCode.ST
    ( addInput
    , getOutputs
    , readIns
    , runIns
    , viewInputs
    , IntMachine
    )

{- | Run each instruction one by one and stop if
an input instruction is encountered with no input
left to use or if the machine has halted

The mutated machine is returned
-}
runUntilInp :: IntMachine s -> ST s (IntMachine s)
runUntilInp mach = do
    -- Read the current instruction and parse out the opcode
    (opcode, _, _, _) <- readIns mach
    -- Check the input sequence of the machine
    inps <- viewInputs mach
    case (opcode, inps) of
        -- Opcode is 3 (input instruction) but no inputs left to use, return
        (3, []) -> pure mach
        -- Run the current instruction and continue (unless machine has halted)
        -- If machine has halted, return the machine
        _ -> runIns mach >>= maybe (pure mach) runUntilInp
```
Now, a function that imitates the amplifier design. That is, start at the first amplifier machine - feed it 0 to get an output, feed that output to the next amp and so on. Notice the pattern? It's a fold, but the intermediate states (representing each amplifer's modified machine) should be preserved to return back. This is where `scanlM` comes in
```hs
{- | Run the list of machines (each machine representing an amplifier)
`m` is the starting machine, which's last output is fed into the first amp
the rest of the amps use the previous amp's output

Which means this is essentially a fold, but all the intermediate states should be remembered
to be returned as a new list of machines - that's a scanl
Discard the first element though, that's just the starting element passed
-}
runAmps :: IntMachine s -> [IntMachine s] -> ST s [IntMachine s]
runAmps m ms = tail <$> scanlM (\acc x -> getLastOutput acc >>= addInput x >>= runUntilInp) m ms
    where
        {- | Get the final output produced by given machine
        If no output has been provided, use 0 (this will come into play for the very first amp run) -}
        getLastOutput mach = getOutputs mach <&> \outs -> if null outs then 0 else last outs
```
Finally, a function that just runs `runAmps` till one of the machines halts
```hs
{- | Run all amps till one of them halts
All of the machines in each amp is modified accordingly

In the end, the final list of modified amps are returned

The final output should be the greatest output amongst all of these
machines
-}
runAmpsTillHalt :: IntMachine s -> [IntMachine s] -> ST s [IntMachine s]
runAmpsTillHalt startMach machs =
    -- Run all the amplifiers once
    runAmps startMach machs
    -- Read the current instruction of all the modified machines in the amplifiers
    >>= \newMachs -> mapM readIns newMachs
        >>= (\inss ->
            -- Check if any of the machines has its instruction pointer set to 99 (aka has halted) 
            if any (\(op, _, _, _) -> op == 99) inss
            {- If none of them has halted, runAmpsTillHalt again, passing in the 
            final amplifier machine as starting mach and the modified set of machines -}
            then pure newMachs
            -- Otherwise, return the set of machines at hand - signifying one of them has halted and the process is over
            else runAmpsTillHalt (last newMachs) newMachs
        )
```

So the final solution function would look like
```hs
solution :: [Int] -> [Int] -> ST s Int
solution inpl phases =
    sequence [constructMachine inpl [x] | x <- phases]
        -- Run all the amps till they halt
        >>= \ms -> runAmpsTillHalt (head ms) ms
            -- Get the maximum output amongst all the machines' outputs (aka final output)
            >>= mapM (getOutputs >=> pure . last) <&> maximum
```
`inpl` is the puzzle input as a list of ints, `phases` is the phase setting as a list of 5 ints, returned result is the final output with given phase setting

To find the optimal phase setting, you can just run `solution` on all permutations of `[0, 1, 2, 3, 4]` (for day 1) and `[5, 6, 7, 8, 9]` (for day 2)

```hs
-- | Try multiple permutations of [0, 1, 2, 3, 4] phase setting to get the maximum final output
optimalPhaseP1 :: [Int] -> ST s Int
optimalPhaseP1 inpl = sequence [solution inpl phase | phase <- permutations [0, 1, 2, 3, 4]] <&> maximum

-- | Try multiple permutations of [5, 6, 7, 8, 9] phase setting to get the maximum final output
optimalPhaseP2 :: [Int]] -> ST s Int
optimalPhaseP2 inpl = sequence [solution inpl phase | phase <- permutations [5, 6, 7, 8, 9]] <&> maximum
```

## Day 9 solution
```hs
solution :: [Int] -> IO ()
solution inpl = void $
    -- Construct the mutable IntCode array 
    constructMachine inpl
    -- Run the machine
    >>= runMachine
```
Same as day 5 - this time the part 1 input is 1 and part 2 input is 2 - the result will be printed in stdout

## Day 9 solution (using `IntCode.ST`)
```hs
import Control.Monad.ST (stToIO)
import Data.Functor ((<&>))
import Data.Sequence (Seq)

import IntCode.ST (constructMachine, runMachine, getOutputs)

solution :: [Int] -> Int -> IO (Seq Int)
solution inpl progInp = stToIO $
    -- Construct the mutable IntCode array 
    constructMachine inpl [progInp]
    -- Run the machine
    >>= runMachine
    -- Get the outputs as a list
    >>= getOutputs
    -- Return the last element of said list
    <&> last
```
Same as day 5 - this time the part 1 `progInp` is `[1]` and part 2 `progInp` is `[2]` - the returned value is a sequence of outputs - the final of which is the answer.

No stdio interaction is necessary.
