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
1. Spotter: any user can call to get the price of the collateral by calling peek() in Pip contract
1. CollateralAuction.sol: Handles Dutch auctions of liquidated CDP collateral

   - This contract manages the auction process when CDPs are liquidated. It uses a Dutch
   - auction format where prices decline over time according to a price calculator.
   - Key features:
     - Dutch auction mechanism with declining prices
     - Partial collateral purchases allowed above minimum thresholds
     - Keeper incentives through fees
     - Circuit breaker system for emergency stops
     - Auction reset mechanism if price drops too far or time expires

   The auction process:

   1. LiquidationEngine calls start() to initiate auction
   2. Starting price = current collateral price \* boost multiplier
   3. Price declines according to calc contract
   4. Buyers can purchase collateral via take() at current price
   5. Auction needs reset via redo() if:
      - Price drops below min_delta_price_ratio threshold
      - Time exceeds max_duration
   6. Emergency stop via yank() if needed

   Security features:

   - Three-level circuit breaker system
   - Minimum debt/collateral thresholds
   - Price validity checks
   - Access controls on admin functions

1. flop: collecting LET that is unbacked by selling its governance token. when the debt auction can't cover the debt, flop is called to sell the governance token to cover the debt, reducing unbacked LET.

## CDPEngine

The CDP Engine is the core contract responsible for managing Collateralized Debt Positions (CDPs) and system debt accounting.

### Key Features

1. CDP Management

   - Users can create CDPs by locking collateral and generating stablecoin debt
   - Supports multiple collateral types with different parameters
   - Tracks collateral and debt positions per user
   - Handles CDP modifications (add/remove collateral, generate/repay debt)

2. System Accounting

   - Tracks total system debt and unbacked debt
   - Manages stability fee accumulation via rate accumulator
   - Enforces debt ceilings and minimum debt requirements
   - Handles internal bookkeeping of collateral and stablecoin balances

3. Access Control
   - Admin functions protected by Auth modifier
   - Delegated access control via can mapping
   - Emergency circuit breaker system
   - Secure asset transfer functions

### Key Functions

1. modify_cdp()

   - Core function for CDP manipulation
   - Allows adding/removing collateral and generating/repaying debt
   - Enforces safety checks:
     - Debt ceiling compliance
     - Collateralization ratio
     - Minimum debt requirements
     - Access control

2. Asset Management

   - transfer_collateral(): Move collateral between addresses
   - transfer_coin(): Transfer stablecoins between addresses
   - modify_collateral_balance(): Adjust raw collateral balances

3. System Configuration
   - init(): Initialize new collateral types
   - set(): Configure system parameters
   - update_min_coin(): Update minimum debt requirements

### Important State Variables

1. Mappings

   - collaterals: Collateral type configurations
   - positions: User CDP positions
   - gem: Raw collateral balances
   - coin: Stablecoin balances
   - unbacked_debts: Debt accounting

2. System State
   - sys_debt: Total system debt
   - sys_unbacked_debt: Total unbacked debt
   - sys_max_debt: Global debt ceiling

### Security Considerations

1. Access Control

   - Admin functions protected by auth modifier
   - Delegated access via can mapping
   - Circuit breaker for emergency stops

2. Safety Checks
   - Collateralization ratio enforcement
   - Debt ceiling compliance
   - Minimum debt requirements
   - Arithmetic overflow protection

## Oracle

The Oracle contract serves as a secure price feed mechanism for the LET stablecoin system, integrating with Pyth Network for reliable price data.

### Key Features

1. Price Feed Management

   - Integrates with Pyth Network for real-time price data
   - Maintains current price state with confidence intervals
   - Enforces maximum price staleness threshold
   - Provides standardized price interface for system contracts

2. Security Mechanisms

   - Whitelist access control for price reads
   - Emergency circuit breaker system
   - Price staleness checks
   - Fee-based price updates

3. System Integration
   - Provides price data to Spotter contract
   - Supports CDP liquidation decisions
   - Enables system-wide price-dependent operations
   - Standardizes price format for system use

### Main Functions

1. poke()

   - Updates current price from Pyth
   - Requires fee payment for updates
   - Enforces staleness threshold
   - Returns excess fees to caller

2. peek()
   - Returns current price and validity
   - Restricted to whitelisted contracts
   - Used by system contracts for price checks
   - Returns standardized price format

### Security Features

1. Access Control

   - Whitelisted access to price reads
   - Admin functions protected by Auth modifier
   - Emergency stop functionality
   - Fee-based update mechanism

2. Price Validity

   - Maximum staleness threshold
   - Confidence interval tracking
   - Price validity checks
   - Pyth Network security features

3. System Protection
   - Circuit breaker system
   - Standardized price format
   - Excess fee return
   - Clear error handling
