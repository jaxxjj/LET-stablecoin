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

## CDPEngine.sol

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

## Jug.sol

The Jug contract manages and collects stability fees for different collateral types in the system, handling fee rate accumulation and collection.

### Key Features

1. Fee Rate Management

   - Global base stability fee configuration
   - Collateral-specific fee rates
   - Time-based fee accumulation
   - Rate parameter controls

2. Fee Collection Process

   - Automated fee calculation
   - Time-elapsed rate accumulation
   - Per-collateral fee tracking
   - Fee destination management

3. System Integration
   - Coordinates with CDP Engine
   - Updates rate accumulator
   - Handles fee distribution
   - Maintains fee state

### Main Functions

1. init()/set()

   - Collateral type initialization
   - Fee rate configuration
   - Parameter updates
   - System address management

2. collect_stability_fee()

   - Calculates accumulated fees
   - Updates rate accumulator
   - Processes fee collection
   - Maintains timestamps

### Security Features

1. Access Control

   - Auth-protected initialization
   - Controlled parameter updates
   - Protected fee collection
   - Secure state modifications

2. Safety Checks

   - Time-based validations
   - Rate accumulator updates
   - State consistency checks
   - Parameter boundaries

3. State Management
   - Accurate timestamp tracking
   - Fee rate precision [ray]
   - Collection state updates
   - System synchronization

## Oracle.sol

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

## EmergencyShutdown

The EmergencyShutdown contract provides a secure and controlled mechanism for system shutdown in emergency situations, ensuring user funds can be safely recovered.

### Key Features

1. System Shutdown Management

   - Coordinated shutdown of all system components
   - Permanent price feed freezing
   - Auction process termination
   - CDP operations suspension

2. Price Settlement

   - Final collateral price fixing
   - Price validation checks
   - One-time price setting per collateral
   - Oracle price snapshot capture

3. User Fund Recovery
   - Collateral redemption mechanism
   - Fair price settlement
   - Proportional stablecoin redemption
   - Direct collateral recovery

### Main Functions

1. shutdown_system()

   - Initiates system-wide shutdown
   - Stops all active system components
   - Records shutdown timestamp
   - Prevents new operations

2. set_final_price()

   - Sets final collateral prices
   - Uses last valid Oracle price
   - One-time operation per collateral
   - Ensures price validity

3. redeem_collateral()
   - Allows user collateral recovery
   - Uses fixed final prices
   - Burns equivalent stablecoin
   - Direct collateral transfer

### Security Features

1. Access Control

   - Admin-only shutdown initiation
   - Protected price setting
   - Controlled redemption process
   - Irreversible shutdown mechanism

2. State Management

   - Clear shutdown state tracking
   - Final price immutability
   - System component coordination
   - Safe state transitions

3. User Protection
   - Fair price settlement
   - Guaranteed collateral access
   - Proportional redemption rights
   - Clear recovery process

## SurplusAuction.sol

The SurplusAuction contract manages the auctioning of surplus LET (system profits from stability fees) in exchange for MKR tokens which are then burned.

### Key Features

1. Auction Management
   - Auctions surplus LET for MKR tokens
   - Increasing price auction mechanism
   - Configurable auction parameters
   - Automatic MKR token burning
2. Bidding Process

   - Minimum bid increase requirement
   - Time-limited bidding periods
   - Auction duration constraints
   - Automatic bid settlement

3. System Integration
   - Handles system stability fee surplus
   - Burns MKR to reduce supply
   - Controls maximum LET in auction
   - Coordinates with CDP Engine

### Main Functions

1. start()

   - Initiates new surplus auction
   - Sets initial LET amount
   - Sets starting bid
   - Tracks auction parameters

2. bid()

   - Places new bid with higher MKR amount
   - Enforces minimum bid increase
   - Handles bid expiry timing
   - Returns previous bid to bidder

3. claim()
   - Settles completed auction
   - Transfers LET to winning bidder
   - Burns winning MKR bid
   - Cleans up auction state

### Security Features

1. Access Control

   - Admin-only auction initiation
   - Circuit breaker system
   - Parameter adjustment controls
   - Auction limits enforcement

2. Auction Safety

   - Minimum bid increase (5%)
   - Maximum auction duration (2 days)
   - Bid lifetime limits (3 hours)
   - Maximum LET auction limits

3. System Protection
   - Emergency shutdown capability
   - Bid validation checks
   - Token transfer safety
   - State consistency checks

## AuctionPriceCalculator.sol

The AuctionPriceCalculator contracts provide different price calculation strategies for Dutch auctions in the collateral liquidation process. Each implementation offers a unique price decay model optimized for different market conditions.

### Key Features

1. Multiple Price Models

   - Linear decrease for predictable price discovery
   - Stairstep exponential for quick price finding
   - Continuous exponential for smooth price decay
   - Configurable parameters for each model

2. Time-based Calculations

   - Price updates based on elapsed time
   - Configurable duration parameters
   - Automatic price computation
   - Zero price floor enforcement

3. System Integration
   - Used by CollateralAuction contract
   - Standardized interface for all models
   - Precision-preserving calculations [ray]
   - Flexible model selection

### Implementations

1. LinearDecrease

   - Linear price reduction over time
   - Simple and predictable decay pattern
   - Price reaches zero at duration end
   - Formula: price = initial_price \* (duration - elapsed_time)/duration

2. StairstepExponentialDecrease

   - Step-wise price reduction
   - Configurable step interval
   - Percentage-based price cuts
   - Formula: price = initial_price \* (cut ^ (elapsed_time/step))

3. ExponentialDecrease
   - Continuous exponential decay
   - Smooth price reduction curve
   - Maximum duration limit
   - Formula: price = initial*price * e^(-decay \_ elapsed_time)

### Key Parameters

1. Time Parameters

   - duration: Maximum auction length [seconds]
   - step: Time between price drops [seconds]
   - Configurable per auction type

2. Price Parameters
   - cut: Price reduction per step [ray]
   - decay: Exponential decay rate [ray]
   - All calculations preserve [ray] precision

### Security Features

1. Parameter Validation

   - Maximum value checks
   - Type safety enforcement
   - Duration constraints
   - Rate limitations

2. Access Control

   - Admin-only parameter updates
   - Protected configuration changes
   - Secure integration points

3. Calculation Safety
   - Overflow protection
   - Precision maintenance
   - Zero-price floor
   - Time boundary checks

## Coin.sol

The Coin contract implements the system's stablecoin (LET), providing standard ERC20 functionality with controlled minting and burning capabilities.

### Key Features

1. Token Implementation

   - Standard ERC20 interface
   - 18 decimal precision
   - Controlled supply management
   - Efficient transfer mechanisms

2. Supply Control

   - Authorized minting capability
   - Controlled burning process
   - Total supply tracking
   - Balance management

3. System Integration
   - Used in CDP collateral auctions
   - Handles stability fee payments
   - Supports surplus auctions
   - Core system settlement token

### Main Functions

1. transfer/transferFrom()

   - Standard ERC20 transfers
   - Allowance management
   - Balance updates
   - Event emission

2. mint/burn()

   - Authorized supply control
   - System debt management
   - Total supply adjustments
   - Access controlled operations

3. approve/push/pull()
   - Delegation management
   - Convenient transfer wrappers
   - Authorization tracking
   - Flexible transfer patterns

### Security Features

1. Access Control

   - Auth-protected minting
   - Controlled supply management
   - Secure transfer logic
   - Protected state updates

2. Safety Checks
   - Balance validation
   - Allowance verification
   - Overflow protection
   - State consistency

## DSEngine.sol

The DSEngine (Debt & Surplus Engine) manages system debt from liquidations and surplus from stability fees, maintaining system solvency through auction mechanisms.

### Key Features

1. Debt Queue Management

   - Handles liquidation-generated debt
   - Time-delayed debt processing
   - Queued debt tracking
   - Controlled debt settlement

2. Auction Coordination

   - Triggers surplus auctions for excess LET
   - Initiates debt auctions for bad debt
   - Manages auction parameters
   - Tracks auction state

3. System Integration
   - Coordinates with CDP Engine
   - Controls auction contracts
   - Maintains system balance
   - Handles emergency shutdown

### Main Functions

1. push_debt_to_queue()/pop_debt_from_queue()

   - Queues liquidation debt
   - Time-delayed processing
   - Debt tracking updates
   - Queue management

2. start_surplus_auction()/start_debt_auction()

   - Initiates system auctions
   - Parameter validation
   - State updates
   - Auction coordination

3. settle_debt()
   - Direct debt settlement
   - Surplus utilization
   - System debt reduction
   - Balance verification

### Security Features

1. Access Control

   - Auth-protected operations
   - Parameter configuration limits
   - Auction contract management
   - State update protection

2. Safety Checks

   - Debt queue validation
   - Auction preconditions
   - Balance verification
   - System state consistency

3. Circuit Breaker
   - Emergency shutdown capability
   - Auction suspension
   - Debt queue clearing
   - System state preservation
