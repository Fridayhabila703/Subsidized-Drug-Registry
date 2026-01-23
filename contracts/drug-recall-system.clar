(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_INVALID_PARAMETERS (err u302))
(define-constant ERR_ALREADY_EXISTS (err u303))
(define-constant ERR_RECALL_CLOSED (err u304))

(define-data-var next-recall-id uint u1)
(define-data-var next-response-id uint u1)

(define-map recalls
    { recall-id: uint }
    {
        drug-id: (string-ascii 50),
        batch-ids: (list 50 (string-ascii 50)),
        severity-level: (string-ascii 20),
        recall-reason: (string-ascii 200),
        issued-by: principal,
        issued-date: uint,
        effective-date: uint,
        status: (string-ascii 20),
        affected-quantity: uint,
        recovered-quantity: uint,
        total-notified: uint,
        resolution-notes: (optional (string-ascii 200)),
    }
)

(define-map recall-notifications
    {
        recall-id: uint,
        beneficiary: principal,
    }
    {
        notified-date: uint,
        acknowledged: bool,
        response-action: (optional (string-ascii 50)),
        response-date: (optional uint),
    }
)

(define-map beneficiary-recall-history
    { beneficiary: principal }
    {
        total-recalls: uint,
        acknowledged-recalls: uint,
        pending-recalls: uint,
        last-recall-date: uint,
    }
)

(define-map batch-recall-status
    {
        drug-id: (string-ascii 50),
        batch-id: (string-ascii 50),
    }
    {
        recall-id: uint,
        is-recalled: bool,
        recall-date: uint,
    }
)

(define-map recall-responses
    { response-id: uint }
    {
        recall-id: uint,
        beneficiary: principal,
        has-product: bool,
        quantity: uint,
        return-location: (string-ascii 100),
        response-date: uint,
        processed: bool,
    }
)

(define-map recall-statistics
    { recall-id: uint }
    {
        total-affected-beneficiaries: uint,
        total-notifications-sent: uint,
        total-acknowledged: uint,
        total-responses: uint,
        recovery-rate: uint,
        last-updated: uint,
    }
)

(define-public (issue-recall
        (drug-id (string-ascii 50))
        (batch-ids (list 50 (string-ascii 50)))
        (severity-level (string-ascii 20))
        (recall-reason (string-ascii 200))
        (affected-quantity uint)
        (effective-date uint)
    )
    (let ((recall-id (var-get next-recall-id)))
        (asserts! (> (len drug-id) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len batch-ids) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len severity-level) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len recall-reason) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> affected-quantity u0) ERR_INVALID_PARAMETERS)

        (map-set recalls { recall-id: recall-id } {
            drug-id: drug-id,
            batch-ids: batch-ids,
            severity-level: severity-level,
            recall-reason: recall-reason,
            issued-by: tx-sender,
            issued-date: burn-block-height,
            effective-date: effective-date,
            status: "active",
            affected-quantity: affected-quantity,
            recovered-quantity: u0,
            total-notified: u0,
            resolution-notes: none,
        })

        (unwrap-panic (mark-batches-recalled drug-id batch-ids recall-id))

        (map-set recall-statistics { recall-id: recall-id } {
            total-affected-beneficiaries: u0,
            total-notifications-sent: u0,
            total-acknowledged: u0,
            total-responses: u0,
            recovery-rate: u0,
            last-updated: burn-block-height,
        })

        (var-set next-recall-id (+ recall-id u1))
        (ok recall-id)
    )
)

(define-public (notify-beneficiary
        (recall-id uint)
        (beneficiary principal)
    )
    (let (
            (recall-data (unwrap! (map-get? recalls { recall-id: recall-id }) ERR_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status recall-data) "active") ERR_RECALL_CLOSED)
        (asserts!
            (is-none (map-get? recall-notifications {
                recall-id: recall-id,
                beneficiary: beneficiary,
            }))
            ERR_ALREADY_EXISTS
        )

        (map-set recall-notifications {
            recall-id: recall-id,
            beneficiary: beneficiary,
        } {
            notified-date: burn-block-height,
            acknowledged: false,
            response-action: none,
            response-date: none,
        })

        (map-set recalls { recall-id: recall-id }
            (merge recall-data { total-notified: (+ (get total-notified recall-data) u1) })
        )

        (let ((history (default-to {
                total-recalls: u0,
                acknowledged-recalls: u0,
                pending-recalls: u0,
                last-recall-date: u0,
            }
                (map-get? beneficiary-recall-history { beneficiary: beneficiary })
            )))
            (map-set beneficiary-recall-history { beneficiary: beneficiary }
                (merge history {
                    total-recalls: (+ (get total-recalls history) u1),
                    pending-recalls: (+ (get pending-recalls history) u1),
                    last-recall-date: burn-block-height,
                })
            )
        )

        (unwrap-panic (update-recall-statistics recall-id))
        (ok true)
    )
)

(define-public (acknowledge-recall (recall-id uint))
    (let (
            (notification-data (unwrap!
                (map-get? recall-notifications {
                    recall-id: recall-id,
                    beneficiary: tx-sender,
                })
                ERR_NOT_FOUND
            ))
            (history (unwrap!
                (map-get? beneficiary-recall-history { beneficiary: tx-sender })
                ERR_NOT_FOUND
            ))
        )
        (asserts! (not (get acknowledged notification-data)) ERR_INVALID_PARAMETERS)

        (map-set recall-notifications {
            recall-id: recall-id,
            beneficiary: tx-sender,
        }
            (merge notification-data { acknowledged: true })
        )

        (map-set beneficiary-recall-history { beneficiary: tx-sender }
            (merge history {
                acknowledged-recalls: (+ (get acknowledged-recalls history) u1),
                pending-recalls: (- (get pending-recalls history) u1),
            })
        )

        (unwrap-panic (update-recall-statistics recall-id))
        (ok true)
    )
)

(define-public (submit-recall-response
        (recall-id uint)
        (has-product bool)
        (quantity uint)
        (return-location (string-ascii 100))
    )
    (let (
            (response-id (var-get next-response-id))
            (recall-data (unwrap! (map-get? recalls { recall-id: recall-id }) ERR_NOT_FOUND))
            (notification-data (unwrap!
                (map-get? recall-notifications {
                    recall-id: recall-id,
                    beneficiary: tx-sender,
                })
                ERR_NOT_FOUND
            ))
        )
        (asserts! (is-eq (get status recall-data) "active") ERR_RECALL_CLOSED)
        (asserts! (> (len return-location) u0) ERR_INVALID_PARAMETERS)

        (map-set recall-responses { response-id: response-id } {
            recall-id: recall-id,
            beneficiary: tx-sender,
            has-product: has-product,
            quantity: quantity,
            return-location: return-location,
            response-date: burn-block-height,
            processed: false,
        })

        (map-set recall-notifications {
            recall-id: recall-id,
            beneficiary: tx-sender,
        }
            (merge notification-data {
                response-action: (some (if has-product "return-initiated" "no-product")),
                response-date: (some burn-block-height),
            })
        )

        (var-set next-response-id (+ response-id u1))
        (unwrap-panic (update-recall-statistics recall-id))
        (ok response-id)
    )
)

(define-public (process-recall-response (response-id uint))
    (let (
            (response-data (unwrap! (map-get? recall-responses { response-id: response-id }) ERR_NOT_FOUND))
            (recall-data (unwrap! (map-get? recalls { recall-id: (get recall-id response-data) }) ERR_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (not (get processed response-data)) ERR_INVALID_PARAMETERS)

        (map-set recall-responses { response-id: response-id }
            (merge response-data { processed: true })
        )

        (if (get has-product response-data)
            (map-set recalls { recall-id: (get recall-id response-data) }
                (merge recall-data {
                    recovered-quantity: (+ (get recovered-quantity recall-data) (get quantity response-data))
                })
            )
            true
        )

        (unwrap-panic (update-recall-statistics (get recall-id response-data)))
        (ok true)
    )
)

(define-public (close-recall
        (recall-id uint)
        (resolution-notes (string-ascii 200))
    )
    (let ((recall-data (unwrap! (map-get? recalls { recall-id: recall-id }) ERR_NOT_FOUND)))
        (asserts!
            (or
                (is-eq tx-sender (get issued-by recall-data))
                (is-eq tx-sender CONTRACT_OWNER)
            )
            ERR_UNAUTHORIZED
        )
        (asserts! (is-eq (get status recall-data) "active") ERR_RECALL_CLOSED)

        (map-set recalls { recall-id: recall-id }
            (merge recall-data {
                status: "closed",
                resolution-notes: (some resolution-notes),
            })
        )

        (ok true)
    )
)

(define-public (update-recall-severity
        (recall-id uint)
        (new-severity (string-ascii 20))
    )
    (let ((recall-data (unwrap! (map-get? recalls { recall-id: recall-id }) ERR_NOT_FOUND)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> (len new-severity) u0) ERR_INVALID_PARAMETERS)

        (map-set recalls { recall-id: recall-id }
            (merge recall-data { severity-level: new-severity })
        )
        (ok true)
    )
)

(define-private (mark-batches-recalled
        (drug-id (string-ascii 50))
        (batch-ids (list 50 (string-ascii 50)))
        (recall-id uint)
    )
    (begin
        (map mark-single-batch-recalled
            batch-ids
            (list
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
                { drug-id: drug-id, recall-id: recall-id }
            )
        )
        (ok true)
    )
)

(define-private (mark-single-batch-recalled
        (batch-id (string-ascii 50))
        (data { drug-id: (string-ascii 50), recall-id: uint })
    )
    (map-set batch-recall-status {
        drug-id: (get drug-id data),
        batch-id: batch-id,
    } {
        recall-id: (get recall-id data),
        is-recalled: true,
        recall-date: burn-block-height,
    })
)

(define-private (update-recall-statistics (recall-id uint))
    (let (
            (recall-data (unwrap! (map-get? recalls { recall-id: recall-id }) ERR_NOT_FOUND))
            (current-stats (unwrap!
                (map-get? recall-statistics { recall-id: recall-id })
                ERR_NOT_FOUND
            ))
            (recovery-rate (if (> (get affected-quantity recall-data) u0)
                (/ (* (get recovered-quantity recall-data) u100) (get affected-quantity recall-data))
                u0
            ))
        )
        (map-set recall-statistics { recall-id: recall-id }
            (merge current-stats {
                total-notifications-sent: (get total-notified recall-data),
                recovery-rate: recovery-rate,
                last-updated: burn-block-height,
            })
        )
        (ok true)
    )
)

(define-read-only (get-recall (recall-id uint))
    (map-get? recalls { recall-id: recall-id })
)

(define-read-only (get-recall-notification
        (recall-id uint)
        (beneficiary principal)
    )
    (map-get? recall-notifications {
        recall-id: recall-id,
        beneficiary: beneficiary,
    })
)

(define-read-only (get-beneficiary-recall-history (beneficiary principal))
    (map-get? beneficiary-recall-history { beneficiary: beneficiary })
)

(define-read-only (is-batch-recalled
        (drug-id (string-ascii 50))
        (batch-id (string-ascii 50))
    )
    (match (map-get? batch-recall-status {
        drug-id: drug-id,
        batch-id: batch-id,
    })
        status-data (get is-recalled status-data)
        false
    )
)

(define-read-only (get-batch-recall-info
        (drug-id (string-ascii 50))
        (batch-id (string-ascii 50))
    )
    (map-get? batch-recall-status {
        drug-id: drug-id,
        batch-id: batch-id,
    })
)

(define-read-only (get-recall-response (response-id uint))
    (map-get? recall-responses { response-id: response-id })
)

(define-read-only (get-recall-statistics (recall-id uint))
    (map-get? recall-statistics { recall-id: recall-id })
)

(define-read-only (get-next-recall-id)
    (var-get next-recall-id)
)

(define-read-only (get-next-response-id)
    (var-get next-response-id)
)

(define-read-only (get-recall-recovery-rate (recall-id uint))
    (match (map-get? recalls { recall-id: recall-id })
        recall-data (if (> (get affected-quantity recall-data) u0)
            (/ (* (get recovered-quantity recall-data) u100) (get affected-quantity recall-data))
            u0
        )
        u0
    )
)

(define-read-only (has-pending-recalls (beneficiary principal))
    (match (map-get? beneficiary-recall-history { beneficiary: beneficiary })
        history-data (> (get pending-recalls history-data) u0)
        false
    )
)
