(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_INVALID_PARAMETERS (err u103))
(define-constant ERR_EXPIRED (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))

(define-data-var next-drug-id uint u1)
(define-data-var registry-fee uint u1000000)
(define-data-var validation-period uint u144)

(define-map drugs
    { drug-id: uint }
    {
        name: (string-ascii 100),
        manufacturer: (string-ascii 100),
        category: (string-ascii 50),
        subsidy-percentage: uint,
        original-price: uint,
        subsidized-price: uint,
        expiry-block: uint,
        registrant: principal,
        validator: (optional principal),
        status: (string-ascii 20),
        registration-block: uint,
    }
)

(define-map drug-batches
    {
        drug-id: uint,
        batch-id: (string-ascii 50),
    }
    {
        quantity: uint,
        manufacturing-date: uint,
        expiry-date: uint,
        distributor: principal,
        distributed-quantity: uint,
        status: (string-ascii 20),
    }
)

(define-map validators
    { validator: principal }
    {
        name: (string-ascii 100),
        license-number: (string-ascii 50),
        active: bool,
        validation-count: uint,
        registration-block: uint,
    }
)

(define-map beneficiaries
    { beneficiary: principal }
    {
        name: (string-ascii 100),
        id-number: (string-ascii 50),
        eligible: bool,
        total-claimed: uint,
        registration-block: uint,
    }
)

(define-map drug-claims
    { claim-id: uint }
    {
        drug-id: uint,
        batch-id: (string-ascii 50),
        beneficiary: principal,
        quantity: uint,
        claim-amount: uint,
        claim-block: uint,
        approved: bool,
    }
)

(define-data-var next-claim-id uint u1)

(define-public (register-drug
        (name (string-ascii 100))
        (manufacturer (string-ascii 100))
        (category (string-ascii 50))
        (subsidy-percentage uint)
        (original-price uint)
        (expiry-blocks uint)
    )
    (let (
            (drug-id (var-get next-drug-id))
            (subsidized-price (/ (* original-price (- u100 subsidy-percentage)) u100))
            (expiry-block (+ burn-block-height expiry-blocks))
        )
        (asserts! (and (> (len name) u0) (> (len manufacturer) u0))
            ERR_INVALID_PARAMETERS
        )
        (asserts! (and (<= subsidy-percentage u100) (> original-price u0))
            ERR_INVALID_PARAMETERS
        )

        (try! (stx-transfer? (var-get registry-fee) tx-sender CONTRACT_OWNER))

        (map-set drugs { drug-id: drug-id } {
            name: name,
            manufacturer: manufacturer,
            category: category,
            subsidy-percentage: subsidy-percentage,
            original-price: original-price,
            subsidized-price: subsidized-price,
            expiry-block: expiry-block,
            registrant: tx-sender,
            validator: none,
            status: "pending",
            registration-block: burn-block-height,
        })

        (var-set next-drug-id (+ drug-id u1))
        (ok drug-id)
    )
)

(define-public (register-validator
        (name (string-ascii 100))
        (license-number (string-ascii 50))
    )
    (begin
        (asserts! (and (> (len name) u0) (> (len license-number) u0))
            ERR_INVALID_PARAMETERS
        )
        (asserts! (is-none (map-get? validators { validator: tx-sender }))
            ERR_ALREADY_EXISTS
        )

        (map-set validators { validator: tx-sender } {
            name: name,
            license-number: license-number,
            active: true,
            validation-count: u0,
            registration-block: burn-block-height,
        })
        (ok true)
    )
)

(define-public (validate-drug
        (drug-id uint)
        (approved bool)
    )
    (let (
            (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_NOT_FOUND))
            (validator-data (unwrap! (map-get? validators { validator: tx-sender })
                ERR_UNAUTHORIZED
            ))
        )
        (asserts! (get active validator-data) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status drug-data) "pending") ERR_INVALID_PARAMETERS)
        (asserts! (< burn-block-height (get expiry-block drug-data)) ERR_EXPIRED)

        (map-set drugs { drug-id: drug-id }
            (merge drug-data {
                validator: (some tx-sender),
                status: (if approved
                    "approved"
                    "rejected"
                ),
            })
        )

        (map-set validators { validator: tx-sender }
            (merge validator-data { validation-count: (+ (get validation-count validator-data) u1) })
        )
        (ok true)
    )
)

(define-public (add-drug-batch
        (drug-id uint)
        (batch-id (string-ascii 50))
        (quantity uint)
        (manufacturing-date uint)
        (expiry-date uint)
    )
    (let ((drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_NOT_FOUND)))
        (asserts! (is-eq (get registrant drug-data) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status drug-data) "approved")
            ERR_INVALID_PARAMETERS
        )
        (asserts! (> quantity u0) ERR_INVALID_PARAMETERS)
        (asserts!
            (is-none (map-get? drug-batches {
                drug-id: drug-id,
                batch-id: batch-id,
            }))
            ERR_ALREADY_EXISTS
        )

        (map-set drug-batches {
            drug-id: drug-id,
            batch-id: batch-id,
        } {
            quantity: quantity,
            manufacturing-date: manufacturing-date,
            expiry-date: expiry-date,
            distributor: tx-sender,
            distributed-quantity: u0,
            status: "available",
        })
        (ok true)
    )
)

(define-public (register-beneficiary
        (name (string-ascii 100))
        (id-number (string-ascii 50))
    )
    (begin
        (asserts! (and (> (len name) u0) (> (len id-number) u0))
            ERR_INVALID_PARAMETERS
        )
        (asserts! (is-none (map-get? beneficiaries { beneficiary: tx-sender }))
            ERR_ALREADY_EXISTS
        )

        (map-set beneficiaries { beneficiary: tx-sender } {
            name: name,
            id-number: id-number,
            eligible: true,
            total-claimed: u0,
            registration-block: burn-block-height,
        })
        (ok true)
    )
)

(define-public (claim-subsidy
        (drug-id uint)
        (batch-id (string-ascii 50))
        (quantity uint)
    )
    (let (
            (claim-id (var-get next-claim-id))
            (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR_NOT_FOUND))
            (batch-data (unwrap!
                (map-get? drug-batches {
                    drug-id: drug-id,
                    batch-id: batch-id,
                })
                ERR_NOT_FOUND
            ))
            (beneficiary-data (unwrap! (map-get? beneficiaries { beneficiary: tx-sender })
                ERR_UNAUTHORIZED
            ))
            (claim-amount (* quantity (get subsidized-price drug-data)))
            (available-quantity (- (get quantity batch-data) (get distributed-quantity batch-data)))
        )
        (asserts! (get eligible beneficiary-data) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status drug-data) "approved")
            ERR_INVALID_PARAMETERS
        )
        (asserts! (is-eq (get status batch-data) "available")
            ERR_INVALID_PARAMETERS
        )
        (asserts! (<= quantity available-quantity) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> quantity u0) ERR_INVALID_PARAMETERS)

        (map-set drug-claims { claim-id: claim-id } {
            drug-id: drug-id,
            batch-id: batch-id,
            beneficiary: tx-sender,
            quantity: quantity,
            claim-amount: claim-amount,
            claim-block: burn-block-height,
            approved: false,
        })

        (var-set next-claim-id (+ claim-id u1))
        (ok claim-id)
    )
)

(define-public (approve-claim (claim-id uint))
    (let (
            (claim-data (unwrap! (map-get? drug-claims { claim-id: claim-id }) ERR_NOT_FOUND))
            (drug-data (unwrap! (map-get? drugs { drug-id: (get drug-id claim-data) })
                ERR_NOT_FOUND
            ))
            (batch-data (unwrap!
                (map-get? drug-batches {
                    drug-id: (get drug-id claim-data),
                    batch-id: (get batch-id claim-data),
                })
                ERR_NOT_FOUND
            ))
            (beneficiary-data (unwrap!
                (map-get? beneficiaries { beneficiary: (get beneficiary claim-data) })
                ERR_NOT_FOUND
            ))
        )
        (asserts! (is-eq tx-sender (get registrant drug-data)) ERR_UNAUTHORIZED)
        (asserts! (not (get approved claim-data)) ERR_INVALID_PARAMETERS)

        (map-set drug-claims { claim-id: claim-id }
            (merge claim-data { approved: true })
        )

        (map-set drug-batches {
            drug-id: (get drug-id claim-data),
            batch-id: (get batch-id claim-data),
        }
            (merge batch-data { distributed-quantity: (+ (get distributed-quantity batch-data) (get quantity claim-data)) })
        )

        (map-set beneficiaries { beneficiary: (get beneficiary claim-data) }
            (merge beneficiary-data { total-claimed: (+ (get total-claimed beneficiary-data) (get claim-amount claim-data)) })
        )
        (ok true)
    )
)

(define-public (set-registry-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set registry-fee new-fee)
        (ok true)
    )
)

(define-public (deactivate-validator (validator principal))
    (let ((validator-data (unwrap! (map-get? validators { validator: validator }) ERR_NOT_FOUND)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set validators { validator: validator }
            (merge validator-data { active: false })
        )
        (ok true)
    )
)

(define-read-only (get-drug (drug-id uint))
    (map-get? drugs { drug-id: drug-id })
)

(define-read-only (get-drug-batch
        (drug-id uint)
        (batch-id (string-ascii 50))
    )
    (map-get? drug-batches {
        drug-id: drug-id,
        batch-id: batch-id,
    })
)

(define-read-only (get-validator (validator principal))
    (map-get? validators { validator: validator })
)

(define-read-only (get-beneficiary (beneficiary principal))
    (map-get? beneficiaries { beneficiary: beneficiary })
)

(define-read-only (get-claim (claim-id uint))
    (map-get? drug-claims { claim-id: claim-id })
)

(define-read-only (get-next-drug-id)
    (var-get next-drug-id)
)

(define-read-only (get-registry-fee)
    (var-get registry-fee)
)

(define-read-only (is-drug-valid (drug-id uint))
    (match (map-get? drugs { drug-id: drug-id })
        drug-data (and
            (is-eq (get status drug-data) "approved")
            (< burn-block-height (get expiry-block drug-data))
        )
        false
    )
)

(define-read-only (get-available-quantity
        (drug-id uint)
        (batch-id (string-ascii 50))
    )
    (match (map-get? drug-batches {
        drug-id: drug-id,
        batch-id: batch-id,
    })
        batch-data (- (get quantity batch-data) (get distributed-quantity batch-data))
        u0
    )
)
