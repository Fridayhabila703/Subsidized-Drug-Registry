;; ===============================================
;; Drug Price History Tracking System
;; ===============================================
;; Independent smart contract for tracking drug price changes over time
;; Provides historical pricing data, trend analysis, volatility calculations,
;; price comparisons, and automated alerts for significant price changes

;; ===============================================
;; Constants
;; ===============================================
(define-constant CONTRACT_OWNER tx-sender)

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PRICE (err u201))
(define-constant ERR_DRUG_NOT_FOUND (err u202))
(define-constant ERR_INVALID_PARAMETERS (err u203))
(define-constant ERR_INSUFFICIENT_HISTORY (err u204))
(define-constant ERR_PRICE_ENTRY_NOT_FOUND (err u205))
(define-constant ERR_INVALID_TIME_RANGE (err u206))
(define-constant ERR_ALREADY_EXISTS (err u207))

;; Price alert thresholds (percentage changes)
(define-constant ALERT_THRESHOLD_MINOR u10)  ;; 10% change
(define-constant ALERT_THRESHOLD_MAJOR u25)  ;; 25% change
(define-constant ALERT_THRESHOLD_CRITICAL u50) ;; 50% change

;; Maximum entries for price history lists
(define-constant MAX_PRICE_ENTRIES u100)

;; ===============================================
;; Data Variables
;; ===============================================
(define-data-var next-entry-id uint u1)
(define-data-var next-alert-id uint u1)
(define-data-var price-recording-fee uint u100000) ;; 0.1 STX

;; ===============================================
;; Data Structures
;; ===============================================

;; Price history entries with detailed tracking
(define-map price-history
    { entry-id: uint }
    {
        drug-id: (string-ascii 50),
        price: uint,
        change-reason: (string-ascii 100),
        previous-price: (optional uint),
        percentage-change: int,
        recorded-by: principal,
        timestamp: uint,
        block-height: uint,
        is-validated: bool
    }
)

;; Current prices for quick lookup
(define-map current-prices
    { drug-id: (string-ascii 50) }
    {
        price: uint,
        last-updated: uint,
        last-entry-id: uint,
        update-count: uint
    }
)

;; Price statistics per drug
(define-map price-statistics
    { drug-id: (string-ascii 50) }
    {
        min-price: uint,
        max-price: uint,
        average-price: uint,
        total-entries: uint,
        first-recorded: uint,
        last-updated: uint,
        volatility-score: uint
    }
)

;; Price alerts for significant changes
(define-map price-alerts
    { alert-id: uint }
    {
        drug-id: (string-ascii 50),
        entry-id: uint,
        alert-type: (string-ascii 20), ;; minor, major, critical
        old-price: uint,
        new-price: uint,
        percentage-change: int,
        triggered-at: uint,
        acknowledged: bool
    }
)

;; Drug authorization - who can record prices for which drugs
(define-map price-recorders
    { 
        recorder: principal,
        drug-id: (string-ascii 50) 
    }
    {
        authorized: bool,
        authorization-date: uint,
        authorized-by: principal
    }
)

;; Drug registration for price tracking
(define-map tracked-drugs
    { drug-id: (string-ascii 50) }
    {
        name: (string-ascii 100),
        category: (string-ascii 50),
        registered-by: principal,
        registration-date: uint,
        active: bool,
        initial-price: uint
    }
)

;; ===============================================
;; Authorization Functions
;; ===============================================

(define-private (is-authorized-recorder (drug-id (string-ascii 50)))
    (or 
        (is-eq tx-sender CONTRACT_OWNER)
        (default-to false 
            (get authorized 
                (map-get? price-recorders { 
                    recorder: tx-sender, 
                    drug-id: drug-id 
                })
            )
        )
    )
)

(define-public (authorize-price-recorder 
        (recorder principal) 
        (drug-id (string-ascii 50))
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> (len drug-id) u0) ERR_INVALID_PARAMETERS)
        (asserts! (is-some (map-get? tracked-drugs { drug-id: drug-id })) ERR_DRUG_NOT_FOUND)
        
        (map-set price-recorders
            { recorder: recorder, drug-id: drug-id }
            {
                authorized: true,
                authorization-date: burn-block-height,
                authorized-by: tx-sender
            }
        )
        (ok true)
    )
)

(define-public (revoke-price-recorder 
        (recorder principal) 
        (drug-id (string-ascii 50))
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set price-recorders
            { recorder: recorder, drug-id: drug-id }
            {
                authorized: false,
                authorization-date: burn-block-height,
                authorized-by: tx-sender
            }
        )
        (ok true)
    )
)

;; ===============================================
;; Drug Registration Functions
;; ===============================================

(define-public (register-drug-for-tracking
        (drug-id (string-ascii 50))
        (name (string-ascii 100))
        (category (string-ascii 50))
        (initial-price uint)
    )
    (begin
        (asserts! (or (is-eq tx-sender CONTRACT_OWNER)
                      (is-some (map-get? tracked-drugs { drug-id: drug-id }))) 
                  ERR_UNAUTHORIZED)
        (asserts! (and (> (len drug-id) u0) (> (len name) u0)) ERR_INVALID_PARAMETERS)
        (asserts! (> initial-price u0) ERR_INVALID_PRICE)
        (asserts! (is-none (map-get? tracked-drugs { drug-id: drug-id })) ERR_ALREADY_EXISTS)
        
        (map-set tracked-drugs { drug-id: drug-id }
            {
                name: name,
                category: category,
                registered-by: tx-sender,
                registration-date: burn-block-height,
                active: true,
                initial-price: initial-price
            }
        )
        
        ;; Initialize current price and statistics
        (map-set current-prices { drug-id: drug-id }
            {
                price: initial-price,
                last-updated: burn-block-height,
                last-entry-id: u0,
                update-count: u1
            }
        )
        
        (map-set price-statistics { drug-id: drug-id }
            {
                min-price: initial-price,
                max-price: initial-price,
                average-price: initial-price,
                total-entries: u1,
                first-recorded: burn-block-height,
                last-updated: burn-block-height,
                volatility-score: u0
            }
        )
        
        (ok true)
    )
)

;; ===============================================
;; Core Price Recording Functions
;; ===============================================

(define-public (record-price-change
        (drug-id (string-ascii 50))
        (new-price uint)
        (change-reason (string-ascii 100))
    )
    (let (
            (entry-id (var-get next-entry-id))
            (current-price-data (unwrap! 
                (map-get? current-prices { drug-id: drug-id }) 
                ERR_DRUG_NOT_FOUND
            ))
            (previous-price (get price current-price-data))
            (percentage-change (calculate-percentage-change previous-price new-price))
            (drug-data (unwrap! 
                (map-get? tracked-drugs { drug-id: drug-id }) 
                ERR_DRUG_NOT_FOUND
            ))
        )
        
        ;; Validate inputs and authorization
        (asserts! (get active drug-data) ERR_DRUG_NOT_FOUND)
        (asserts! (is-authorized-recorder drug-id) ERR_UNAUTHORIZED)
        (asserts! (> new-price u0) ERR_INVALID_PRICE)
        (asserts! (> (len change-reason) u0) ERR_INVALID_PARAMETERS)
        
        ;; Pay recording fee
        (try! (stx-transfer? (var-get price-recording-fee) tx-sender CONTRACT_OWNER))
        
        ;; Create price history entry
        (map-set price-history { entry-id: entry-id }
            {
                drug-id: drug-id,
                price: new-price,
                change-reason: change-reason,
                previous-price: (some previous-price),
                percentage-change: percentage-change,
                recorded-by: tx-sender,
                timestamp: burn-block-height,
                block-height: burn-block-height,
                is-validated: false
            }
        )
        
        ;; Update current price
        (map-set current-prices { drug-id: drug-id }
            (merge current-price-data {
                price: new-price,
                last-updated: burn-block-height,
                last-entry-id: entry-id,
                update-count: (+ (get update-count current-price-data) u1)
            })
        )
        
        ;; Update statistics
        (unwrap-panic (update-price-statistics drug-id new-price))
        
        ;; Check for price alerts
        (unwrap-panic (check-and-create-alert drug-id entry-id previous-price new-price percentage-change))
        
        ;; Increment entry counter
        (var-set next-entry-id (+ entry-id u1))
        
        (ok entry-id)
    )
)

(define-public (validate-price-entry (entry-id uint))
    (let (
            (entry-data (unwrap! 
                (map-get? price-history { entry-id: entry-id }) 
                ERR_PRICE_ENTRY_NOT_FOUND
            ))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (not (get is-validated entry-data)) ERR_INVALID_PARAMETERS)
        
        (map-set price-history { entry-id: entry-id }
            (merge entry-data { is-validated: true })
        )
        (ok true)
    )
)

;; ===============================================
;; Price Analysis Functions
;; ===============================================

(define-public (calculate-price-trend
        (drug-id (string-ascii 50))
        (blocks-back uint)
    )
    (let (
            (current-block burn-block-height)
            (start-block (if (> current-block blocks-back) 
                            (- current-block blocks-back) 
                            u0))
            (current-price-data (unwrap! 
                (map-get? current-prices { drug-id: drug-id }) 
                ERR_DRUG_NOT_FOUND
            ))
            (current-price (get price current-price-data))
            (historical-price (unwrap! 
                (get-price-at-block drug-id start-block) 
                ERR_INSUFFICIENT_HISTORY
            ))
        )
        
        (asserts! (> blocks-back u0) ERR_INVALID_PARAMETERS)
        
        (let (
                (price-change (calculate-percentage-change historical-price current-price))
                (trend-direction (if (> price-change 0)
                                   "upward"
                                   (if (< price-change 0)
                                       "downward"
                                       "stable")))
            )
            (ok {
                drug-id: drug-id,
                start-block: start-block,
                end-block: current-block,
                start-price: historical-price,
                end-price: current-price,
                percentage-change: price-change,
                trend-direction: trend-direction,
                blocks-analyzed: blocks-back
            })
        )
    )
)

(define-public (calculate-price-volatility
        (drug-id (string-ascii 50))
        (blocks-back uint)
    )
    (let (
            (stats (unwrap! 
                (map-get? price-statistics { drug-id: drug-id }) 
                ERR_DRUG_NOT_FOUND
            ))
            (price-range (if (> (get max-price stats) (get min-price stats))
                            (- (get max-price stats) (get min-price stats))
                            u0))
            (avg-price (get average-price stats))
            (volatility-ratio (if (> avg-price u0)
                                 (/ (* price-range u100) avg-price)
                                 u0))
        )
        
        (asserts! (> blocks-back u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (get total-entries stats) u1) ERR_INSUFFICIENT_HISTORY)
        
        (let (
                (volatility-level (if (> volatility-ratio u50)
                                    "high"
                                    (if (> volatility-ratio u20)
                                        "moderate"
                                        "low")))
            )
            (ok {
                drug-id: drug-id,
                min-price: (get min-price stats),
                max-price: (get max-price stats),
                average-price: avg-price,
                price-range: price-range,
                volatility-ratio: volatility-ratio,
                volatility-level: volatility-level,
                total-entries: (get total-entries stats)
            })
        )
    )
)

(define-public (compare-drug-prices
        (drug-id-1 (string-ascii 50))
        (drug-id-2 (string-ascii 50))
    )
    (let (
            (price-1-data (unwrap! 
                (map-get? current-prices { drug-id: drug-id-1 }) 
                ERR_DRUG_NOT_FOUND
            ))
            (price-2-data (unwrap! 
                (map-get? current-prices { drug-id: drug-id-2 }) 
                ERR_DRUG_NOT_FOUND
            ))
            (price-1 (get price price-1-data))
            (price-2 (get price price-2-data))
            (price-difference (if (> price-1 price-2)
                                (- price-1 price-2)
                                (- price-2 price-1)))
            (percentage-diff (if (> price-2 u0)
                               (/ (* price-difference u100) price-2)
                               u0))
        )
        
        (ok {
            drug-1: drug-id-1,
            drug-2: drug-id-2,
            price-1: price-1,
            price-2: price-2,
            price-difference: price-difference,
            percentage-difference: percentage-diff,
            cheaper-drug: (if (< price-1 price-2) drug-id-1 drug-id-2),
            last-updated-1: (get last-updated price-1-data),
            last-updated-2: (get last-updated price-2-data)
        })
    )
)

;; ===============================================
;; Alert System Functions
;; ===============================================

(define-private (check-and-create-alert
        (drug-id (string-ascii 50))
        (entry-id uint)
        (old-price uint)
        (new-price uint)
        (percentage-change int)
    )
    (let (
            (abs-change (if (< percentage-change 0) 
                           (- 0 percentage-change) 
                           percentage-change))
            (alert-type (if (>= abs-change (to-int ALERT_THRESHOLD_CRITICAL))
                           "critical"
                           (if (>= abs-change (to-int ALERT_THRESHOLD_MAJOR))
                               "major"
                               (if (>= abs-change (to-int ALERT_THRESHOLD_MINOR))
                                   "minor"
                                   "none"))))
        )
        
        (if (not (is-eq alert-type "none"))
            (let ((alert-id (var-get next-alert-id)))
                (map-set price-alerts { alert-id: alert-id }
                    {
                        drug-id: drug-id,
                        entry-id: entry-id,
                        alert-type: alert-type,
                        old-price: old-price,
                        new-price: new-price,
                        percentage-change: percentage-change,
                        triggered-at: burn-block-height,
                        acknowledged: false
                    }
                )
                (var-set next-alert-id (+ alert-id u1))
                (ok alert-id)
            )
            (ok u0)
        )
    )
)

(define-public (acknowledge-price-alert (alert-id uint))
    (let (
            (alert-data (unwrap! 
                (map-get? price-alerts { alert-id: alert-id }) 
                ERR_PRICE_ENTRY_NOT_FOUND
            ))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (not (get acknowledged alert-data)) ERR_INVALID_PARAMETERS)
        
        (map-set price-alerts { alert-id: alert-id }
            (merge alert-data { acknowledged: true })
        )
        (ok true)
    )
)

;; ===============================================
;; Read-Only Functions
;; ===============================================

(define-read-only (get-current-price (drug-id (string-ascii 50)))
    (map-get? current-prices { drug-id: drug-id })
)

(define-read-only (get-price-entry (entry-id uint))
    (map-get? price-history { entry-id: entry-id })
)

(define-read-only (get-drug-statistics (drug-id (string-ascii 50)))
    (map-get? price-statistics { drug-id: drug-id })
)

(define-read-only (get-price-alert (alert-id uint))
    (map-get? price-alerts { alert-id: alert-id })
)

(define-read-only (get-tracked-drug (drug-id (string-ascii 50)))
    (map-get? tracked-drugs { drug-id: drug-id })
)

(define-read-only (is-price-recorder-authorized (recorder principal) (drug-id (string-ascii 50)))
    (default-to false 
        (get authorized 
            (map-get? price-recorders { 
                recorder: recorder, 
                drug-id: drug-id 
            })
        )
    )
)

(define-read-only (get-next-entry-id)
    (var-get next-entry-id)
)

(define-read-only (get-next-alert-id)
    (var-get next-alert-id)
)

(define-read-only (get-recording-fee)
    (var-get price-recording-fee)
)

;; ===============================================
;; Helper Functions
;; ===============================================

(define-private (calculate-percentage-change (old-price uint) (new-price uint))
    (if (is-eq old-price u0)
        0
        (let (
                (difference (if (> new-price old-price)
                              (- new-price old-price)
                              (- old-price new-price)))
                (percentage (/ (* difference u100) old-price))
                (signed-percentage (to-int percentage))
            )
            (if (> new-price old-price)
                signed-percentage
                (- 0 signed-percentage)
            )
        )
    )
)

(define-private (update-price-statistics (drug-id (string-ascii 50)) (new-price uint))
    (let (
            (current-stats (unwrap! 
                (map-get? price-statistics { drug-id: drug-id }) 
                ERR_DRUG_NOT_FOUND
            ))
            (new-total-entries (+ (get total-entries current-stats) u1))
            (new-min (if (< new-price (get min-price current-stats)) 
                        new-price 
                        (get min-price current-stats)))
            (new-max (if (> new-price (get max-price current-stats)) 
                        new-price 
                        (get max-price current-stats)))
            (current-total (+ (* (get average-price current-stats) (get total-entries current-stats)) new-price))
            (new-average (/ current-total new-total-entries))
            (price-range (- new-max new-min))
            (volatility (if (> new-average u0) (/ (* price-range u100) new-average) u0))
        )
        
        (map-set price-statistics { drug-id: drug-id }
            (merge current-stats {
                min-price: new-min,
                max-price: new-max,
                average-price: new-average,
                total-entries: new-total-entries,
                last-updated: burn-block-height,
                volatility-score: volatility
            })
        )
        (ok true)
    )
)

(define-private (get-price-at-block (drug-id (string-ascii 50)) (target-block uint))
    ;; Simplified implementation - returns current price as fallback
    ;; In a full implementation, this would search through price history
    (match (map-get? current-prices { drug-id: drug-id })
        price-data (some (get price price-data))
        none
    )
)

;; ===============================================
;; Administrative Functions
;; ===============================================

(define-public (set-recording-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set price-recording-fee new-fee)
        (ok true)
    )
)

(define-public (deactivate-drug (drug-id (string-ascii 50)))
    (let (
            (drug-data (unwrap! 
                (map-get? tracked-drugs { drug-id: drug-id }) 
                ERR_DRUG_NOT_FOUND
            ))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set tracked-drugs { drug-id: drug-id }
            (merge drug-data { active: false })
        )
        (ok true)
    )
)

(define-read-only (get-contract-info)
    {
        contract-owner: CONTRACT_OWNER,
        next-entry-id: (var-get next-entry-id),
        next-alert-id: (var-get next-alert-id),
        recording-fee: (var-get price-recording-fee),
        deployed-at: burn-block-height
    }
)
