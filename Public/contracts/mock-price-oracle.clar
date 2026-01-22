;; title: mock-price-oracle
;; version: 1.0.0
;; summary: Mock price oracle for testing collateral-manager
;; description: Simple price oracle that stores and returns asset prices

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u6000))
(define-constant ERR-ASSET-NOT-FOUND (err u6001))

;; Data Maps
(define-map asset-prices principal uint)

;; Public Functions

;; Set price for an asset (admin only)
(define-public (set-price (asset principal) (price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set asset-prices asset price)
    (print {
      event: "price-updated",
      asset: asset,
      price: price,
      timestamp: stacks-block-time
    })
    (ok true)
  )
)

;; Batch set prices for multiple assets
(define-public (set-prices-batch (items (list 20 {asset: principal, price: uint})))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (fold set-price-batch-fn items (ok true))
  )
)

(define-private (set-price-batch-fn (item {asset: principal, price: uint}) (state (response bool uint)))
  (begin
    (map-set asset-prices (get asset item) (get price item))
    (ok true)
  )
)

;; Get price for an asset (implements price-oracle-trait)
(define-read-only (get-price (asset principal))
  (match (map-get? asset-prices asset)
    price (ok price)
    (err ERR-ASSET-NOT-FOUND)
  )
)

;; Simulate price feed with random variation (for testing)
(define-public (simulate-price-update (asset principal) (base-price uint) (variation-percent uint))
  (let (
    (random-factor (mod stacks-block-time u100))
    (variation (/ (* base-price variation-percent) u100))
    (new-price (if (> random-factor u50)
      (+ base-price variation)
      (- base-price variation)))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set asset-prices asset new-price)
    (print {
      event: "simulated-price-update",
      asset: asset,
      base-price: base-price,
      new-price: new-price,
      timestamp: stacks-block-time
    })
    (ok new-price)
  )
)

;; Read-Only Functions

(define-read-only (get-all-prices (assets (list 20 principal)))
  (ok (map get-single-price assets))
)

(define-private (get-single-price (asset principal))
  {
    asset: asset,
    price: (default-to u0 (map-get? asset-prices asset))
  }
)

(define-read-only (get-owner)
  (ok CONTRACT-OWNER)
)
