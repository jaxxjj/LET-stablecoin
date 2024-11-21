# Main concepts

1. Stability fee:

   1. fee accumulates over time
   2. fee rate changes over time intervals
   3. rate accumulation function: R(t) function initilized since deployed:
      1. amount \* R(k+j-1)/R(k-1)
      2. use the rate accumulation function to calculate the fee from contract deployed to current timestamp and divide it by the accumulation function before user borrowed.
      3. when multiple borrows from different times by a single user, use formula: (amount1/R from deployed to borrow1) + (amount2/R from deployed to borrow2) combine and multiply by the current R(t) (from deployed to current timestamp)

# Contracts

1. GemJoin
1. CDPEngine
1. CoinJoin
1. Spot
