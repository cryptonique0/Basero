;; title: collateral-manager
;; version: 1.0.0
;; summary: Multi-asset collateral management
;; description: Track and manage collateral types - Clarity 4

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u5500))
(define-constant ERR-INVALID-COLLATERAL (err u5501))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u5502))
(define-constant ERR-BELOW-LIQUIDATION (err u5503))
(define-constant ERR-TRANSFER-FAILED (err u5504))
(define-constant ERR-NOT-LIQUIDATABLE (err u5505))
(define-constant ERR-PAUSED (err u5506))
(define-constant ERR-BLACKLISTED (err u5507))
(define-constant ERR-ORACLE (err u5508))
(define-constant MAX-FEE-BASIS-POINTS u1000)  ;; 10% max fee

;; Oracle trait: expected external contract must implement get-price
(define-trait price-oracle-trait
  ((get-price (principal) (response uint uint)))
)

;; Data Variables
(define-data-var total-collateral-value uint u0)
(define-data-var deposit-fee-basis-points uint u50)  ;; 0.5% default
(define-data-var withdrawal-fee-basis-points uint u50)  ;; 0.5% default
(define-data-var borrow-fee-basis-points uint u100)  ;; 1.0% default
(define-data-var is-paused bool false)
(define-data-var collected-fees uint u0)
(define-data-var event-counter uint u0)
(define-data-var price-oracle (optional principal) none)

;; Data Maps - Using stacks-block-time for Clarity 4
(define-map collateral-types principal {
  name: (string-ascii 20),
  ltv-ratio: uint,  ;; Basis points (7500 = 75%)
  liquidation-threshold: uint,  ;; Basis points (8500 = 85%)
  is-enabled: bool,
  is-paused: bool,  ;; Asset-level pause
  price-per-unit: uint,  ;; Price in USD (6 decimals)
  total-deposited: uint,
  reward-rate-bps: uint,  ;; Rewards per second in basis points
  added-at: uint  ;; Clarity 4: Unix timestamp
})

(define-map user-collateral {user: principal, asset: principal} {
  amount: uint,
  locked-at: uint,  ;; Clarity 4: Unix timestamp
  borrowed-against: uint
})

(define-map user-total-collateral principal {
  total-value-usd: uint,
  total-borrowed: uint,
  health-factor: uint  ;; 10000 = 1.0 (healthy)
})

;; Rewards tracking per user and asset
(define-map user-rewards {user: principal, asset: principal} {
  accrued: uint,
  last-updated: uint
})

;; Admin role mapping
(define-map admin-roles principal bool)

;; Blacklist for users and assets
(define-map user-blacklist principal bool)
(define-map asset-blacklist principal bool)

;; Fee recipient and tracking
(define-data-var fee-recipient principal CONTRACT-OWNER)

;; Event log for all state changes
(define-map event-log uint {
  event-type: (string-ascii 30),
  user: principal,
  asset: principal,
  amount: uint,
  timestamp: uint
})

;; Public Functions

(define-public (add-collateral-type (asset principal) (name (string-ascii 20)) (ltv uint) (threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (map-set collateral-types asset {
      name: name,
      ltv-ratio: ltv,
      liquidation-threshold: threshold,
      is-enabled: true,
      is-paused: false,
      price-per-unit: u1000000,  ;; Default $1.00
      total-deposited: u0,
      reward-rate-bps: u0,
      added-at: stacks-block-time
    })

    (print {
      event: "collateral-type-added",
      asset: asset,
      name: name,
      ltv: ltv,
      threshold: threshold,
      timestamp: stacks-block-time
    })

    (log-event "collateral-type-added" tx-sender asset ltv)

    (ok true)
  )
)

(define-public (update-collateral-price (asset principal) (new-price uint))
  (let (
    (collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (map-set collateral-types asset
      (merge collateral-type { price-per-unit: new-price }))

    (log-event "price-updated" tx-sender asset new-price)

    (ok true)
  )
)

;; Oracle integration
(define-public (set-price-oracle (new-oracle <price-oracle-trait>))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set price-oracle (some new-oracle))
    (log-event "oracle-updated" tx-sender new-oracle u0)
    (ok true)
  )
)

(define-public (refresh-price-from-oracle (asset principal))
  (let (
    (oracle (unwrap! (var-get price-oracle) ERR-ORACLE))
    (price-res (contract-call? oracle get-price asset))
  )
    (match price-res
      price (let ((collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL)))
        (map-set collateral-types asset (merge collateral-type { price-per-unit: price }))
        (log-event "price-refreshed" tx-sender asset price)
        (ok price))
      err (err ERR-ORACLE))
  )
)

;; Collateral parameter upgrades
(define-public (update-collateral-params (asset principal) (ltv uint) (threshold uint))
  (let ((collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set collateral-types asset (merge collateral-type {
      ltv-ratio: ltv,
      liquidation-threshold: threshold
    }))
    (log-event "collateral-params-updated" tx-sender asset ltv)
    (ok true)
  )
)

;; Rewards configuration and claims
(define-public (set-reward-rate (asset principal) (rate-bps uint))
  (let ((collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= rate-bps u10000) ERR-INVALID-COLLATERAL)
    (map-set collateral-types asset (merge collateral-type { reward-rate-bps: rate-bps }))
    (log-event "reward-rate-updated" tx-sender asset rate-bps)
    (ok true)
  )
)

(define-public (claim-rewards (asset principal))
  (let (
    (collateral (default-to { amount: u0 } (map-get? user-collateral {user: tx-sender, asset: asset})))
  )
    (try! (accrue-rewards tx-sender asset (get amount collateral)))
    (let (
      (reward-state (default-to { accrued: u0, last-updated: stacks-block-time } (map-get? user-rewards {user: tx-sender, asset: asset})))
      (payout (get accrued reward-state))
    )
      (asserts! (> payout u0) ERR-INSUFFICIENT-COLLATERAL)
      (try! (stx-transfer? payout CONTRACT-OWNER tx-sender))
      (map-set user-rewards {user: tx-sender, asset: asset} { accrued: u0, last-updated: stacks-block-time })
      (log-event "rewards-claimed" tx-sender asset payout)
      (ok payout)
    )
  )
)

;; Batch operations for gas efficiency
(define-public (deposit-collateral-batch (items (list 10 {asset: principal, amount: uint})))
  (fold deposit-batch-fn items (ok true))
)

(define-private (deposit-batch-fn (item {asset: principal, amount: uint}) (state (response bool bool)))
  (match state
    ok-state (begin
      (try! (deposit-collateral (get asset item) (get amount item)))
      (ok ok-state))
    err-state err-state)
)

(define-public (withdraw-collateral-batch (items (list 10 {asset: principal, amount: uint})))
  (fold withdraw-batch-fn items (ok true))
)

(define-private (withdraw-batch-fn (item {asset: principal, amount: uint}) (state (response bool bool)))
  (match state
    ok-state (begin
      (try! (withdraw-collateral (get asset item) (get amount item)))
      (ok ok-state))
    err-state err-state)
)

(define-public (deposit-collateral (asset principal) (amount uint))
  (let (
    (collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL))
    (current-collateral (default-to
      { amount: u0, locked-at: u0, borrowed-against: u0 }
      (map-get? user-collateral {user: tx-sender, asset: asset})))
    (new-amount (+ (get amount current-collateral) amount))
    (fee-amount (/ (* amount (var-get deposit-fee-basis-points)) u10000))
    (net-amount (- amount fee-amount))
    (collateral-value (/ (* net-amount (get price-per-unit collateral-type)) u1000000))
  )
    ;; Check if paused globally or at asset level
    (asserts! (not (var-get is-paused)) ERR-PAUSED)
    (asserts! (not (get is-paused collateral-type)) ERR-PAUSED)

    ;; Check blacklists
    (asserts! (not (default-to false (map-get? user-blacklist tx-sender))) ERR-BLACKLISTED)
    (asserts! (not (default-to false (map-get? asset-blacklist asset))) ERR-BLACKLISTED)

    ;; Validate inputs
    (asserts! (get is-enabled collateral-type) ERR-INVALID-COLLATERAL)
    (asserts! (> amount u0) ERR-INVALID-COLLATERAL)

    ;; Accrue rewards on existing balance before mutation
    (try! (accrue-rewards tx-sender asset (get amount current-collateral)))

    ;; Transfer STX to contract (for STX collateral)
    ;; In production, add SIP-010 token transfers for other assets
    (try! (stx-transfer? net-amount tx-sender CONTRACT-OWNER))

    ;; Collect fees
    (if (> fee-amount u0)
      (var-set collected-fees (+ (var-get collected-fees) fee-amount))
      false
    )

    ;; Update user collateral
    (map-set user-collateral {user: tx-sender, asset: asset} {
      amount: new-amount,
      locked-at: stacks-block-time,
      borrowed-against: (get borrowed-against current-collateral)
    })

    ;; Update collateral type totals
    (map-set collateral-types asset
      (merge collateral-type {
        total-deposited: (+ (get total-deposited collateral-type) net-amount)
      }))

    ;; Update user total collateral
    (update-user-collateral-value tx-sender collateral-value true)

    ;; Update global total
    (var-set total-collateral-value (+ (var-get total-collateral-value) collateral-value))

    (print {
      event: "collateral-deposited",
      user: tx-sender,
      asset: asset,
      amount: net-amount,
      fee: fee-amount,
      value-usd: collateral-value,
      timestamp: stacks-block-time
    })

    (log-event "collateral-deposited" tx-sender asset net-amount)

    (ok new-amount)
  )
)

(define-public (withdraw-collateral (asset principal) (amount uint))
  (let (
    (collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL))
    (current-collateral (unwrap! (map-get? user-collateral {user: tx-sender, asset: asset}) ERR-INSUFFICIENT-COLLATERAL))
    (new-amount (- (get amount current-collateral) amount))
    (fee-amount (/ (* amount (var-get withdrawal-fee-basis-points)) u10000))
    (net-amount (- amount fee-amount))
    (collateral-value (/ (* net-amount (get price-per-unit collateral-type)) u1000000))
    (borrowed (get borrowed-against current-collateral))
    (remaining-value (/ (* new-amount (get price-per-unit collateral-type)) u1000000))
    (max-borrow (/ (* remaining-value (get ltv-ratio collateral-type)) u10000))
  )
    ;; Check if paused
    (asserts! (not (var-get is-paused)) ERR-PAUSED)
    (asserts! (not (get is-paused collateral-type)) ERR-PAUSED)

    ;; Check blacklist
    (asserts! (not (default-to false (map-get? user-blacklist tx-sender))) ERR-BLACKLISTED)

    (asserts! (>= (get amount current-collateral) amount) ERR-INSUFFICIENT-COLLATERAL)
    (asserts! (> amount u0) ERR-INVALID-COLLATERAL)

    ;; Accrue rewards on current balance before mutation
    (try! (accrue-rewards tx-sender asset (get amount current-collateral)))

    ;; Check health factor - can't withdraw if it would make position unhealthy
    (asserts! (>= max-borrow borrowed) ERR-BELOW-LIQUIDATION)

    ;; Transfer STX back to user (net amount after fees)
    (try! (stx-transfer? net-amount CONTRACT-OWNER tx-sender))

    ;; Collect fees
    (if (> fee-amount u0)
      (var-set collected-fees (+ (var-get collected-fees) fee-amount))
      false
    )

    ;; Update user collateral
    (if (is-eq new-amount u0)
      (map-delete user-collateral {user: tx-sender, asset: asset})
      (map-set user-collateral {user: tx-sender, asset: asset}
        (merge current-collateral { amount: new-amount }))
    )

    ;; Update collateral type totals
    (map-set collateral-types asset
      (merge collateral-type {
        total-deposited: (- (get total-deposited collateral-type) net-amount)
      }))

    ;; Update user total collateral
    (update-user-collateral-value tx-sender collateral-value false)

    ;; Update global total
    (var-set total-collateral-value (- (var-get total-collateral-value) collateral-value))

    (print {
      event: "collateral-withdrawn",
      user: tx-sender,
      asset: asset,
      amount: net-amount,
      fee: fee-amount,
      value-usd: collateral-value,
      timestamp: stacks-block-time
    })

    (log-event "collateral-withdrawn" tx-sender asset net-amount)

    (ok new-amount)
  )
)

(define-public (record-borrow (user principal) (asset principal) (borrow-amount uint))
  (let (
    (current-collateral (unwrap! (map-get? user-collateral {user: user, asset: asset}) ERR-INSUFFICIENT-COLLATERAL))
    (fee-amount (/ (* borrow-amount (var-get borrow-fee-basis-points)) u10000))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    ;; Accrue rewards before changing borrowed state
    (try! (accrue-rewards user asset (get amount current-collateral)))

    ;; Collect borrow fees
    (if (> fee-amount u0)
      (var-set collected-fees (+ (var-get collected-fees) fee-amount))
      false
    )

    (map-set user-collateral {user: user, asset: asset}
      (merge current-collateral {
        borrowed-against: (+ (get borrowed-against current-collateral) borrow-amount)
      }))

    (print {
      event: "borrow-recorded",
      user: user,
      asset: asset,
      amount: borrow-amount,
      fee: fee-amount,
      timestamp: stacks-block-time
    })

    (log-event "borrow-recorded" user asset borrow-amount)

    (ok true)
  )
)

;; Admin Management Functions

(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set admin-roles new-admin true)
    (print { event: "admin-added", admin: new-admin, timestamp: stacks-block-time })
    (log-event "admin-added" tx-sender new-admin u1)
    (ok true)
  )
)

(define-public (remove-admin (admin-to-remove principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-delete admin-roles admin-to-remove)
    (print { event: "admin-removed", admin: admin-to-remove, timestamp: stacks-block-time })
    (log-event "admin-removed" tx-sender admin-to-remove u0)
    (ok true)
  )
)

;; Pause/Emergency Controls

(define-public (toggle-global-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set is-paused (not (var-get is-paused)))
    (print { event: "global-pause-toggled", paused: (var-get is-paused), timestamp: stacks-block-time })
    (log-event "global-pause-toggled" tx-sender CONTRACT-OWNER (if (var-get is-paused) u1 u0))
    (ok true)
  )
)

(define-public (toggle-asset-pause (asset principal))
  (let (
    (collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set collateral-types asset
      (merge collateral-type { is-paused: (not (get is-paused collateral-type)) }))
    (print { event: "asset-pause-toggled", asset: asset, paused: (not (get is-paused collateral-type)), timestamp: stacks-block-time })
    (log-event "asset-pause-toggled" tx-sender asset (if (not (get is-paused collateral-type)) u1 u0))
    (ok true)
  )
)

;; Blacklist Management

(define-public (blacklist-user (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set user-blacklist user true)
    (print { event: "user-blacklisted", user: user, timestamp: stacks-block-time })
    (log-event "user-blacklisted" tx-sender user u1)
    (ok true)
  )
)

(define-public (remove-user-blacklist (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-delete user-blacklist user)
    (print { event: "user-blacklist-removed", user: user, timestamp: stacks-block-time })
    (log-event "user-blacklist-removed" tx-sender user u0)
    (ok true)
  )
)

(define-public (blacklist-asset (asset principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set asset-blacklist asset true)
    (print { event: "asset-blacklisted", asset: asset, timestamp: stacks-block-time })
    (log-event "asset-blacklisted" tx-sender asset u1)
    (ok true)
  )
)

(define-public (remove-asset-blacklist (asset principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-delete asset-blacklist asset)
    (print { event: "asset-blacklist-removed", asset: asset, timestamp: stacks-block-time })
    (log-event "asset-blacklist-removed" tx-sender asset u0)
    (ok true)
  )
)

;; Fee Management

(define-public (set-deposit-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee MAX-FEE-BASIS-POINTS) ERR-INVALID-COLLATERAL)
    (var-set deposit-fee-basis-points new-fee)
    (print { event: "deposit-fee-updated", fee-bps: new-fee, timestamp: stacks-block-time })
    (log-event "deposit-fee-updated" tx-sender CONTRACT-OWNER new-fee)
    (ok true)
  )
)

(define-public (set-withdrawal-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee MAX-FEE-BASIS-POINTS) ERR-INVALID-COLLATERAL)
    (var-set withdrawal-fee-basis-points new-fee)
    (print { event: "withdrawal-fee-updated", fee-bps: new-fee, timestamp: stacks-block-time })
    (log-event "withdrawal-fee-updated" tx-sender CONTRACT-OWNER new-fee)
    (ok true)
  )
)

(define-public (set-borrow-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee MAX-FEE-BASIS-POINTS) ERR-INVALID-COLLATERAL)
    (var-set borrow-fee-basis-points new-fee)
    (print { event: "borrow-fee-updated", fee-bps: new-fee, timestamp: stacks-block-time })
    (log-event "borrow-fee-updated" tx-sender CONTRACT-OWNER new-fee)
    (ok true)
  )
)

(define-public (set-fee-recipient (new-recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set fee-recipient new-recipient)
    (print { event: "fee-recipient-updated", recipient: new-recipient, timestamp: stacks-block-time })
    (log-event "fee-recipient-updated" tx-sender new-recipient u0)
    (ok true)
  )
)

(define-public (claim-collected-fees)
  (let (
    (fees (var-get collected-fees))
  )
    (asserts! (is-eq tx-sender (var-get fee-recipient)) ERR-UNAUTHORIZED)
    (asserts! (> fees u0) ERR-INSUFFICIENT-COLLATERAL)
    (try! (stx-transfer? fees CONTRACT-OWNER tx-sender))
    (var-set collected-fees u0)
    (print { event: "fees-claimed", amount: fees, recipient: tx-sender, timestamp: stacks-block-time })
    (log-event "fees-claimed" tx-sender CONTRACT-OWNER fees)
    (ok fees)
  )
)

;; Private Functions

;; Centralized event logging into event-log map
(define-private (log-event (etype (string-ascii 30)) (user principal) (asset principal) (amount uint))
  (let ((next-id (+ u1 (var-get event-counter))))
    (var-set event-counter next-id)
    (map-set event-log next-id {
      event-type: etype,
      user: user,
      asset: asset,
      amount: amount,
      timestamp: stacks-block-time
    })
    true
  )
)

;; Accrue rewards for a user and asset based on time and reward rate
(define-private (accrue-rewards (user principal) (asset principal) (current-amount uint))
  (let (
    (reward-state (default-to { accrued: u0, last-updated: stacks-block-time } (map-get? user-rewards {user: user, asset: asset})))
    (collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL))
    (delta (if (> stacks-block-time (get last-updated reward-state)) (- stacks-block-time (get last-updated reward-state)) u0))
    (rate (get reward-rate-bps collateral-type))
    (earned (/ (* current-amount rate delta) u10000))
  )
    (map-set user-rewards {user: user, asset: asset} {
      accrued: (+ (get accrued reward-state) earned),
      last-updated: stacks-block-time
    })
    (ok true)
  )
)

;; Liquidation: Anyone can liquidate unhealthy positions
(define-public (liquidate-collateral (user principal) (asset principal))
  (let (
    (collateral-type (unwrap! (map-get? collateral-types asset) ERR-INVALID-COLLATERAL))
    (current-collateral (unwrap! (map-get? user-collateral {user: user, asset: asset}) ERR-INSUFFICIENT-COLLATERAL))
    (borrowed (get borrowed-against current-collateral))
    (amount (get amount current-collateral))
    (collateral-value (/ (* amount (get price-per-unit collateral-type)) u1000000))
    (liquidation-value (/ (* collateral-value (get liquidation-threshold collateral-type)) u10000))
    (health-factor (if (is-eq borrowed u0) u10000 (/ (* liquidation-value u10000) borrowed)))
  )
    ;; Accrue rewards on current balance before seizure
    (try! (accrue-rewards user asset amount))

    ;; Only allow liquidation if health factor is below threshold
    (asserts! (< health-factor u10000) ERR-NOT-LIQUIDATABLE)

    ;; Calculate amount to seize (up to borrowed value, capped by collateral)
    (let (
      (seize-amount (min amount (/ borrowed (get price-per-unit collateral-type))))
      (seize-value (/ (* seize-amount (get price-per-unit collateral-type)) u1000000))
    )
      ;; Transfer seized collateral to liquidator
      (try! (stx-transfer? seize-amount CONTRACT-OWNER tx-sender))

      ;; Update user collateral
      (let (
        (remaining-amount (- amount seize-amount))
      )
        (if (is-eq remaining-amount u0)
          (map-delete user-collateral {user: user, asset: asset})
          (map-set user-collateral {user: user, asset: asset}
            (merge current-collateral {
              amount: remaining-amount,
              borrowed-against: u0
            })
          )
        )
      )

      ;; Update collateral type totals
      (map-set collateral-types asset
        (merge collateral-type {
          total-deposited: (- (get total-deposited collateral-type) seize-amount)
        }))

      ;; Update user total collateral
      (update-user-collateral-value user seize-value false)

      ;; Update global total
      (var-set total-collateral-value (- (var-get total-collateral-value) seize-value))

      (print {
        event: "collateral-liquidated",
        liquidator: tx-sender,
        user: user,
        asset: asset,
        seized-amount: seize-amount,
        seized-value-usd: seize-value,
        timestamp: stacks-block-time
      })

      (log-event "collateral-liquidated" tx-sender asset seize-amount)

      (ok seize-amount)
    )
  )
)

(define-private (update-user-collateral-value (user principal) (value uint) (is-deposit bool))
  (let (
    (current-totals (default-to
      { total-value-usd: u0, total-borrowed: u0, health-factor: u10000 }
      (map-get? user-total-collateral user)))
    (new-value (if is-deposit
      (+ (get total-value-usd current-totals) value)
      (- (get total-value-usd current-totals) value)))
  )
    (map-set user-total-collateral user
      (merge current-totals { total-value-usd: new-value }))
    true
  )
)

;; Read-Only Functions

(define-read-only (get-collateral-type (asset principal))
  (map-get? collateral-types asset)
)

(define-read-only (get-user-collateral (user principal) (asset principal))
  (map-get? user-collateral {user: user, asset: asset})
)

(define-read-only (get-user-total-collateral (user principal))
  (map-get? user-total-collateral user)
)

(define-read-only (get-total-collateral-value)
  (var-get total-collateral-value)
)

(define-read-only (calculate-max-borrow (user principal) (asset principal))
  (match (map-get? user-collateral {user: user, asset: asset})
    collateral (match (map-get? collateral-types asset)
      coll-type (let (
        (collateral-value (/ (* (get amount collateral) (get price-per-unit coll-type)) u1000000))
        (max-borrow (/ (* collateral-value (get ltv-ratio coll-type)) u10000))
      )
        (ok max-borrow))
      (err ERR-INVALID-COLLATERAL))
    (err ERR-INSUFFICIENT-COLLATERAL)
  )
)

(define-read-only (get-health-factor (user principal) (asset principal))
  (match (map-get? user-collateral {user: user, asset: asset})
    collateral (match (map-get? collateral-types asset)
      coll-type (let (
        (collateral-value (/ (* (get amount collateral) (get price-per-unit coll-type)) u1000000))
        (borrowed (get borrowed-against collateral))
        (liquidation-value (/ (* collateral-value (get liquidation-threshold coll-type)) u10000))
      )
        (if (is-eq borrowed u0)
          (ok u10000)  ;; Perfect health if no borrows
          (ok (/ (* liquidation-value u10000) borrowed))))  ;; Health factor
      (err ERR-INVALID-COLLATERAL))
    (err ERR-INSUFFICIENT-COLLATERAL)
  )
)

;; Clarity 4 Enhanced Functions

;; 1. Clarity 4: principal-destruct? - Validate and decompose collateral asset principals
(define-read-only (validate-asset-principal (asset principal))
  (principal-destruct? asset)
)

;; 2. Clarity 4: int-to-utf8 - Format collateral values for display
(define-read-only (format-collateral-value (user principal) (asset principal))
  (match (map-get? user-collateral {user: user, asset: asset})
    collateral (ok (int-to-utf8 (get amount collateral)))
    (err ERR-INSUFFICIENT-COLLATERAL)
  )
)

;; 3. Clarity 4: string-to-uint? - Parse price inputs from string
(define-read-only (parse-price-string (price-str (string-ascii 20)))
  (match (string-to-uint? price-str)
    price (ok price)
    (err u998)
  )
)

;; 4. Clarity 4: buff-to-uint-le - Convert buffer to collateral amount
(define-read-only (buffer-to-amount (amount-buff (buff 16)))
  (ok (buff-to-uint-le amount-buff))
)

;; 5. Clarity 4: burn-block-height - Get Bitcoin timestamp for collateral tracking
(define-read-only (get-collateral-burn-time)
  (ok {
    stacks-time: stacks-block-time,
    burn-time: burn-block-height,
    time-diff: (- stacks-block-time burn-block-height)
  })
)

;; Additional Read-Only Functions for New Features

(define-read-only (is-paused-global)
  (var-get is-paused)
)

(define-read-only (is-asset-paused (asset principal))
  (match (map-get? collateral-types asset)
    coll-type (ok (get is-paused coll-type))
    (err ERR-INVALID-COLLATERAL)
  )
)

(define-read-only (is-user-blacklisted (user principal))
  (ok (default-to false (map-get? user-blacklist user)))
)

(define-read-only (is-asset-blacklisted (asset principal))
  (ok (default-to false (map-get? asset-blacklist asset)))
)

(define-read-only (is-admin (user principal))
  (ok (default-to false (map-get? admin-roles user)))
)

(define-read-only (get-fee-config)
  (ok {
    deposit-fee-bps: (var-get deposit-fee-basis-points),
    withdrawal-fee-bps: (var-get withdrawal-fee-basis-points),
    borrow-fee-bps: (var-get borrow-fee-basis-points),
    collected-fees: (var-get collected-fees),
    fee-recipient: (var-get fee-recipient)
  })
)

(define-read-only (get-deposit-fee)
  (var-get deposit-fee-basis-points)
)

(define-read-only (get-withdrawal-fee)
  (var-get withdrawal-fee-basis-points)
)

(define-read-only (get-borrow-fee)
  (var-get borrow-fee-basis-points)
)

(define-read-only (get-collected-fees)
  (var-get collected-fees)
)

(define-read-only (get-fee-recipient)
  (var-get fee-recipient)
)

(define-read-only (get-price-oracle)
  (var-get price-oracle)
)

(define-read-only (get-event (id uint))
  (map-get? event-log id)
)

(define-read-only (get-user-rewards (user principal) (asset principal))
  (map-get? user-rewards {user: user, asset: asset})
)

(define-read-only (get-pending-rewards (user principal) (asset principal))
  (match (map-get? collateral-types asset)
    coll-type (let (
      (reward-state (default-to { accrued: u0, last-updated: stacks-block-time } (map-get? user-rewards {user: user, asset: asset})))
      (current-collateral (default-to { amount: u0 } (map-get? user-collateral {user: user, asset: asset})))
      (delta (if (> stacks-block-time (get last-updated reward-state)) (- stacks-block-time (get last-updated reward-state)) u0))
      (earned (/ (* (get amount current-collateral) (get reward-rate-bps coll-type) delta) u10000))
    )
      (ok (+ (get accrued reward-state) earned)))
    (err ERR-INVALID-COLLATERAL))
)

(define-read-only (calculate-deposit-fee (amount uint))
  (/ (* amount (var-get deposit-fee-basis-points)) u10000)
)

(define-read-only (calculate-withdrawal-fee (amount uint))
  (/ (* amount (var-get withdrawal-fee-basis-points)) u10000)
)

(define-read-only (calculate-borrow-fee (amount uint))
  (/ (* amount (var-get borrow-fee-basis-points)) u10000)
)

(define-read-only (get-contract-owner)
  (ok CONTRACT-OWNER)
)
